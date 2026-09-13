import Foundation

/// Almacén local de claves: ~/.config/conbarai/auth con formato
/// PROVEEDOR_API_KEY=valor, permisos 0600, igual que hace pi/opencode con
/// sus auth.json. Las claves llegan por UI/stdin — jamás escritas en el repo.
enum KeyStore {
    static var path: String { "\(Paths.settingsDir)/auth" }

    /// Todas las claves guardadas (solo pares válidos). `at` permite a los
    /// tests usar un fichero temporal sin tocar el almacén del usuario.
    static func all(at customPath: String? = nil) -> [String: String] {
        let file = customPath ?? path
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            if k.hasSuffix("_API_KEY"), v.count >= 12 { out[k] = v }
        }
        return out
    }

    static func key(for provider: ProviderDef) -> String? {
        all()[provider.keyEnv]
    }

    /// Guarda (o borra, con valor vacío) una clave conservando las demás.
    @discardableResult
    static func set(env: String, value: String, at customPath: String? = nil) -> Bool {
        let file = customPath ?? path
        var current = all(at: file)
        if value.isEmpty {
            current.removeValue(forKey: env)
        } else {
            guard value.count >= 12 else { return false }
            current[env] = value
        }
        let body = current.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") + "\n"
        let dir = (file as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        return fm.createFile(atPath: file, contents: body.data(using: .utf8),
                             attributes: [.posixPermissions: 0o600])
    }

    /// Máscara prudente para UI: solo los últimos 4 caracteres.
    static func mask(_ value: String) -> String {
        guard value.count > 8 else { return "••••••" }
        return "••••••••\(value.suffix(4))"
    }
}
