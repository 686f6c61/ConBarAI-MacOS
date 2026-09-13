import Foundation

/// Comprobación de versiones contra GitHub Releases, como el tray de la versión Ubuntu.
/// Única llamada de red de ConBarAI; se desactiva con update_check=false.
enum UpdateCheck {
    static func latestVersion(repo: String = Paths.repo, timeout: TimeInterval = 10) -> String? {
        // Solo https y solo el host de la API de GitHub; nada de localhost/privados.
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
              url.scheme == "https", url.host == "api.github.com" else { return nil }

        let sem = DispatchSemaphore(value: 0)
        var found: String?
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 5
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: url) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            found = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        }
        task.resume()
        _ = sem.wait(timeout: .now() + timeout + 5)
        return found
    }

    static func isOutdated(current: String, latest: String) -> Bool {
        let c = current.split(separator: ".").map { Int($0) ?? 0 }
        let l = latest.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(c.count, l.count) {
            let a = i < c.count ? c[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}
