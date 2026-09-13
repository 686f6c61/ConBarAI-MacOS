import Foundation

/// Proveedores soportados por los Ajustes de ConBarAI. Las claves NUNCA se
/// escriben en el repo: viven en ~/.config/conbarai/auth (0600) y llegan a pi
/// por interpolación de entorno en models.json ("apiKey": "$X_API_KEY").
struct ProviderDef {
    let id: String          // clave en models.json y prefijo de --model
    let name: String
    let baseURL: String     // raíz OpenAI-compatible (o Anthropic)
    let keyEnv: String
    let api: String         // api de pi: openai-completions | anthropic-messages
    let staticModels: [String] // respaldo si /models falla o no existe
}

/// Error simple para poder usar Result<[String], …> (String no es Error).
struct ProviderFetchError: Error {
    let message: String
}

enum Providers {
    static let all: [ProviderDef] = [
        ProviderDef(id: "nan", name: "NaN (clúster comunitario)",
                    baseURL: "https://api.nan.builders/v1", keyEnv: "NAN_API_KEY",
                    api: "openai-completions",
                    staticModels: ["deepseek-v4-flash", "qwen3.6", "qwen3.8-flash",
                                   "glm5.3-flash", "mimo-v2.5", "gemma4"]),
        ProviderDef(id: "openai", name: "OpenAI",
                    baseURL: "https://api.openai.com/v1", keyEnv: "OPENAI_API_KEY",
                    api: "openai-completions",
                    staticModels: ["gpt-5.2", "gpt-5.1", "gpt-5-mini", "o4-mini"]),
        ProviderDef(id: "claude", name: "Anthropic (Claude)",
                    baseURL: "https://api.anthropic.com/v1", keyEnv: "ANTHROPIC_API_KEY",
                    api: "anthropic-messages",
                    staticModels: ["claude-opus-4", "claude-sonnet-4", "claude-haiku-4"]),
        ProviderDef(id: "zai", name: "Z.ai (GLM)",
                    baseURL: "https://api.z.ai/api/paas/v4", keyEnv: "ZAI_API_KEY",
                    api: "openai-completions",
                    staticModels: ["glm-4.6", "glm-4.5", "glm-4.5-air", "glm-4.5-flash"]),
        ProviderDef(id: "kimi", name: "Kimi (Moonshot)",
                    baseURL: "https://api.moonshot.ai/v1", keyEnv: "KIMI_API_KEY",
                    api: "openai-completions",
                    staticModels: ["kimi-k2", "kimi-k2-turbo-preview"]),
        ProviderDef(id: "xai", name: "x.ai (Grok)",
                    baseURL: "https://api.x.ai/v1", keyEnv: "XAI_API_KEY",
                    api: "openai-completions",
                    staticModels: ["grok-4", "grok-4-fast", "grok-3-mini"]),
    ]

    static func byID(_ id: String) -> ProviderDef? {
        all.first { $0.id == id }
    }

    /// GET <baseURL>/models con la key. Solo https y solo el host del
    /// proveedor: nada de redirecciones raras ni URLs controlables por usuario.
    static func fetchModels(_ p: ProviderDef, key: String, timeout: TimeInterval = 15) -> Result<[String], ProviderFetchError> {
        guard let url = URL(string: p.baseURL + "/models"), url.scheme == "https",
              let host = url.host, host == URL(string: p.baseURL)?.host else {
            return .failure(ProviderFetchError(message: "URL inválida"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if p.api == "anthropic-messages" {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let sem = DispatchSemaphore(value: 0)
        var payload: Data?
        var status = 0
        var err: String?
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            if let error { err = error.localizedDescription; return }
            if let http = response as? HTTPURLResponse { status = http.statusCode }
            payload = data
        }
        task.resume()
        _ = sem.wait(timeout: .now() + timeout + 5)

        if let err { return .failure(ProviderFetchError(message: "red: \(err)")) }
        guard status == 200, let payload else {
            return .failure(ProviderFetchError(message: "HTTP \(status)"))
        }
        switch parseModels(payload) {
        case .success(let models) where !models.isEmpty:
            return .success(models.sorted())
        default:
            return .failure(ProviderFetchError(message: "respuesta sin modelos"))
        }
    }

    /// Formato OpenAI/Anthropic: {"data":[{"id":"gpt-..."},...]}.
    static func parseModels(_ data: Data) -> Result<[String], ProviderFetchError> {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(ProviderFetchError(message: "JSON ilegible"))
        }
        var ids: [String] = []
        if let list = obj["data"] as? [[String: Any]] {
            for m in list {
                if let id = m["id"] as? String, !id.isEmpty { ids.append(id) }
            }
        }
        return ids.isEmpty ? .failure(ProviderFetchError(message: "sin campo data[].id")) : .success(ids)
    }

    /// Modelos para pi: entradas con contexto por defecto; pi ajusta lo demás.
    static func piModelsEntry(ids: [String]) -> [[String: Any]] {
        ids.map { ["id": $0, "name": $0, "contextWindow": 128000,
                   "input": ["text", "image"] ] }
    }
}
