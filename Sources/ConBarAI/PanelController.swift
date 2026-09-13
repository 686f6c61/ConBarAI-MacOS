import AppKit
import Carbon.HIToolbox

/// La "isla": una ventana sin borde a nivel statusBar, anclada al notch del MacBook.
/// Colapsada es una píldora que se esconde debajo del island; expandida se abre
/// como consola flotante con la sesión de OpenCode.
final class IslandWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        acceptsMouseMovedEvents = true
    }
}

/// Contenido con esquinas redondeadas y fondo del tema con opacidad configurada.
final class IslandContentView: NSView {
    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set {
            wantsLayer = true
            layer?.cornerRadius = newValue
            layer?.masksToBounds = true
        }
    }

    func setBackgroundColor(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}

final class PanelController: NSObject {
    let window = IslandWindow()
    private(set) var settings: Settings
    private var expanded = false
    private var hosting = false

    // Contenido
    private let root = IslandContentView()
    private let pillView = PillView()
    private let consoleView = ConsoleView()
    private let splash = SplashView()
    private var terminalHost: TerminalHost?

    // Estado de sesión
    private(set) var currentSession = "oc"
    private(set) var currentWorkdir: String

    // Refrescos
    private var pillTimer: Timer?
    private var usageTimer: Timer?
    private var lastExpandedAt = Date.distantPast
    private var pendingAutohide: DispatchWorkItem?
    /// La próxima consola arrancará con conversación nueva (pi sin -c).
    private var startFreshSession = false

    var onWantQuit: (() -> Void)?
    var onSettingsChanged: ((Settings) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        let state = SessionState.load()
        currentWorkdir = state.lastWorkdir.isEmpty ? Sessions.defaultWorkdir(settings: settings)
                                                   : state.lastWorkdir
        currentSession = Sessions.validated(state.lastSession) ?? "oc"
        super.init()

        window.contentView = root
        root.addSubview(pillView)
        root.addSubview(consoleView)
        root.addSubview(splash)
        // SIN ESTO la consola se queda al tamaño píldora dentro de la isla
        // expandida: la terminal vive en un tubo de 2x2 y no se ve nada.
        pillView.autoresizingMask = [.width, .height]
        consoleView.autoresizingMask = [.width, .height]
        splash.autoresizingMask = [.width, .height]
        pillView.frame = root.bounds
        consoleView.frame = root.bounds
        splash.frame = root.bounds
        splash.isHidden = true
        pillView.onTap = { [weak self] in self?.toggle() }

        // ⌘W esconde la isla (Esc queda para las TUI).
        // ⌘N/⌘K = conversación nueva: pi repinta su historial desde memoria en
        // cuanto recibe input, así que "limpiar pantalla" sin sesión nueva no
        // persiste — el atajo de clear clásico (⌘K) también abre sesión nueva.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.expanded, event.window === self.window,
                  event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers else { return event }
            if ProcessInfo.processInfo.environment["CONBARAI_DEBUG"] == "1" {
                NSLog("conbarai key: ⌘\(key)")
            }
            if key == "w" {
                self.collapse()
                return nil
            }
            if key == "n" || key == "k" {
                self.newSession()
                return nil
            }
            return event
        }

        applyTheme()
        layoutCollapsed(immediately: true)

        NSApp.activate(ignoringOtherApps: false)
        window.orderFrontRegardless()

        // Autoocultar cuando el foco se va a otra app (paridad con autohide=True).
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
        // Cambios de modelo desde Ajustes → relevo de consola al momento.
        NotificationCenter.default.addObserver(self, selector: #selector(modelChanged),
                                               name: .init("conbarai.modelChanged"), object: nil)
        startPillPolling()

        // Precalentado general: pi nace desacoplado (100×30) un segundo tras
        // arrancar el panel; abrir la isla es instantáneo y el banner nace íntegro.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            Tmux.prewarmDetached(session: self.currentSession, workdir: self.currentWorkdir,
                                 settings: self.settings)
        }

        // Modo prueba: precalienta, despliega y se fotografía a sí mismo.
        if let snap = ProcessInfo.processInfo.environment["CONBARAI_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.expand()
            }
            // El splash dura ~1,2 s desde el expand: captura a mitad.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { [weak self] in
                self?.snapshot(to: snap.replacingOccurrences(of: ".png", with: "-splash.png"))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.8) { [weak self] in
                self?.expand() // por si algo la plegó
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.snapshot(to: snap) // ya con la isla abierta del todo
                }
            }
        }

        // Autotest visual: A (conversación en curso) → sintetiza ⌘N real →
        // B (tras nueva sesión) → simula Enter → C (¿queda limpio de verdad?).
        if ProcessInfo.processInfo.environment["CONBARAI_AUTOTEST"] == "new" {
            let stamp = Int(Date().timeIntervalSince1970)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.ensureTerminal()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.expand()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
                self?.snapshot(to: "/tmp/cba-\(stamp)-A-antes.png")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { [weak self] in
                self?.synthesizeCommandKey("n")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) { [weak self] in
                self?.snapshot(to: "/tmp/cba-\(stamp)-B-tras-nueva.png")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                self?.terminalHost?.terminal.send(txt: "\r")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 17.0) { [weak self] in
                self?.snapshot(to: "/tmp/cba-\(stamp)-C-tras-enter.png")
            }
        }
    }

    /// Sintetiza ⌘<tecla> contra NUESTRO proceso: no requiere permisos TCC
    /// y pasa por el mismo monitor local que las teclas de verdad.
    private func synthesizeCommandKey(_ key: String) {
        let code: CGKeyCode
        switch key {
        case "k": code = CGKeyCode(kVK_ANSI_K)
        case "n": code = CGKeyCode(kVK_ANSI_N)
        default: return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) {
            down.flags = .maskCommand
            down.postToPid(pid)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
            up.flags = .maskCommand
            up.postToPid(pid)
        }
    }

    /// Captura de NUESTRA propia vista renderizando su capa a un contexto
    /// propio: sin TCC y sin posibilidad de píxeles ajenos.
    private func snapshot(to path: String) {
        let scale: CGFloat = 2
        let w = Int(root.bounds.width * scale), h = Int(root.bounds.height * scale)
        guard w > 0, h > 0, let layer = root.layer,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            NSLog("conbarai snapshot: contexto inválido bounds=\(root.bounds)")
            return
        }
        ctx.scaleBy(x: scale, y: scale)
        // La isla es translúcida: fondo negro para que la captura sea legible.
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(root.bounds)
        layer.render(in: ctx)
        guard let cg = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("conbarai snapshot: \(path) (\(cg.width)×\(cg.height))")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func modelChanged() {
        settings = Settings.load()
        terminalHost?.apply(theme: Theme.byName(settings.theme), settings: settings)
        if expanded { restartConsole() }
    }

    @objc private func appDidResignActive() {
        guard settings.autohide, expanded else { return }
        pendingAutohide?.cancel()
        // Recién abierta (<1s): aunque roben el foco, se queda abierta.
        guard Date().timeIntervalSince(lastExpandedAt) > 1.0 else { return }
        // Debounce de 0,8s: si recuperamos el foco en ese margen, no esconder.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.expanded, self.settings.autohide else { return }
            if NSApp.isActive || self.window.isKeyWindow { return }
            if ProcessInfo.processInfo.environment["CONBARAI_DEBUG"] == "1" {
                NSLog("conbarai autohide: escondo (perdí el foco y no volvió)")
            }
            self.collapse()
        }
        pendingAutohide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Geometría del notch

    /// Pantalla con notch (la integrada); si no hay, la principal.
    private func anchorScreen() -> NSScreen {
        let screens = NSScreen.screens
        return screens.first { screenHasNotch($0) } ?? NSScreen.main ?? screens.first ?? NSScreen()
    }

    private func screenHasNotch(_ s: NSScreen) -> Bool {
        s.safeAreaInsets.top > 0 || s.auxiliaryTopLeftArea != nil || s.auxiliaryTopRightArea != nil
    }

    /// Altura de la zona superior ocupada por menu bar + notch.
    private func topBarHeight(_ s: NSScreen) -> CGFloat {
        max(s.safeAreaInsets.top, s.auxiliaryTopLeftArea?.height ?? 0, 24)
    }

    /// Ancho del notch real de la pantalla, nil si no tiene.
    private func notchWidth(_ s: NSScreen) -> CGFloat? {
        guard let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return nil }
        let w = s.frame.width - l.width - r.width
        return (40...400).contains(w) ? w : nil
    }

    /// Píldora colapsada. Con notch se esconde DENTRO de la zona del island
    /// (negro sobre negro: no se ve); sin notch, píldora clásica bajo la barra.
    /// Con aviso pendiente, asoma una franja de 16pt con el punto ámbar.
    private func pillFrame(on s: NSScreen, revealAlert: Bool = false) -> NSRect {
        let bar = topBarHeight(s)
        if let nw = notchWidth(s) {
            let h = bar + (revealAlert ? 16 : 0)
            // Borde superior fijo en el top de la pantalla: crece hacia abajo.
            return NSRect(x: s.frame.midX - nw / 2, y: s.frame.maxY - h, width: nw, height: h)
        }
        let w: CGFloat = 160
        let h: CGFloat = 28
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - bar - h, width: w, height: h)
    }

    private func expandedFrame(on s: NSScreen) -> NSRect {
        let w = settings.width * s.frame.width
        let h = settings.height * s.frame.height
        let x = s.frame.midX - w / 2
        // La isla "se abre" casi pegada al notch: parece que el island crece.
        let top = s.frame.maxY - topBarHeight(s) - 6
        return NSRect(x: x, y: top - h, width: w, height: h)
    }

    // MARK: - Estados

    var isExpanded: Bool { expanded }

    func toggle() { expanded ? collapse() : expand() }

    func expand() {
        guard !expanded else { return }
        expanded = true
        lastExpandedAt = Date()
        pendingAutohide?.cancel()
        // App .accessory: activar ANTES de mostrar, y la ventana key de una vez.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        ensureTerminal()
        focusTerminal()
        // Firma de la casa: splash al abrir, se desvanece solo.
        splash.present(theme: Theme.byName(settings.theme))
        animate(to: expandedFrame(on: anchorScreen()), corner: 22) { [weak self] in
            guard let self else { return }
            // Segundo empujón: la activación de apps accessory a veces tarda.
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            self.window.makeKey()
            self.focusTerminal()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.splash.dismiss()
            }
            // Al abrir se limpia el aviso de esa sesión, como en Ubuntu.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.expanded else { return }
                Alerts.clear(session: self.currentSession)
                self.refreshAlertDots()
            }
        }
        startUsagePolling()
        refreshUsage()
    }

    /// El teclado debe caer en la terminal, no en la ventana vacía.
    private func focusTerminal() {
        guard let host = terminalHost else { return }
        window.initialFirstResponder = host.terminal
        let ok = window.makeFirstResponder(host.terminal)
        if ProcessInfo.processInfo.environment["CONBARAI_DEBUG"] == "1" {
            NSLog("conbarai focus: ok=\(ok) key=\(window.isKeyWindow) active=\(NSApp.isActive) resp=\(window.firstResponder.debugDescription)")
        }
    }

    func collapse() {
        guard expanded else { return }
        expanded = false
        splash.dismiss(immediately: true)
        stopUsagePolling()
        animate(to: pillFrame(on: anchorScreen()), corner: 12, focusBack: true) { [weak self] in
            // Desprender el cliente tmux: sin cliente pegado con tamaño píldora,
            // el pane conserva su tamaño sano y el scrollback no se tritura.
            // pi sigue vivo en el servidor; el próximo expand re-engancha.
            self?.detachClient()
        }
    }

    private func detachClient() {
        guard let host = terminalHost else { return }
        host.onTerminated = nil // detach intencionado: sin aviso de "sesión muerta"
        host.terminal.terminate()
        terminalHost = nil
    }

    private func animate(to frame: NSRect, corner: CGFloat, focusBack: Bool = false,
                         completion: (() -> Void)? = nil) {
        let showConsole = expanded
        let showPill = !expanded && settings.island_pill
        if showConsole { consoleView.isHidden = false }
        if showPill { pillView.isHidden = false }
        setBackground(collapsed: !expanded)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
            pillView.animator().alphaValue = showPill ? 1 : 0
            consoleView.animator().alphaValue = showConsole ? 1 : 0
            root.cornerRadius = corner
        }, completionHandler: {
            self.pillView.isHidden = !showPill
            self.consoleView.isHidden = !showConsole
            if !showConsole && !showPill {
                // Sin píldora, colapsada = invisible del todo (nada que se coma clics).
                self.window.orderOut(nil)
            }
            if focusBack { NSApp.deactivate() }
            completion?()
        })
    }

    private func layoutCollapsed(immediately: Bool) {
        let f = pillFrame(on: anchorScreen())
        if immediately {
            window.setFrame(f, display: true)
            root.cornerRadius = 12
            consoleView.isHidden = true
            pillView.isHidden = !settings.island_pill
            setBackground(collapsed: true)
        }
    }

    // MARK: - Terminal y sesiones

    private func ensureTerminal() {
        guard terminalHost == nil else { return }
        install(session: currentSession, workdir: currentWorkdir)
    }

    private func install(session: String, workdir: String) {
        detachClient() // mata al cliente tmux, la sesión sigue viva
        // La carpeta por defecto se crea si no existe; las elegidas a mano ya existen.
        try? FileManager.default.createDirectory(atPath: workdir, withIntermediateDirectories: true)
        let host = TerminalHost(session: session, workdir: workdir, settings: settings,
                                fresh: startFreshSession)
        startFreshSession = false
        host.onTerminated = { [weak self] _ in
            // La sesión "está muerta" pero remain-on-exit la conserva visible para reiniciar.
            self?.consoleView.showDeadHint()
        }
        consoleView.installTerminal(host)
        terminalHost = host
        currentSession = session
        currentWorkdir = workdir
        SessionState(lastSession: session, lastWorkdir: workdir).save()
        consoleView.setHeader(session: session, workdir: workdir)
        SkillInstaller.linkInto(workdir: workdir)
        PiConfig.ensureQuietStartup(workdir: workdir)
        if expanded { focusTerminal() }
        refreshUsage()
    }

    /// Cambia de carpeta/sesión desde el tray.
    func switchTo(workdir: String) {
        let session = Sessions.session(forWorkdir: workdir, settings: settings)
        install(session: session, workdir: workdir)
        SkillInstaller.linkInto(workdir: workdir)
        if !expanded { expand() }
    }

    func restartConsole() {
        detachClient()
        consoleView.hideDeadHint()
        if expanded { ensureTerminal() } else { expand() }
    }

    /// Conversación nueva en la misma carpeta: consola limpia.
    /// La conversación anterior no se pierde: dentro de pi, `pi -r` la recupera.
    func newSession() {
        Tmux.killSession(currentSession)
        startFreshSession = true
        restartConsole()
        // Cero residuos: la pantalla se borra también a la fuerza tras el relevo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.clearScreen()
        }
    }

    /// Borra pantalla Y scrollback; el agente y su conversación siguen intactos.
    func clearScreen() {
        // ESC[H ESC[2J ESC[3J: cursor a casa, limpiar pantalla, limpiar scrollback.
        terminalHost?.terminal.feed(text: "\u{1b}[H\u{1b}[2J\u{1b}[3J")
    }

    func killCurrentSession() {
        Tmux.killSession(currentSession)
        restartConsole()
    }

    // MARK: - Ajustes en vivo

    func update(settings newSettings: Settings) {
        settings = newSettings
        applyTheme()
        if expanded {
            window.setFrame(expandedFrame(on: anchorScreen()), display: true, animate: true)
        } else {
            window.setFrame(pillFrame(on: anchorScreen(), revealAlert: !Alerts.present().isEmpty),
                            display: true, animate: true)
            pillView.isHidden = !settings.island_pill
        }
        terminalHost?.apply(theme: Theme.byName(settings.theme), settings: settings)
        HotKeyCenter.shared.register(raw: settings.keybinding) { [weak self] in self?.toggle() }
        onSettingsChanged?(settings)
    }

    private func applyTheme() {
        let theme = Theme.byName(settings.theme)
        consoleView.apply(theme: theme)
        pillView.apply(theme: theme)
        pillView.isTucked = notchWidth(anchorScreen()) != nil
        setBackground(collapsed: !expanded)
    }

    /// Colapsada con notch: negro puro (invisible sobre el island).
    /// En cualquier otro caso, el fondo del tema con la opacidad configurada.
    private func setBackground(collapsed: Bool) {
        let theme = Theme.byName(settings.theme)
        let tucked = notchWidth(anchorScreen()) != nil
        func color(_ hex: UInt32, alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        }
        if collapsed && tucked {
            root.setBackgroundColor(.black)
        } else {
            root.setBackgroundColor(color(theme.bg, alpha: max(settings.opacity, 0.55)))
        }
    }

    // MARK: - Sondeos (avisos y uso)

    private func startPillPolling() {
        pillTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAlertDots()
        }
    }

    private func refreshAlertDots() {
        let alerts = Alerts.present()
        let mine = alerts.contains(currentSession)
        pillView.setAlert(active: mine || !alerts.isEmpty, count: alerts.count)
        consoleView.setAlert(active: mine, count: alerts.count)
        // Colapsada con notch: con aviso asoma la franja del punto; sin aviso vuelve
        // a esconderse del todo dentro del island.
        if !expanded, window.isVisible, settings.island_pill,
           notchWidth(anchorScreen()) != nil {
            let target = pillFrame(on: anchorScreen(), revealAlert: !alerts.isEmpty)
            if !NSEqualRects(window.frame, target) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.allowsImplicitAnimation = true
                    window.animator().setFrame(target, display: true)
                }
            }
        }
    }

    private func startUsagePolling() {
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func stopUsagePolling() {
        usageTimer?.invalidate()
        usageTimer = nil
    }

    private func refreshUsage() {
        consoleView.setUsage(Usage.forDirectory(currentWorkdir))
    }
}

/// Splash de la casa: "Console Bar AI — by 686f6c61" al abrir la isla.
/// Vive en la UI de la isla, no en el terminal: pi borra el scrollback al
/// redimensionarse y cualquier banner impreso moriría en el primer resize.
final class SplashView: NSView {
    private let title = NSTextField(labelWithString: "Console Bar AI")
    private let byline = NSTextField(labelWithString: "")
    private var appliedTheme = Theme.tokyoNight

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.alignment = .center
        byline.font = .systemFont(ofSize: 12, weight: .regular)
        byline.textColor = .white.withAlphaComponent(0.65)
        byline.alignment = .center
        addSubview(title)
        addSubview(byline)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func present(theme: Theme) {
        appliedTheme = theme
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        title.textColor = color(theme.accent)
        byline.stringValue = "by 686f6c61 · v\(Paths.version) · \(theme.name)"
        alphaValue = 0
        isHidden = false
        needsLayout = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 1
        }
    }

    func dismiss(immediately: Bool = false) {
        if immediately {
            isHidden = true
            alphaValue = 0
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            self.animator().alphaValue = 0
        }, completionHandler: {
            if self.alphaValue == 0 { self.isHidden = true }
        })
    }

    override func layout() {
        super.layout()
        title.sizeToFit()
        byline.sizeToFit()
        let total = title.frame.height + 8 + byline.frame.height
        title.frame.origin = NSPoint(x: (bounds.width - title.frame.width) / 2,
                                     y: bounds.midY + total / 2 - title.frame.height)
        byline.frame.origin = NSPoint(x: (bounds.width - byline.frame.width) / 2,
                                      y: bounds.midY + total / 2 - title.frame.height - 8 - byline.frame.height)
    }
}

/// Píldora colapsada. En modo "tucked" vive dentro de la zona negra del notch:
/// sin avisos no se ve nada; con aviso asoma un punto ámbar bajo el island.
final class PillView: NSView {
    var onTap: (() -> Void)?
    private let dot = NSView()
    private let badge = NSTextField(labelWithString: "")
    private var theme = Theme.tokyoNight
    private var alertActive = false

    /// true cuando la píldora está metida en la zona del notch (pantallas con island).
    var isTucked = false {
        didSet { needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.isHidden = true
        addSubview(dot)
        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .white
        badge.isHidden = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onTap?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    func apply(theme: Theme) { self.theme = theme }

    func setAlert(active: Bool, count: Int) {
        alertActive = active
        dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
        dot.layer?.cornerRadius = active ? 5 : 4
        dot.isHidden = !active
        if active, count > 1 {
            badge.stringValue = "\(count)"
            badge.isHidden = false
        } else {
            badge.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard alertActive else { return }
        let dotSize: CGFloat = 10
        // Tucked: el punto va en la franja inferior (lo único que asoma del notch).
        let centerY = isTucked ? 8 : bounds.midY
        dot.frame = NSRect(x: bounds.midX - dotSize / 2, y: centerY - dotSize / 2,
                           width: dotSize, height: dotSize)
        badge.sizeToFit()
        badge.frame.origin = NSPoint(x: dot.frame.maxX + 6, y: centerY - badge.frame.height / 2)
    }
}

/// Consola expandida: cabecera (sesión · uso) + terminal.
final class ConsoleView: NSView {
    private let header = NSView()
    private let brandLabel = NSTextField(labelWithString: "Console Bar AI")
    private let sessionLabel = NSTextField(labelWithString: "oc")
    private let usageLabel = NSTextField(labelWithString: "")
    private let alertDot = NSView()
    private let hintLabel = NSTextField(labelWithString: "⌘N/⌘K nueva · ⌘W esconde")
    private let deadHint = NSTextField(labelWithString: "sesión terminada — reiníciala desde el tray")
    private var hostView: NSView?
    /// Referencia viva a la terminal para devolverle el teclado con un clic.
    weak var terminalRef: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        header.wantsLayer = true
        brandLabel.font = .systemFont(ofSize: 12, weight: .bold)
        sessionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        sessionLabel.textColor = .white
        usageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        usageLabel.textColor = .white.withAlphaComponent(0.75)
        hintLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .white.withAlphaComponent(0.45)
        alertDot.wantsLayer = true
        alertDot.layer?.cornerRadius = 4
        alertDot.layer?.backgroundColor = NSColor.systemYellow.cgColor
        alertDot.isHidden = true

        deadHint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        deadHint.textColor = NSColor.systemYellow
        deadHint.alignment = .center
        deadHint.isHidden = true

        header.addSubview(brandLabel)
        header.addSubview(sessionLabel)
        header.addSubview(usageLabel)
        header.addSubview(alertDot)
        header.addSubview(hintLabel)
        addSubview(header)
        addSubview(deadHint)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Marco de la terminal con aire: nada pegado a los bordes redondeados.
    private func terminalFrame() -> NSRect {
        let headerH: CGFloat = 34
        let side: CGFloat = 10
        let bottom: CGFloat = 8
        return NSRect(x: side, y: bottom,
                      width: bounds.width - side * 2,
                      height: bounds.height - headerH - bottom - 4)
    }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 34
        header.frame = NSRect(x: 0, y: bounds.height - headerH, width: bounds.width, height: headerH)
        brandLabel.sizeToFit()
        brandLabel.frame.origin = NSPoint(x: 14, y: (headerH - brandLabel.frame.height) / 2)
        sessionLabel.sizeToFit()
        sessionLabel.frame.origin = NSPoint(x: brandLabel.frame.maxX + 10,
                                            y: (headerH - sessionLabel.frame.height) / 2)
        alertDot.frame = NSRect(x: sessionLabel.frame.maxX + 8, y: (headerH - 8) / 2, width: 8, height: 8)
        hintLabel.sizeToFit()
        hintLabel.frame.origin = NSPoint(x: bounds.width - hintLabel.frame.width - 14,
                                         y: (headerH - hintLabel.frame.height) / 2)
        usageLabel.sizeToFit()
        usageLabel.frame.origin = NSPoint(x: hintLabel.frame.minX - usageLabel.frame.width - 14,
                                          y: (headerH - usageLabel.frame.height) / 2)
        hostView?.frame = terminalFrame()
        deadHint.frame = NSRect(x: 0, y: 10, width: bounds.width, height: 18)
    }

    /// Clic en cualquier parte de la consola (cabecera incluida) = teclado
    /// de vuelta a la terminal, aunque la activación automática haya fallado.
    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let t = terminalRef { window?.makeFirstResponder(t) }
        super.mouseDown(with: event)
    }

    func installTerminal(_ host: TerminalHost) {
        hostView?.removeFromSuperview()
        hostView = host
        terminalRef = host.terminal
        addSubview(host)
        host.frame = terminalFrame()
        host.needsLayout = true
        deadHint.isHidden = true
    }

    func setHeader(session: String, workdir: String) {
        let folder = (workdir as NSString).lastPathComponent
        sessionLabel.stringValue = folder.isEmpty ? session : "\(session) · \(folder)"
    }

    func setUsage(_ usage: Usage.Totals?) {
        usageLabel.stringValue = usage.map { "\($0.shortTokens) tok · \($0.shortCost)" } ?? ""
        needsLayout = true
    }

    func setAlert(active: Bool, count: Int) {
        alertDot.isHidden = !active
    }

    func showDeadHint() { deadHint.isHidden = false }
    func hideDeadHint() { deadHint.isHidden = true }

    func apply(theme: Theme) {
        header.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        brandLabel.textColor = color(theme.accent)
    }
}
