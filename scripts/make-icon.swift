// Draws the app icon at 1024x1024 and writes it as a PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ path: CGPath, _ top: CGColor, _ bottom: CGColor, in rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

// Background: macOS-style rounded square with a deep blue "Mission Control" gradient.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = roundedRect(plate, 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
ctx.addPath(platePath)
ctx.setFillColor(color(0x1B2350))
ctx.fillPath()
ctx.restoreGState()
fillGradient(platePath, color(0x3D5AFE), color(0x161C48), in: plate)

// Soft glow behind the windows.
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let glow = CGGradient(colorsSpace: space, colors: [color(0x8FA4FF, 0.35), color(0x8FA4FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
ctx.restoreGState()

/// A window thumbnail with a title bar, a few content lines, and an app icon badge at the bottom.
func drawWindow(_ rect: CGRect, badge: (top: UInt32, bottom: UInt32), glyph: (CGRect) -> Void) {
    let radius = rect.width * 0.06
    let path = roundedRect(rect, radius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x000000, 0.45))
    ctx.addPath(path)
    ctx.setFillColor(color(0xF4F6FF))
    ctx.fillPath()
    ctx.restoreGState()

    // Title bar with traffic lights.
    let barHeight = rect.height * 0.16
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(color(0xDDE2F5))
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - barHeight, width: rect.width, height: barHeight))
    ctx.restoreGState()
    let dot = barHeight * 0.38
    for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(color(UInt32(hex)))
        ctx.fillEllipse(in: CGRect(x: rect.minX + barHeight * 0.45 + CGFloat(i) * dot * 1.6,
                                   y: rect.maxY - barHeight / 2 - dot / 2, width: dot, height: dot))
    }

    // Content lines.
    let lineHeight = rect.height * 0.06
    for (i, widthFactor) in [0.7, 0.55, 0.62].enumerated() {
        let y = rect.maxY - barHeight - lineHeight * 1.6 - CGFloat(i) * lineHeight * 1.9
        ctx.addPath(roundedRect(CGRect(x: rect.minX + rect.width * 0.1, y: y, width: rect.width * widthFactor, height: lineHeight), lineHeight / 2))
        ctx.setFillColor(color(0xC3CAE6))
        ctx.fillPath()
    }

    // App icon badge, centred at the bottom of the window like the overlay draws it.
    let side = rect.width * 0.26
    let badgeRect = CGRect(x: rect.midX - side / 2, y: rect.minY - side * 0.3, width: side, height: side)
    let badgePath = roundedRect(badgeRect, side * 0.23)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: color(0x000000, 0.4))
    ctx.addPath(badgePath)
    ctx.setFillColor(color(badge.bottom))
    ctx.fillPath()
    ctx.restoreGState()
    fillGradient(badgePath, color(badge.top), color(badge.bottom), in: badgeRect)
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    glyph(badgeRect.insetBy(dx: side * 0.27, dy: side * 0.27))
}

drawWindow(CGRect(x: 178, y: 530, width: 316, height: 214), badge: (0xFFB347, 0xFF6A00)) { r in
    ctx.fillEllipse(in: r)
}
drawWindow(CGRect(x: 530, y: 530, width: 316, height: 214), badge: (0x6EE7A0, 0x14A85A)) { r in
    ctx.addPath(roundedRect(r, r.width * 0.2))
    ctx.fillPath()
}
drawWindow(CGRect(x: 272, y: 238, width: 480, height: 248), badge: (0xFF7EB3, 0xE0245E)) { r in
    ctx.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY))
    ctx.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
    ctx.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    ctx.closePath()
    ctx.fillPath()
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
