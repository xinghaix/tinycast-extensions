import AppKit
import Foundation

// MARK: - Canonical Color Value & Spaces

struct ColorRGBA: Equatable, Sendable {
    var r: Double // 0...1 sRGB
    var g: Double // 0...1 sRGB
    var b: Double // 0...1 sRGB
    var a: Double // 0...1

    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
        self.a = min(max(a, 0), 1)
    }

    var r255: Int { Int((r * 255.0).rounded()) }
    var g255: Int { Int((g * 255.0).rounded()) }
    var b255: Int { Int((b * 255.0).rounded()) }
    var a255: Int { Int((a * 255.0).rounded()) }

    var hasAlpha: Bool { a < 0.998 }

    var hex6Lower: String { String(format: "#%02x%02x%02x", r255, g255, b255) }
    var hex6Upper: String { String(format: "#%02X%02X%02X", r255, g255, b255) }
    var hex8Lower: String { String(format: "#%02x%02x%02x%02x", r255, g255, b255, a255) }
    var hex8Upper: String { String(format: "#%02X%02X%02X%02X", r255, g255, b255, a255) }
    var hexAutoLower: String { hasAlpha ? hex8Lower : hex6Lower }
    var hexAutoUpper: String { hasAlpha ? hex8Upper : hex6Upper }
    var androidArgbHex: String { String(format: "#%02X%02X%02X%02X", a255, r255, g255, b255) }
    var hex0xARGB: String { String(format: "0x%02X%02X%02X%02X", a255, r255, g255, b255) }
    var hex0xRGB: String { String(format: "0x%02X%02X%02X", r255, g255, b255) }

    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    func composited(over bg: ColorRGBA) -> ColorRGBA {
        let outA = a + bg.a * (1.0 - a)
        guard outA > 1e-6 else { return ColorRGBA(r: 0, g: 0, b: 0, a: 0) }
        return ColorRGBA(
            r: (r * a + bg.r * bg.a * (1.0 - a)) / outA,
            g: (g * a + bg.g * bg.a * (1.0 - a)) / outA,
            b: (b * a + bg.b * bg.a * (1.0 - a)) / outA,
            a: outA
        )
    }
}

struct ColorHSL: Equatable, Sendable {
    var h: Double // 0...360
    var s: Double // 0...100
    var l: Double // 0...100
    var a: Double // 0...1
}

struct ColorHSV: Equatable, Sendable {
    var h: Double // 0...360
    var s: Double // 0...100
    var v: Double // 0...100
    var a: Double // 0...1
}

struct ColorOKLCH: Equatable, Sendable {
    var l: Double // 0...1
    var c: Double // 0...0.4
    var h: Double // 0...360
    var a: Double // 0...1
}

struct ColorOKLab: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double
    var alpha: Double
}

struct ColorLab: Equatable, Sendable {
    var l: Double // 0...100 (D50)
    var a: Double
    var b: Double
    var alpha: Double
}

struct ColorCMYK: Equatable, Sendable {
    var c: Double // 0...100
    var m: Double // 0...100
    var y: Double // 0...100
    var k: Double // 0...100
}

struct ColorFormatEntry: Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case web = "CSS / Web"
        case apple = "Apple (SwiftUI / AppKit / UIKit)"
        case mobile = "Android / Flutter / Hex / 印刷"
    }
    let id: String
    let group: Group
    let title: String
    let value: String
    let badge: String
}

struct ColorMatchBadge: Sendable {
    let name: String
    let source: String
    let hex: String
    let deltaE: Double
}

struct WcagReport: Sendable {
    let ratio: Double
    let apcaLc: Double
    let aaNormal: Bool    // >= 4.5
    let aaaNormal: Bool   // >= 7.0
    let aaLarge: Bool     // >= 3.0
    let aaaLarge: Bool    // >= 4.5
    let effectiveForeground: ColorRGBA
}

struct ColorHarmonyItem: Identifiable, Sendable {
    let id: String
    let role: String
    let angleOffset: Int
    let color: ColorRGBA
}

struct ColorHarmonyGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [ColorHarmonyItem]
}

struct PaletteShade: Identifiable, Sendable {
    var id: Int { step }
    let step: Int
    let color: ColorRGBA
    let isBase: Bool
}

struct CvdSimulation: Identifiable, Sendable {
    let id: String
    let title: String
    let prevalence: String
    let color: ColorRGBA
}

// MARK: - Color Conversion & Analysis Engine

enum ColorEngine {
    // MARK: Named Colors (All 148 CSS Level 4 + Core Tailwind Palette)

    static let cssNamedColors: [String: String] = [
        "aliceblue": "#f0f8ff", "antiquewhite": "#faebd7", "aqua": "#00ffff", "aquamarine": "#7fffd4",
        "azure": "#f0ffff", "beige": "#f5f5dc", "bisque": "#ffe4c4", "black": "#000000",
        "blanchedalmond": "#ffebcd", "blue": "#0000ff", "blueviolet": "#8a2be2", "brown": "#a52a2a",
        "burlywood": "#deb887", "cadetblue": "#5f9ea0", "chartreuse": "#7fff00", "chocolate": "#d2691e",
        "coral": "#ff7f50", "cornflowerblue": "#6495ed", "cornsilk": "#fff8dc", "crimson": "#dc143c",
        "cyan": "#00ffff", "darkblue": "#00008b", "darkcyan": "#008b8b", "darkgoldenrod": "#b8860b",
        "darkgray": "#a9a9a9", "darkgreen": "#006400", "darkgrey": "#a9a9a9", "darkkhaki": "#bdb76b",
        "darkmagenta": "#8b008b", "darkolivegreen": "#556b2f", "darkorange": "#ff8c00", "darkorchid": "#9932cc",
        "darkred": "#8b0000", "darksalmon": "#e9967a", "darkseagreen": "#8fbc8f", "darkslateblue": "#483d8b",
        "darkslategray": "#2f4f4f", "darkslategrey": "#2f4f4f", "darkturquoise": "#00ced1", "darkviolet": "#9400d3",
        "deeppink": "#ff1493", "deepskyblue": "#00bfff", "dimgray": "#696969", "dimgrey": "#696969",
        "dodgerblue": "#1e90ff", "firebrick": "#b22222", "floralwhite": "#fffaf0", "forestgreen": "#228b22",
        "fuchsia": "#ff00ff", "gainsboro": "#dcdcdc", "ghostwhite": "#f8f8ff", "gold": "#ffd700",
        "goldenrod": "#daa520", "gray": "#808080", "green": "#008000", "greenyellow": "#adff2f",
        "grey": "#808080", "honeydew": "#f0fff0", "hotpink": "#ff69b4", "indianred": "#cd5c5c",
        "indigo": "#4b0082", "ivory": "#fffff0", "khaki": "#f0e68c", "lavender": "#e6e6fa",
        "lavenderblush": "#fff0f5", "lawngreen": "#7cfc00", "lemonchiffon": "#fffacd", "lightblue": "#add8e6",
        "lightcoral": "#f08080", "lightcyan": "#e0ffff", "lightgoldenrodyellow": "#fafad2", "lightgray": "#d3d3d3",
        "lightgreen": "#90ee90", "lightgrey": "#d3d3d3", "lightpink": "#ffb6c1", "lightsalmon": "#ffa07a",
        "lightseagreen": "#20b2aa", "lightskyblue": "#87cefa", "lightslategray": "#778899", "lightslategrey": "#778899",
        "lightsteelblue": "#b0c4de", "lightyellow": "#ffffe0", "lime": "#00ff00", "limegreen": "#32cd32",
        "linen": "#faf0e6", "magenta": "#ff00ff", "maroon": "#800000", "mediumaquamarine": "#66cdaa",
        "mediumblue": "#0000cd", "mediumorchid": "#ba55d3", "mediumpurple": "#9370db", "mediumseagreen": "#3cb371",
        "mediumslateblue": "#7b68ee", "mediumspringgreen": "#00fa9a", "mediumturquoise": "#48d1cc", "mediumvioletred": "#c71585",
        "midnightblue": "#191970", "mintcream": "#f5fffa", "mistyrose": "#ffe4e1", "moccasin": "#ffe4b5",
        "navajowhite": "#ffdead", "navy": "#000080", "oldlace": "#fdf5e6", "olive": "#808000",
        "olivedrab": "#6b8e23", "orange": "#ffa500", "orangered": "#ff4500", "orchid": "#da70d6",
        "palegoldenrod": "#eee8aa", "palegreen": "#98fb98", "paleturquoise": "#afeeee", "palevioletred": "#db7093",
        "papayawhip": "#ffefd5", "peachpuff": "#ffdab9", "peru": "#cd853f", "pink": "#ffc0cb",
        "plum": "#dda0dd", "powderblue": "#b0e0e6", "purple": "#800080", "rebeccapurple": "#663399",
        "red": "#ff0000", "rosybrown": "#bc8f8f", "royalblue": "#4169e1", "saddlebrown": "#8b4513",
        "salmon": "#fa8072", "sandybrown": "#f4a460", "seagreen": "#2e8b57", "seashell": "#fff5ee",
        "sienna": "#a0522d", "silver": "#c0c0c0", "skyblue": "#87ceeb", "slateblue": "#6a5acd",
        "slategray": "#708090", "slategrey": "#708090", "snow": "#fffafa", "springgreen": "#00ff7f",
        "steelblue": "#4682b4", "tan": "#d2b48c", "teal": "#008080", "thistle": "#d8bfd8",
        "tomato": "#ff6347", "transparent": "#00000000", "turquoise": "#40e0d0", "violet": "#ee82ee",
        "wheat": "#f5deb3", "white": "#ffffff", "whitesmoke": "#f5f5f5", "yellow": "#ffff00", "yellowgreen": "#9acd32",
    ]

    static let tailwindNamedColors: [(name: String, hex: String)] = [
        ("slate-500", "#64748b"), ("slate-700", "#334155"), ("slate-900", "#0f172a"),
        ("gray-500", "#6b7280"), ("zinc-500", "#71717a"), ("zinc-900", "#18181b"),
        ("red-500", "#ef4444"), ("red-600", "#dc2626"), ("orange-500", "#f97316"),
        ("amber-500", "#f59e0b"), ("yellow-400", "#facc15"), ("lime-500", "#84cc16"),
        ("green-500", "#22c55e"), ("emerald-500", "#10b981"), ("teal-500", "#14b8a6"),
        ("cyan-500", "#06b6d4"), ("sky-500", "#0ea5e9"), ("blue-500", "#3b82f6"),
        ("blue-600", "#2563eb"), ("indigo-500", "#6366f1"), ("indigo-600", "#4f46e5"),
        ("violet-500", "#8b5cf6"), ("purple-500", "#a855f7"), ("fuchsia-500", "#d946ef"),
        ("pink-500", "#ec4899"), ("rose-500", "#f43f5e"),
    ]

    static let presets: [(title: String, hex: String)] = [
        ("Blue 500", "#3B82F6"),
        ("Indigo 500", "#6366F1"),
        ("Emerald", "#10B981"),
        ("Amber", "#F59E0B"),
        ("Rose", "#F43F5E"),
        ("Violet", "#8B5CF6"),
        ("Teal", "#14B8A6"),
        ("Rebecca", "#663399"),
        ("Coral", "#FF6B6B"),
        ("Dark UI", "#1E293B"),
    ]

    // MARK: - Universal Color Parser

    static func parse(_ raw: String) -> ColorRGBA? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let low = s.lowercased()

        // 1. Named CSS or Tailwind tokens
        if let hex = cssNamedColors[low] {
            return parseHex(hex)
        }
        if let tw = tailwindNamedColors.first(where: { $0.name == low }) {
            return parseHex(tw.hex)
        }

        // 2. Android / Flutter / Jetpack Compose Color(0xAARRGGBB)
        if let m = s.wholeMatch(of: /(?i)^(?:Color\s*\(\s*)?0x([0-9a-f]{6}|[0-9a-f]{8})\s*\)?$/) {
            let digits = String(m.1)
            if digits.count == 6 {
                return parseHex("#" + digits)
            }
            // 0xAARRGGBB -> split AA RR GG BB
            let a = hexByte(digits, at: 0)
            let r = hexByte(digits, at: 2)
            let g = hexByte(digits, at: 4)
            let b = hexByte(digits, at: 6)
            return ColorRGBA(r: r, g: g, b: b, a: a)
        }

        // 3. Hex (#RGB, #RGBA, #RRGGBB, #RRGGBBAA, or bare 6/8-char hex containing at least one A-F letter)
        if s.hasPrefix("#") {
            return parseHex(s)
        }
        if s.wholeMatch(of: /^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/) != nil,
           s.contains(where: { ("a"..."f").contains($0) || ("A"..."F").contains($0) }) {
            return parseHex(s)
        }

        // 4. SwiftUI / AppKit / UIKit constructors
        if let swiftColor = parseSwiftConstructor(s) {
            return swiftColor
        }

        // 5. CSS functional syntaxes
        if let fn = parseCssFunction(s) {
            return fn
        }

        // 6. Bare numeric RGB/RGBA tuple: "59, 130, 246" or "0.23, 0.51, 0.96"
        if let m = s.wholeMatch(of: /^\s*([+-]?\d+(?:\.\d+)?)\s*[, ]\s*([+-]?\d+(?:\.\d+)?)\s*[, ]\s*([+-]?\d+(?:\.\d+)?)(?:\s*[,\/]\s*([+-]?\d+(?:\.\d+)?%?))?\s*$/) {
            if let v1 = Double(m.1), let v2 = Double(m.2), let v3 = Double(m.3) {
                let alpha = m.4.flatMap { parseAlpha(String($0)) } ?? 1.0
                if v1 <= 1.0 && v2 <= 1.0 && v3 <= 1.0 && (m.1.contains(".") || m.2.contains(".") || m.3.contains(".")) {
                    return ColorRGBA(r: v1, g: v2, b: v3, a: alpha)
                }
                if (0...255).contains(v1) && (0...255).contains(v2) && (0...255).contains(v3) {
                    return ColorRGBA(r: v1 / 255.0, g: v2 / 255.0, b: v3 / 255.0, a: alpha)
                }
            }
        }

        return nil
    }

    private static func parseHex(_ raw: String) -> ColorRGBA? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard body.allSatisfy(\.isHexDigit) else { return nil }
        switch body.count {
        case 3:
            let chars = Array(body)
            let r = Double(Int(String([chars[0], chars[0]]), radix: 16) ?? 0) / 255.0
            let g = Double(Int(String([chars[1], chars[1]]), radix: 16) ?? 0) / 255.0
            let b = Double(Int(String([chars[2], chars[2]]), radix: 16) ?? 0) / 255.0
            return ColorRGBA(r: r, g: g, b: b, a: 1.0)
        case 4:
            let chars = Array(body)
            let r = Double(Int(String([chars[0], chars[0]]), radix: 16) ?? 0) / 255.0
            let g = Double(Int(String([chars[1], chars[1]]), radix: 16) ?? 0) / 255.0
            let b = Double(Int(String([chars[2], chars[2]]), radix: 16) ?? 0) / 255.0
            let a = Double(Int(String([chars[3], chars[3]]), radix: 16) ?? 255) / 255.0
            return ColorRGBA(r: r, g: g, b: b, a: a)
        case 6:
            return ColorRGBA(r: hexByte(body, at: 0), g: hexByte(body, at: 2), b: hexByte(body, at: 4), a: 1.0)
        case 8:
            return ColorRGBA(r: hexByte(body, at: 0), g: hexByte(body, at: 2), b: hexByte(body, at: 4), a: hexByte(body, at: 6))
        default:
            return nil
        }
    }

    private static func hexByte(_ str: String, at offset: Int) -> Double {
        let start = str.index(str.startIndex, offsetBy: offset)
        let end = str.index(start, offsetBy: 2)
        return Double(Int(str[start..<end], radix: 16) ?? 0) / 255.0
    }

    private static func parseSwiftConstructor(_ s: String) -> ColorRGBA? {
        guard s.range(of: #"(?i)^(?:NSColor|UIColor|Color|CGColor)\s*\("#, options: .regularExpression) != nil,
              let open = s.firstIndex(of: "("),
              let close = s.lastIndex(of: ")") else { return nil }
        let inner = String(s[s.index(after: open)..<close])
        func extract(_ labelPattern: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: "\(labelPattern)\\s*:\\s*([+-]?\\d+(?:\\.\\d+)?)", options: .caseInsensitive),
                  let m = re.firstMatch(in: inner, range: NSRange(inner.startIndex..<inner.endIndex, in: inner)),
                  let r = Range(m.range(at: 1), in: inner) else { return nil }
            return Double(inner[r])
        }
        guard let r = extract("(?:srgbRed|displayP3Red|red)"),
              let g = extract("green"),
              let b = extract("blue") else { return nil }
        let a = extract("(?:alpha|opacity)") ?? 1.0
        return ColorRGBA(r: r, g: g, b: b, a: a)
    }

    private static func parseCssFunction(_ s: String) -> ColorRGBA? {
        guard let m = s.wholeMatch(of: /(?i)^([a-z]+)\s*\((.+)\)$/) else { return nil }
        let name = String(m.1).lowercased()
        let inner = String(m.2).trimmingCharacters(in: .whitespacesAndNewlines)

        // Split optional "/ alpha"
        let slashSplit = inner.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let body = slashSplit[0]
        var tokens = body.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var alpha = 1.0
        if slashSplit.count == 2 {
            guard let a = parseAlpha(slashSplit[1]) else { return nil }
            alpha = a
        } else if tokens.count == 4 && name != "cmyk" {
            guard let a = parseAlpha(tokens.removeLast()) else { return nil }
            alpha = a
        }

        switch name {
        case "rgb", "rgba":
            guard tokens.count == 3,
                  let r = parseRgbComponent(tokens[0]),
                  let g = parseRgbComponent(tokens[1]),
                  let b = parseRgbComponent(tokens[2]) else { return nil }
            return ColorRGBA(r: r, g: g, b: b, a: alpha)
        case "hsl", "hsla":
            guard tokens.count == 3,
                  let h = parseAngle(tokens[0]),
                  let sat = parsePercentOrNumber(tokens[1], maxVal: 100),
                  let lit = parsePercentOrNumber(tokens[2], maxVal: 100) else { return nil }
            return fromHSL(ColorHSL(h: h, s: min(max(sat, 0), 100), l: min(max(lit, 0), 100), a: alpha))
        case "hsv", "hsb":
            guard tokens.count == 3,
                  let h = parseAngle(tokens[0]),
                  let sat = parsePercentOrNumber(tokens[1], maxVal: 100),
                  let val = parsePercentOrNumber(tokens[2], maxVal: 100) else { return nil }
            return fromHSV(ColorHSV(h: h, s: min(max(sat, 0), 100), v: min(max(val, 0), 100), a: alpha))
        case "hwb":
            guard tokens.count == 3,
                  let h = parseAngle(tokens[0]),
                  let w = parsePercentOrNumber(tokens[1], maxVal: 100),
                  let b = parsePercentOrNumber(tokens[2], maxVal: 100) else { return nil }
            return fromHWB(h: h, wPct: w, bPct: b, alpha: alpha)
        case "oklch":
            guard tokens.count == 3,
                  let l = parseOklabL(tokens[0]),
                  let c = parsePercentOrUnit(tokens[1], percentFull: 0.4),
                  let h = parseAngle(tokens[2]) else { return nil }
            return fromOKLCH(ColorOKLCH(l: min(max(l, 0), 1), c: max(c, 0), h: h, a: alpha))
        case "oklab":
            guard tokens.count == 3,
                  let l = parseOklabL(tokens[0]),
                  let aComp = parsePercentOrUnit(tokens[1], percentFull: 0.4),
                  let bComp = parsePercentOrUnit(tokens[2], percentFull: 0.4) else { return nil }
            return fromOKLab(ColorOKLab(l: min(max(l, 0), 1), a: aComp, b: bComp, alpha: alpha))
        case "lab":
            guard tokens.count == 3,
                  let l = parsePercentOrNumber(tokens[0], maxVal: 100),
                  let aComp = parsePercentOrUnit(tokens[1], percentFull: 125.0),
                  let bComp = parsePercentOrUnit(tokens[2], percentFull: 125.0) else { return nil }
            return fromLab(ColorLab(l: min(max(l, 0), 100), a: aComp, b: bComp, alpha: alpha))
        case "lch":
            guard tokens.count == 3,
                  let l = parsePercentOrNumber(tokens[0], maxVal: 100),
                  let c = parsePercentOrUnit(tokens[1], percentFull: 150.0),
                  let h = parseAngle(tokens[2]) else { return nil }
            let rad = h * .pi / 180.0
            return fromLab(ColorLab(l: min(max(l, 0), 100), a: c * cos(rad), b: c * sin(rad), alpha: alpha))
        case "cmyk":
            guard tokens.count == 4,
                  let c = parseCmykComponent(tokens[0]),
                  let m = parseCmykComponent(tokens[1]),
                  let y = parseCmykComponent(tokens[2]),
                  let k = parseCmykComponent(tokens[3]) else { return nil }
            return fromCMYK(ColorCMYK(c: c, m: m, y: y, k: k), alpha: alpha)
        default:
            return nil
        }
    }

    private static func parseAlpha(_ token: String) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return min(max(v / 100.0, 0), 1)
        }
        guard let v = Double(token) else { return nil }
        return min(max(v, 0), 1)
    }

    private static func parseRgbComponent(_ token: String) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return min(max(v / 100.0, 0), 1)
        }
        guard let v = Double(token) else { return nil }
        return min(max(v / 255.0, 0), 1)
    }

    private static func parsePercentOrNumber(_ token: String, maxVal: Double) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return v * (maxVal / 100.0)
        }
        return Double(token)
    }

    private static func parsePercentOrUnit(_ token: String, percentFull: Double) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return (v / 100.0) * percentFull
        }
        return Double(token)
    }

    private static func parseOklabL(_ token: String) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return v / 100.0
        }
        guard let v = Double(token) else { return nil }
        return v > 1.0 ? v / 100.0 : v
    }

    private static func parseCmykComponent(_ token: String) -> Double? {
        if token.hasSuffix("%"), let v = Double(token.dropLast()) {
            return min(max(v, 0), 100)
        }
        guard let v = Double(token) else { return nil }
        return min(max(v <= 1.0 ? v * 100.0 : v, 0), 100)
    }

    private static func parseAngle(_ token: String) -> Double? {
        let low = token.lowercased()
        let raw: Double
        if low.hasSuffix("deg"), let v = Double(low.dropLast(3)) { raw = v }
        else if low.hasSuffix("rad"), let v = Double(low.dropLast(3)) { raw = v * 180.0 / .pi }
        else if low.hasSuffix("grad"), let v = Double(low.dropLast(4)) { raw = v * 0.9 }
        else if low.hasSuffix("turn"), let v = Double(low.dropLast(4)) { raw = v * 360.0 }
        else if let v = Double(low) { raw = v }
        else { return nil }
        let mod = raw.truncatingRemainder(dividingBy: 360.0)
        return mod < 0 ? mod + 360.0 : mod
    }

    // MARK: - Color Space Conversions

    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linearToSrgb(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }

    static func toHSL(_ c: ColorRGBA) -> ColorHSL {
        let maxC = max(c.r, c.g, c.b)
        let minC = min(c.r, c.g, c.b)
        let d = maxC - minC
        let l = (maxC + minC) / 2.0
        var h = 0.0
        var s = 0.0
        if d > 1e-7 {
            s = d / (1.0 - abs(2.0 * l - 1.0))
            if maxC == c.r {
                h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == c.g {
                h = (c.b - c.r) / d + 2.0
            } else {
                h = (c.r - c.g) / d + 4.0
            }
            h *= 60.0
            if h < 0 { h += 360.0 }
        }
        return ColorHSL(h: h, s: min(max(s * 100.0, 0), 100), l: min(max(l * 100.0, 0), 100), a: c.a)
    }

    static func fromHSL(_ hsl: ColorHSL) -> ColorRGBA {
        let h = ((hsl.h.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let s = min(max(hsl.s / 100.0, 0), 1)
        let l = min(max(hsl.l / 100.0, 0), 1)
        let c = (1.0 - abs(2.0 * l - 1.0)) * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = l - c / 2.0
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return ColorRGBA(r: r1 + m, g: g1 + m, b: b1 + m, a: hsl.a)
    }

    static func toHSV(_ c: ColorRGBA) -> ColorHSV {
        let maxC = max(c.r, c.g, c.b)
        let minC = min(c.r, c.g, c.b)
        let d = maxC - minC
        var h = 0.0
        if d > 1e-7 {
            if maxC == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6.0) }
            else if maxC == c.g { h = (c.b - c.r) / d + 2.0 }
            else { h = (c.r - c.g) / d + 4.0 }
            h *= 60.0
            if h < 0 { h += 360.0 }
        }
        let s = maxC > 1e-7 ? (d / maxC) * 100.0 : 0.0
        return ColorHSV(h: h, s: s, v: maxC * 100.0, a: c.a)
    }

    static func fromHSV(_ hsv: ColorHSV) -> ColorRGBA {
        let h = ((hsv.h.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let s = min(max(hsv.s / 100.0, 0), 1)
        let v = min(max(hsv.v / 100.0, 0), 1)
        let c = v * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return ColorRGBA(r: r1 + m, g: g1 + m, b: b1 + m, a: hsv.a)
    }

    static func toHWB(_ c: ColorRGBA) -> (h: Double, w: Double, b: Double) {
        let hsv = toHSV(c)
        let w = min(c.r, c.g, c.b) * 100.0
        let blk = (1.0 - max(c.r, c.g, c.b)) * 100.0
        return (hsv.h, w, blk)
    }

    static func fromHWB(h: Double, wPct: Double, bPct: Double, alpha: Double = 1.0) -> ColorRGBA {
        let w = max(wPct, 0) / 100.0
        let blk = max(bPct, 0) / 100.0
        if w + blk >= 1.0 {
            let gray = w / (w + blk)
            return ColorRGBA(r: gray, g: gray, b: gray, a: alpha)
        }
        let pure = fromHSL(ColorHSL(h: h, s: 100, l: 50, a: alpha))
        let factor = 1.0 - w - blk
        return ColorRGBA(r: pure.r * factor + w, g: pure.g * factor + w, b: pure.b * factor + w, a: alpha)
    }

    static func toCMYK(_ c: ColorRGBA) -> ColorCMYK {
        let k = 1.0 - max(c.r, c.g, c.b)
        if k >= 0.9999 {
            return ColorCMYK(c: 0, m: 0, y: 0, k: 100)
        }
        let denom = 1.0 - k
        return ColorCMYK(
            c: ((1.0 - c.r - k) / denom) * 100.0,
            m: ((1.0 - c.g - k) / denom) * 100.0,
            y: ((1.0 - c.b - k) / denom) * 100.0,
            k: k * 100.0
        )
    }

    static func fromCMYK(_ cmyk: ColorCMYK, alpha: Double = 1.0) -> ColorRGBA {
        let c = min(max(cmyk.c / 100.0, 0), 1)
        let m = min(max(cmyk.m / 100.0, 0), 1)
        let y = min(max(cmyk.y / 100.0, 0), 1)
        let k = min(max(cmyk.k / 100.0, 0), 1)
        return ColorRGBA(
            r: (1.0 - c) * (1.0 - k),
            g: (1.0 - m) * (1.0 - k),
            b: (1.0 - y) * (1.0 - k),
            a: alpha
        )
    }

    static func toOKLab(_ c: ColorRGBA) -> ColorOKLab {
        let r = srgbToLinear(c.r)
        let g = srgbToLinear(c.g)
        let b = srgbToLinear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return ColorOKLab(
            l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            alpha: c.a
        )
    }

    static func toOKLCH(_ c: ColorRGBA) -> ColorOKLCH {
        let lab = toOKLab(c)
        let chroma = hypot(lab.a, lab.b)
        var hue = atan2(lab.b, lab.a) * 180.0 / .pi
        if hue < 0 { hue += 360.0 }
        if chroma < 1e-6 { hue = 0 }
        return ColorOKLCH(l: lab.l, c: chroma, h: hue, a: c.a)
    }

    private static func rawLinearFromOKLab(_ lab: ColorOKLab) -> (Double, Double, Double) {
        let l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_
        return (
            +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    static func fromOKLab(_ lab: ColorOKLab) -> ColorRGBA {
        let (r, g, b) = rawLinearFromOKLab(lab)
        return ColorRGBA(r: linearToSrgb(r), g: linearToSrgb(g), b: linearToSrgb(b), a: lab.alpha)
    }

    /// Gamut-mapped OKLCH -> sRGB conversion (binary reduces Chroma while preserving perceptual L and Hue).
    static func fromOKLCH(_ lch: ColorOKLCH) -> ColorRGBA {
        let L = min(max(lch.l, 0), 1)
        let rad = lch.h * .pi / 180.0
        func inGamut(_ cTest: Double) -> Bool {
            let (r, g, b) = rawLinearFromOKLab(ColorOKLab(l: L, a: cTest * cos(rad), b: cTest * sin(rad), alpha: lch.a))
            return r >= -0.0005 && r <= 1.0005 && g >= -0.0005 && g <= 1.0005 && b >= -0.0005 && b <= 1.0005
        }
        var targetC = max(lch.c, 0)
        if targetC > 0 && !inGamut(targetC) {
            var lo = 0.0
            var hi = targetC
            for _ in 0..<18 {
                let mid = (lo + hi) * 0.5
                if inGamut(mid) { lo = mid } else { hi = mid }
            }
            targetC = lo
        }
        return fromOKLab(ColorOKLab(l: L, a: targetC * cos(rad), b: targetC * sin(rad), alpha: lch.a))
    }

    // CSS Color 4 CIE Lab (D50) via sRGB -> XYZ(D65) -> Bradford -> XYZ(D50)
    static func toLab(_ c: ColorRGBA) -> ColorLab {
        let r = srgbToLinear(c.r), g = srgbToLinear(c.g), b = srgbToLinear(c.b)
        // sRGB -> XYZ (D50 combined matrix per CSS Color 4)
        let X = 0.4360747 * r + 0.3850649 * g + 0.1430804 * b
        let Y = 0.2225045 * r + 0.7168786 * g + 0.0606169 * b
        let Z = 0.0139322 * r + 0.0971045 * g + 0.7141733 * b
        let xn = 0.964295676, yn = 1.0, zn = 0.825104603
        let e = 216.0 / 24389.0
        let k = 24389.0 / 27.0
        let fx = X / xn > e ? cbrt(X / xn) : (k * (X / xn) + 16.0) / 116.0
        let fy = Y / yn > e ? cbrt(Y / yn) : (k * (Y / yn) + 16.0) / 116.0
        let fz = Z / zn > e ? cbrt(Z / zn) : (k * (Z / zn) + 16.0) / 116.0
        return ColorLab(l: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz), alpha: c.a)
    }

    static func fromLab(_ lab: ColorLab) -> ColorRGBA {
        let fy = (lab.l + 16.0) / 116.0
        let fx = lab.a / 500.0 + fy
        let fz = fy - lab.b / 200.0
        let e = 216.0 / 24389.0
        let k = 24389.0 / 27.0
        let xr = fx * fx * fx > e ? fx * fx * fx : (116.0 * fx - 16.0) / k
        let yr = lab.l > k * e ? pow((lab.l + 16.0) / 116.0, 3.0) : lab.l / k
        let zr = fz * fz * fz > e ? fz * fz * fz : (116.0 * fz - 16.0) / k
        let X = xr * 0.964295676, Y = yr * 1.0, Z = zr * 0.825104603
        // XYZ(D50) -> linear sRGB
        let r =  3.1338561 * X - 1.6168667 * Y - 0.4906146 * Z
        let g = -0.9787684 * X + 1.9161415 * Y + 0.0334540 * Z
        let b =  0.0719453 * X - 0.2289914 * Y + 1.4052427 * Z
        return ColorRGBA(r: linearToSrgb(r), g: linearToSrgb(g), b: linearToSrgb(b), a: lab.alpha)
    }

    // MARK: - Formatting Matrix

    static func formatAll(_ c: ColorRGBA) -> [ColorFormatEntry] {
        let hsl = toHSL(c)
        let hsv = toHSV(c)
        let hwb = toHWB(c)
        let oklch = toOKLCH(c)
        let oklab = toOKLab(c)
        let lab = toLab(c)
        let cmyk = toCMYK(c)
        let lchC = hypot(lab.a, lab.b)
        var lchH = atan2(lab.b, lab.a) * 180.0 / .pi
        if lchH < 0 { lchH += 360.0 }

        let aFmt = fmtDec(c.a, 2)
        let aPct = "\(Int((c.a * 100.0).rounded()))%"
        let hasA = c.hasAlpha

        let rgbLegacy = hasA
            ? "rgba(\(c.r255), \(c.g255), \(c.b255), \(aFmt))"
            : "rgb(\(c.r255), \(c.g255), \(c.b255))"
        let rgbModern = hasA
            ? "rgb(\(c.r255) \(c.g255) \(c.b255) / \(aPct))"
            : "rgb(\(c.r255) \(c.g255) \(c.b255))"
        let hslLegacy = hasA
            ? "hsla(\(Int(hsl.h.rounded())), \(Int(hsl.s.rounded()))%, \(Int(hsl.l.rounded()))%, \(aFmt))"
            : "hsl(\(Int(hsl.h.rounded())), \(Int(hsl.s.rounded()))%, \(Int(hsl.l.rounded()))%)"
        let hslModern = hasA
            ? "hsl(\(fmtDec(hsl.h, 1)) \(fmtDec(hsl.s, 1))% \(fmtDec(hsl.l, 1))% / \(aPct))"
            : "hsl(\(fmtDec(hsl.h, 1)) \(fmtDec(hsl.s, 1))% \(fmtDec(hsl.l, 1))%)"
        let hwbStr = hasA
            ? "hwb(\(Int(hwb.h.rounded())) \(Int(hwb.w.rounded()))% \(Int(hwb.b.rounded()))% / \(aPct))"
            : "hwb(\(Int(hwb.h.rounded())) \(Int(hwb.w.rounded()))% \(Int(hwb.b.rounded()))%)"
        let oklchStr = hasA
            ? "oklch(\(fmtDec(oklch.l * 100.0, 2))% \(fmtDec(oklch.c, 4)) \(fmtDec(oklch.h, 1)) / \(aPct))"
            : "oklch(\(fmtDec(oklch.l * 100.0, 2))% \(fmtDec(oklch.c, 4)) \(fmtDec(oklch.h, 1)))"
        let oklabStr = hasA
            ? "oklab(\(fmtDec(oklab.l * 100.0, 2))% \(fmtDec(oklab.a, 4)) \(fmtDec(oklab.b, 4)) / \(aPct))"
            : "oklab(\(fmtDec(oklab.l * 100.0, 2))% \(fmtDec(oklab.a, 4)) \(fmtDec(oklab.b, 4)))"
        let labStr = hasA
            ? "lab(\(fmtDec(lab.l, 1))% \(fmtDec(lab.a, 1)) \(fmtDec(lab.b, 1)) / \(aPct))"
            : "lab(\(fmtDec(lab.l, 1))% \(fmtDec(lab.a, 1)) \(fmtDec(lab.b, 1)))"
        let lchStr = hasA
            ? "lch(\(fmtDec(lab.l, 1))% \(fmtDec(lchC, 1)) \(fmtDec(lchH, 1)) / \(aPct))"
            : "lch(\(fmtDec(lab.l, 1))% \(fmtDec(lchC, 1)) \(fmtDec(lchH, 1)))"

        let rF = fmtDec(c.r, 4), gF = fmtDec(c.g, 4), bF = fmtDec(c.b, 4)
        let swiftColor = hasA
            ? "Color(.sRGB, red: \(rF), green: \(gF), blue: \(bF), opacity: \(fmtDec(c.a, 3)))"
            : "Color(red: \(rF), green: \(gF), blue: \(bF))"
        let nsColor = "NSColor(srgbRed: \(rF), green: \(gF), blue: \(bF), alpha: \(aFmt))"
        let uiColor = "UIColor(red: \(rF), green: \(gF), blue: \(bF), alpha: \(aFmt))"
        let cgColor = "CGColor(srgbRed: \(rF), green: \(gF), blue: \(bF), alpha: \(aFmt))"

        let rgb565 = ((c.r255 & 0xF8) << 8) | ((c.g255 & 0xFC) << 3) | (c.b255 >> 3)

        var list: [ColorFormatEntry] = [
            ColorFormatEntry(id: "hex-auto-lower", group: .web, title: "Hex 小写", value: c.hexAutoLower, badge: hasA ? "8位 RGBA" : "HEX"),
            ColorFormatEntry(id: "hex-auto-upper", group: .web, title: "Hex 大写", value: c.hexAutoUpper, badge: "HEX"),
            ColorFormatEntry(id: "rgb-legacy", group: .web, title: hasA ? "CSS rgba()" : "CSS rgb()", value: rgbLegacy, badge: "CSS"),
            ColorFormatEntry(id: "rgb-modern", group: .web, title: "CSS4 rgb() 空格语法", value: rgbModern, badge: "CSS4"),
            ColorFormatEntry(id: "hsl-legacy", group: .web, title: hasA ? "CSS hsla()" : "CSS hsl()", value: hslLegacy, badge: "CSS"),
            ColorFormatEntry(id: "hsl-modern", group: .web, title: "CSS4 hsl() 空格语法", value: hslModern, badge: "CSS4"),
            ColorFormatEntry(id: "oklch", group: .web, title: "CSS4 OKLCH (推荐均匀色域)", value: oklchStr, badge: "OKLCH"),
            ColorFormatEntry(id: "oklab", group: .web, title: "CSS4 OKLab", value: oklabStr, badge: "OKLab"),
            ColorFormatEntry(id: "hwb", group: .web, title: "CSS4 HWB", value: hwbStr, badge: "HWB"),
            ColorFormatEntry(id: "lab", group: .web, title: "CSS4 CIE Lab (D50)", value: labStr, badge: "Lab"),
            ColorFormatEntry(id: "lch", group: .web, title: "CSS4 CIE LCH", value: lchStr, badge: "LCH"),
            ColorFormatEntry(id: "tailwind-cls", group: .web, title: "Tailwind CSS 任意值类", value: "text-[\(c.hexAutoLower)] / bg-[\(c.hexAutoLower)]", badge: "TW"),

            ColorFormatEntry(id: "swiftui", group: .apple, title: "SwiftUI Color", value: swiftColor, badge: "SwiftUI"),
            ColorFormatEntry(id: "nscolor", group: .apple, title: "AppKit NSColor (sRGB)", value: nsColor, badge: "macOS"),
            ColorFormatEntry(id: "uicolor", group: .apple, title: "UIKit UIColor", value: uiColor, badge: "iOS"),
            ColorFormatEntry(id: "cgcolor", group: .apple, title: "CoreGraphics CGColor", value: cgColor, badge: "CG"),

            ColorFormatEntry(id: "android-argb", group: .mobile, title: "Android XML (#AARRGGBB)", value: c.androidArgbHex, badge: "Android"),
            ColorFormatEntry(id: "compose-flutter", group: .mobile, title: "Jetpack Compose / Flutter", value: "Color(\(c.hex0xARGB))", badge: "0xAARRGGBB"),
            ColorFormatEntry(id: "hex-0x", group: .mobile, title: "C / Shader 十六进制", value: c.hex0xRGB, badge: "0xRGB"),
            ColorFormatEntry(id: "float-tuple", group: .mobile, title: "归一化浮点 vec3/vec4", value: hasA ? "\(rF), \(gF), \(bF), \(aFmt)" : "\(rF), \(gF), \(bF)", badge: "Float"),
            ColorFormatEntry(id: "hsv", group: .mobile, title: "HSV / HSB (Design 工具)", value: "hsv(\(Int(hsv.h.rounded())), \(Int(hsv.s.rounded()))%, \(Int(hsv.v.rounded()))%)", badge: "HSB"),
            ColorFormatEntry(id: "cmyk", group: .mobile, title: "CMYK (印刷近似)", value: "cmyk(\(Int(cmyk.c.rounded()))%, \(Int(cmyk.m.rounded()))%, \(Int(cmyk.y.rounded()))%, \(Int(cmyk.k.rounded()))%)", badge: "CMYK"),
            ColorFormatEntry(id: "rgb565", group: .mobile, title: "16-bit RGB565 (嵌入式屏)", value: String(format: "0x%04X", rgb565), badge: "16-bit"),
        ]
        if hasA {
            list.insert(ColorFormatEntry(id: "hex6-strip", group: .web, title: "Hex 6 位 (不含 Alpha)", value: c.hex6Lower, badge: "RGB"), at: 2)
        }
        return list
    }

    private static func fmtDec(_ value: Double, _ decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", value)
        if !s.contains(".") { return s }
        return s.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    // MARK: - Nearest CSS & Tailwind Color

    static func nearestNamedMatches(to c: ColorRGBA) -> (css: ColorMatchBadge?, tailwind: ColorMatchBadge?) {
        let targetLab = toOKLab(c)
        func dist(_ hex: String) -> Double {
            guard let ref = parseHex(hex) else { return .infinity }
            let refLab = toOKLab(ref)
            let dl = targetLab.l - refLab.l
            let da = targetLab.a - refLab.a
            let db = targetLab.b - refLab.b
            return sqrt(dl * dl + da * da + db * db) * 100.0
        }

        var bestCss: ColorMatchBadge?
        for (name, hex) in cssNamedColors where name != "transparent" && name != "grey" && !name.contains("grey") {
            let d = dist(hex)
            if bestCss == nil || d < bestCss!.deltaE {
                bestCss = ColorMatchBadge(name: name, source: "CSS", hex: hex, deltaE: d)
            }
        }

        var bestTw: ColorMatchBadge?
        for item in tailwindNamedColors {
            let d = dist(item.hex)
            if bestTw == nil || d < bestTw!.deltaE {
                bestTw = ColorMatchBadge(name: item.name, source: "Tailwind", hex: item.hex, deltaE: d)
            }
        }
        return (bestCss, bestTw)
    }

    // MARK: - WCAG 2.1 + APCA Contrast

    static func relativeLuminance(_ c: ColorRGBA) -> Double {
        0.2126 * srgbToLinear(c.r) + 0.7152 * srgbToLinear(c.g) + 0.0722 * srgbToLinear(c.b)
    }

    static func evaluateContrast(foreground fg: ColorRGBA, background bg: ColorRGBA) -> WcagReport {
        let opaqueBg = ColorRGBA(r: bg.r, g: bg.g, b: bg.b, a: 1.0)
        let effFg = fg.a < 0.999 ? fg.composited(over: opaqueBg) : fg
        let l1 = relativeLuminance(effFg)
        let l2 = relativeLuminance(opaqueBg)
        let ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        let lc = apcaContrast(txt: effFg, bg: opaqueBg)
        return WcagReport(
            ratio: ratio,
            apcaLc: lc,
            aaNormal: ratio >= 4.5,
            aaaNormal: ratio >= 7.0,
            aaLarge: ratio >= 3.0,
            aaaLarge: ratio >= 4.5,
            effectiveForeground: effFg
        )
    }

    /// APCA-W3 (0.0.98G-4g) perceptual contrast index Lc
    private static func apcaContrast(txt: ColorRGBA, bg: ColorRGBA) -> Double {
        let trc = 2.4
        func y(_ c: ColorRGBA) -> Double {
            let val = 0.2126729 * pow(c.r, trc) + 0.7151522 * pow(c.g, trc) + 0.0721750 * pow(c.b, trc)
            return val >= 0.022 ? val : val + pow(0.022 - val, 1.414)
        }
        let yTxt = y(txt), yBg = y(bg)
        if abs(yBg - yTxt) < 0.0005 { return 0.0 }
        var output = 0.0
        if yBg > yTxt {
            let sapc = (pow(yBg, 0.56) - pow(yTxt, 0.57)) * 1.14
            output = sapc < 0.1 ? 0.0 : (sapc - 0.027) * 100.0
        } else {
            let sapc = (pow(yBg, 0.65) - pow(yTxt, 0.62)) * 1.14
            output = sapc > -0.1 ? 0.0 : (sapc + 0.027) * 100.0
        }
        return output
    }

    /// Auto-adjust foreground color in OKLCH to meet a target WCAG contrast ratio against background.
    static func autoFixForContrast(foreground fg: ColorRGBA, background bg: ColorRGBA, targetRatio: Double = 4.5) -> ColorRGBA {
        let report = evaluateContrast(foreground: fg, background: bg)
        if report.ratio >= targetRatio { return fg }
        let baseLch = toOKLCH(ColorRGBA(r: fg.r, g: fg.g, b: fg.b, a: 1.0))
        let bgLum = relativeLuminance(bg)
        let tryDarker = bgLum > 0.18
        var best = fg
        for step in 1...100 {
            let frac = Double(step) / 100.0
            let candL = tryDarker ? max(0, baseLch.l * (1.0 - frac)) : min(1, baseLch.l + (1.0 - baseLch.l) * frac)
            let cand = fromOKLCH(ColorOKLCH(l: candL, c: baseLch.c, h: baseLch.h, a: fg.a))
            if evaluateContrast(foreground: cand, background: bg).ratio >= targetRatio {
                return cand
            }
            best = cand
        }
        // Fallback try opposite direction if one extremity did not reach target
        for step in 1...100 {
            let frac = Double(step) / 100.0
            let candL = !tryDarker ? max(0, baseLch.l * (1.0 - frac)) : min(1, baseLch.l + (1.0 - baseLch.l) * frac)
            let cand = fromOKLCH(ColorOKLCH(l: candL, c: baseLch.c, h: baseLch.h, a: fg.a))
            if evaluateContrast(foreground: cand, background: bg).ratio >= targetRatio {
                return cand
            }
        }
        return best
    }

    // MARK: - Harmonies, 50-950 Scale, Mix & CVD Simulation

    static func harmonies(for c: ColorRGBA) -> [ColorHarmonyGroup] {
        let baseHsl = toHSL(c)
        func makeItem(_ role: String, _ deg: Int) -> ColorHarmonyItem {
            let shifted = fromHSL(ColorHSL(h: baseHsl.h + Double(deg), s: baseHsl.s, l: baseHsl.l, a: c.a))
            return ColorHarmonyItem(id: "\(role)-\(deg)", role: role, angleOffset: deg, color: shifted)
        }
        return [
            ColorHarmonyGroup(id: "complementary", title: "互补色 (Complementary)", items: [
                makeItem("主色", 0), makeItem("互补 180°", 180),
            ]),
            ColorHarmonyGroup(id: "analogous", title: "类似色 (Analogous)", items: [
                makeItem("-30°", -30), makeItem("主色", 0), makeItem("+30°", 30),
            ]),
            ColorHarmonyGroup(id: "triadic", title: "三色均衡 (Triadic)", items: [
                makeItem("主色", 0), makeItem("+120°", 120), makeItem("+240°", 240),
            ]),
            ColorHarmonyGroup(id: "split", title: "分裂互补 (Split-Complementary)", items: [
                makeItem("主色", 0), makeItem("+150°", 150), makeItem("+210°", 210),
            ]),
            ColorHarmonyGroup(id: "tetradic", title: "四色方阵 (Tetradic / Square)", items: [
                makeItem("主色", 0), makeItem("+90°", 90), makeItem("+180°", 180), makeItem("+270°", 270),
            ]),
        ]
    }

    static func tailwindScale(for c: ColorRGBA) -> [PaletteShade] {
        let steps: [(step: Int, targetL: Double)] = [
            (50, 0.97), (100, 0.93), (200, 0.86), (300, 0.77), (400, 0.68),
            (500, 0.59), (600, 0.51), (700, 0.43), (800, 0.35), (900, 0.27), (950, 0.19),
        ]
        let baseLch = toOKLCH(ColorRGBA(r: c.r, g: c.g, b: c.b, a: 1.0))
        var closestIdx = 0
        var bestDiff = Double.infinity
        for (idx, item) in steps.enumerated() {
            let d = abs(item.targetL - baseLch.l)
            if d < bestDiff { bestDiff = d; closestIdx = idx }
        }

        return steps.enumerated().map { idx, item in
            if idx == closestIdx {
                return PaletteShade(step: item.step, color: c, isBase: true)
            }
            // Gently taper chroma near extremes for natural Tailwind-like highlights & shadows
            let chromaFactor: Double
            if item.targetL > 0.85 { chromaFactor = 0.25 + (1.0 - item.targetL) * 4.0 }
            else if item.targetL < 0.35 { chromaFactor = 0.45 + item.targetL }
            else { chromaFactor = 0.92 }
            let shade = fromOKLCH(ColorOKLCH(l: item.targetL, c: baseLch.c * min(1.0, chromaFactor), h: baseLch.h, a: c.a))
            return PaletteShade(step: item.step, color: shade, isBase: false)
        }
    }

    enum MixSpace: String, CaseIterable, Sendable {
        case oklch = "OKLCH"
        case oklab = "OKLab"
        case srgb = "sRGB"
    }

    static func mix(_ c1: ColorRGBA, _ c2: ColorRGBA, steps: Int, space: MixSpace) -> [ColorRGBA] {
        let cnt = max(2, steps)
        return (0..<cnt).map { i in
            let t = Double(i) / Double(cnt - 1)
            let alpha = c1.a + (c2.a - c1.a) * t
            switch space {
            case .srgb:
                return ColorRGBA(
                    r: c1.r + (c2.r - c1.r) * t,
                    g: c1.g + (c2.g - c1.g) * t,
                    b: c1.b + (c2.b - c1.b) * t,
                    a: alpha
                )
            case .oklab:
                let a = toOKLab(c1), b = toOKLab(c2)
                return fromOKLab(ColorOKLab(
                    l: a.l + (b.l - a.l) * t,
                    a: a.a + (b.a - a.a) * t,
                    b: a.b + (b.b - a.b) * t,
                    alpha: alpha
                ))
            case .oklch:
                let a = toOKLCH(c1), b = toOKLCH(c2)
                var dh = b.h - a.h
                if a.c < 0.002 { dh = 0 }
                else if b.c < 0.002 { dh = 0 }
                else if dh > 180 { dh -= 360 }
                else if dh < -180 { dh += 360 }
                let h = a.c < 0.002 ? b.h : (b.c < 0.002 ? a.h : a.h + dh * t)
                return fromOKLCH(ColorOKLCH(
                    l: a.l + (b.l - a.l) * t,
                    c: a.c + (b.c - a.c) * t,
                    h: (h + 360).truncatingRemainder(dividingBy: 360),
                    a: alpha
                ))
            }
        }
    }

    static func simulateCvd(_ c: ColorRGBA) -> [CvdSimulation] {
        let r = srgbToLinear(c.r), g = srgbToLinear(c.g), b = srgbToLinear(c.b)
        func apply(_ m: (Double, Double, Double, Double, Double, Double, Double, Double, Double)) -> ColorRGBA {
            ColorRGBA(
                r: linearToSrgb(m.0 * r + m.1 * g + m.2 * b),
                g: linearToSrgb(m.3 * r + m.4 * g + m.5 * b),
                b: linearToSrgb(m.6 * r + m.7 * g + m.8 * b),
                a: c.a
            )
        }
        let lum = linearToSrgb(relativeLuminance(c))
        return [
            CvdSimulation(id: "normal", title: "正常视觉", prevalence: "基准", color: c),
            CvdSimulation(id: "protanopia", title: "红色盲 (Protanopia)", prevalence: "~1% 男性", color: apply((0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998))),
            CvdSimulation(id: "deuteranopia", title: "绿色盲 (Deuteranopia)", prevalence: "~1% 男性", color: apply((0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881))),
            CvdSimulation(id: "tritanopia", title: "蓝色盲 (Tritanopia)", prevalence: "<0.01%", color: apply((1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900))),
            CvdSimulation(id: "achromatopsia", title: "全色盲 / 灰度 (Achromatopsia)", prevalence: "极罕见", color: ColorRGBA(r: lum, g: lum, b: lum, a: c.a)),
        ]
    }

    // MARK: - Native Screen Eyedropper (NSColorSampler)

    @MainActor
    static func pickFromScreen(completion: @escaping @MainActor (ColorRGBA?) -> Void) {
        let sampler = NSColorSampler()
        sampler.show { selected in
            guard let srgb = selected?.usingColorSpace(.sRGB) else {
                Task { @MainActor in completion(nil) }
                return
            }
            let picked = ColorRGBA(
                r: Double(srgb.redComponent),
                g: Double(srgb.greenComponent),
                b: Double(srgb.blueComponent),
                a: Double(srgb.alphaComponent)
            )
            Task { @MainActor in completion(picked) }
        }
    }
}
