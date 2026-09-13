// Genera el icono de ConBarAI: la isla (píldora bajo el notch) sobre fondo
// oscuro, punto ámbar y el prompt ">_". Uso:
//   swift scripts/make-icon.swift icons/icon.iconset icons/ConBarAI.icns
import AppKit
import Foundation

let args = CommandLine.arguments
let iconset = args.count > 1 ? args[1] : "icons/icon.iconset"
let icns = args.count > 2 ? args[2] : "icons/ConBarAI.icns"

func draw(size: CGFloat) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let f = NSRect(x: 0, y: 0, width: size, height: size)
    let s = size / 128 // factor de escala respecto al diseño base

    // Fondo: cuadrado redondeado oscuro
    let bg = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.14, alpha: 1)
    bg.setFill()
    NSBezierPath(roundedRect: f, xRadius: 28 * s, yRadius: 28 * s).fill()

    // Halo suave del acento
    let accent = NSColor(calibratedRed: 0.48, green: 0.64, blue: 0.97, alpha: 1)
    (accent.withAlphaComponent(0.18).setFill())
    NSBezierPath(roundedRect: f.insetBy(dx: 8 * s, dy: 8 * s), xRadius: 24 * s, yRadius: 24 * s).fill()

    // La isla: píldora negra arriba con el notch
    let island = NSRect(x: 18 * s, y: 66 * s, width: 92 * s, height: 26 * s)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: 13 * s, yRadius: 13 * s).fill()
    // …y la consola abierta debajo
    let console = NSRect(x: 30 * s, y: 18 * s, width: 68 * s, height: 46 * s)
    (NSColor.black.withAlphaComponent(0.9).setFill())
    NSBezierPath(roundedRect: console, xRadius: 10 * s, yRadius: 10 * s).fill()

    // Punto ámbar (aviso) asomando bajo la isla
    NSColor.systemYellow.setFill()
    NSBezierPath(ovalIn: NSRect(x: 59 * s, y: 60 * s, width: 10 * s, height: 10 * s)).fill()

    // ">_" de la consola
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 30 * s, weight: .bold),
        .foregroundColor: accent,
        .paragraphStyle: para,
    ]
    (">_" as NSString).draw(in: console.offsetBy(dx: 0, dy: 6 * s), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, CGFloat)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                                  ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                                  ("icon_256x256", 256), ("icon_256x256@2x", 512),
                                  ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in sizes {
    if let data = draw(size: px) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset, "-o", icns]
try? proc.run()
proc.waitUntilExit()
print("icono en \(icns) (exit \(proc.terminationStatus))")
