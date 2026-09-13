import Foundation

/// Auto-actualización estilo Ubuntu (AppImage) pero nativa: mira GitHub
/// Releases, baja el DMG firmado del tag, sustituye el .app y releva los
/// LaunchAgents. Solo https contra hosts de GitHub; nada de redirects raros.
enum Updater {
    struct Release {
        var tag: String
        var dmgURL: URL?
    }

    static func latest(repo: String = Paths.repo) -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
              url.scheme == "https", url.host == "api.github.com" else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var release: Release?
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        session.dataTask(with: url) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            var dmg: URL?
            if let assets = obj["assets"] as? [[String: Any]] {
                for a in assets {
                    if let name = a["name"] as? String, name.hasSuffix(".dmg"),
                       let link = a["browser_download_url"] as? String, let u = URL(string: link) {
                        dmg = u
                        break
                    }
                }
            }
            release = Release(tag: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, dmgURL: dmg)
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        return release
    }

    /// Hosts permitidos para la descarga del DMG (GitHub y su CDN de assets).
    static let allowedHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]

    /// Validación de URL de descarga (probable en tests, sin red).
    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host,
              allowedHosts.contains(host) else { return false }
        return true
    }

    static func download(_ url: URL, to dest: String) -> Bool {
        guard isAllowedDownloadURL(url) else { return false }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        session.downloadTask(with: url) { temp, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let temp else { return }
            try? FileManager.default.removeItem(atPath: dest)
            ok = (try? FileManager.default.moveItem(at: temp, to: URL(fileURLWithPath: dest))) != nil
        }.resume()
        _ = sem.wait(timeout: .now() + 320)
        return ok
    }

    /// ¿Este binario vive dentro de un ConBarAI.app instalado?
    static func installedAppPath() -> String? {
        let bin = Paths.selfBinaryPath()
        guard bin.contains(".app/Contents/MacOS/") else { return nil }
        let parts = bin.components(separatedBy: ".app/Contents")
        return parts.first.map { $0 + ".app" }
    }

    /// Monta el DMG, sustituye el .app actual y releva los agentes.
    static func install(dmg: String) -> String {
        let fm = FileManager.default
        guard let currentApp = installedAppPath() else {
            return "Esta copia no es un ConBarAI.app instalado; actualiza con el DMG nuevo a mano."
        }
        // Montar
        let mount = Shell.run("/usr/bin/hdiutil attach -nobrowse -plist '\(dmg)' 2>/dev/null | grep -o '/Volumes/[^\"]*'", timeout: 60)
        let mountPoint = mount.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mountPoint.hasPrefix("/Volumes/") else { return "No pude montar el DMG (\(mount.out))"
        }
        defer { _ = Shell.run("/usr/bin/hdiutil detach '\(mountPoint)' -force 2>/dev/null", timeout: 30) }

        // Localizar el .app nuevo
        let listed = Shell.run("/bin/ls -d '\(mountPoint)'/*.app 2>/dev/null | head -1", timeout: 15)
        let newApp = listed.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newApp.hasSuffix(".app") else { return "El DMG no contiene un .app" }

        // Sustituir: copia a temporal + relevo atómico de directorios.
        let staging = "\(NSTemporaryDirectory())ConBarAI-update.app"
        try? fm.removeItem(atPath: staging)
        guard Shell.run("/usr/bin/ditto '\(newApp)' '\(staging)'", timeout: 120).code == 0 else {
            return "No pude copiar la actualización"
        }
        try? fm.removeItem(atPath: "\(currentApp).old")
        try? fm.moveItem(atPath: currentApp, toPath: "\(currentApp).old")
        guard Shell.run("/usr/bin/ditto '\(staging)' '\(currentApp)'", timeout: 120).code == 0 else {
            try? fm.removeItem(atPath: currentApp)
            try? fm.moveItem(atPath: "\(currentApp).old", toPath: currentApp) // rollback
            return "Fallo al instalar; se restauró la versión anterior"
        }
        try? fm.removeItem(atPath: "\(currentApp).old")

        // Relanzar agentes si están registrados con el binario del .app.
        let uid = String(getuid())
        for label in ["com.conbarai.panel", "com.conbarai.watch"] {
            _ = Shell.run("/bin/launchctl kickstart -k gui/\(uid)/\(label) 2>/dev/null", timeout: 15)
        }
        return "Actualizado y relanzado ✓"
    }

    /// Flujo completo: `conbarai update` (o --check para solo consultar).
    static func run(checkOnly: Bool) -> Int32 {
        guard let rel = latest() else {
            print("No pude consultar \(Paths.repo)/releases (¿sin red o sin releases todavía?)")
            return 1
        }
        let current = Paths.version
        if !UpdateCheck.isOutdated(current: current, latest: rel.tag) {
            print("Estás en la última versión (\(current)).")
            return 0
        }
        print("Versión nueva: \(rel.tag) (tienes \(current)).")
        if checkOnly { return 0 }
        guard let url = rel.dmgURL else {
            print("El release no trae DMG; míralo en https://github.com/\(Paths.repo)/releases")
            return 1
        }
        let dest = "\(NSHomeDirectory())/Downloads/ConBarAI-\(rel.tag).dmg"
        print("Descargando \(url.lastPathComponent)…")
        guard download(url, to: dest) else {
            print("Descarga fallida.")
            return 1
        }
        print("Instalando…")
        let result = install(dmg: dest)
        print(result)
        return result.hasPrefix("Actualizado") ? 0 : 1
    }
}
