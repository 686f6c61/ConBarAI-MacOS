import AppKit

/// Ajustes de proveedores y modelos: claves por proveedor (almacén 0600),
/// modelos cargados EN VIVO desde la API de cada uno, y modelo por defecto.
final class ProviderSettingsWindow: NSObject, NSWindowDelegate {
    static let shared = ProviderSettingsWindow()

    private var window: NSWindow?
    private let providerPopup = NSPopUpButton()
    private let statusField = NSTextField(labelWithString: "")
    private let keyField = NSSecureTextField()
    private let saveKeyButton = NSButton(title: "Guardar clave", target: nil, action: nil)
    private let modelsPopup = NSPopUpButton()
    private let loadButton = NSButton(title: "Cargar modelos de la API", target: nil, action: nil)
    private let defaultLabel = NSTextField(labelWithString: "")
    private let setDefaultButton = NSButton(title: "Establecer como predeterminado", target: nil, action: nil)
    private let infoField = NSTextField(wrappingLabelWithString: "")
    private var fetched: [String] = []

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "ConBarAI · Proveedores y modelos"
        w.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 470))

        // Proveedor
        addLabel("Proveedor", to: root, at: NSPoint(x: 20, y: 420))
        providerPopup.frame = NSRect(x: 140, y: 416, width: 280, height: 26)
        for p in Providers.all { providerPopup.addItem(withTitle: p.name) }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        root.addSubview(providerPopup)
        statusField.font = .systemFont(ofSize: 11)
        statusField.frame = NSRect(x: 430, y: 420, width: 170, height: 20)
        root.addSubview(statusField)

        // API key
        addLabel("API key", to: root, at: NSPoint(x: 20, y: 380))
        keyField.frame = NSRect(x: 140, y: 376, width: 360, height: 24)
        keyField.placeholderString = "sk-…"
        root.addSubview(keyField)
        saveKeyButton.frame = NSRect(x: 510, y: 375, width: 90, height: 28)
        saveKeyButton.bezelStyle = .rounded
        saveKeyButton.target = self
        saveKeyButton.action = #selector(saveKey)
        root.addSubview(saveKeyButton)

        // Modelos
        addLabel("Modelos", to: root, at: NSPoint(x: 20, y: 340))
        modelsPopup.frame = NSRect(x: 140, y: 336, width: 360, height: 26)
        root.addSubview(modelsPopup)
        loadButton.frame = NSRect(x: 510, y: 334, width: 130, height: 28)
        loadButton.bezelStyle = .rounded
        loadButton.target = self
        loadButton.action = #selector(loadModels)
        root.addSubview(loadButton)

        // Predeterminado
        defaultLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        defaultLabel.frame = NSRect(x: 20, y: 300, width: 400, height: 20)
        root.addSubview(defaultLabel)
        setDefaultButton.frame = NSRect(x: 430, y: 296, width: 170, height: 28)
        setDefaultButton.bezelStyle = .rounded
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setDefault)
        root.addSubview(setDefaultButton)

        // Referencia rápida de slash + info de seguridad
        let commandsField = NSTextField(wrappingLabelWithString:
            "En la consola: /model cambia de modelo al vuelo · /new sesión nueva · /compact compacta contexto · /resume reanuda otra charla · /hotkeys todos los atajos (lista completa: conbarai help).")
        commandsField.font = .systemFont(ofSize: 10)
        commandsField.textColor = .secondaryLabelColor
        commandsField.frame = NSRect(x: 20, y: 240, width: 580, height: 50)
        root.addSubview(commandsField)

        // Info de seguridad
        infoField.font = .systemFont(ofSize: 10)
        infoField.textColor = .secondaryLabelColor
        infoField.alignment = .left
        infoField.stringValue = "Las claves se guardan en ~/.config/conbarai/auth (permisos 0600) y se inyectan por entorno; nunca van al repositorio. El modelo por defecto se aplica a la consola al reiniciarla."
        infoField.frame = NSRect(x: 20, y: 180, width: 580, height: 50)
        root.addSubview(infoField)

        w.contentView = root
        w.center()
        w.delegate = self
        window = w
        refresh()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Modo prueba: la ventana se fotografía a sí misma.
        if let snap = ProcessInfo.processInfo.environment["CONBARAI_SNAPSHOT_SETTINGS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.snapshotSelf(to: snap)
            }
        }
    }

    /// Cerrar la ventana solo mata la app cuando va en modo independiente
    /// (conbarai settings); desde el tray, el panel debe seguir vivo.
    func windowShouldClose(_ notification: Notification) -> Bool {
        if ProcessInfo.processInfo.environment["CONBARAI_SETTINGS_STANDALONE"] == "1" {
            NSApp.terminate(nil)
        }
        return true
    }

    private func snapshotSelf(to path: String) {
        guard let content = window?.contentView, let layer = content.layer else { return }
        content.wantsLayer = true
        let scale: CGFloat = 2
        let w = Int(content.bounds.width * scale), h = Int(content.bounds.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(content.bounds)
        layer.render(in: ctx)
        guard let cg = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("conbarai settings-snapshot: \(path)")
            if ProcessInfo.processInfo.environment["CONBARAI_SETTINGS_STANDALONE"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    private func addLabel(_ text: String, to view: NSView, at point: NSPoint) {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.frame.origin = point
        view.addSubview(l)
    }

    private var currentProvider: ProviderDef {
        Providers.all[max(0, providerPopup.indexOfSelectedItem)]
    }

    /// Modelos por proveedor ya cargados en esta sesión de la ventana.
    private var cache: [String: [String]] = [:]

    private func refresh() {
        let p = currentProvider
        let stored = KeyStore.key(for: p)
        statusField.stringValue = stored != nil ? "✓ clave guardada (\(KeyStore.mask(stored!)))" : "sin clave"
        keyField.stringValue = ""
        modelsPopup.removeAllItems()
        modelsPopup.addItem(withTitle: "— pulsa «Cargar modelos» —")
        fetched = []
        defaultLabel.stringValue = "Predeterminado actual: \(Settings.load().resolvedModel)"
        // Con clave guardada, los modelos se precargan solos (caché si procede).
        if stored != nil {
            autoLoadModels()
        }
    }

    @objc private func providerChanged() { refresh() }

    /// Precarga: caché → API en segundo plano. Nunca pide re-escribir la key.
    private func autoLoadModels() {
        let p = currentProvider
        if let cached = cache[p.id] {
            applyModels(cached, status: "✓ \(cached.count) modelos (de caché)")
            return
        }
        statusField.stringValue = "precargando modelos…"
        fetchInto(p) { [weak self] in
            self?.cache[p.id] = self?.fetched
        }
    }

    @objc private func saveKey() {
        let p = currentProvider
        let value = keyField.stringValue.trimmingCharacters(in: .whitespaces)
        guard value.count >= 12 else {
            statusField.stringValue = "clave demasiado corta"
            return
        }
        KeyStore.set(env: p.keyEnv, value: value)
        OpenCodeConfig.propagateToTmux()
        cache.removeValue(forKey: p.id) // clave nueva: catálogo fresco
        refresh() // refresh dispara la precarga que además valida la clave
    }

    /// Descarga (o fuerza) el catálogo y lo vuelca en el desplegable.
    private func fetchInto(_ p: ProviderDef, completion: (() -> Void)? = nil) {
        guard let key = KeyStore.key(for: p) else {
            statusField.stringValue = "guarda primero la clave"
            return
        }
        statusField.stringValue = "cargando modelos de la API…"
        loadButton.isEnabled = false
        DispatchQueue.global().async { [self] in
            let result = Providers.fetchModels(p, key: key)
            DispatchQueue.main.async { [self] in
                loadButton.isEnabled = true
                switch result {
                case .success(let models):
                    applyModels(models, status: "✓ \(models.count) modelos de la API")
                case .failure(let error):
                    // La API no listó (o la key no vale): catálogo estático.
                    applyModels(p.staticModels, status: "catálogo estático (\(error.message))")
                }
                completion?()
            }
        }
    }

    private func applyModels(_ models: [String], status: String) {
        fetched = models
        modelsPopup.removeAllItems()
        modelsPopup.addItems(withTitles: models)
        statusField.stringValue = status
    }

    @objc private func loadModels() {
        let p = currentProvider
        cache.removeValue(forKey: p.id) // botón = recarga forzada
        fetchInto(p) { [weak self] in
            self?.cache[p.id] = self?.fetched
        }
    }

    @objc private func setDefault() {
        let p = currentProvider
        guard let raw = modelsPopup.titleOfSelectedItem,
              !raw.hasPrefix("—"), fetched.contains(raw) else {
            statusField.stringValue = "carga y elige un modelo"
            return
        }
        var settings = Settings.load()
        settings.model = "\(p.id)/\(raw)"
        settings.save()
        // Registrar el proveedor en models.json de pi (con sus modelos).
        PiConfig.ensureProvider(p, models: fetched)
        defaultLabel.stringValue = "Predeterminado actual: \(settings.resolvedModel)"
        statusField.stringValue = "✓ predeterminado: \(p.id)/\(raw) — reiniciando consola…"
        // La consola arranca con --model: relevo para que aplique ya.
        NotificationCenter.default.post(name: .init("conbarai.modelChanged"), object: nil)
    }
}
