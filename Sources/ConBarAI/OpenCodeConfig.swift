import Foundation

/// El "opencode propio" de ConBarAI, aislado del opencode del sistema:
/// OPENCODE_CONFIG apunta a estos ficheros, que definen el provider NaN
/// (api.nan.builders) con deepseek-v4-flash por defecto.
///
/// La API key NUNCA se escribe en el JSON: se interpola con {env:NAN_API_KEY}
/// y la key vive en ~/.config/conbarai/auth (0600) o en el entorno.
enum OpenCodeConfig {
    static var panelConfigPath: String { "\(Paths.settingsDir)/opencode.json" }
    static var crashConfigPath: String { "\(Paths.shareDir)/conbarai-crash.json" }
    static var authPath: String { "\(Paths.settingsDir)/auth" }

    static let baseURL = "https://api.nan.builders/v1"
    static let defaultModel = "nan/deepseek-v4-flash"

    /// Modelos documentados del clúster NaN (gist de referencia).
    static let nanModels: [String: [String: Any]] = [
        "qwen3.6": ["name": "Qwen 3.6", "contextWindow": 262144,
                    "modalities": ["input": ["text", "image"], "output": ["text"]]],
        "deepseek-v4-flash": ["name": "DeepSeek V4 Flash", "contextWindow": 500000,
                               "modalities": ["input": ["text", "image"], "output": ["text"]]],
        "mimo-v2.5": ["name": "MiMo v2.5 (omnimodal)", "contextWindow": 500000,
                      "modalities": ["input": ["text", "image", "audio"], "output": ["text"]]],
        "gemma4": ["name": "Gemma 4", "contextWindow": 262144,
                   "modalities": ["input": ["text", "image"], "output": ["text"]]],
        "qwen3.8-flash": ["name": "Qwen 3.8 Flash", "contextWindow": 262144,
                          "modalities": ["input": ["text", "image"], "output": ["text"]]],
        "glm5.3-flash": ["name": "GLM 5.3 Flash", "contextWindow": 500000,
                         "modalities": ["input": ["text", "image"], "output": ["text"]]],
    ]

    private static func providerBlock() -> [String: Any] {
        [
            "npm": "@ai-sdk/openai-compatible",
            "name": "NaN",
            "options": [
                "baseURL": baseURL,
                "apiKey": "{env:NAN_API_KEY}",
            ],
            "models": nanModels,
        ]
    }

    /// Config del panel: NaN completo, deepseek-v4-flash por defecto.
    /// Se crea si falta; si ya existe no se toca (el usuario puede editarlo).
    @discardableResult
    static func ensurePanelConfig() -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: panelConfigPath) {
            let config: [String: Any] = [
                "$schema": "https://opencode.ai/config.json",
                "model": defaultModel,
                "provider": ["nan": providerBlock()],
                "compaction": ["auto": true, "prune": true, "reserved": 50000],
            ]
            writeJSON(config, to: panelConfigPath)
        }
        return panelConfigPath
    }

    /// Config del agente de crashes: mismo modelo, pero con la skill cargada y
    /// TODO denegado salvo una lista cerrada de comandos de solo lectura.
    /// Se regenera siempre (es interna).
    @discardableResult
    static func ensureCrashConfig() -> String {
        // Allowlist read-only de macOS (equivalente de _CRASH_RO_CMDS de Ubuntu).
        let readOnly: [String] = [
            "sw_vers", "uname", "sysctl", "system_profiler", "uptime",
            "ps", "df", "diskutil", "pmset", "memory_pressure", "vm_stat",
            "log", "lsof", "defaults", "pkgutil", "ioreg", "networksetup",
            "grep", "head", "tail", "wc", "cat", "sort", "sed", "awk",
        ]
        var bash: [String: String] = ["*": "deny"]
        for cmd in readOnly { bash[cmd] = "allow" }

        let config: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "model": defaultModel,
            "provider": ["nan": providerBlock()],
            "skills": ["paths": [Paths.skillsDir]],
            "permission": [
                "edit": "deny",
                "webfetch": "deny",
                "external_directory": ["*": "allow"],
                "bash": bash,
            ],
        ]
        writeJSON(config, to: crashConfigPath)
        return crashConfigPath
    }

    private static func writeJSON(_ object: [String: Any], to path: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if let data = try? JSONSerialization.data(withJSONObject: object,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            fm.createFile(atPath: path, contents: data,
                          attributes: [.posixPermissions: 0o600])
        }
    }

    // MARK: - API key (entorno o fichero local 0600; jamás en el repo)

    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["NAN_API_KEY"],
           env.hasPrefix("sk-"), env.count > 8 { return env }
        return KeyStore.key(for: Providers.byID("nan")!)
    }

    /// Guarda la key en ~/.config/conbarai/auth con 0600. Llega por stdin
    /// (el instalador la pide sin eco); nunca como argumento visible en ps.
    static func installKeyFromStdin() -> Bool {
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces),
              line.hasPrefix("sk-"), line.count > 8 else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.settingsDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let body = "NAN_API_KEY=\(line)\n"
        let ok = fm.createFile(atPath: authPath, contents: body.data(using: .utf8),
                               attributes: [.posixPermissions: 0o600])
        if ok { propagateToTmux() }
        return ok
    }

    /// Expone OPENCODE_CONFIG y TODAS las claves del almacén al servidor tmux
    /// dedicado, para que los panes usen NUESTRO pi con el proveedor que sea.
    static func propagateToTmux() {
        guard let tmux = Shell.tmuxPath() else { return }
        ensurePanelConfig()
        // start-server primero: set-environment falla en silencio sin servidor.
        var cmd = "\(Shell.shQuote(tmux)) -L \(Paths.socketName) start-server; " +
                  "\(Shell.shQuote(tmux)) -L \(Paths.socketName) set-environment -g OPENCODE_CONFIG \(Shell.shQuote(panelConfigPath))"
        for (env, value) in KeyStore.all().sorted(by: { $0.key < $1.key }) {
            cmd += "; \(Shell.shQuote(tmux)) -L \(Paths.socketName) set-environment -g \(env) \(Shell.shQuote(value))"
        }
        _ = Shell.run(cmd, timeout: 10)
    }
}
