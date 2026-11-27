// Draws the app icon and writes an .iconset: swift scripts/make-icon.swift <folder.iconset>
// Dark squircle with the same 270° gauge as the display: track, green->amber arc with glow, pace dot.
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // squircle background (macOS icon grid margin)
    let inset = s * 0.098
    let bg = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.225, yRadius: bg.width * 0.225)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    ctx.restoreGState()
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.16, green: 0.16, blue: 0.19, alpha: 1),
                        NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)])!
        .draw(in: bg, angle: -90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: bg.midX, y: bg.maxY), radius: 0,
              toCenter: NSPoint(x: bg.midX, y: bg.maxY), radius: bg.width * 0.8, options: [])
    ctx.restoreGState()

    // gauge (AppKit angles: counter-clockwise from 3 o'clock; the gap is at the bottom)
    let c = NSPoint(x: s / 2, y: s / 2 - s * 0.01)
    let r = s * 0.25
    let w = s * 0.075
    func arc(from a0: CGFloat, to a1: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.lineWidth = w
        p.lineCapStyle = .round
        p.appendArc(withCenter: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
        return p
    }
    let start: CGFloat = 225, end: CGFloat = -45     // full 270° track
    let value: CGFloat = 0.68
    let valueEnd = start - 270 * value

    NSColor.white.withAlphaComponent(0.13).setStroke()
    arc(from: start, to: end).stroke()

    // value arc: gradient green -> amber, with glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: NSColor(red: 0.95, green: 0.70, blue: 0.28, alpha: 0.7).cgColor)
    let valuePath = arc(from: start, to: valueEnd)
    let cgStroke = valuePath.cgPath.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 1)
    ctx.addPath(cgStroke)
    ctx.clip()
    NSGradient(colors: [NSColor(red: 0.31, green: 0.82, blue: 0.55, alpha: 1),
                        NSColor(red: 0.95, green: 0.70, blue: 0.28, alpha: 1)])!
        .draw(in: NSRect(x: c.x - r - w, y: c.y - r - w, width: 2 * (r + w), height: 2 * (r + w)), angle: 0)
    ctx.restoreGState()

    // pace dot
    let pace: CGFloat = 0.52
    let pa = (start - 270 * pace) * .pi / 180
    let dot = s * 0.05
    let dc = NSPoint(x: c.x + r * cos(pa), y: c.y + r * sin(pa))
    NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: dc.x - dot * 0.75, y: dc.y - dot * 0.75, width: dot * 1.5, height: dot * 1.5)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: dc.x - dot / 2, y: dc.y - dot / 2, width: dot, height: dot)).fill()

    // accent square in the middle (the device header mark)
    let sq = s * 0.085
    NSColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: c.x - sq / 2, y: c.y - sq / 2, width: sq, height: sq),
                 xRadius: sq * 0.28, yRadius: sq * 0.28).fill()

    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("uso: make-icon.swift <cartella.iconset>\n".utf8))
    exit(64)
}
let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
