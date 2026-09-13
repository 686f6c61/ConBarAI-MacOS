import Foundation

/// Rutas y constantes compartidas. Paridad con oc_common.py de la versión Ubuntu,
/// con los equivalentes nativos de macOS donde corresponde.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static var settingsDir: String { "\(home)/.config/conbarai" }
    static var settingsFile: String { "\(settingsDir)/settings.json" }
    static var tmuxConfFile: String { "\(settingsDir)/tmux.conf" }

    static var stateDir: String { "\(home)/.local/state/conbarai" }
    static var alertsDir: String { "\(stateDir)/alerts" }
    static var sessionsFile: String { "\(stateDir)/sessions.json" }
    static var crashDir: String { "\(stateDir)/crash" }
    static var crashIgnoreDir: String { "\(crashDir)/ignore" }
    static var crashPendingFile: String { "\(crashDir)/pending.json" }
    static var crashWatchFile: String { "\(crashDir)/watch.json" }
    static var hookWrapper: String { "\(stateDir)/alert-hook.zsh" }

    static var shareDir: String { "\(home)/.local/share/conbarai" }
    static var skillsDir: String { "\(shareDir)/skills" }
    /// Skills que carga la consola (la primera es también la del analizador).
    static let bundledSkills = ["macos-operator", "mac-gui-pilot", "conbarai-ops"]
    static let bundledSkill = "macos-operator"

    static var launchAgentsDir: String { "\(home)/Library/LaunchAgents" }

    static var opencodeDB: String { "\(home)/.local/share/opencode/opencode.db" }

    /// Informes de fallo de macOS (equivalente de journald/apport).
    static let userCrashReportsDir = "\(home)/Library/Logs/DiagnosticReports"
    static let systemCrashReportsDir = "/Library/Logs/DiagnosticReports"

    static let version = "1.5.0"
    static let repo = "686f6c61/ConBarAI-MacOS"
    static let socketName = "conbarai"

    /// Ruta absoluta de este binario, resolviendo el symlink de ~/.local/bin.
    static func selfBinaryPath() -> String {
        var path = CommandLine.arguments.first ?? "/usr/local/bin/conbarai"
        if !path.hasPrefix("/") {
            path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path).standardizedFileURL.path
        }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Crea los directorios de estado con permisos cerrados (0700), como la versión Ubuntu.
    static func ensureStateDirs() {
        let fm = FileManager.default
        for dir in [settingsDir, stateDir, alertsDir, crashDir, crashIgnoreDir,
                    shareDir, skillsDir, launchAgentsDir, userCrashReportsDir] {
            if !fm.fileExists(atPath: dir) {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            }
        }
    }
}
