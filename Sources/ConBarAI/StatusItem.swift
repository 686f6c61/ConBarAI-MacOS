import AppKit
import Carbon.HIToolbox

/// Icono en la barra de menús con el menú de ConBarAI (equivalente del tray Ayatana).
final class StatusItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private weak var panel: PanelController?
    private var settings: Settings

    init(panel: PanelController, settings: Settings) {
        self.panel = panel
        self.settings = settings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button, let img = NSImage(systemSymbolName: "terminal.fill",
                                                       accessibilityDescription: "ConBarAI") {
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu: menu)
    }

    private func rebuild(menu: NSMenu) {
        menu.removeAllItems()
        guard let panel else { return }
        settings = Settings.load()
        let hotkey = HotKey.display(settings.keybinding)

        menu.addItem(title: "Mostrar/ocultar consola  \(hotkey)") { panel.toggle() }
        menu.addItem(title: "Nueva sesión en carpeta…") { [weak self] in self?.pickWorkdir() }
        menu.addItem(NSMenuItem.separator())

        // Sesiones gestionadas
        let sessions = Sessions.managed()
        let sessMenu = NSMenu()
        if sessions.isEmpty {
            sessMenu.addItem(title: "(sin sesiones)") {}
            sessMenu.items.last?.isEnabled = false
        } else {
            for s in sessions {
                sessMenu.addItem(title: (s == panel.currentSession ? "● " : "○ ") + s) { [weak self] in
                    self?.switchToSession(s)
                }
            }
        }
        menu.addItem(title: "Sesiones", submenu: sessMenu)
        menu.addItem(title: "Conversación nueva  ⌘N/⌘K") { panel.newSession() }
        menu.addItem(title: "Reiniciar agente (misma conversación)") { panel.restartConsole() }
        menu.addItem(title: "Cerrar sesión actual (tmux)") { panel.killCurrentSession() }
        menu.addItem(NSMenuItem.separator())

        let info = NSMenuItem(title: "Carpeta de trabajo: \(shortPath(panel.currentWorkdir))", action: {})
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(title: "Cambiar carpeta de trabajo…") { [weak self] in self?.pickWorkdir() }
        menu.addItem(NSMenuItem.separator())

        // Ajustes
        let adj = NSMenu()
        adj.addItem(check: "Autoocultar al perder foco", on: settings.autohide) { [weak self] on in
            self?.mutate { $0.autohide = on }
        }
        adj.addItem(check: "Píldora bajo el island", on: settings.island_pill) { [weak self] on in
            self?.mutate { $0.island_pill = on }
        }
        let themes = NSMenu()
        for t in Theme.all {
            themes.addItem(check: t, on: t == settings.theme) { [weak self] _ in
                self?.mutate { $0.theme = t }
            }
        }
        adj.addItem(title: "Tema", submenu: themes)
        let opMenu = NSMenu()
        for pct in [60, 70, 80, 90, 100] {
            opMenu.addItem(check: "\(pct)%", on: abs(settings.opacity * 100 - Double(pct)) < 2.5) { [weak self] _ in
                self?.mutate { $0.opacity = Double(pct) / 100 }
            }
        }
        adj.addItem(title: "Opacidad", submenu: opMenu)
        adj.addItem(check: "Vigilar crashes", on: settings.crash_watch) { [weak self] on in
            self?.mutate { $0.crash_watch = on }
        }
        adj.addItem(check: "Analizar crashes con IA", on: settings.crash_analyze) { [weak self] on in
            self?.mutate { $0.crash_analyze = on }
        }
        adj.addItem(check: "Cargar tus extensiones de pi", on: settings.loadGlobalExtensions) { [weak self] on in
            self?.mutate { $0.agent_extensions = on }
            self?.panel?.restartConsole()
        }
        adj.addItem(title: "Cambiar atajo…  \(hotkey)") { [weak self] in
            HotKeyRecorder.begin { [weak self] combo in
                guard let self, let combo else { return }
                self.mutate { $0.keybinding = combo }
            }
        }
        let agentMenu = NSMenu()
        for (label, value) in [("Automático (pi si está)", "auto"), ("Pi (ligero)", "pi"), ("OpenCode", "opencode")] {
            let current = settings.agent ?? "auto"
            agentMenu.addItem(check: label, on: current == value) { [weak self] _ in
                self?.mutate { $0.agent = value }
                // Reinicio de consola para que el nuevo agente arranque limpio.
                self?.panel?.restartConsole()
            }
        }
        adj.addItem(title: "Agente", submenu: agentMenu)
        adj.addItem(title: "Proveedores y modelos…") {
            ProviderSettingsWindow.shared.show()
        }
        let sizeMenu = NSMenu()
        for (label, w) in [("Compacto 38%", 0.38), ("Normal 45%", 0.45), ("Amplio 55%", 0.55), ("Enorme 70%", 0.70)] {
            sizeMenu.addItem(check: label, on: abs(settings.width - w) < 0.01) { [weak self] _ in
                self?.mutate { s in
                    s.width = w
                    s.height = min(0.95, w + 0.18)
                }
            }
        }
        adj.addItem(title: "Tamaño de la isla", submenu: sizeMenu)
        menu.addItem(title: "Ajustes", submenu: adj)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(title: "Ayuda (man conbarai)") { HelpWindow.show() }
        menu.addItem(title: "Comprobar actualizaciones") { [weak self] in self?.checkUpdates() }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(title: "Salir de ConBarAI") { NSApp.terminate(nil) }
    }

    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: Paths.home, with: "~")
    }

    private func switchToSession(_ session: String) {
        // La sesión existe en tmux: se rescata su carpeta registrada o la de defecto.
        let dir = SessionState.load()
        let workdir = (session == Sessions.session(forWorkdir: dir.lastWorkdir, settings: settings))
            ? dir.lastWorkdir : Sessions.defaultWorkdir(settings: settings)
        panel?.switchTo(workdir: workdir)
    }

    private func pickWorkdir() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.message = "Carpeta para la sesión de OpenCode"
        if open.runModal() == .OK, let url = open.url {
            panel?.switchTo(workdir: url.path)
        }
    }

    private func mutate(_ change: (inout Settings) -> Void) {
        var s = Settings.load()
        change(&s)
        s.clamp()
        s.save()
        panel?.update(settings: s)
    }

    private func checkUpdates() {
        DispatchQueue.global().async {
            guard let latest = UpdateCheck.latestVersion() else {
                Shell.notify("No pude comprobar actualizaciones")
                return
            }
            guard UpdateCheck.isOutdated(current: Paths.version, latest: latest) else {
                Shell.notify("Estás en la última versión (\(Paths.version))")
                return
            }
            // Como el AppImage de Ubuntu: se descarga e instala solo.
            Shell.notify("Actualizando a \(latest)…")
            let bin = Paths.selfBinaryPath()
            let ok = Shell.spawnDetached(bin, ["update"])
            if !ok { Shell.notify("No pude lanzar la actualización — ejecuta: conbarai update") }
        }
    }
}

/// Ventana que captura la siguiente combinación de teclas para el atajo global.
final class HotKeyRecorder {
    private static var panel: NSPanel?
    private static var monitor: Any?
    private static var completion: ((String?) -> Void)?

    static func begin(completion: @escaping (String?) -> Void) {
        guard panel == nil else { return }
        self.completion = completion

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Nuevo atajo para ConBarAI"
        p.isFloatingPanel = true
        p.level = .floating
        let label = NSTextField(wrappingLabelWithString:
            "Pulsa la combinación deseada (con ⌘, ⌥, ⌃ o ⇧).\nEsc para cancelar. Evita ⌘Return: se lo robarías a Mail.")
        label.alignment = .center
        label.frame = NSRect(x: 16, y: 20, width: 348, height: 80)
        p.contentView?.addSubview(label)
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                finish(nil)
                return nil
            }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Al menos un modificador fuerte (⌘/⌥/⌃); ⇧ sola no registra atajo global.
            guard !mods.intersection([.command, .option, .control]).isEmpty,
                  let combo = HotKey.string(from: event) else { return event }
            finish(combo)
            return nil
        }
    }

    private static func finish(_ combo: String?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.close()
        panel = nil
        completion?(combo)
        completion = nil
    }
}

/// Manual integrado estilo man page, como el de la versión Ubuntu.
final class HelpWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "conbarai(1)"
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let text = NSTextView()
        text.isEditable = false
        text.isRichText = false
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = Help.manual
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        w.contentView = scroll
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

extension NSMenu {
    @discardableResult
    func addItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action)
        addItem(item)
        return item
    }

    @discardableResult
    func addItem(check title: String, on: Bool, action: @escaping (Bool) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title) {}
        item.actionClosure = { action(item.state != .on) }
        item.state = on ? .on : .off
        addItem(item)
        return item
    }

    @discardableResult
    func addItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: {})
        item.submenu = submenu
        addItem(item)
        return item
    }
}

extension NSMenuItem {
    convenience init(title: String, action: @escaping () -> Void) {
        self.init(title: title, action: nil, keyEquivalent: "")
        self.actionClosure = action
        target = self
        self.action = #selector(invokeClosure)
    }
}

private extension NSMenuItem {
    static var associatedClosureKey: UInt8 = 0

    var actionClosure: (() -> Void)? {
        get { objc_getAssociatedObject(self, &NSMenuItem.associatedClosureKey) as? () -> Void }
        set { objc_setAssociatedObject(self, &NSMenuItem.associatedClosureKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    @objc func invokeClosure() { actionClosure?() }
}
