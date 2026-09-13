import Foundation
import AppKit
import Carbon.HIToolbox

/// Atajo global estilo Super+Return de Ubuntu, sobre la API Carbon.
/// Acepta los mismos nombres que GTK ("alt+return") más los de macOS ("cmd+ctrl+space").
struct HotKey: Equatable {
    var carbonMods: Int
    var keyCode: UInt32

    static func parse(_ raw: String) -> HotKey? {
        // Acepta "alt+return" y el formato GTK "<Super>Return" (separa con <> o espacios).
        let parts = raw.lowercased()
            .replacingOccurrences(of: "<", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .replacingOccurrences(of: "+", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        var mods = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "super", "win", "meta": mods |= cmdKey
            case "ctrl", "control": mods |= controlKey
            case "alt", "option", "opt": mods |= optionKey
            case "shift": mods |= shiftKey
            default: return nil
            }
        }
        guard mods != 0 else { return nil }
        guard let code = keyCode(for: parts.last!) else { return nil }
        return HotKey(carbonMods: mods, keyCode: code)
    }

    static func keyCode(for name: String) -> UInt32? {
        switch name {
        case "return", "enter": return UInt32(kVK_Return)
        case "space": return UInt32(kVK_Space)
        case "tab": return UInt32(kVK_Tab)
        case "delete", "backspace": return UInt32(kVK_Delete)
        case "escape", "esc": return UInt32(kVK_Escape)
        case "left": return UInt32(kVK_LeftArrow)
        case "right": return UInt32(kVK_RightArrow)
        case "down": return UInt32(kVK_DownArrow)
        case "up": return UInt32(kVK_UpArrow)
        default: break
        }
        if name.count == 1, let scalar = name.unicodeScalars.first {
            let letterKeys: [Character: Int] = [
                "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
                "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
                "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
                "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
                "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
                "z": kVK_ANSI_Z, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
                "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
                "0": kVK_ANSI_0,
            ]
            if let code = letterKeys[Character(scalar)] { return UInt32(code) }
        }
        if name.hasPrefix("f"), let n = Int(name.dropFirst()), (1...19).contains(n) {
            let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
                         kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17,
                         kVK_F18, kVK_F19]
            return UInt32(fKeys[n - 1])
        }
        return nil
    }

    /// Reconstruye la cadena canónica ("alt+return") desde un evento, para el grabador de atajos.
    static func string(from event: NSEvent) -> String? {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else { return nil }
        let key: String
        switch event.keyCode {
        case UInt16(kVK_Return): key = "return"
        case UInt16(kVK_Space): key = "space"
        case UInt16(kVK_Tab): key = "tab"
        case UInt16(kVK_Delete): key = "delete"
        case UInt16(kVK_Escape): key = "escape"
        case UInt16(kVK_LeftArrow): key = "left"
        case UInt16(kVK_RightArrow): key = "right"
        case UInt16(kVK_DownArrow): key = "down"
        case UInt16(kVK_UpArrow): key = "up"
        default:
            guard chars.count == 1, chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { return nil }
            key = chars
        }
        var parts: [String] = []
        let f = event.modifierFlags
        if f.contains(.command) { parts.append("cmd") }
        if f.contains(.control) { parts.append("ctrl") }
        if f.contains(.option) { parts.append("alt") }
        if f.contains(.shift) { parts.append("shift") }
        guard parts.count >= 1 else { return nil }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Versión visible en los menús ("⌥⏎").
    static func display(_ raw: String) -> String {
        guard let spec = parse(raw) else { return raw }
        var s = ""
        if spec.carbonMods & cmdKey != 0 { s += "⌘" }
        if spec.carbonMods & controlKey != 0 { s += "⌃" }
        if spec.carbonMods & optionKey != 0 { s += "⌥" }
        if spec.carbonMods & shiftKey != 0 { s += "⇧" }
        let keyNames: [Int: String] = [
            kVK_Return: "⏎", kVK_Space: "espacio", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_Escape: "esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓",
            kVK_UpArrow: "↑",
        ]
        if let shown = keyNames[Int(spec.keyCode)] { s += shown } else { s += raw.split(separator: "+").last.map(String.init) ?? "" }
        return s
    }
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature: OSType = 0x43424149 // "CBAI"
    private let hotKeyID: UInt32 = 1

    var registeredSpec: HotKey?

    @discardableResult
    func register(raw: String, action: @escaping () -> Void) -> Bool {
        guard let spec = HotKey.parse(raw) else { return false }
        unregister()
        var installed = false
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == 0x43424149 {
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { center.action?() }
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, UInt32(spec.carbonMods),
                                         EventHotKeyID(signature: signature, id: hotKeyID),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, ref != nil {
            hotKeyRef = ref
            self.action = action
            registeredSpec = spec
            installed = true
        }
        return installed
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        action = nil
        registeredSpec = nil
    }
}
