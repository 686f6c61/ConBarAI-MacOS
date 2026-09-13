import Foundation

/// Configuración de tmux en un socket dedicado (-L conbarai) para no tocar
/// la configuración global del usuario. Las sesiones sobreviven a que la
/// consola se esconda, se cierre o se reinicie el Mac.
enum Tmux {
    static let conf = """
    # Generado por ConBarAI — no editar a mano (se regenera).
    set -g default-terminal "xterm-256color"
    set -ga terminal-overrides ",xterm-256color:Tc"
    set -g escape-time 10
    set -g status off
    set -g mouse on
    set -g remain-on-exit on
    set -g set-clipboard on
    set -g bell-action any
    set -g visual-bell off
    set -g detach-on-destroy off
    # El agente responde mientras la isla está escondida → aviso silencioso.
    set -g monitor-activity on
    set -g activity-action none
    # Pi lo pide: teclas modificadas y formato csi-u dentro del panel.
    set -g extended-keys on
    set -g extended-keys-format csi-u
    """

    /// Escribe el tmux.conf, el wrapper del hook de campana y registra el hook.
    /// El hook alert-bell toca el marcador y lanza la notificación (paridad con Ubuntu).
    @discardableResult
    static func ensureSetup() -> Bool {
        guard let tmux = Shell.tmuxPath() else { return false }
        Paths.ensureStateDirs()
        let fm = FileManager.default

        // El conf se regenera siempre: es nuestro, no editable a mano.
        fm.createFile(atPath: Paths.tmuxConfFile, contents: conf.data(using: .utf8),
                      attributes: [.posixPermissions: 0o600])
        let bin = Shell.shQuote(Paths.selfBinaryPath())
        // "$2" vacío para la campana (con notificación) y "quiet" para la actividad.
        let wrapper = """
        #!/bin/zsh
        # Hooks de ConBarAI: campana (notifica) y actividad (solo marcador).
        exec \(bin) alert "$1" "$2"
        """
        fm.createFile(atPath: Paths.hookWrapper, contents: wrapper.data(using: .utf8),
                      attributes: [.posixPermissions: 0o700])

        // Arrancar el servidor, desprender clientes huérfanos y registrar hooks.
        // tmux achica el pane al cliente más pequeño: un cliente muerto con
        // tamaño píldora rompe el TUI para los clientes nuevos, así que fuera.
        let bellHook = "run-shell -b \(Shell.shQuote("\(Paths.hookWrapper) #{hook_session_name}"))"
        let quietHook = "run-shell -b \(Shell.shQuote("\(Paths.hookWrapper) #{hook_session_name} quiet"))"
        _ = Shell.run("\(Shell.shQuote(tmux)) -L \(Paths.socketName) -f \(Shell.shQuote(Paths.tmuxConfFile)) start-server; " +
                          "\(Shell.shQuote(tmux)) -L \(Paths.socketName) detach-client -a 2>/dev/null || true; " +
                          "\(Shell.shQuote(tmux)) -L \(Paths.socketName) set-hook -g alert-bell \(Shell.shQuote(bellHook)); " +
                          "\(Shell.shQuote(tmux)) -L \(Paths.socketName) set-hook -g alert-activity \(Shell.shQuote(quietHook))",
                      timeout: 10)
        // El agente de los panes es el nuestro: NaN + deepseek-v4-flash.
        PiConfig.ensureNaNProvider()
        OpenCodeConfig.propagateToTmux()
        return true
    }

    /// Precalentado: crea la sesión DESACOPLADA (sin cliente enano que achique
    /// el pane). pi arranca a 100×30 y el banner nace íntegro; el primer expand
    /// del usuario engancha el cliente real.
    @discardableResult
    static func prewarmDetached(session: String, workdir: String, settings: Settings) -> Bool {
        guard let tmux = Shell.tmuxPath(),
              let args = attachArgs(session: session, workdir: workdir, settings: settings, fresh: true)
        else { return false }
        // ¿Ya vive? Nada que precalentar.
        let exists = Shell.run("\(Shell.shQuote(tmux)) -L \(Paths.socketName) has-session -t \(Shell.shQuote(session)) 2>/dev/null",
                               timeout: 5).code == 0
        if exists { return true }
        // new-session en modo detached (-d): sin cliente, sin -A.
        var detached = args
        if let i = detached.firstIndex(of: "new-session") {
            detached.replaceSubrange(i...i, with: ["new-session", "-d"])
        }
        return Shell.spawnDetached(tmux, detached)
    }

    /// Argumentos para adjuntar o crear la sesión (new-session -A).
    /// Todo va encadenado en UNA invocación de tmux (separador ";" como
    /// argumento): el servidor muere sin sesiones, así que los hooks y el
    /// entorno del panel (OPENCODE_CONFIG/NAN_API_KEY) deben fijarse justo
    /// antes de crear la sesión, en la misma cadena.
    /// `fresh` = arrancar pi SIN -c: conversación nueva, consola limpia.
    static func attachArgs(session: String, workdir: String, settings: Settings,
                           fresh: Bool = false) -> [String]? {
        guard let tmux = Shell.tmuxPath(), Sessions.validated(session) != nil else { return nil }
        // ¿Continuar la charla? Solo si la sesión ya vive y no piden nueva.
        // (pi -c no falla sin sesión previa, así que se decide por tmux.)
        let exists = Shell.run("\(Shell.shQuote(tmux)) -L \(Paths.socketName) has-session -t \(Shell.shQuote(session)) 2>/dev/null",
                               timeout: 5).code == 0
        let wantsContinue = !fresh && exists
        let inner: String
        switch Agent.resolve(setting: settings.agent) {
        case .pi:
            var flags = "--model \(Shell.shQuote(settings.resolvedModel)) -a --offline"
            if !settings.loadGlobalExtensions {
                // Isla aislada: ni extensiones ni banners del pi global del usuario.
                flags += " --no-extensions"
            }
            for skill in Paths.bundledSkills {
                let dir = "\(Paths.skillsDir)/\(skill)"
                if FileManager.default.fileExists(atPath: "\(dir)/SKILL.md") {
                    flags += " --skill \(Shell.shQuote(dir))"
                }
            }
            // OJO: nada de banners impresos en el terminal — pi borra el
            // scrollback al redimensionarse y se los comería en el primer
            // resize. La marca va en el splash de la isla y en la cabecera.
            if wantsContinue {
                inner = "cd \(Shell.shQuote(workdir)) && exec pi -c \(flags)"
            } else {
                inner = "cd \(Shell.shQuote(workdir)) && exec pi \(flags)"
            }
        case .opencode:
            if let oc = Shell.opencodePath() {
                inner = "cd \(Shell.shQuote(workdir)) && exec \(Shell.shQuote(oc))\(settings.continue_session ? " -c" : "")"
            } else {
                inner = "printf '\\\\033[33mConBarAI: sin agente instalado.\\\\nInstala pi (npm i -g @mariozechner/pi-coding-agent) u opencode\\\\033[0m\\\\n'; exec /bin/zsh -l"
            }
        case nil:
            inner = "printf '\\\\033[33mConBarAI: sin agente instalado.\\\\nInstala pi (npm i -g @mariozechner/pi-coding-agent) u opencode\\\\033[0m\\\\n'; exec /bin/zsh -l"
        }
        let bellHook = "run-shell -b \(Shell.shQuote("\(Paths.hookWrapper) #{hook_session_name}"))"
        let quietHook = "run-shell -b \(Shell.shQuote("\(Paths.hookWrapper) #{hook_session_name} quiet"))"

        var args = ["-L", Paths.socketName, "-f", Paths.tmuxConfFile,
                    "start-server", ";",
                    "set-hook", "-g", "alert-bell", bellHook, ";",
                    "set-hook", "-g", "alert-activity", quietHook, ";",
                    // Opciones de teclado que pi pide: aplicadas en cada attach
                    // porque el conf solo se lee al arrancar el servidor.
                    "set", "-g", "extended-keys", "on", ";",
                    "set", "-g", "extended-keys-format", "csi-u", ";",
                    "set-environment", "-g", "OPENCODE_CONFIG", OpenCodeConfig.panelConfigPath, ";"]
        // Todas las claves del almacén (NaN, OpenAI, Claude, z.ai, Kimi, x.ai…).
        for (env, value) in KeyStore.all().sorted(by: { $0.key < $1.key }) {
            args += ["set-environment", "-g", env, value, ";"]
        }
        args += ["new-session", "-A", "-s", session, "-x", "100", "-y", "30", inner]
        return args
    }

    static func killSession(_ session: String) {
        guard let tmux = Shell.tmuxPath(), Sessions.validated(session) != nil else { return }
        _ = Shell.run("'\(tmux)' -L \(Paths.socketName) kill-session -t \(Shell.shQuote(session)) 2>/dev/null", timeout: 5)
    }
}
