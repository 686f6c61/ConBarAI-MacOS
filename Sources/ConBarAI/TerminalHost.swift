import AppKit
import SwiftTerm

/// Terminal real (PTY vía SwiftTerm) corriendo tmux-attach sobre el socket dedicado.
final class TerminalHost: NSView, LocalProcessTerminalViewDelegate {
    let terminal: LocalProcessTerminalView
    let session: String
    let workdir: String
    var onTerminated: ((Int32?) -> Void)?

    init(session: String, workdir: String, settings: Settings, fresh: Bool = false) {
        self.session = session
        self.workdir = workdir
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        terminal.processDelegate = self
        apply(theme: Theme.byName(settings.theme), settings: settings)
        addSubview(terminal)

        Tmux.ensureSetup()
        guard let tmux = Shell.tmuxPath(),
              let args = Tmux.attachArgs(session: session, workdir: workdir,
                                         settings: settings, fresh: fresh) else {
            terminal.startProcess(executable: "/bin/zsh", args: ["-l"],
                                  environment: TerminalHost.baseEnvironment())
            return
        }
        terminal.startProcess(executable: tmux, args: args,
                              environment: TerminalHost.baseEnvironment(),
                              currentDirectory: workdir)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no está soportado") }

    static func baseEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        return env.map { "\($0.key)=\($0.value)" }
    }

    func apply(theme: Theme, settings: Settings) {
        func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
            NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255.0,
                    green: CGFloat((hex >> 8) & 0xff) / 255.0,
                    blue: CGFloat(hex & 0xff) / 255.0, alpha: alpha)
        }
        terminal.font = TerminalHost.pickFont(named: settings.font, size: CGFloat(settings.font_size))
        terminal.nativeBackgroundColor = color(theme.bg, alpha: settings.opacity)
        terminal.nativeForegroundColor = color(theme.fg)
        terminal.caretColor = color(theme.cursor)
        terminal.selectedTextBackgroundColor = color(theme.selection)
        terminal.installColors(theme.ansi.map {
            SwiftTerm.Color(red: UInt16(($0 >> 16) & 0xff), green: UInt16(($0 >> 8) & 0xff), blue: UInt16($0 & 0xff))
        })
        if let layer = layer { layer.backgroundColor = color(theme.bg, alpha: settings.opacity).cgColor }
    }

    static func pickFont(named: String, size: CGFloat) -> NSFont {
        if named != "auto", let f = NSFont(name: named, size: size) { return f }
        let families = NSFontManager.shared.availableFontFamilies
        for family in ["JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono",
                       "JetBrainsMonoNL Nerd Font", "JetBrains Mono", "FiraCode Nerd Font"] {
            if families.contains(family), let f = NSFont(name: family, size: size) { return f }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    override func layout() {
        super.layout()
        terminal.frame = bounds
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [onTerminated] in onTerminated?(exitCode) }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
