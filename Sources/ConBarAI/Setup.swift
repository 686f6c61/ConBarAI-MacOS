import Darwin
import Foundation

/// Primera ejecución desde el ConBarAI.app del DMG: registra LaunchAgents
/// apuntando al binario del .app, instala las skills que viajan en el bundle,
/// enlaza ~/.local/bin y deja los ajustes listos. Sin sudo, reversible con
/// uninstall.sh o `launchctl bootout`.
enum Setup {
    /// Recursos del bundle: <app>/Contents/Resources/skills/…
    static func bundledSkillsSource() -> String? {
        guard let app = Updater.installedAppPath() else { return nil }
        let dir = "\(app)/Contents/Resources/skills"
        return FileManager.default.fileExists(atPath: dir) ? dir : nil
    }

    @discardableResult
    static func run(leaveLoaded: Bool = true) -> Int32 {
        guard let app = Updater.installedAppPath() else {
            print("conbarai setup se ejecuta desde el ConBarAI.app instalado (DMG).")
            print("Para instalación desde fuentes usa: bash install.sh")
            return 1
        }
        Paths.ensureStateDirs()
        // Marca de "ya configurado": el panel del .app se auto-instala al 1er arranque.
        FileManager.default.createFile(atPath: "\(Paths.stateDir)/.setup-done",
                                       contents: Data(), attributes: [.posixPermissions: 0o600])
        let bin = "\(app)/Contents/MacOS/conbarai"
        guard FileManager.default.isExecutableFile(atPath: bin) else {
            print("Binario no encontrado en el .app")
            return 1
        }
        Paths.ensureStateDirs()

        print("▸ Skills")
        if let src = bundledSkillsSource() {
            _ = SkillInstaller.install(from: src) // copia todas al canónico
            print("  instaladas: \(Paths.bundledSkills.joined(separator: ", "))")
        } else {
            print("  el bundle no trae skills (se usarán las ya instaladas)")
        }

        print("▸ Enlace en ~/.local/bin")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: "\(NSHomeDirectory())/.local/bin",
                                withIntermediateDirectories: true)
        try? fm.removeItem(atPath: "\(NSHomeDirectory())/.local/bin/conbarai")
        do {
            try fm.createSymbolicLink(atPath: "\(NSHomeDirectory())/.local/bin/conbarai",
                                      withDestinationPath: bin)
            print("  ~/.local/bin/conbarai → \(bin)")
        } catch {
            print("  no pude crear el symlink: \(error.localizedDescription)")
        }

        print("▸ Ajustes iniciales")
        _ = Settings.load().save()
        OpenCodeConfig.ensurePanelConfig()
        OpenCodeConfig.ensureCrashConfig()
        _ = PiConfig.ensureNaNProvider()

        print("▸ LaunchAgents (autostart sin Dock)")
        let uid = String(getuid())
        let agents: [(String, String, Bool)] = [
            ("com.conbarai.panel", "panel", true),
            ("com.conbarai.watch", "watch", true),
        ]
        let agentsDir = Paths.launchAgentsDir
        try? fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        for (label, sub, keepAlive) in agents {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key>
                <array><string>\(bin)</string><string>\(sub)</string></array>
                <key>EnvironmentVariables</key>
                <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
                <key>RunAtLoad</key><true/>
                \(keepAlive ? "<key>KeepAlive</key><true/>" : "")
                <key>LimitLoadToSessionType</key><string>Aqua</string>
            </dict>
            </plist>
            """
            let path = "\(agentsDir)/\(label).plist"
            _ = Shell.run("/bin/launchctl bootout gui/\(uid)/\(label) 2>/dev/null", timeout: 10)
            fm.createFile(atPath: path, contents: plist.data(using: .utf8),
                          attributes: [.posixPermissions: 0o644])
            _ = Shell.run("/bin/launchctl bootstrap gui/\(uid) '\(path)'", timeout: 15)
            if !leaveLoaded {
                // Auto-instalación durante el arranque del panel: no duplicar
                // procesos — el agente quedará cargado en el próximo login.
                _ = Shell.run("/bin/launchctl bootout gui/\(uid)/\(label) 2>/dev/null", timeout: 10)
                print("  \(label) registrado (activo desde el próximo login)")
            } else {
                print("  \(label) activo")
            }
        }

        print("▸ Dependencias de la consola")
        let deps = Deps.current()
        if deps.allPresent {
            print("  pi + tmux listos")
        } else if isatty(0) == 1 {
            // `conbarai setup` por terminal: ofrece instalar sobre la marcha.
            _ = Deps.installInteractive()
        } else {
            // Auto-setup del primer arranque (sin TTY): la isla ofrecerá
            // instalarlas con un botón la primera vez que se abra.
            for dep in deps.missing {
                print("  falta \(dep): \(Deps.guidanceText(for: dep, status: deps))")
            }
        }

        print("""
        ConBarAI \(Paths.version) instalado ✓
          • ⌥⏎ (o clic en el notch) despliega la consola con pi.
          • Claves y modelos: menú  → Ajustes → «Proveedores y modelos…»
            (o ejecuta: conbarai settings)
          • Actualizaciones: conbarai update
        """)
        return 0
    }
}
