import Foundation

/// Ejecución de comandos con timeout, notificaciones y resolución de binarios.
/// Es el sustituto de subprocess/notify-send de la versión Ubuntu.
enum Shell {
    struct Result {
        let code: Int32
        let out: String
    }

    static func run(_ command: String, timeout: TimeInterval = 15,
                    cwd: String? = nil, env: [String: String]? = nil) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment
        if let env { environment.merge(env) { _, new in new } }
        p.environment = environment

        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        // Tuberías grandes: leer en segundo plano evita bloqueos del hijo.
        var data = Data()
        let lock = NSLock()
        out.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            lock.lock(); data.append(chunk); lock.unlock()
            if chunk.isEmpty { h.readabilityHandler = nil }
        }

        do {
            try p.run()
        } catch {
            return Result(code: 127, out: "conbarai: no pude lanzar \(command): \(error)")
        }

        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            p.waitUntilExit()
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { p.terminate() }
            _ = sem.wait(timeout: .now() + 5)
            lock.lock(); let partial = data; lock.unlock()
            return Result(code: 124, out: String(data: partial, encoding: .utf8) ?? "")
        }
        out.fileHandleForReading.readabilityHandler = nil
        lock.lock(); let full = data; lock.unlock()
        return Result(code: p.terminationStatus, out: String(data: full, encoding: .utf8) ?? "")
    }

    static func notify(_ message: String, title: String = "ConBarAI") {
        let esc = message.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        _ = run(String(format: "/usr/bin/osascript -e 'display notification \"%@\" with title \"%@\"'", esc, title),
                timeout: 10)
    }

    /// Escapa una ruta para incrustarla entre comillas simples en un comando de shell.
    static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static let candidateDirs = [
        "\(Paths.home)/.opencode/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    /// Busca un binario en las rutas habituales (launchd no hereda el PATH del usuario).
    static func which(_ tool: String) -> String? {
        for dir in candidateDirs {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let r = run("/usr/bin/env zsh -lc 'command -v \(tool)' 2>/dev/null", timeout: 10)
        let line = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.code == 0 && line.hasPrefix("/")) ? line : nil
    }

    static func opencodePath() -> String? { which("opencode") }
    static func tmuxPath() -> String? { which("tmux") }
    static func piPath() -> String? { which("pi") }
    static func brewPath() -> String? { which("brew") }
    static func npmPath() -> String? { which("npm") }

    /// Lanza un proceso desacoplado (sin esperar) — usado para análisis de crashes.
    static func spawnDetached(_ executable: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            return true
        } catch { return false }
    }
}
