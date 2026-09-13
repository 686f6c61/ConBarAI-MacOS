import Foundation

/// Paletas Tokyo Night / Catppuccin / Dracula / Gruvbox, igual que la versión Ubuntu.
struct Theme {
    let name: String
    let bg: UInt32
    let fg: UInt32
    let cursor: UInt32
    let selection: UInt32
    let ansi: [UInt32] // 16 colores

    static let all = ["tokyo-night", "catppuccin", "dracula", "gruvbox"]

    static func byName(_ raw: String) -> Theme {
        switch raw.lowercased() {
        case "catppuccin": return catppuccin
        case "dracula": return dracula
        case "gruvbox": return gruvbox
        default: return tokyoNight
        }
    }

    static let tokyoNight = Theme(
        name: "tokyo-night", bg: 0x1a1b26, fg: 0xa9b1d6, cursor: 0xc0caf5, selection: 0x33467c,
        ansi: [0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6,
               0x414868, 0xff7a93, 0xb9f27c, 0xff9e64, 0x7da6ff, 0xbb9af7, 0x0db9d7, 0xc0caf5])

    static let catppuccin = Theme(
        name: "catppuccin", bg: 0x1e1e2e, fg: 0xcdd6f4, cursor: 0xf5e0dc, selection: 0x585b70,
        ansi: [0x45475a, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xbac2de,
               0x585b70, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xa6adc8])

    static let dracula = Theme(
        name: "dracula", bg: 0x282a36, fg: 0xf8f8f2, cursor: 0xf8f8f2, selection: 0x44475a,
        ansi: [0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
               0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff])

    static let gruvbox = Theme(
        name: "gruvbox", bg: 0x282828, fg: 0xebdbb2, cursor: 0xebdbb2, selection: 0x504945,
        ansi: [0x282828, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0xa89984,
               0x928374, 0xfb4934, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xebdbb2])

    /// Color de acento (azul ANSI del tema) para marca y banners.
    var accent: UInt32 { ansi[4] }
}
