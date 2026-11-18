import AppKit
import CoreGraphics
import Foundation

struct IconSpec {
    let relativePath: String
    let symbol: String
    let fallbackSymbol: String
    let topHex: UInt32
    let bottomHex: UInt32
}

func nsColor(hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255.0
    let g = CGFloat((hex >> 8) & 0xff) / 255.0
    let b = CGFloat(hex & 0xff) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func renderIcon(_ spec: IconSpec, rootDir: URL) throws {
    let size = 512
    let fSize = CGFloat(size)
    let tileInset: CGFloat = 24
    let tileRect = NSRect(x: tileInset, y: tileInset, width: fSize - tileInset * 2, height: fSize - tileInset * 2)
    let cornerRadius: CGFloat = 104

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bitmap alloc failed"])
    }
    rep.size = NSSize(width: fSize, height: fSize)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "GraphicsContext failed"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Clear canvas
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: fSize, height: fSize).fill()

    // Squircle-like continuous rounded rect clip
    let path = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    // Vertical gradient background (AppKit flipped=false: angle 270 is top-to-bottom)
    let gradient = NSGradient(starting: nsColor(hex: spec.topHex), ending: nsColor(hex: spec.bottomHex))!
    gradient.draw(in: tileRect, angle: 270)

    // Subtle top specular highlight
    let highlight = NSGradient(
        starting: NSColor(white: 1.0, alpha: 0.22),
        ending: NSColor(white: 1.0, alpha: 0.0)
    )!
    highlight.draw(
        in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2),
        angle: 270
    )

    // Inner subtle rim stroke
    NSColor(white: 1.0, alpha: 0.16).setStroke()
    path.lineWidth = 4
    path.stroke()

    // Crisp white SF Symbol centered inside tile
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 210, weight: .semibold)
        .applying(.init(paletteColors: [.white]))

    let symbolImage =
        NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        ?? NSImage(systemSymbolName: spec.fallbackSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)

    if let symbolImage {
        let sSize = symbolImage.size
        let maxBox: CGFloat = 260
        let scale = min(maxBox / max(sSize.width, 1), maxBox / max(sSize.height, 1), 1.3)
        let drawW = sSize.width * scale
        let drawH = sSize.height * scale
        let drawRect = NSRect(
            x: (fSize - drawW) / 2,
            y: (fSize - drawH) / 2,
            width: drawW,
            height: drawH
        )
        symbolImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.96)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }

    let outURL = rootDir.appendingPathComponent(spec.relativePath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: outURL, options: .atomic)
}

let specs: [IconSpec] = [
    // tiny-devkit
    IconSpec(relativePath: "extensions/tiny-devkit/assets/devkit.png", symbol: "wrench.and.screwdriver.fill", fallbackSymbol: "hammer.fill", topHex: 0x4F46E5, bottomHex: 0x3730A3),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-uuid.png", symbol: "touchid", fallbackSymbol: "number.square.fill", topHex: 0x6366F1, bottomHex: 0x4338CA),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-timestamp.png", symbol: "clock.fill", fallbackSymbol: "clock", topHex: 0xF59E0B, bottomHex: 0xD97706),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-hash.png", symbol: "lock.shield.fill", fallbackSymbol: "shield.fill", topHex: 0x10B981, bottomHex: 0x047857),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-codec.png", symbol: "chevron.left.forwardslash.chevron.right", fallbackSymbol: "curlybraces", topHex: 0x8B5CF6, bottomHex: 0x6D28D9),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-json.png", symbol: "curlybraces", fallbackSymbol: "doc.text.fill", topHex: 0x06B6D4, bottomHex: 0x0E7490),
    IconSpec(relativePath: "extensions/tiny-devkit/assets/cmd-color.png", symbol: "paintpalette.fill", fallbackSymbol: "eyedropper", topHex: 0xEC4899, bottomHex: 0x8B5CF6),

    // tiny-shortcuts
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/shortcuts.png", symbol: "bolt.fill", fallbackSymbol: "sparkles", topHex: 0x0EA5E9, bottomHex: 0x0369A1),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-password.png", symbol: "key.fill", fallbackSymbol: "lock.fill", topHex: 0xF43F5E, bottomHex: 0xBE123C),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-text.png", symbol: "textformat", fallbackSymbol: "doc.plaintext.fill", topHex: 0x3B82F6, bottomHex: 0x1D4ED8),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-qr.png", symbol: "qrcode", fallbackSymbol: "barcode", topHex: 0x334155, bottomHex: 0x0F172A),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-cron.png", symbol: "calendar.badge.clock", fallbackSymbol: "calendar", topHex: 0xF97316, bottomHex: 0xC2410C),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-network.png", symbol: "network", fallbackSymbol: "globe", topHex: 0x14B8A6, bottomHex: 0x0F766E),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-clipboard.png", symbol: "doc.on.clipboard.fill", fallbackSymbol: "doc.on.doc.fill", topHex: 0x7C3AED, bottomHex: 0x5B21B6),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-terminal.png", symbol: "terminal.fill", fallbackSymbol: "terminal", topHex: 0x27272A, bottomHex: 0x18181B),
    IconSpec(relativePath: "extensions/tiny-shortcuts/assets/cmd-finder.png", symbol: "folder.fill", fallbackSymbol: "folder", topHex: 0x2563EB, bottomHex: 0x1E40AF),
]

let rootDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for spec in specs {
    try renderIcon(spec, rootDir: rootDir)
    print("Generated \(spec.relativePath)")
}
