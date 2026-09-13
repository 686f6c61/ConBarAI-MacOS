import Foundation

/// Ajustes con las mismas claves y valores por defecto que oc_common.py (Ubuntu),
/// para que el archivo settings.json sea portable entre ambas versiones.
struct Settings: Codable {
    var autohide = false // macOS: hay apps que roban el foco sin parar; se pliega a demanda
    var autostart = true
    var workdir = ""
    // Compacidad de la isla Ubuntu + columnas suficientes para el pie de pi.
    var width = 0.45
    var height = 0.63
    var opacity = 0.97
    var keybinding = "alt+return" // ⌘+Return robaría "enviar" a Mail; se puede cambiar desde el tray
    var theme = "tokyo-night"
    var font = "auto"
    var font_size = 12.0
    var continue_session = true
    var diag_pos = "side"
    var update_check = true
    var crash_watch = true
    var crash_analyze = true
    var crash_dedupe = 60.0
    var crash_poll = 8.0
    var island_pill = true // exclusivo macOS: píldora visible bajo el notch
    // Claves nuevas (opcionales para no romper settings.json antiguos):
    // agente de la consola ("auto" → pi si está, si no opencode) y modelo por defecto.
    var agent: String?
    var model: String?
    /// Cargar las extensiones del pi GLOBAL del usuario dentro de la isla.
    /// Por defecto NO: el agente de la isla es el de ConBarAI, inmune a la
    /// configuración global (banners incluidos) venga de quien venga.
    var agent_extensions: Bool?

    var resolvedModel: String { model?.isEmpty == false ? model! : "nan/deepseek-v4-flash" }
    var loadGlobalExtensions: Bool { agent_extensions == true }

    static func load(path: String = Paths.settingsFile) -> Settings {
        guard let data = FileManager.default.contents(atPath: path) else { return Settings() }
        do {
            var s = try JSONDecoder().decode(Settings.self, from: data)
            s.clamp()
            return s
        } catch {
            FileHandle.standardError.write("conbarai: settings.json corrupto (\(error)); usando valores por defecto\n".data(using: .utf8)!)
            return Settings()
        }
    }

    func save(path: String = Paths.settingsFile) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Paths.settingsDir) {
            try? fm.createDirectory(atPath: Paths.settingsDir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        if let data = try? JSONEncoder.withPretty().encode(self) {
            fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }

    mutating func clamp() {
        width = min(max(width, 0.15), 0.90)
        height = min(max(height, 0.20), 0.95)
        opacity = min(max(opacity, 0.50), 1.0)
        font_size = min(max(font_size, 7), 20)
        crash_dedupe = min(max(crash_dedupe, 5), 3600)
        crash_poll = min(max(crash_poll, 2), 120)
    }
}

extension JSONEncoder {
    static func withPretty() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

/// Última sesión/carpeta usada, para restaurar al arrancar.
struct SessionState: Codable {
    var lastSession = "oc"
    var lastWorkdir = ""

    static func load() -> SessionState {
        guard let data = FileManager.default.contents(atPath: Paths.sessionsFile),
              let s = try? JSONDecoder().decode(SessionState.self, from: data) else { return SessionState() }
        return s
    }

    func save() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.stateDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder.withPretty().encode(self) {
            fm.createFile(atPath: Paths.sessionsFile, contents: data,
                          attributes: [.posixPermissions: 0o600])
        }
    }
}
