import Foundation

/// El agente de la consola. Pi (pi.dev) es el ligero por defecto;
/// OpenCode queda como respaldo si está instalado.
enum Agent: String {
    case pi
    case opencode

    /// "auto" → pi si está instalado, si no opencode. Las presencias son
    /// inyectables para los tests.
    static func resolve(setting: String?,
                        piInstalled: Bool = Shell.piPath() != nil,
                        opencodeInstalled: Bool = Shell.opencodePath() != nil) -> Agent? {
        switch setting?.lowercased() {
        case "pi": return piInstalled ? .pi : nil
        case "opencode": return opencodeInstalled ? .opencode : nil
        default:
            if piInstalled { return .pi }
            if opencodeInstalled { return .opencode }
            return nil
        }
    }
}

/// Config de Pi en ~/.pi/agent/models.json: fusiona el provider NaN
/// (deepseek-v4-flash y demás clúster) SIN tocar el resto de providers
/// del usuario (ollama, etc.). La key llega por entorno, nunca escrita.
enum PiConfig {
    static var modelsFile: String { "\(Paths.home)/.pi/agent/models.json" }

    /// Entradas del clúster NaN (documentación del gist).
    static let nanModels: [[String: Any]] = [
        ["id": "deepseek-v4-flash", "name": "DeepSeek V4 Flash", "contextWindow": 500000,
         "input": ["text", "image"], "reasoning": true],
        ["id": "qwen3.6", "name": "Qwen 3.6", "contextWindow": 262144,
         "input": ["text", "image"], "reasoning": true],
        ["id": "qwen3.8-flash", "name": "Qwen 3.8 Flash", "contextWindow": 262144,
         "input": ["text", "image"], "reasoning": true],
        ["id": "glm5.3-flash", "name": "GLM 5.3 Flash", "contextWindow": 500000,
         "input": ["text", "image"], "reasoning": true],
        ["id": "mimo-v2.5", "name": "MiMo v2.5", "contextWindow": 500000,
         "input": ["text", "image"]],
        ["id": "gemma4", "name": "Gemma 4", "contextWindow": 262144,
         "input": ["text", "image"]],
    ]

    static func nanProvider() -> [String: Any] {
        [
            "api": "openai-completions",
            "baseUrl": OpenCodeConfig.baseURL,
            "authHeader": true,
            "apiKey": "$NAN_API_KEY", // interpolación de entorno de pi
            "models": nanModels,
        ]
    }

    /// Añade/actualiza SOLO la clave "nan" dentro de providers; el resto se conserva.
    @discardableResult
    static func ensureNaNProvider() -> Bool {
        let fm = FileManager.default
        let dir = (modelsFile as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        var root: [String: Any] = [:]
        if let data = fm.contents(atPath: modelsFile),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var providers = root["providers"] as? [String: Any] ?? [:]
        providers["nan"] = nanProvider()
        root["providers"] = providers

        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return false }
        // Preservar los permisos cerrados que usa pi para este fichero.
        return fm.createFile(atPath: modelsFile, contents: data,
                             attributes: [.posixPermissions: 0o600])
    }

    /// Añade/actualiza un proveedor externo (OpenAI, Claude, z.ai, Kimi, x.ai…)
    /// en models.json SIN tocar el resto. La clave queda como interpolación
    /// de entorno: el valor vive en el almacén 0600, no aquí.
    /// `at` permite a los tests usar un models.json temporal.
    @discardableResult
    static func ensureProvider(_ p: ProviderDef, models: [String],
                               at customFile: String? = nil) -> Bool {
        let file = customFile ?? modelsFile
        let fm = FileManager.default
        let dir = (file as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        var root: [String: Any] = [:]
        if let data = fm.contents(atPath: file),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        var providers = root["providers"] as? [String: Any] ?? [:]
        providers[p.id] = [
            "api": p.api,
            "baseUrl": p.baseURL,
            "authHeader": p.api != "anthropic-messages",
            "apiKey": "$\(p.keyEnv)",
            "models": Providers.piModelsEntry(ids: models),
        ]
        root["providers"] = providers
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return false }
        return fm.createFile(atPath: file, contents: data,
                             attributes: [.posixPermissions: 0o600])
    }

    /// ¿Está el provider nan ya presente y con nuestra baseUrl?
    static func isConfigured() -> Bool {
        guard let data = FileManager.default.contents(atPath: modelsFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = obj["providers"] as? [String: Any],
              let nan = providers["nan"] as? [String: Any],
              nan["baseUrl"] as? String == OpenCodeConfig.baseURL else { return false }
        return true
    }

    /// Silencia el banner de arranque SOLO en las carpetas que abre ConBarAI,
    /// vía settings de proyecto (<workdir>/.pi/settings.json). El pi del
    /// terminal del usuario conserva su banner.
    @discardableResult
    static func ensureQuietStartup(workdir: String) -> Bool {
        let fm = FileManager.default
        let dir = "\(workdir)/.pi"
        let path = "\(dir)/settings.json"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if let data = fm.contents(atPath: path),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        guard root["quietStartup"] as? Bool != true else { return true }
        root["quietStartup"] = true
        guard let data = try? JSONSerialization.data(withJSONObject: root,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return false }
        return fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}
