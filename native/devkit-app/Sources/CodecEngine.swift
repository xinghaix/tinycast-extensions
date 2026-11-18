import CommonCrypto
import CryptoKit
import Foundation
import zlib

enum CodecOp: String, CaseIterable, Sendable {
    case base64, base64url, hex, url, html, unicode, base32, base58, gzip, deflate, jsonString, rot13, morse

    var title: String {
        switch self {
        case .base64: return "Base64"
        case .base64url: return "Base64URL"
        case .hex: return "Hex"
        case .url: return "URL"
        case .html: return "HTML"
        case .unicode: return "Unicode"
        case .base32: return "Base32"
        case .base58: return "Base58"
        case .gzip: return "Gzip"
        case .deflate: return "Deflate"
        case .jsonString: return "JSON 转义"
        case .rot13: return "ROT13"
        case .morse: return "Morse"
        }
    }
}

struct CodecEntry: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case encode, decode, inspect
    }
    let id: String
    let title: String
    let direction: Direction
    let badge: String
    let output: String
    let plausible: Bool
    let details: String?
}

struct DecodedJwt: Sendable {
    let headerJson: String
    let payloadJson: String
    let algorithm: String
    let signingInput: String
    let signatureB64Url: String
    let issuedAt: String?
    let expiresAt: String?
    let notBefore: String?
    let isExpired: Bool?
}

enum AesMode: String, CaseIterable, Sendable {
    case gcm = "aes-256-gcm"
    case cbc = "aes-256-cbc"
    var title: String { self == .gcm ? "AES-256-GCM (推荐)" : "AES-256-CBC (PKCS7)" }
}

enum AesKeyDerivation: String, CaseIterable, Sendable {
    case pbkdf2, hex, utf8Pad = "utf8-pad"
    var title: String {
        switch self {
        case .pbkdf2: return "任意口令 (PBKDF2-SHA256)"
        case .hex: return "原始 Hex 密钥 (64 位)"
        case .utf8Pad: return "UTF-8 截断/补零 (32B)"
        }
    }
}

enum CodecError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

enum CodecEngine {
    private static let base32Chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let base58Chars = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static let morseMap: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
        "I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.",
        "Q": "--.-", "R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..", "0": "-----", "1": ".----", "2": "..---", "3": "...--",
        "4": "....-", "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.", "-": "-....-",
        "(": "-.--.", ")": "-.--.-", "@": ".--.-.",
    ]
    private static let morseReverse: [String: Character] = Dictionary(uniqueKeysWithValues: morseMap.map { ($0.value, $0.key) })

    private static let htmlDecodeMap: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'",
        "nbsp": "\u{00a0}", "copy": "©", "reg": "®", "trade": "™", "mdash": "—", "ndash": "–", "hellip": "…",
    ]

    // MARK: - Bidirectional Op

    static func runBidirectional(_ input: String, op: CodecOp, encode: Bool) throws -> String {
        switch op {
        case .base64:
            if encode { return Data(input.utf8).base64EncodedString() }
            guard let text = decodeBase64Flexible(input) else { throw CodecError.message("无效的 Base64 或非 UTF-8 字节") }
            return text
        case .base64url:
            if encode {
                return Data(input.utf8).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            guard let text = decodeBase64Flexible(input) else { throw CodecError.message("无效的 Base64URL 或非 UTF-8 字节") }
            return text
        case .hex:
            if encode { return Data(input.utf8).map { String(format: "%02x", $0) }.joined() }
            guard let data = decodeHexBytes(input), let s = String(data: data, encoding: .utf8) else {
                throw CodecError.message("无效的 Hex 字节或非 UTF-8 文本")
            }
            return s
        case .url:
            if encode { return encodeURIComponent(input) }
            guard let dec = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                throw CodecError.message("无效的百分号编码序列")
            }
            return dec
        case .html:
            return encode ? encodeHtml(input) : decodeHtml(input)
        case .unicode:
            return encode ? encodeUnicode(input) : decodeUnicode(input)
        case .base32:
            if encode { return encodeBase32(Data(input.utf8)) }
            guard let data = decodeBase32(input), let s = String(data: data, encoding: .utf8) else {
                throw CodecError.message("无效的 Base32 编码")
            }
            return s
        case .base58:
            if encode { return encodeBase58(Data(input.utf8)) }
            guard let data = decodeBase58(input), let s = String(data: data, encoding: .utf8) else {
                throw CodecError.message("无效的 Base58 编码")
            }
            return s
        case .gzip:
            if encode { return try zlibCompress(Data(input.utf8), gzip: true).base64EncodedString() }
            guard let raw = decodeBase64Raw(input) else { throw CodecError.message("请输入 Base64 格式的 Gzip 数据") }
            let out = try zlibDecompress(raw, gzip: true)
            guard let text = String(data: out, encoding: .utf8) else { throw CodecError.message("解压结果非 UTF-8 文本") }
            return text
        case .deflate:
            if encode { return try zlibCompress(Data(input.utf8), gzip: false).base64EncodedString() }
            guard let raw = decodeBase64Raw(input) else { throw CodecError.message("请输入 Base64 格式的 Deflate 数据") }
            let out = try zlibDecompress(raw, gzip: false)
            guard let text = String(data: out, encoding: .utf8) else { throw CodecError.message("解压结果非 UTF-8 文本") }
            return text
        case .jsonString:
            if encode {
                let data = try JSONSerialization.data(withJSONObject: [input], options: [])
                let arrStr = String(data: data, encoding: .utf8) ?? "[]"
                return String(arrStr.dropFirst().dropLast())
            }
            let wrapped = (input.hasPrefix("\"") && input.hasSuffix("\"")) ? input : "\"\(input)\""
            guard let data = wrapped.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: Data("[\(wrapped)]".utf8)) as? [String],
                  let first = arr.first, !data.isEmpty
            else {
                throw CodecError.message("无法解析为 JSON 字符串字面量")
            }
            return first
        case .rot13:
            return rot13(input)
        case .morse:
            if encode { return encodeMorse(input) }
            guard let dec = decodeMorse(input) else { throw CodecError.message("无效的摩斯电码序列 (仅支持 . - / 空格)") }
            return dec
        }
    }

    // MARK: - Primitive Codecs

    static func encodeURIComponent(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func encodeURI(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ";,/?:@&=+$-_.!~*'()#")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func encodeBase32(_ data: Data) -> String {
        var bits = 0
        var val = 0
        var out = ""
        for b in data {
            val = (val << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                out.append(base32Chars[(val >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { out.append(base32Chars[(val << (5 - bits)) & 31]) }
        while out.count % 8 != 0 { out.append("=") }
        return out
    }

    static func decodeBase32(_ input: String) -> Data? {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "=", with: "")
            .uppercased()
        guard !cleaned.isEmpty else { return nil }
        var bits = 0
        var val = 0
        var out = Data()
        for ch in cleaned {
            guard let idx = base32Chars.firstIndex(of: ch) else { return nil }
            val = (val << 5) | idx
            bits += 5
            if bits >= 8 {
                out.append(UInt8((val >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }

    static func encodeBase58(_ data: Data) -> String {
        if data.isEmpty { return "" }
        let leadingZeros = data.prefix(while: { $0 == 0 }).count
        var bytes = [UInt8](data)
        var encoded = [Character]()
        var start = leadingZeros
        while start < bytes.count {
            var carry = 0
            for i in start..<bytes.count {
                let val = carry * 256 + Int(bytes[i])
                bytes[i] = UInt8(val / 58)
                carry = val % 58
            }
            encoded.append(base58Chars[carry])
            while start < bytes.count && bytes[start] == 0 { start += 1 }
        }
        return String(repeating: "1", count: leadingZeros) + String(encoded.reversed())
    }

    static func decodeBase58(_ input: String) -> Data? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let leadingOnes = s.prefix(while: { $0 == "1" }).count
        var bytes = [UInt8]()
        for ch in s {
            guard var carry = base58Chars.firstIndex(of: ch) else { return nil }
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        return Data(repeating: 0, count: leadingOnes) + Data(bytes.reversed())
    }

    static func encodeHtml(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func decodeHtml(_ input: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
        let ns = input as NSString
        var out = input
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).reversed() {
            let entity = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let cp = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(cp) {
                    replacement = String(scalar)
                }
            } else if entity.hasPrefix("#") {
                if let cp = UInt32(entity.dropFirst(), radix: 10), let scalar = UnicodeScalar(cp) {
                    replacement = String(scalar)
                }
            } else {
                replacement = htmlDecodeMap[entity]
            }
            if let replacement, let swiftRange = Range(match.range, in: out) {
                out.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return out
    }

    static func encodeUnicode(_ input: String, es6: Bool = false) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            let cp = scalar.value
            if cp >= 0x20 && cp <= 0x7e {
                out.append(Character(scalar))
            } else if es6 {
                out += String(format: "\\u{%x}", cp)
            } else if cp <= 0xffff {
                out += String(format: "\\u%04x", cp)
            } else {
                let adj = cp - 0x1_0000
                let hi = 0xd800 + (adj >> 10)
                let lo = 0xdc00 + (adj & 0x3ff)
                out += String(format: "\\u%04x\\u%04x", hi, lo)
            }
        }
        return out
    }

    static func decodeUnicode(_ input: String) -> String {
        var s = input
        if let re6 = try? NSRegularExpression(pattern: #"\\u\{([0-9a-fA-F]{1,6})\}"#) {
            let ns = s as NSString
            for m in re6.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                let hex = ns.substring(with: m.range(at: 1))
                if let cp = UInt32(hex, radix: 16), let sc = UnicodeScalar(cp), let r = Range(m.range, in: s) {
                    s.replaceSubrange(r, with: String(sc))
                }
            }
        }
        if let rePair = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})\\u([0-9a-fA-F]{4})"#) {
            let ns = s as NSString
            for m in rePair.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let hi = UInt16(ns.substring(with: m.range(at: 1)), radix: 16),
                   let lo = UInt16(ns.substring(with: m.range(at: 2)), radix: 16),
                   (0xd800...0xdbff).contains(hi), (0xdc00...0xdfff).contains(lo) {
                    let cp = 0x1_0000 + ((UInt32(hi) - 0xd800) << 10) + (UInt32(lo) - 0xdc00)
                    if let sc = UnicodeScalar(cp), let r = Range(m.range, in: s) {
                        s.replaceSubrange(r, with: String(sc))
                    }
                }
            }
        }
        if let re4 = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#) {
            let ns = s as NSString
            for m in re4.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let cp = UInt32(ns.substring(with: m.range(at: 1)), radix: 16),
                   let sc = UnicodeScalar(cp), let r = Range(m.range, in: s) {
                    s.replaceSubrange(r, with: String(sc))
                }
            }
        }
        return s
    }

    static func formatCodePoints(_ input: String) -> String {
        input.unicodeScalars.prefix(48).map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    static func rot13(_ input: String) -> String {
        String(input.unicodeScalars.map { sc in
            let v = sc.value
            if v >= 65 && v <= 90 { return Character(UnicodeScalar(((v - 65 + 13) % 26) + 65)!) }
            if v >= 97 && v <= 122 { return Character(UnicodeScalar(((v - 97 + 13) % 26) + 97)!) }
            return Character(sc)
        })
    }

    static func encodeMorse(_ input: String) -> String {
        input.uppercased().split(whereSeparator: \.isWhitespace).map { word in
            word.map { morseMap[$0] ?? String($0) }.joined(separator: " ")
        }.joined(separator: " / ")
    }

    static func decodeMorse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ ".-/ \t\n".contains($0) }) else { return nil }
        return trimmed.components(separatedBy: "/").map { word in
            String(word.split(whereSeparator: \.isWhitespace).map { morseReverse[String($0)] ?? "?" })
        }.joined(separator: " ")
    }

    static func decodeBase64Raw(_ input: String) -> Data? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty, s.count % 4 != 1 else { return nil }
        let padded = s.padding(toLength: ((s.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        return Data(base64Encoded: padded)
    }

    static func decodeBase64Flexible(_ input: String) -> String? {
        guard let data = decodeBase64Raw(input), looksReadableUtf8(data) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeBase64Strict(_ input: String) -> (text: String, isUrlSafe: Bool)? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard s.count >= 2 else { return nil }
        let isUrlSafe = s.contains("-") || s.contains("_")
        let std = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard std.count % 4 != 1 else { return nil }
        let padded = std.padding(toLength: ((std.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        guard let data = Data(base64Encoded: padded), looksReadableUtf8(data) else { return nil }
        let reStd = data.base64EncodedString()
        let reNoPad = reStd.replacingOccurrences(of: "=", with: "")
        guard padded == reStd || std.replacingOccurrences(of: "=", with: "") == reNoPad else { return nil }
        return (String(data: data, encoding: .utf8)!, isUrlSafe)
    }

    static func decodeHexBytes(_ input: String) -> Data? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
        let cleaned = s.replacingOccurrences(of: #"[\s:-]"#, with: "", options: .regularExpression)
        guard !cleaned.isEmpty, cleaned.count % 2 == 0, cleaned.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            data.append(b)
            idx = next
        }
        return data
    }

    static func looksReadableUtf8(_ data: Data) -> Bool {
        guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return false }
        for sc in str.unicodeScalars {
            if sc.value < 0x20 && sc.value != 9 && sc.value != 10 && sc.value != 13 {
                return false
            }
        }
        return true
    }

    // MARK: - Zlib (Native <zlib.h>)

    static func zlibCompress(_ data: Data, gzip: Bool) throws -> Data {
        var stream = z_stream()
        let windowBits: Int32 = gzip ? (15 + 16) : 15
        let initRc = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initRc == Z_OK else { throw CodecError.message("zlib deflateInit2 失败 (\(initRc))") }
        defer { deflateEnd(&stream) }

        var out = Data()
        let chunkSize = 16_384
        var buf = [UInt8](repeating: 0, count: chunkSize)
        var status: Int32 = Z_OK

        data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            repeat {
                buf.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = zlib.deflate(&stream, Z_FINISH)
                }
                let written = chunkSize - Int(stream.avail_out)
                if written > 0 { out.append(buf, count: written) }
            } while status == Z_OK
        }
        guard status == Z_STREAM_END else { throw CodecError.message("zlib 压缩失败 (\(status))") }
        return out
    }

    static func zlibDecompress(_ data: Data, gzip: Bool) throws -> Data {
        guard !data.isEmpty else { throw CodecError.message("压缩数据为空") }
        var stream = z_stream()
        let windowBits: Int32 = gzip ? (15 + 16) : 15
        let initRc = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initRc == Z_OK else { throw CodecError.message("zlib inflateInit2 失败 (\(initRc))") }
        defer { inflateEnd(&stream) }

        var out = Data()
        let chunkSize = 16_384
        var buf = [UInt8](repeating: 0, count: chunkSize)
        var status: Int32 = Z_OK

        data.withUnsafeBytes { raw in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            repeat {
                buf.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let written = chunkSize - Int(stream.avail_out)
                if written > 0 { out.append(buf, count: written) }
                if out.count > 64 * 1024 * 1024 { status = Z_MEM_ERROR; break }
            } while status == Z_OK
        }
        guard status == Z_STREAM_END else { throw CodecError.message("解压失败，格式不匹配或数据损坏") }
        return out
    }

    // MARK: - JWT

    static func decodeJwt(_ token: String) -> DecodedJwt? {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        guard let hData = decodeBase64Raw(String(parts[0])),
              let pData = decodeBase64Raw(String(parts[1])),
              let hObj = try? JSONSerialization.jsonObject(with: hData) as? [String: Any],
              let pObj = try? JSONSerialization.jsonObject(with: pData) as? [String: Any]
        else { return nil }

        let hPretty = (try? JSONSerialization.data(withJSONObject: hObj, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let pPretty = (try? JSONSerialization.data(withJSONObject: pObj, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        func toIso(_ val: Any?) -> String? {
            guard let num = val as? NSNumber else { return nil }
            let d = Date(timeIntervalSince1970: num.doubleValue)
            return TimestampEngine.formatDate(d, format: "yyyy-MM-dd HH:mm:ss")
        }
        let expNum = (pObj["exp"] as? NSNumber)?.doubleValue
        return DecodedJwt(
            headerJson: hPretty,
            payloadJson: pPretty,
            algorithm: String(describing: hObj["alg"] ?? "none"),
            signingInput: "\(parts[0]).\(parts[1])",
            signatureB64Url: String(parts[2]),
            issuedAt: toIso(pObj["iat"]),
            expiresAt: toIso(pObj["exp"]),
            notBefore: toIso(pObj["nbf"]),
            isExpired: expNum.map { Date().timeIntervalSince1970 > $0 }
        )
    }

    static func verifyJwtHmac(token: String, secret: String) -> (supported: Bool, valid: Bool, algorithm: String) {
        guard let decoded = decodeJwt(token) else { return (false, false, "invalid") }
        let msg = Data(decoded.signingInput.utf8)
        let key = SymmetricKey(data: Data(secret.utf8))
        let sigBytes: Data
        switch decoded.algorithm {
        case "HS256": sigBytes = Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        case "HS384": sigBytes = Data(HMAC<SHA384>.authenticationCode(for: msg, using: key))
        case "HS512": sigBytes = Data(HMAC<SHA512>.authenticationCode(for: msg, using: key))
        default: return (false, false, decoded.algorithm)
        }
        let computed = sigBytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (true, computed == decoded.signatureB64Url, decoded.algorithm)
    }

    // MARK: - URL Query & Radix

    static func parseUrlQueryParams(_ input: String) -> [(String, String)]? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("http://") || s.lowercased().hasPrefix("https://") {
            guard let comps = URLComponents(string: s), let items = comps.queryItems, !items.isEmpty else { return nil }
            return items.map { ($0.name, $0.value ?? "") }
        }
        if s.contains("=") && (s.contains("?") || s.contains("&")) {
            let q = s.contains("?") ? String(s[s.index(after: s.firstIndex(of: "?")!)...]) : s
            var comps = URLComponents()
            comps.percentEncodedQuery = q
            guard let items = comps.queryItems, !items.isEmpty else { return nil }
            return items.map { ($0.name, $0.value ?? "") }
        }
        return nil
    }

    static func parseInt128Radix(_ input: String) -> (value: Int128, sourceRadix: String)? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "")
        guard !s.isEmpty else { return nil }
        let negative = s.hasPrefix("-")
        if negative { s = String(s.dropFirst()) }
        let lower = s.lowercased()
        let radix: Int
        let label: String
        let digits: String
        if lower.hasPrefix("0x") { radix = 16; label = "Hex (16)"; digits = String(lower.dropFirst(2)) }
        else if lower.hasPrefix("0b") { radix = 2; label = "Binary (2)"; digits = String(lower.dropFirst(2)) }
        else if lower.hasPrefix("0o") { radix = 8; label = "Octal (8)"; digits = String(lower.dropFirst(2)) }
        else { radix = 10; label = "Decimal (10)"; digits = lower }
        guard !digits.isEmpty, let mag = UInt128(digits, radix: radix) else { return nil }
        if negative {
            guard mag <= UInt128(Int128.max) else { return nil }
            return (-Int128(mag), label)
        }
        guard mag <= UInt128(Int128.max) else { return nil }
        return (Int128(mag), label)
    }

    // MARK: - All Codecs Matrix

    static func runAllCodecs(_ input: String) -> [CodecEntry] {
        var entries: [CodecEntry] = []
        let data = Data(input.utf8)

        if let jwt = decodeJwt(input) {
            let status = jwt.isExpired == true ? "\(jwt.algorithm) · 已过期" : jwt.algorithm
            entries.append(CodecEntry(
                id: "jwt-decode", title: "JWT 解析 (Header & Payload)", direction: .inspect,
                badge: status, output: jwt.payloadJson, plausible: true,
                details: "Header:\n\(jwt.headerJson)\n\nPayload:\n\(jwt.payloadJson)"
            ))
        }

        if let params = parseUrlQueryParams(input) {
            let dict = Dictionary(params.map { ($0.0, $0.1) }, uniquingKeysWith: { _, last in last })
            let json = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            entries.append(CodecEntry(
                id: "url-params", title: "URL Query 参数解析 (转 JSON)", direction: .inspect,
                badge: "\(params.count) 个参数", output: json, plausible: true, details: nil
            ))
        }

        if let b64 = decodeBase64Strict(input) {
            entries.append(CodecEntry(
                id: "base64-decode", title: b64.isUrlSafe ? "Base64URL 解码" : "Base64 解码",
                direction: .decode, badge: "可解码", output: b64.text, plausible: true, details: nil
            ))
        }

        if let hexData = decodeHexBytes(input), looksReadableUtf8(hexData), let hexText = String(data: hexData, encoding: .utf8) {
            entries.append(CodecEntry(
                id: "hex-decode", title: "Hex 十六进制解码", direction: .decode,
                badge: "可解码", output: hexText, plausible: true, details: nil
            ))
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 8, let b32Data = decodeBase32(trimmed), looksReadableUtf8(b32Data), let s = String(data: b32Data, encoding: .utf8) {
            entries.append(CodecEntry(id: "base32-decode", title: "Base32 解码", direction: .decode, badge: "可解码", output: s, plausible: true, details: nil))
        }
        if trimmed.count >= 4, let b58Data = decodeBase58(trimmed), looksReadableUtf8(b58Data), let s = String(data: b58Data, encoding: .utf8) {
            entries.append(CodecEntry(id: "base58-decode", title: "Base58 解码", direction: .decode, badge: "可解码", output: s, plausible: true, details: nil))
        }

        if input.range(of: #"%[0-9a-fA-F]{2}"#, options: .regularExpression) != nil || input.contains("+") {
            if let dec = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding, dec != input {
                let hasPct = input.range(of: #"%[0-9a-fA-F]{2}"#, options: .regularExpression) != nil
                entries.append(CodecEntry(id: "url-decode", title: "URL 解码", direction: .decode, badge: hasPct ? "可解码" : "URL", output: dec, plausible: hasPct, details: nil))
            }
        }

        if input.range(of: #"&(?:#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#, options: .regularExpression) != nil {
            let dec = decodeHtml(input)
            if dec != input {
                entries.append(CodecEntry(id: "html-decode", title: "HTML 实体解码", direction: .decode, badge: "可解码", output: dec, plausible: true, details: nil))
            }
        }

        if input.range(of: #"\\u\{?[0-9a-fA-F]{4,6}\}?"#, options: .regularExpression) != nil {
            let dec = decodeUnicode(input)
            if dec != input {
                entries.append(CodecEntry(id: "unicode-decode", title: "Unicode 转义解码", direction: .decode, badge: "可解码", output: dec, plausible: true, details: nil))
            }
        }

        if let raw = decodeBase64Raw(trimmed), trimmed.count >= 8 {
            if let gunz = try? zlibDecompress(raw, gzip: true), let s = String(data: gunz, encoding: .utf8) {
                entries.append(CodecEntry(id: "gunzip-b64", title: "Gzip 解压 (Base64 → UTF-8)", direction: .decode, badge: "Gzip", output: s, plausible: true, details: nil))
            }
            if let inf = try? zlibDecompress(raw, gzip: false), let s = String(data: inf, encoding: .utf8) {
                entries.append(CodecEntry(id: "inflate-b64", title: "Deflate 解压 (Base64 → UTF-8)", direction: .decode, badge: "Deflate", output: s, plausible: true, details: nil))
            }
        }

        if let morse = decodeMorse(input) {
            entries.append(CodecEntry(id: "morse-decode", title: "摩斯电码解码", direction: .decode, badge: "Morse", output: morse, plausible: true, details: nil))
        }

        if let r = parseInt128Radix(input) {
            let v = r.value
            let sign = v < 0 ? "-" : ""
            let absVal = v < 0 ? UInt128(-v) : UInt128(v)
            entries.append(contentsOf: [
                CodecEntry(id: "radix-hex", title: "进制转换 → 十六进制", direction: .inspect, badge: r.sourceRadix, output: "\(sign)0x\(String(absVal, radix: 16))", plausible: r.sourceRadix != "Hex (16)", details: nil),
                CodecEntry(id: "radix-bin", title: "进制转换 → 二进制", direction: .inspect, badge: r.sourceRadix, output: "\(sign)0b\(String(absVal, radix: 2))", plausible: r.sourceRadix != "Binary (2)", details: nil),
                CodecEntry(id: "radix-dec", title: "进制转换 → 十进制", direction: .inspect, badge: r.sourceRadix, output: "\(v)", plausible: r.sourceRadix != "Decimal (10)", details: nil),
            ])
        }

        let gz = try? zlibCompress(data, gzip: true)
        let defl = try? zlibCompress(data, gzip: false)

        entries.append(contentsOf: [
            CodecEntry(id: "base64-encode", title: "Base64 编码", direction: .encode, badge: "Base64", output: data.base64EncodedString(), plausible: false, details: nil),
            CodecEntry(id: "base64url-encode", title: "Base64URL 编码", direction: .encode, badge: "Base64URL", output: data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""), plausible: false, details: nil),
            CodecEntry(id: "hex-encode", title: "Hex 十六进制编码", direction: .encode, badge: "Hex", output: data.map { String(format: "%02x", $0) }.joined(), plausible: false, details: nil),
            CodecEntry(id: "base32-encode", title: "Base32 编码", direction: .encode, badge: "Base32", output: encodeBase32(data), plausible: false, details: nil),
            CodecEntry(id: "base58-encode", title: "Base58 编码", direction: .encode, badge: "Base58", output: encodeBase58(data), plausible: false, details: nil),
            CodecEntry(id: "url-encode", title: "URL 编码 (encodeURIComponent)", direction: .encode, badge: "URL", output: encodeURIComponent(input), plausible: false, details: nil),
            CodecEntry(id: "uri-encode", title: "完整 URI 编码 (encodeURI)", direction: .encode, badge: "URI", output: encodeURI(input), plausible: false, details: nil),
            CodecEntry(id: "html-encode", title: "HTML 实体编码", direction: .encode, badge: "HTML", output: encodeHtml(input), plausible: false, details: nil),
            CodecEntry(id: "unicode-encode", title: "Unicode 转义编码 (\\uXXXX)", direction: .encode, badge: "Unicode", output: encodeUnicode(input), plausible: false, details: formatCodePoints(input)),
            CodecEntry(id: "binary-encode", title: "二进制字节序列 (8-bit)", direction: .encode, badge: "Bin", output: data.map { String($0, radix: 2).leftPad(to: 8, with: "0") }.joined(separator: " "), plausible: false, details: nil),
            CodecEntry(id: "rot13", title: "ROT13 替换密码", direction: .encode, badge: "ROT13", output: rot13(input), plausible: false, details: nil),
            CodecEntry(id: "morse-encode", title: "摩斯电码编码", direction: .encode, badge: "Morse", output: encodeMorse(input), plausible: false, details: nil),
        ])
        if let gz {
            entries.append(CodecEntry(id: "gzip-b64", title: "Gzip 压缩 → Base64", direction: .encode, badge: "\(data.count)B → \(gz.count)B", output: gz.base64EncodedString(), plausible: false, details: nil))
        }
        if let defl {
            entries.append(CodecEntry(id: "deflate-b64", title: "Deflate 压缩 → Base64", direction: .encode, badge: "\(data.count)B → \(defl.count)B", output: defl.base64EncodedString(), plausible: false, details: nil))
        }
        return entries
    }

    // MARK: - AES-256-GCM / AES-256-CBC

    private static func deriveAes256Key(_ secret: String, salt: Data, kdf: AesKeyDerivation) throws -> Data {
        switch kdf {
        case .hex:
            guard let keyData = decodeHexBytes(secret), keyData.count == 32 else {
                throw CodecError.message("Hex 密钥须为 64 个十六进制字符 (32 字节)")
            }
            return keyData
        case .utf8Pad:
            var out = Data(count: 32)
            let raw = Data(secret.utf8)
            out.replaceSubrange(0..<min(32, raw.count), with: raw.prefix(32))
            return out
        case .pbkdf2:
            var derived = [UInt8](repeating: 0, count: 32)
            let pwBytes = Array(secret.utf8).map { Int8(bitPattern: $0) }
            let saltBytes = [UInt8](salt)
            let status = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pwBytes, pwBytes.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                100_000,
                &derived, 32
            )
            guard status == kCCSuccess else { throw CodecError.message("PBKDF2 派生密钥失败") }
            return Data(derived)
        }
    }

    static func encryptAes(_ plaintext: String, secret: String, mode: AesMode = .gcm, kdf: AesKeyDerivation = .pbkdf2) throws -> String {
        guard !secret.isEmpty else { throw CodecError.message("请输入密钥或口令") }
        let salt = kdf == .pbkdf2 ? Data(UUIDEngine.randomBytes(count: 16)) : Data()
        let keyData = try deriveAes256Key(secret, salt: salt, kdf: kdf)
        let plainData = Data(plaintext.utf8)

        var dict: [String: Any] = ["v": 1, "kdf": kdf.rawValue]
        if !salt.isEmpty { dict["salt"] = salt.base64EncodedString() }

        if mode == .gcm {
            let iv = Data(UUIDEngine.randomBytes(count: 12))
            let sealed = try AES.GCM.seal(plainData, using: SymmetricKey(data: keyData), nonce: AES.GCM.Nonce(data: iv))
            dict["alg"] = "AES-256-GCM"
            dict["iv"] = iv.base64EncodedString()
            dict["tag"] = sealed.tag.base64EncodedString()
            dict["ct"] = sealed.ciphertext.base64EncodedString()
        } else {
            let iv = Data(UUIDEngine.randomBytes(count: 16))
            let ct = try aesCbcCrypt(data: plainData, key: keyData, iv: iv, encrypt: true)
            dict["alg"] = "AES-256-CBC"
            dict["iv"] = iv.base64EncodedString()
            dict["ct"] = ct.base64EncodedString()
        }

        let json = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return String(data: json, encoding: .utf8) ?? "{}"
    }

    static func decryptAes(_ payloadText: String, secret: String, fallbackMode: AesMode = .gcm, fallbackKdf: AesKeyDerivation = .pbkdf2) throws -> String {
        guard !secret.isEmpty else { throw CodecError.message("请输入密钥或口令") }
        guard let payloadData = payloadText.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let ivStr = dict["iv"] as? String, let iv = Data(base64Encoded: ivStr),
              let ctStr = dict["ct"] as? String, let ct = Data(base64Encoded: ctStr)
        else {
            throw CodecError.message("密文格式须为加密输出的 JSON Payload")
        }

        let kdf = (dict["kdf"] as? String).flatMap(AesKeyDerivation.init(rawValue:)) ?? fallbackKdf
        let salt = (dict["salt"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data()
        let keyData = try deriveAes256Key(secret, salt: salt, kdf: kdf)

        let algStr = dict["alg"] as? String ?? ""
        let mode: AesMode = algStr == "AES-256-CBC" ? .cbc : (algStr == "AES-256-GCM" ? .gcm : fallbackMode)

        let plainData: Data
        if mode == .gcm {
            guard let tagStr = dict["tag"] as? String, let tag = Data(base64Encoded: tagStr) else {
                throw CodecError.message("GCM 解密缺少认证 tag")
            }
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct, tag: tag)
            plainData = try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } else {
            plainData = try aesCbcCrypt(data: ct, key: keyData, iv: iv, encrypt: false)
        }
        guard let text = String(data: plainData, encoding: .utf8) else {
            throw CodecError.message("解密成功但内容不是合法 UTF-8 文本")
        }
        return text
    }

    private static func aesCbcCrypt(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = out.count
        var written = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    data.withUnsafeBytes { dataPtr in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, capacity, &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw CodecError.message(encrypt ? "AES-CBC 加密失败 (\(status))" : "AES-CBC 解密失败，请检查密钥或密文")
        }
        out.count = written
        return out
    }
}

private extension String {
    func leftPad(to len: Int, with ch: Character) -> String {
        count >= len ? self : String(repeating: ch, count: len - count) + self
    }
}
