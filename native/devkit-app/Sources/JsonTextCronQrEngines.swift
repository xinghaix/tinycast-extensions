import AppKit
import CoreImage
import Darwin
import Foundation

// MARK: - JSON Tools

struct JsonStats: Sendable {
    let rootType: String
    let keyCount: Int
    let maxDepth: Int
    let byteLength: Int
    let minifiedLength: Int
}

struct JsonAnalysis: Sendable {
    let valid: Bool
    let repaired: Bool
    let error: String?
    let pretty2: String?
    let pretty4: String?
    let minified: String?
    let sortedPretty: String?
    let escapedString: String?
    let yaml: String?
    let tsInterface: String?
    let queryString: String?
    let stats: JsonStats?
}

enum JsonEngine {
    static func repairRelaxed(_ raw: String) -> String {
        let src = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.hasPrefix("\"") && src.hasSuffix("\"") {
            if let data = "[\(src)]".data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [String],
               let inner = arr.first {
                let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("{") || t.hasPrefix("[") { return inner }
            }
        }

        let chars = Array(src)
        let n = chars.count
        var out = ""
        out.reserveCapacity(n)
        var i = 0

        while i < n {
            let ch = chars[i]
            let next: Character? = (i + 1 < n) ? chars[i + 1] : nil

            if ch == "\"" {
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == "\"" { j += 1; break }
                    j += 1
                }
                out += String(chars[i..<min(j, n)])
                i = j
                continue
            }

            if ch == "'" {
                var j = i + 1
                var inner = ""
                while j < n {
                    if chars[j] == "\\" && j + 1 < n {
                        let esc = chars[j + 1]
                        if esc == "'" { inner.append("'") }
                        else if esc == "\"" { inner += "\\\"" }
                        else { inner.append("\\"); inner.append(esc) }
                        j += 2
                        continue
                    }
                    if chars[j] == "'" { j += 1; break }
                    if chars[j] == "\"" { inner += "\\\"" }
                    else { inner.append(chars[j]) }
                    j += 1
                }
                out += "\"\(inner)\""
                i = j
                continue
            }

            if ch == "/" && next == "/" {
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
                continue
            }
            if ch == "/" && next == "*" {
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }

            if ch.isLetter || ch == "_" || ch == "$" {
                let prev = out.last(where: { !$0.isWhitespace })
                if prev == "{" || prev == "," {
                    var j = i
                    while j < n && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" || chars[j] == "-") {
                        j += 1
                    }
                    var k = j
                    while k < n && chars[k].isWhitespace { k += 1 }
                    if k < n && chars[k] == ":" {
                        out += "\"\(String(chars[i..<j]))\""
                        i = j
                        continue
                    }
                }
            }

            out.append(ch)
            i += 1
        }

        // Remove trailing commas outside strings
        let outChars = Array(out)
        var final = ""
        final.reserveCapacity(outChars.count)
        i = 0
        while i < outChars.count {
            let ch = outChars[i]
            if ch == "\"" {
                var j = i + 1
                while j < outChars.count {
                    if outChars[j] == "\\" { j += 2; continue }
                    if outChars[j] == "\"" { j += 1; break }
                    j += 1
                }
                final += String(outChars[i..<min(j, outChars.count)])
                i = j
                continue
            }
            if ch == "," {
                var j = i + 1
                while j < outChars.count && outChars[j].isWhitespace { j += 1 }
                if j < outChars.count && (outChars[j] == "}" || outChars[j] == "]") {
                    i += 1
                    continue
                }
            }
            final.append(ch)
            i += 1
        }
        return final
    }

    static func analyze(_ raw: String) -> JsonAnalysis {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return JsonAnalysis(valid: false, repaired: false, error: "输入为空", pretty2: nil, pretty4: nil, minified: nil, sortedPretty: nil, escapedString: nil, yaml: nil, tsInterface: nil, queryString: nil, stats: nil)
        }

        var parsed: Any
        var repaired = false
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])
        } catch let err {
            let candidate = repairRelaxed(trimmed)
            do {
                parsed = try JSONSerialization.jsonObject(with: Data(candidate.utf8), options: [.fragmentsAllowed])
                repaired = true
            } catch {
                return JsonAnalysis(valid: false, repaired: false, error: err.localizedDescription, pretty2: nil, pretty4: nil, minified: nil, sortedPretty: nil, escapedString: nil, yaml: nil, tsInterface: nil, queryString: nil, stats: nil)
            }
        }

        let pretty2 = formatJson(parsed, indentSpaces: 2, sortedKeys: false)
        let pretty4 = formatJson(parsed, indentSpaces: 4, sortedKeys: false)
        let minified = formatJson(parsed, indentSpaces: 0, sortedKeys: false)
        let sortedPretty = formatJson(parsed, indentSpaces: 2, sortedKeys: true)
        let escapedString = (try? JSONSerialization.data(withJSONObject: [minified], options: [])).flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let yaml = toYaml(parsed)
        let ts = toTypeScript(parsed)
        let qs = toQueryString(parsed)
        let (keys, depth) = measure(parsed, depth: 0)
        let rootType: String
        if let arr = parsed as? [Any] { rootType = "Array (\(arr.count))" }
        else if let obj = parsed as? [String: Any] { rootType = "Object (\(obj.count) keys)" }
        else if parsed is NSNull { rootType = "null" }
        else { rootType = String(describing: type(of: parsed)) }

        return JsonAnalysis(
            valid: true, repaired: repaired, error: nil,
            pretty2: pretty2, pretty4: pretty4, minified: minified, sortedPretty: sortedPretty,
            escapedString: escapedString, yaml: yaml, tsInterface: ts, queryString: qs,
            stats: JsonStats(
                rootType: rootType, keyCount: keys, maxDepth: depth,
                byteLength: trimmed.utf8.count, minifiedLength: minified.utf8.count
            )
        )
    }

    private static func formatJson(_ value: Any, indentSpaces: Int, sortedKeys: Bool) -> String {
        if indentSpaces == 0 {
            if let d = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
               let s = String(data: d, encoding: .utf8) {
                return s
            }
        }
        return renderJson(value, indent: indentSpaces, level: 0, sortedKeys: sortedKeys)
    }

    private static func renderJson(_ value: Any, indent: Int, level: Int, sortedKeys: Bool) -> String {
        if value is NSNull { return "null" }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "true" : "false" }
            return "\(num)"
        }
        if let str = value as? String {
            if let d = try? JSONSerialization.data(withJSONObject: [str], options: [.withoutEscapingSlashes]),
               let s = String(data: d, encoding: .utf8) {
                return String(s.dropFirst().dropLast())
            }
            return "\"\(str)\""
        }
        let pad = String(repeating: " ", count: indent * (level + 1))
        let closePad = String(repeating: " ", count: indent * level)
        if let arr = value as? [Any] {
            if arr.isEmpty { return "[]" }
            let body = arr.map { "\(pad)\(renderJson($0, indent: indent, level: level + 1, sortedKeys: sortedKeys))" }.joined(separator: ",\n")
            return "[\n\(body)\n\(closePad)]"
        }
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            let keys = sortedKeys ? dict.keys.sorted() : Array(dict.keys)
            let body = keys.map { k in
                let keyJson = renderJson(k, indent: indent, level: level + 1, sortedKeys: sortedKeys)
                let valJson = renderJson(dict[k] ?? NSNull(), indent: indent, level: level + 1, sortedKeys: sortedKeys)
                return "\(pad)\(keyJson): \(valJson)"
            }.joined(separator: ",\n")
            return "{\n\(body)\n\(closePad)}"
        }
        return "\(value)"
    }

    private static func measure(_ value: Any, depth: Int) -> (Int, Int) {
        if let arr = value as? [Any] {
            var keys = 0
            var maxD = depth + (arr.isEmpty ? 0 : 1)
            for item in arr {
                let (k, d) = measure(item, depth: depth + 1)
                keys += k
                maxD = max(maxD, d)
            }
            return (keys, maxD)
        }
        if let dict = value as? [String: Any] {
            var keys = dict.count
            var maxD = depth + (dict.isEmpty ? 0 : 1)
            for v in dict.values {
                let (k, d) = measure(v, depth: depth + 1)
                keys += k
                maxD = max(maxD, d)
            }
            return (keys, maxD)
        }
        return (0, depth)
    }

    static func toYaml(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        if value is NSNull { return "null" }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "true" : "false" }
            return "\(num)"
        }
        if let str = value as? String {
            let needsQuotes = str.isEmpty || str.range(of: #"[:#\n\r\t{}\[\],&*!|>'"%@`]|^\s|\s$"#, options: .regularExpression) != nil
                || ["true", "false", "null"].contains(str.lowercased())
            if needsQuotes { return renderJson(str, indent: 0, level: 0, sortedKeys: false) }
            return str
        }
        if let arr = value as? [Any] {
            if arr.isEmpty { return "[]" }
            return arr.map { item in
                if item is [Any] || item is [String: Any] {
                    let rendered = toYaml(item, indent: indent + 1)
                    let trimmed = rendered.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
                    return "\(pad)- \(trimmed)"
                }
                return "\(pad)- \(toYaml(item, indent: indent + 1))"
            }.joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            return dict.keys.sorted().map { k in
                let v = dict[k] ?? NSNull()
                let safeKey = k.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil ? k : renderJson(k, indent: 0, level: 0, sortedKeys: false)
                let isComplex = (v as? [Any]).map { !$0.isEmpty } ?? (v as? [String: Any]).map { !$0.isEmpty } ?? false
                if isComplex {
                    return "\(pad)\(safeKey):\n\(toYaml(v, indent: indent + 1))"
                }
                return "\(pad)\(safeKey): \(toYaml(v, indent: indent + 1))"
            }.joined(separator: "\n")
        }
        return "\(value)"
    }

    static func toTypeScript(_ value: Any, rootName: String = "Root") -> String {
        var interfaces: [String] = []
        var seen = Set<String>()

        func toPascal(_ s: String) -> String {
            let cleaned = s.replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if cleaned.isEmpty { return "Item" }
            let joined = cleaned.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            return joined.first?.isNumber == true ? "T\(joined)" : joined
        }

        func uniqueName(_ base: String) -> String {
            let b = toPascal(base)
            var candidate = b
            var idx = 2
            while seen.contains(candidate) { candidate = "\(b)\(idx)"; idx += 1 }
            seen.insert(candidate)
            return candidate
        }

        func infer(_ val: Any, hint: String) -> String {
            if val is NSNull { return "null" }
            if let num = val as? NSNumber {
                return CFGetTypeID(num) == CFBooleanGetTypeID() ? "boolean" : "number"
            }
            if val is String { return "string" }
            if let arr = val as? [Any] {
                if arr.isEmpty { return "unknown[]" }
                var types = [String]()
                for item in arr {
                    let t = infer(item, hint: "\(hint)Item")
                    if !types.contains(t) { types.append(t) }
                }
                let union = types.count == 1 ? types[0] : "(\(types.joined(separator: " | ")))"
                return "\(union)[]"
            }
            if let dict = val as? [String: Any] {
                let name = uniqueName(hint)
                let fields = dict.keys.sorted().map { k in
                    let safeK = k.range(of: #"^[a-zA-Z_$][a-zA-Z0-9_$]*$"#, options: .regularExpression) != nil ? k : renderJson(k, indent: 0, level: 0, sortedKeys: false)
                    return "  \(safeK): \(infer(dict[k] ?? NSNull(), hint: k));"
                }
                interfaces.append("export interface \(name) {\n\(fields.joined(separator: "\n"))\n}")
                return name
            }
            return "unknown"
        }

        let rootType = infer(value, hint: rootName)
        if interfaces.isEmpty { return "export type \(rootName) = \(rootType);" }
        if !interfaces.contains(where: { $0.hasPrefix("export interface \(rootName) ") }) {
            interfaces.append("export type \(rootName) = \(rootType);")
        }
        return interfaces.reversed().joined(separator: "\n\n")
    }

    private static func toQueryString(_ value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        var comps = URLComponents()
        comps.queryItems = dict.keys.sorted().map { k in
            let v = dict[k] ?? NSNull()
            let str: String
            if let s = v as? String { str = s }
            else if v is [Any] || v is [String: Any] { str = formatJson(v, indentSpaces: 0, sortedKeys: true) }
            else if v is NSNull { str = "null" }
            else if let num = v as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() { str = num.boolValue ? "true" : "false" }
            else { str = "\(v)" }
            return URLQueryItem(name: k, value: str)
        }
        return comps.percentEncodedQuery ?? ""
    }
}

// MARK: - Password Engine

struct PasswordPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let entropyBits: Int
    let strength: String
    let description: String
}

enum PasswordEngine {
    private static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    private static let digits = Array("0123456789")
    private static let symbols = Array("!@#$%^&*()-_=+[]{}|;:,.<>?")
    private static let ambiguous = Set("0O1lI|`'\"")
    private static let words = [
        "amber", "anchor", "apple", "arctic", "arrow", "atlas", "aurora", "autumn",
        "bamboo", "beacon", "breeze", "bridge", "bronze", "canyon", "cedar", "cipher",
        "cobalt", "comet", "compass", "copper", "coral", "cosmos", "crater", "crystal",
        "delta", "desert", "dragon", "drift", "eclipse", "ember", "emerald", "engine",
        "falcon", "fiber", "fjord", "flame", "forest", "fossil", "frost", "galaxy",
        "garnet", "geyser", "glacier", "granite", "harbor", "harvest", "haven", "helium",
        "horizon", "indigo", "island", "ivory", "jasper", "juniper", "kernel", "kinetic",
        "lagoon", "lantern", "lattice", "laurel", "legend", "lemon", "liberty", "lotus",
        "lunar", "magnet", "maple", "marble", "matrix", "meadow", "mercury", "meteor",
        "mirage", "monarch", "mosaic", "nebula", "nectar", "neutron", "nimbus", "nordic",
        "obsidian", "ocean", "octave", "olive", "omega", "onyx", "opal", "orbit",
        "orchid", "origin", "osprey", "oxygen", "pacific", "palace", "panda", "paradox",
        "pebble", "pelican", "pepper", "phantom", "phoenix", "photon", "pioneer", "planet",
        "plasma", "plateau", "plum", "polar", "portal", "prism", "pulsar", "puzzle",
        "python", "quantum", "quartz", "quasar", "quest", "quiver", "radar", "radiant",
        "rainbow", "ranger", "raven", "reactor", "redwood", "reef", "relic", "ripple",
        "river", "rocket", "ruby", "runway", "saffron", "sage", "sailor", "sapphire",
        "saturn", "scarlet", "sculpt", "sector", "sequoia", "shadow", "shield", "sierra",
        "signal", "silver", "solar", "solstice", "sonic", "spark", "spectra", "sphere",
        "spiral", "spruce", "starlight", "static", "stellar", "stone", "storm", "stream",
        "summit", "sunrise", "sunset", "swift", "symbol", "tango", "tempest", "terra",
        "thistle", "thunder", "tiger", "timber", "titan", "topaz", "torch", "torrent",
        "transit", "treasure", "trident", "tundra", "tunnel", "turbine", "twilight", "typhoon",
        "ultra", "umbra", "unicorn", "unity", "uranium", "valley", "vanguard", "vector",
        "velvet", "vertex", "vessel", "vibrant", "victor", "violet", "vortex", "voyage",
        "walnut", "wander", "warden", "wave", "whisper", "willow", "winter", "wisdom",
        "wizard", "zenith", "zephyr", "zinc", "zodiac", "zone",
    ]

    private static func randomInt(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        let limit = UInt32.max - (UInt32.max % UInt32(upperBound))
        while true {
            let b = UUIDEngine.randomBytes(count: 4)
            let v = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
            if v < limit { return Int(v % UInt32(upperBound)) }
        }
    }

    static func generatePassword(
        length: Int,
        useUpper: Bool = true,
        useLower: Bool = true,
        useDigits: Bool = true,
        useSymbols: Bool = true,
        excludeAmbiguous: Bool = false
    ) -> (password: String, entropyBits: Int) {
        let filt: ([Character]) -> [Character] = { arr in
            excludeAmbiguous ? arr.filter { !ambiguous.contains($0) } : arr
        }
        var pools = [[Character]]()
        if useUpper { pools.append(filt(upper)) }
        if useLower { pools.append(filt(lower)) }
        if useDigits { pools.append(filt(digits)) }
        if useSymbols { pools.append(filt(symbols)) }
        pools = pools.filter { !$0.isEmpty }
        let full = pools.flatMap { $0 }.isEmpty ? filt(lower + digits) : pools.flatMap { $0 }
        let len = max(4, min(256, length))

        var chars = [Character]()
        for pool in pools where chars.count < len {
            chars.append(pool[randomInt(upperBound: pool.count)])
        }
        while chars.count < len {
            chars.append(full[randomInt(upperBound: full.count)])
        }
        for i in stride(from: chars.count - 1, through: 1, by: -1) {
            let j = randomInt(upperBound: i + 1)
            chars.swapAt(i, j)
        }
        let entropy = Int((Double(len) * log2(Double(max(2, full.count)))).rounded())
        return (String(chars), entropy)
    }

    static func generatePassphrase(wordCount: Int = 5, separator: String = "-", capitalize: Bool = false) -> (passphrase: String, entropyBits: Int) {
        let cnt = max(2, min(16, wordCount))
        let chosen = (0..<cnt).map { _ -> String in
            let w = words[randomInt(upperBound: words.count)]
            return capitalize ? w.prefix(1).uppercased() + w.dropFirst() : w
        }
        let entropy = Int((Double(cnt) * log2(Double(words.count))).rounded())
        return (chosen.joined(separator: separator), entropy)
    }

    static func classify(_ bits: Int) -> String {
        if bits < 45 { return "较弱" }
        if bits < 70 { return "中等" }
        if bits < 100 { return "强" }
        return "极强"
    }

    static func presets() -> [PasswordPreset] {
        let p16 = generatePassword(length: 16)
        let p24 = generatePassword(length: 24)
        let p20Clean = generatePassword(length: 20, useSymbols: false, excludeAmbiguous: true)
        let ph5 = generatePassphrase(wordCount: 5)
        let ph4Cap = generatePassphrase(wordCount: 4, capitalize: true)
        let pin6 = generatePassword(length: 6, useUpper: false, useLower: false, useDigits: true, useSymbols: false)
        let token = "sk_live_" + Data(UUIDEngine.randomBytes(count: 24)).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let hex256 = UUIDEngine.randomBytes(count: 32).map { String(format: "%02x", $0) }.joined()
        let b64Key = Data(UUIDEngine.randomBytes(count: 32)).base64EncodedString()
        let p32 = generatePassword(length: 32)
        let hex512 = UUIDEngine.randomBytes(count: 64).map { String(format: "%02x", $0) }.joined()

        return [
            PasswordPreset(id: "pw-16", title: "强密码 · 16 位 (含符号)", value: p16.password, entropyBits: p16.entropyBits, strength: classify(p16.entropyBits), description: "日常网站账号推荐"),
            PasswordPreset(id: "pw-24", title: "高强密码 · 24 位 (含符号)", value: p24.password, entropyBits: p24.entropyBits, strength: classify(p24.entropyBits), description: "核心后台与云账号"),
            PasswordPreset(id: "pw-20-clean", title: "易读密码 · 20 位 (无符号/去易混淆)", value: p20Clean.password, entropyBits: p20Clean.entropyBits, strength: classify(p20Clean.entropyBits), description: "排除 0/O/1/l/I"),
            PasswordPreset(id: "phrase-5", title: "助记词短语 · 5 词 (Diceware)", value: ph5.passphrase, entropyBits: ph5.entropyBits, strength: classify(ph5.entropyBits), description: "易读易记单词短语"),
            PasswordPreset(id: "phrase-4-cap", title: "助记词短语 · 4 词首字母大写", value: ph4Cap.passphrase, entropyBits: ph4Cap.entropyBits, strength: classify(ph4Cap.entropyBits), description: "满足首字母大写要求"),
            PasswordPreset(id: "api-token", title: "API Token (Base64URL · 192-bit)", value: token, entropyBits: 192, strength: "极强", description: "URL 安全随机令牌"),
            PasswordPreset(id: "hex-256", title: "256-bit Hex 密钥 (AES-256 / HMAC)", value: hex256, entropyBits: 256, strength: "极强", description: "64 位十六进制密钥"),
            PasswordPreset(id: "b64-256", title: "256-bit Base64 Secret (JWT)", value: b64Key, entropyBits: 256, strength: "极强", description: "32 字节 Base64 密钥"),
            PasswordPreset(id: "pw-32", title: "超强密码 · 32 位全字符集", value: p32.password, entropyBits: p32.entropyBits, strength: classify(p32.entropyBits), description: "数据库主密码"),
            PasswordPreset(id: "hex-512", title: "512-bit Hex 密钥 (HS512)", value: hex512, entropyBits: 512, strength: "极强", description: "128 位十六进制主密钥"),
            PasswordPreset(id: "pin-6", title: "6 位数字 PIN 码", value: pin6.password, entropyBits: pin6.entropyBits, strength: classify(pin6.entropyBits), description: "随机 6 位数字"),
        ]
    }
}

// MARK: - Text Tools

struct TextStats: Sendable {
    let chars: Int
    let charsNoSpaces: Int
    let bytesUtf8: Int
    let words: Int
    let lines: Int
}

enum TextEngine {
    static func stats(_ input: String) -> TextStats {
        let lines = input.isEmpty ? 0 : input.components(separatedBy: .newlines).count
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.isEmpty ? 0 : trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return TextStats(
            chars: input.count,
            charsNoSpaces: input.filter { !$0.isWhitespace }.count,
            bytesUtf8: input.utf8.count,
            words: words,
            lines: lines
        )
    }

    static func splitWords(_ input: String) -> [String] {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([A-Z]+)([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[_\-./\\:\s]+"#, with: " ", options: .regularExpression)
        return s.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    static func camelCase(_ input: String) -> String {
        let w = splitWords(input)
        guard !w.isEmpty else { return "" }
        return w.enumerated().map { idx, item in
            idx == 0 ? item.lowercased() : item.prefix(1).uppercased() + item.dropFirst().lowercased()
        }.joined()
    }

    static func pascalCase(_ input: String) -> String {
        splitWords(input).map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
    }

    static func snakeCase(_ input: String) -> String { splitWords(input).map { $0.lowercased() }.joined(separator: "_") }
    static func constantCase(_ input: String) -> String { splitWords(input).map { $0.uppercased() }.joined(separator: "_") }
    static func kebabCase(_ input: String) -> String { splitWords(input).map { $0.lowercased() }.joined(separator: "-") }
    static func dotCase(_ input: String) -> String { splitWords(input).map { $0.lowercased() }.joined(separator: ".") }
    static func titleCase(_ input: String) -> String { splitWords(input).map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ") }
    static func sentenceCase(_ input: String) -> String {
        let joined = splitWords(input).map { $0.lowercased() }.joined(separator: " ")
        return joined.isEmpty ? "" : joined.prefix(1).uppercased() + joined.dropFirst()
    }
    static func slug(_ input: String) -> String {
        let folded = input.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return folded.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func caseConversions(_ input: String) -> [(id: String, title: String, value: String)] {
        [
            ("camel", "camelCase", camelCase(input)),
            ("pascal", "PascalCase", pascalCase(input)),
            ("snake", "snake_case", snakeCase(input)),
            ("constant", "CONSTANT_CASE", constantCase(input)),
            ("kebab", "kebab-case", kebabCase(input)),
            ("dot", "dot.case", dotCase(input)),
            ("title", "Title Case", titleCase(input)),
            ("sentence", "Sentence case", sentenceCase(input)),
            ("upper", "UPPERCASE (全大写)", input.uppercased()),
            ("lower", "lowercase (全小写)", input.lowercased()),
            ("slug", "URL Slug", slug(input)),
        ]
    }

    static func lineTransform(_ input: String, action: String) -> String {
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        switch action {
        case "trim": return lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case "dropEmpty": return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        case "dedupe":
            var seen = Set<String>()
            return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
        case "sortAsc": return lines.sorted().joined(separator: "\n")
        case "sortDesc": return lines.sorted(by: >).joined(separator: "\n")
        case "reverse": return lines.reversed().joined(separator: "\n")
        case "number": return lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case "csv": return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case "jsonArray":
            let nonEmpty = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return (try? JSONSerialization.data(withJSONObject: nonEmpty, options: [.prettyPrinted, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        case "collapse": return input.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        default: return input
        }
    }
}

// MARK: - QR Engine (CoreImage CIQRCodeGenerator)

enum QrCorrectionLevel: String, CaseIterable, Sendable {
    case L, M, Q, H
    var title: String {
        switch self {
        case .L: return "L (7%)"
        case .M: return "M (15% 推荐)"
        case .Q: return "Q (25%)"
        case .H: return "H (30%)"
        }
    }
}

enum QrEngine {
    static func generate(text: String, level: QrCorrectionLevel, size: CGFloat = 260) -> (image: NSImage, moduleCount: Int, svg: String)? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(level.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        let moduleCount = Int(extent.width)
        let scale = max(1.0, floor(size / max(1.0, extent.width)))
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let ctx = CIContext()
        guard let cgImg = ctx.createCGImage(transformed, from: transformed.extent) else { return nil }
        let nsImage = NSImage(cgImage: cgImg, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))

        // Extract crisp monochrome module matrix to build clean standalone SVG for export
        let rep = NSBitmapImageRep(ciImage: output)
        let margin = 2
        let svgScale = 8
        let total = moduleCount + margin * 2
        let svgSize = total * svgScale
        var pathCmds = ""
        for y in 0..<moduleCount {
            for x in 0..<moduleCount {
                let brightness = rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1.0
                if brightness < 0.5 {
                    let px = (x + margin) * svgScale
                    let py = (y + margin) * svgScale
                    pathCmds += "M\(px) \(py)h\(svgScale)v\(svgScale)h-\(svgScale)z"
                }
            }
        }
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(svgSize) \(svgSize)\" width=\"\(svgSize)\" height=\"\(svgSize)\"><rect width=\"\(svgSize)\" height=\"\(svgSize)\" rx=\"\(svgScale * 2)\" fill=\"#FFFFFF\"/><path fill=\"#111827\" d=\"\(pathCmds)\"/></svg>"
        return (nsImage, moduleCount, svg)
    }
}

// MARK: - Cron Engine

struct CronFieldSpec: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let raw: String
    let summary: String
}

struct ParsedCron: Sendable {
    let expression: String
    let normalized: String
    let hasSeconds: Bool
    let description: String
    let fields: [CronFieldSpec]
    let nextRuns: [Date]
}

enum CronError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum CronEngine {
    static let presets: [(title: String, expression: String)] = [
        ("每分钟执行", "* * * * *"),
        ("每 5 分钟执行", "*/5 * * * *"),
        ("每小时整点", "0 * * * *"),
        ("每天凌晨 00:00", "0 0 * * *"),
        ("工作日早 9:00", "0 9 * * 1-5"),
        ("工作日 9-18点每15分", "*/15 9-18 * * 1-5"),
        ("每周一早 8:30", "30 8 * * 1"),
        ("每月 1 号 02:00", "0 2 1 * *"),
    ]

    private static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
    ]
    private static let monthAliases: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    private static let dowAliases: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
    ]
    private static let dowCn = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    static func parse(_ expression: String, from: Date = Date(), count: Int = 10) throws -> ParsedCron {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CronError.message("请输入 Cron 表达式") }

        let expanded = macros[trimmed.lowercased()] ?? trimmed
        let tokens = expanded.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count == 5 || tokens.count == 6 else {
            throw CronError.message("需要 5 段 (分 时 日 月 周) 或 6 段 (秒 分 时 日 月 周)，当前 \(tokens.count) 段")
        }

        let hasSec = tokens.count == 6
        let (secRaw, minRaw, hourRaw, domRaw, monRaw, dowRaw) = hasSec
            ? (tokens[0], tokens[1], tokens[2], tokens[3], tokens[4], tokens[5])
            : ("0", tokens[0], tokens[1], tokens[2], tokens[3], tokens[4])

        let secSet = Set(try expandField(secRaw, min: 0, max: 59))
        let minSet = Set(try expandField(minRaw, min: 0, max: 59))
        let hourSet = Set(try expandField(hourRaw, min: 0, max: 23))
        let domSet = Set(try expandField(domRaw, min: 1, max: 31))
        let monSet = Set(try expandField(monRaw, min: 1, max: 12, aliases: monthAliases))
        let dowSet = Set(try expandField(dowRaw, min: 0, max: 7, aliases: dowAliases, wrap7: true))

        let domWild = domRaw == "*" || domRaw == "?"
        let dowWild = dowRaw == "*" || dowRaw == "?"

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var cursor = cal.date(bySetting: .nanosecond, value: 0, of: from) ?? from
        if hasSec {
            cursor = cursor.addingTimeInterval(1)
        } else {
            cursor = cal.date(bySetting: .second, value: 0, of: cursor)?.addingTimeInterval(60) ?? cursor.addingTimeInterval(60)
        }

        var nextRuns = [Date]()
        let maxIter = hasSec ? 200_000 : 525_600
        let step: TimeInterval = hasSec ? 1 : 60
        let maxYear = cal.component(.year, from: from) + 5

        var iter = 0
        while nextRuns.count < count && iter < maxIter && cal.component(.year, from: cursor) <= maxYear {
            iter += 1
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: cursor)
            guard let m = comps.month, let d = comps.day, let h = comps.hour, let minVal = comps.minute, let s = comps.second, let wd = comps.weekday else { break }

            if !monSet.contains(m) {
                var nextComps = DateComponents(year: comps.year, month: m + 1, day: 1, hour: 0, minute: 0, second: 0)
                if m == 12 { nextComps = DateComponents(year: (comps.year ?? 2026) + 1, month: 1, day: 1, hour: 0, minute: 0, second: 0) }
                cursor = cal.date(from: nextComps) ?? cursor.addingTimeInterval(86_400)
                continue
            }

            let dow = wd - 1 // Sunday=0
            let dayOk = (domWild && dowWild) ? true : (domWild ? dowSet.contains(dow) : (dowWild ? domSet.contains(d) : (domSet.contains(d) || dowSet.contains(dow))))
            if !dayOk {
                cursor = cal.startOfDay(for: cursor).addingTimeInterval(86_400)
                continue
            }
            if !hourSet.contains(h) {
                cursor = cal.date(bySettingHour: h, minute: 0, second: 0, of: cursor)?.addingTimeInterval(3600) ?? cursor.addingTimeInterval(3600)
                continue
            }
            if !minSet.contains(minVal) {
                cursor = cal.date(bySetting: .second, value: 0, of: cursor)?.addingTimeInterval(60) ?? cursor.addingTimeInterval(60)
                continue
            }
            if hasSec && !secSet.contains(s) {
                cursor = cursor.addingTimeInterval(1)
                continue
            }

            nextRuns.append(cursor)
            cursor = cursor.addingTimeInterval(step)
        }

        var fields = [CronFieldSpec]()
        if hasSec { fields.append(CronFieldSpec(name: "秒 (Second)", raw: secRaw, summary: describe(secRaw, "秒"))) }
        fields.append(contentsOf: [
            CronFieldSpec(name: "分 (Minute)", raw: minRaw, summary: describe(minRaw, "分钟")),
            CronFieldSpec(name: "时 (Hour)", raw: hourRaw, summary: describe(hourRaw, "小时")),
            CronFieldSpec(name: "日 (Day)", raw: domRaw, summary: describe(domRaw, "日")),
            CronFieldSpec(name: "月 (Month)", raw: monRaw, summary: describe(monRaw, "月")),
            CronFieldSpec(name: "周 (Weekday)", raw: dowRaw, summary: describeDow(dowRaw)),
        ])

        let desc = buildDesc(sec: hasSec ? secRaw : nil, min: minRaw, hour: hourRaw, dom: domRaw, mon: monRaw, dow: dowRaw)
        return ParsedCron(expression: trimmed, normalized: tokens.joined(separator: " "), hasSeconds: hasSec, description: desc, fields: fields, nextRuns: nextRuns)
    }

    private static func expandField(_ raw: String, min: Int, max: Int, aliases: [String: Int]? = nil, wrap7: Bool = false) throws -> [Int] {
        var set = Set<Int>()
        for part in raw.split(separator: ",", omittingEmptySubsequences: false).map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            guard !part.isEmpty else { throw CronError.message("无效字段: \(raw)") }
            let slashParts = part.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard slashParts.count <= 2 else { throw CronError.message("无效步长: \(part)") }
            let step = slashParts.count == 2 ? (Int(slashParts[1]) ?? 0) : 1
            guard step > 0 else { throw CronError.message("步长须为正整数: \(part)") }
            let rangePart = slashParts[0]
            if rangePart == "*" || rangePart == "?" {
                for v in stride(from: min, through: max, by: step) { set.insert(wrap7 && v == 7 ? 0 : v) }
            } else if rangePart.contains("-") {
                let bounds = rangePart.split(separator: "-").map(String.init)
                guard bounds.count == 2 else { throw CronError.message("无效范围: \(rangePart)") }
                let s = try parseVal(bounds[0], min: min, max: max, aliases: aliases, wrap7: false)
                let e = try parseVal(bounds[1], min: min, max: max, aliases: aliases, wrap7: false)
                guard s <= e else { throw CronError.message("范围起止无效: \(rangePart)") }
                for v in stride(from: s, through: e, by: step) { set.insert(wrap7 && v == 7 ? 0 : v) }
            } else {
                let s = try parseVal(rangePart, min: min, max: max, aliases: aliases, wrap7: wrap7)
                if slashParts.count == 2 {
                    for v in stride(from: s, through: max, by: step) { set.insert(wrap7 && v == 7 ? 0 : v) }
                } else {
                    set.insert(s)
                }
            }
        }
        return set.sorted()
    }

    private static func parseVal(_ raw: String, min: Int, max: Int, aliases: [String: Int]?, wrap7: Bool) throws -> Int {
        let low = raw.lowercased()
        var v = aliases?[low] ?? Int(raw) ?? -999
        if wrap7 && v == 7 { v = 0 }
        guard v >= min && v <= max else { throw CronError.message("Cron 数值越界: \(raw)") }
        return v
    }

    private static func describe(_ raw: String, _ unit: String) -> String {
        if raw == "*" || raw == "?" { return "每\(unit)" }
        if raw.hasPrefix("*/") { return "每 \(raw.dropFirst(2)) \(unit)" }
        return raw
    }

    private static func describeDow(_ raw: String) -> String {
        if raw == "*" || raw == "?" { return "每天" }
        guard let vals = try? expandField(raw, min: 0, max: 7, aliases: dowAliases, wrap7: true) else { return raw }
        if vals == [1, 2, 3, 4, 5] { return "工作日 (周一至周五)" }
        if vals == [0, 6] { return "周末 (周六、周日)" }
        return vals.compactMap { $0 < dowCn.count ? dowCn[$0] : nil }.joined(separator: "、")
    }

    private static func buildDesc(sec: String?, min: String, hour: String, dom: String, mon: String, dow: String) -> String {
        var parts = [String]()
        if mon != "*" { parts.append("\(mon) 月") }
        if dow != "*" && dow != "?" { parts.append(describeDow(dow)) }
        if dom != "*" && dom != "?" { parts.append("每月第 \(dom) 日") }
        if hour == "*" && min == "*" && (sec == nil || sec == "*") {
            parts.append(sec != nil ? "每秒执行" : "每分钟执行")
        } else if hour == "*" && min.hasPrefix("*/") {
            parts.append("每 \(min.dropFirst(2)) 分钟执行")
        } else if hour == "*" {
            parts.append("每小时第 \(min) 分")
        } else if let h = Int(hour), let m = Int(min) {
            parts.append(String(format: "在 %02d:%02d", h, m))
        } else {
            parts.append("时(\(hour)) 分(\(min))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Network & Ports

struct NetworkInterfaceEntry: Identifiable, Sendable {
    let id: String
    let iface: String
    let family: String
    let address: String
    let cidr: String
}

struct ListeningPortEntry: Identifiable, Sendable {
    let id: String
    let pid: Int32
    let command: String
    let endpoint: String
    let port: String
    let url: String
}

enum NetworkEngine {
    static func readLocalInterfaces() -> [NetworkInterfaceEntry] {
        var listPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&listPtr) == 0, let first = listPtr else { return [] }
        defer { freeifaddrs(first) }

        var results = [NetworkInterfaceEntry]()
        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let flags = Int32(bitPattern: ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0,
                  let sa = ptr.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let saLen = socklen_t(sa.pointee.sa_len)
            guard getnameinfo(sa, saLen, &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let addr = hostBuf.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress!)
            }.components(separatedBy: "%").first ?? ""
            guard !addr.isEmpty, !(family == AF_INET6 && addr.hasPrefix("fe80:")) else { continue }

            let iface = String(cString: ptr.pointee.ifa_name)
            let famStr = family == AF_INET ? "IPv4" : "IPv6"
            let key = "\(iface)-\(famStr)-\(addr)"
            guard seen.insert(key).inserted else { continue }
            results.append(NetworkInterfaceEntry(id: key, iface: iface, family: famStr, address: addr, cidr: addr))
        }

        return results.sorted {
            if $0.family != $1.family { return $0.family == "IPv4" }
            return $0.iface < $1.iface
        }
    }

    static func listListeningPorts() async -> [ListeningPortEntry] {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            proc.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            do { try proc.run() } catch { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return parseLsof(text)
        }.value
    }

    private static func parseLsof(_ output: String) -> [ListeningPortEntry] {
        var entries = [ListeningPortEntry]()
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""

        for rawLine in output.components(separatedBy: .newlines) {
            guard let tag = rawLine.first else { continue }
            let val = String(rawLine.dropFirst())
            if tag == "p" { pid = Int32(val) ?? 0; command = "" }
            else if tag == "c" { command = val }
            else if tag == "n", pid > 0, let colonIdx = val.lastIndex(of: ":") {
                let host = String(val[..<colonIdx])
                let port = String(val[val.index(after: colonIdx)...])
                let key = "\(pid):\(host):\(port)"
                guard seen.insert(key).inserted else { continue }
                let urlHost = (host == "*" || host == "[::]" || host == "0.0.0.0") ? "127.0.0.1" : host
                entries.append(ListeningPortEntry(
                    id: "port-\(key)", pid: pid, command: command.isEmpty ? "unknown" : command,
                    endpoint: val, port: port, url: "http://\(urlHost):\(port)"
                ))
            }
        }
        return entries.sorted { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) || $0.pid < $1.pid }
    }

    static func fetchPublicIp() async throws -> String {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        let (data, _) = try await session.data(from: URL(string: "https://api.ipify.org?format=json")!)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ip = obj["ip"] as? String else {
            throw CodecError.message("未返回 IP 字段")
        }
        return ip
    }
}

// MARK: - Smart Clipboard Detection

enum SmartClipboardKind: Sendable {
    case empty, uuidOrId, jwt, timestamp, json, url, color, base64, hex, text

    var label: String {
        switch self {
        case .empty: return "空剪贴板"
        case .uuidOrId: return "UUID / 唯一标识符"
        case .jwt: return "JWT Token"
        case .timestamp: return "时间戳 / 日期"
        case .json: return "JSON 数据"
        case .url: return "URL / 链接参数"
        case .color: return "颜色 / 色值"
        case .base64: return "Base64 编码内容"
        case .hex: return "Hex 十六进制内容"
        case .text: return "纯文本"
        }
    }
}

enum SmartDetector {
    static func detect(_ raw: String) -> SmartClipboardKind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .empty }
        if UUIDEngine.shared.inspect(s) != nil { return .uuidOrId }
        if CodecEngine.decodeJwt(s) != nil { return .jwt }
        if s.range(of: #"^-?\d{10}(\.\d+)?$|^-?\d{13}$|^-?\d{16}$|^-?\d{19}$|^\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}"#, options: .regularExpression) != nil,
           TimestampEngine.parse(s) != nil {
            return .timestamp
        }
        if (s.hasPrefix("{") || s.hasPrefix("[")) && JsonEngine.analyze(s).valid { return .json }
        if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") || CodecEngine.parseUrlQueryParams(s) != nil {
            return .url
        }
        if !s.hasPrefix("#"), let hex = CodecEngine.decodeHexBytes(s), CodecEngine.looksReadableUtf8(hex) {
            return .hex
        }
        if ColorEngine.parse(s) != nil { return .color }
        if CodecEngine.decodeBase64Strict(s) != nil { return .base64 }
        if let hex = CodecEngine.decodeHexBytes(s), CodecEngine.looksReadableUtf8(hex) { return .hex }
        return .text
    }
}
