import Darwin
import Foundation

/// Dependencias externas de la consola (pi y tmux) y su instalación desde
/// canales oficiales. ConBarAI nunca descarga ni ejecuta instaladores
/// remotos por su cuenta: lanza el gestor de paquetes que ya tenga el
/// usuario (Homebrew para tmux, npm para pi) y, si no está, le manda a la
/// web oficial para que lo instale él.
enum Deps {
    static let brewURL = "https://brew.sh"
    static let nodeURL = "https://nodejs.org"
    static let piPackage = "@mariozechner/pi-coding-agent"

    struct Status {
        var pi: Bool
        var tmux: Bool
        var brew: Bool
        var npm: Bool

        /// Orden estable: tmux primero (sin él no hay sesión que abrir).
        var missing: [String] {
            var m: [String] = []
            if !tmux { m.append("tmux") }
            if !pi { m.append("pi") }
            return m
        }

        var allPresent: Bool { pi && tmux }
    }

    /// Estado real de la máquina. `CONBARAI_SIMULATE_MISSING=pi,tmux`
    /// permite ver la portada de dependencias en una máquina que ya lo
    /// tiene todo (harness de pruebas, igual que CONBARAI_SNAPSHOT).
    static func current() -> Status {
        let sim = Set((ProcessInfo.processInfo.environment["CONBARAI_SIMULATE_MISSING"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        var s = Status(pi: Shell.piPath() != nil,
                       tmux: Shell.tmuxPath() != nil,
                       brew: Shell.brewPath() != nil,
                       npm: Shell.npmPath() != nil)
        if sim.contains("pi") { s.pi = false }
        if sim.contains("tmux") { s.tmux = false }
        return s
    }

    /// Comando del canal oficial para instalar una dependencia, o nil si en
    /// esta máquina no hay canal (tocará la guía manual).
    static func installCommand(dep: String, brewPath: String?, npmPath: String?) -> String? {
        switch dep {
        case "tmux":
            return brewPath.map { "\(Shell.shQuote($0)) install tmux" }
        case "pi":
            return npmPath.map { "\(Shell.shQuote($0)) install -g \(piPackage)" }
        default:
            return nil
        }
    }

    /// Qué puede hacer el usuario con lo que falta: canal listo o web oficial.
    static func guidanceText(for dep: String, status: Status) -> String {
        let brewPath = status.brew ? "/opt/homebrew/bin/brew" : nil
        let npmPath = status.npm ? "/opt/homebrew/bin/npm" : nil
        if installCommand(dep: dep, brewPath: brewPath, npmPath: npmPath) != nil {
            return dep == "tmux" ? "se instalará con Homebrew" : "se instalará con npm"
        }
        switch dep {
        case "tmux": return "instala Homebrew desde \(brewURL) y vuelve a abrir la isla"
        case "pi": return "instala Node.js desde \(nodeURL) (incluye npm)"
        default: return ""
        }
    }

    /// Instala lo que falta por su canal oficial. brew/npm pueden tardar:
    /// timeout largo y sin prompts interactivos. Devuelve (éxito, log).
    static func runInstall(_ deps: [String]) -> (ok: Bool, log: String) {
        let brewPath = Shell.brewPath()
        let npmPath = Shell.npmPath()
        var log: [String] = []
        var ok = true
        for dep in deps {
            guard let cmd = installCommand(dep: dep, brewPath: brewPath, npmPath: npmPath) else {
                ok = false
                log.append("\(dep): \(guidanceText(for: dep, status: current()))")
                continue
            }
            // Sin auto-update de brew: la instalación es más rápida y silenciosa.
            let env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1"]
            let r = Shell.run(cmd, timeout: 900, env: env)
            log.append("$ \(cmd)\n\(r.out.trimmingCharacters(in: .whitespacesAndNewlines))")
            if r.code != 0 { ok = false }
        }
        return (ok, log.joined(separator: "\n"))
    }

    /// Instalación interactiva para el CLI (`conbarai deps`, `conbarai
    /// setup`): pregunta dependencia a dependencia. Sin TTY solo informa.
    @discardableResult
    static func installInteractive() -> Int32 {
        guard isatty(0) == 1 else { return report() }
        var s = current()
        guard !s.allPresent else { return 0 }
        for dep in s.missing {
            let how = guidanceText(for: dep, status: s)
            if installCommand(dep: dep, brewPath: Shell.brewPath(), npmPath: Shell.npmPath()) == nil {
                print("  falta \(dep): \(how)")
                continue
            }
            print("  falta \(dep) (\(how))")
            print("¿Instalar \(dep) ahora? [S/n] ", terminator: "")
            guard let line = readLine(), !line.lowercased().hasPrefix("n") else { continue }
            let r = runInstall([dep])
            print(r.log)
            print(r.ok ? "  \(dep) instalado ✓" : "  no se pudo instalar \(dep)")
        }
        s = current()
        return s.allPresent ? 0 : 1
    }

    /// Estado + guía sin instalar nada (para verificación y CI).
    @discardableResult
    static func report() -> Int32 {
        let s = current()
        print("Dependencias de la consola:")
        print("  tmux : \(s.tmux ? "✓ presente" : "— falta")")
        print("  pi   : \(s.pi ? "✓ presente" : "— falta")")
        if s.allPresent { return 0 }
        for dep in s.missing {
            print("  \(dep): \(guidanceText(for: dep, status: s))")
        }
        print("Canal de instalación oficial: Homebrew (tmux) · npm (pi)")
        return 1
    }

    /// `conbarai deps`: estado e instalación guiada.
    @discardableResult
    static func cli() -> Int32 {
        let code = report()
        guard code != 0 else { return 0 }
        guard isatty(0) == 1 else { return code }
        print()
        return installInteractive() == 0 ? 0 : 1
    }
}
