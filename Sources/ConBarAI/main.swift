import AppKit

// MARK: - Arranque de la app de la isla

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: PanelController?
    var statusItem: StatusItem?
    var initialSettings: Settings

    init(settings: Settings) { self.initialSettings = settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Primer arranque del .app del DMG: auto-instalación (agentes, skills, link).
        if Updater.installedAppPath() != nil,
           !FileManager.default.fileExists(atPath: "\(Paths.stateDir)/.setup-done") {
            _ = Setup.run(leaveLoaded: false)
        }
        panel = PanelController(settings: initialSettings)
        statusItem = StatusItem(panel: panel!, settings: initialSettings)
        HotKeyCenter.shared.register(raw: initialSettings.keybinding) { [weak self] in
            self?.panel?.toggle()
        }
        if initialSettings.update_check {
            DispatchQueue.global().async {
                if let latest = UpdateCheck.latestVersion(),
                   UpdateCheck.isOutdated(current: Paths.version, latest: latest) {
                    Shell.notify("Versión nueva disponible: \(latest) (tienes \(Paths.version))")
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregister()
        // Desprender a nuestros clientes tmux con elegancia: las sesiones siguen,
        // pero sin huérfanos achicando el pane para el próximo arranque.
        if let tmux = Shell.tmuxPath() {
            _ = Shell.run("\(Shell.shQuote(tmux)) -L \(Paths.socketName) detach-client -a 2>/dev/null", timeout: 5)
        }
    }
}

func runPanelApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate(settings: Settings.load())
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // sin icono en el Dock; vive en el tray y el island
    app.run()
}

// MARK: - CLI

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "panel"

switch cmd {
case "panel", "app":
    runPanelApp()
case "watch":
    CrashWatcher.runForever()
case "crash-run":
    CrashAnalyzer.cli(args)
case "alert":
    guard args.count > 2 else { print("uso: conbarai alert <sesión> [quiet]"); exit(64) }
    Alerts.mark(session: args[2], quiet: args.count > 3 && args[3] == "quiet")
case "usage":
    let dir = args.count > 2 ? args[2] : FileManager.default.currentDirectoryPath
    if let u = Usage.forDirectory(dir) {
        print("\(dir): \(u.tokensTotal) tokens (\(u.tokensIn) in / \(u.tokensOut) out), coste \(String(format: "$%.4f", u.cost))")
    } else {
        print("Sin datos de uso para \(dir) (¿existe \(Paths.opencodeDB)?)")
        exit(1)
    }
case "mute", "unmute":
    guard args.count > 2 else { print("uso: conbarai \(cmd) <programa>"); exit(64) }
    CrashWatcher.setMuted(args[2], muted: cmd == "mute")
    print(cmd == "mute" ? "Avisos de \(args[2]) silenciados" : "Avisos de \(args[2]) reactivados")
case "providers":
    print("Proveedores configurables (claves en \(KeyStore.path), 0600):")
    let stored = KeyStore.all()
    let model = Settings.load().resolvedModel
    for p in Providers.all {
        let has = stored[p.keyEnv] != nil
        print("  \(p.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(has ? "✓ clave" : "— sin clave")   \(p.keyEnv)")
    }
    print("Modelo predeterminado: \(model)")
    print("Configúralo en el tray → Ajustes → «Proveedores y modelos…»")
case "settings":
    // Abre la ventana de proveedores/modelos sin buscar el tray.
    setenv("CONBARAI_SETTINGS_STANDALONE", "1", 1)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    ProviderSettingsWindow.shared.show()
    app.run()
case "occonfig":
    Paths.ensureStateDirs()
    let panel = OpenCodeConfig.ensurePanelConfig()
    let crash = OpenCodeConfig.ensureCrashConfig()
    let piOK = PiConfig.ensureNaNProvider()
    Tmux.ensureSetup()
    OpenCodeConfig.propagateToTmux()
    print("agente           : \(Agent.resolve(setting: nil).map { $0.rawValue } ?? "ninguno (instala pi u opencode)")")
    print("pi models.json   : \(piOK ? "NaN fusionado (\(PiConfig.modelsFile))" : "no pude escribir models.json")")
    print("config opencode  : \(panel) + \(crash) (respaldo)")
    print("tmux del panel   : OPENCODE_CONFIG + NAN_API_KEY exportados")
    print(OpenCodeConfig.apiKey() != nil
          ? "API key         : presente (\(OpenCodeConfig.authPath))"
          : "API key         : FALTA — guardala con: printf 'sk-…' | conbarai key set")
case "key":
    let sub = args.count > 2 ? args[2] : ""
    switch sub {
    case "set":
        if OpenCodeConfig.installKeyFromStdin() {
            print("API key guardada en \(OpenCodeConfig.authPath) (0600)")
        } else {
            print("La key debe llegar por stdin y empezar por sk-")
            exit(1)
        }
    case "status":
        print(OpenCodeConfig.apiKey() != nil ? "API key presente" : "sin API key")
    default:
        print("uso: conbarai key set   (la key va por stdin, sin argumentos)")
        exit(64)
    }
case "setup":
    exit(Setup.run())
case "update":
    exit(Updater.run(checkOnly: args.contains("--check")))
case "skill":
    SkillInstaller.cli(args)
case "help", "--help", "-h":
    print(Help.manual)
case "--version", "version":
    print(Paths.version)
default:
    FileHandle.standardError.write("conbarai: subcomando desconocido «\(cmd)»\n\n".data(using: .utf8)!)
    print(Help.manual)
    exit(64)
}
