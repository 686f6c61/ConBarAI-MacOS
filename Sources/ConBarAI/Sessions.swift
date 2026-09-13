import Foundation

/// Lógica de sesiones tmux, portada 1:1 de oc_common.py.
enum Sessions {
    static let sessionRegex = "^[a-z0-9][a-z0-9_-]{0,47}$"
    static let defaultSession = "oc"

    /// Nombre de sesión válido o nada. Nunca interpolar una sesión sin pasar por aquí.
    static func validated(_ name: String) -> String? {
        name.range(of: sessionRegex, options: .regularExpression) != nil ? name : nil
    }

    /// Carpeta de trabajo por defecto: ajuste explícito → ~/Documents/ConBarAI → ~.
    static func defaultWorkdir(settings: Settings) -> String {
        if !settings.workdir.isEmpty { return NSString(string: settings.workdir).expandingTildeInPath }
        let docs = "\(Paths.home)/Documents"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: docs, isDirectory: &isDir), isDir.boolValue {
            return "\(docs)/ConBarAI"
        }
        return Paths.home
    }

    /// Slug del nombre de carpeta: minúsculas, no-alfanuméricos → guion.
    static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        return out.isEmpty ? "sesion" : String(out.prefix(48))
    }

    /// Sesión tmux para una carpeta: "oc" si es la carpeta por defecto, "oc-<slug>" si no.
    static func session(forWorkdir workdir: String, settings: Settings) -> String {
        let resolved = NSString(string: workdir).expandingTildeInPath
        let def = defaultWorkdir(settings: settings)
        if resolved == def || resolved == NSString(string: def).resolvingSymlinksInPath { return defaultSession }
        let base = (resolved as NSString).lastPathComponent
        return "\(defaultSession)-\(slug(base))"
    }

    /// Lista de sesiones gestionadas por ConBarAI en el socket dedicado.
    static func managed() -> [String] {
        guard let tmux = Shell.tmuxPath() else { return [] }
        let r = Shell.run("'\(tmux)' -L \(Paths.socketName) ls -F '#{session_name}' 2>/dev/null", timeout: 5)
        guard r.code == 0 else { return [] }
        return r.out.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix(defaultSession) && validated($0) != nil }
            .sorted()
    }
}

/// Marcadores de atención (equivalente del hook alert-bell de la versión Ubuntu).
/// "quiet" solo marca (actividad del agente); sin él, además notifica (campana).
enum Alerts {
    static func mark(session: String, quiet: Bool = false) {
        guard Sessions.validated(session) != nil else { return }
        Paths.ensureStateDirs()
        let path = "\(Paths.alertsDir)/\(session).alert"
        FileManager.default.createFile(atPath: path, contents: Data(),
                                       attributes: [.posixPermissions: 0o600])
        if !quiet {
            Shell.notify("La sesión \(session) quiere tu atención", title: "ConBarAI")
        }
    }

    static func present() -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: Paths.alertsDir) else { return [] }
        return names.filter { $0.hasSuffix(".alert") }.map { String($0.dropLast(6)) }.sorted()
    }

    static func clear(session: String) {
        guard Sessions.validated(session) != nil else { return }
        try? FileManager.default.removeItem(atPath: "\(Paths.alertsDir)/\(session).alert")
    }
}
