import CryptoKit
import Foundation
import Security

enum UuidVersionFormat: String, CaseIterable, Sendable {
    case standard
    case uppercase
    case compact
    case compactUpper
    case braced
    case urn

    var title: String {
        switch self {
        case .standard: return "标准小写"
        case .uppercase: return "标准大写"
        case .compact: return "无连字符"
        case .compactUpper: return "无连字符大写"
        case .braced: return "大括号"
        case .urn: return "URN"
        }
    }
}

enum IdKind: String, CaseIterable, Sendable {
    case v7, v4, ulid, nanoid, v6, v1, v5, v3, v8, ksuid, objectid, nilUuid = "nil", maxUuid = "max"

    var shortLabel: String {
        switch self {
        case .v7: return "v7 推荐"
        case .v4: return "v4"
        case .ulid: return "ULID"
        case .nanoid: return "NanoID"
        case .v6: return "v6"
        case .v1: return "v1"
        case .v5: return "v5"
        case .v3: return "v3"
        case .v8: return "v8"
        case .ksuid: return "KSUID"
        case .objectid: return "ObjectID"
        case .nilUuid: return "Nil"
        case .maxUuid: return "Max"
        }
    }

    var title: String {
        switch self {
        case .v7: return "UUID v7 · 时序有序"
        case .v4: return "UUID v4 · 加密随机"
        case .ulid: return "ULID · Crockford Base32"
        case .nanoid: return "NanoID · URL 安全"
        case .v6: return "UUID v6 · 重排时间序"
        case .v1: return "UUID v1 · 公历时间戳"
        case .v5: return "UUID v5 · SHA-1 命名空间"
        case .v3: return "UUID v3 · MD5 命名空间"
        case .v8: return "UUID v8 · 自定义 / SHA-256"
        case .ksuid: return "KSUID · Base62 有序"
        case .objectid: return "MongoDB ObjectID"
        case .nilUuid: return "Nil UUID · 全零"
        case .maxUuid: return "Max UUID · 全 F"
        }
    }

    var needsNamespace: Bool { self == .v3 || self == .v5 }
    var supportsSeed: Bool { self == .v3 || self == .v5 || self == .v8 }
}

enum UuidNamespace: String, CaseIterable, Sendable {
    case dns, url, oid, x500

    var title: String {
        switch self {
        case .dns: return "DNS"
        case .url: return "URL"
        case .oid: return "OID"
        case .x500: return "X.500 DN"
        }
    }

    var uuidString: String {
        switch self {
        case .dns: return "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
        case .url: return "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
        case .oid: return "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
        case .x500: return "6ba7b814-9dad-11d1-80b4-00c04fd430c8"
        }
    }
}

struct UuidVariants: Sendable {
    let standard: String
    let uppercase: String
    let compact: String
    let compactUpper: String
    let braced: String
    let urn: String
    let base64: String
    let base64url: String
    let u128Decimal: String
    let hexBytes: String

    func value(for format: UuidVersionFormat) -> String {
        switch format {
        case .standard: return standard
        case .uppercase: return uppercase
        case .compact: return compact
        case .compactUpper: return compactUpper
        case .braced: return braced
        case .urn: return urn
        }
    }

    var allRows: [(String, String)] {
        [
            ("标准小写 (8-4-4-4-12)", standard),
            ("标准大写 (UPPERCASE)", uppercase),
            ("无连字符小写 (Compact)", compact),
            ("无连字符大写 (COMPACT)", compactUpper),
            ("大括号 ({...})", braced),
            ("URN (urn:uuid:...)", urn),
            ("Base64 (16 字节)", base64),
            ("Base64URL (22 字符)", base64url),
            ("128-bit 无符号整数", u128Decimal),
            ("C / Rust 字节数组", hexBytes),
        ]
    }
}

struct InspectedIdentifier: Sendable {
    let kind: String
    let normalized: String
    let label: String
    let version: String
    let variant: String
    let sortable: Bool
    let timestampMs: Int64?
    let timestampIso: String?
    let nodeHex: String?
    let clockSeq: Int?
    let entropyBits: Int
    let variants: UuidVariants?
}

final class UUIDEngine: @unchecked Sendable {
    static let shared = UUIDEngine()

    static let nilUuid = "00000000-0000-0000-0000-000000000000"
    static let maxUuid = "ffffffff-ffff-ffff-ffff-ffffffffffff"
    private static let gregorianEpochOffsetMs: Int64 = 12_219_292_800_000
    private static let ksuidEpochSec: Int64 = 1_400_000_000
    private static let crockfordChars = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let base62Chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let nanoIdAlphabet = Array("ModuleSymbhasOwnPr-0123456789ABCDEFGHNRVfgctiUvz_KqYTJkLxpZXIjQW")

    private let lock = NSLock()
    private var lastGregorianMs: Int64 = 0
    private var gregorianTicks: Int64 = 0
    private let sessionClockSeq: UInt16
    private let sessionNode: [UInt8]
    private var lastV7Ms: Int64 = -1
    private var v7Counter: UInt16 = 0
    private var lastUlidMs: Int64 = -1
    private var lastUlidRand: [UInt8] = Array(repeating: 0, count: 10)
    private var objectIdCounter: UInt32
    private let objectIdProcess: [UInt8]

    private init() {
        let clk = UUIDEngine.randomBytes(count: 2)
        sessionClockSeq = ((UInt16(clk[0]) << 8) | UInt16(clk[1])) & 0x3fff
        var node = UUIDEngine.randomBytes(count: 6)
        node[0] |= 0x01
        sessionNode = node
        let oid = UUIDEngine.randomBytes(count: 3)
        objectIdCounter = (UInt32(oid[0]) << 16) | (UInt32(oid[1]) << 8) | UInt32(oid[2])
        objectIdProcess = UUIDEngine.randomBytes(count: 5)
    }

    static func randomBytes(count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            for i in 0..<count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return bytes
    }

    static func bytesToUuid(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 16)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let a = hex.prefix(8)
        let b = hex.dropFirst(8).prefix(4)
        let c = hex.dropFirst(12).prefix(4)
        let d = hex.dropFirst(16).prefix(4)
        let e = hex.dropFirst(20).prefix(12)
        return "\(a)-\(b)-\(c)-\(d)-\(e)"
    }

    static func parseUuidBytes(_ input: String) -> [UInt8]? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("urn:uuid:") {
            s = String(s.dropFirst(9))
        }
        if s.hasPrefix("{") && s.hasSuffix("}") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        let hex: String
        if s.count == 36 {
            let parts = s.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 5,
                parts[0].count == 8, parts[1].count == 4, parts[2].count == 4,
                parts[3].count == 4, parts[4].count == 12
            else { return nil }
            hex = parts.joined()
        } else if s.count == 32 {
            hex = s
        } else {
            return nil
        }
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        var idx = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        return bytes
    }

    private func nextGregorianTimestamp100ns(timestampMs: Int64?) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let ms = timestampMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        let ticks: Int64
        if timestampMs == nil {
            if ms == lastGregorianMs {
                gregorianTicks = (gregorianTicks + 1) % 10_000
            } else {
                lastGregorianMs = ms
                gregorianTicks = 0
            }
            ticks = gregorianTicks
        } else {
            ticks = 0
        }
        let total100ns = (ms + Self.gregorianEpochOffsetMs) * 10_000 + ticks
        return UInt64(max(0, total100ns))
    }

    func generateV1(timestampMs: Int64? = nil) -> String {
        let ts = nextGregorianTimestamp100ns(timestampMs: timestampMs)
        let timeLow = UInt32(truncatingIfNeeded: ts)
        let timeMid = UInt16(truncatingIfNeeded: ts >> 32)
        let timeHi = UInt16(truncatingIfNeeded: ts >> 48) & 0x0fff
        var out = [UInt8](repeating: 0, count: 16)
        out[0] = UInt8((timeLow >> 24) & 0xff)
        out[1] = UInt8((timeLow >> 16) & 0xff)
        out[2] = UInt8((timeLow >> 8) & 0xff)
        out[3] = UInt8(timeLow & 0xff)
        out[4] = UInt8((timeMid >> 8) & 0xff)
        out[5] = UInt8(timeMid & 0xff)
        let verHi = 0x1000 | timeHi
        out[6] = UInt8((verHi >> 8) & 0xff)
        out[7] = UInt8(verHi & 0xff)
        out[8] = 0x80 | UInt8((sessionClockSeq >> 8) & 0x3f)
        out[9] = UInt8(sessionClockSeq & 0xff)
        for i in 0..<6 { out[10 + i] = sessionNode[i] }
        return Self.bytesToUuid(out)
    }

    func generateV6(timestampMs: Int64? = nil) -> String {
        let ts = nextGregorianTimestamp100ns(timestampMs: timestampMs)
        let timeHigh = UInt32(truncatingIfNeeded: ts >> 28)
        let timeMid = UInt16(truncatingIfNeeded: ts >> 12)
        let timeLow = UInt16(truncatingIfNeeded: ts) & 0x0fff
        var out = [UInt8](repeating: 0, count: 16)
        out[0] = UInt8((timeHigh >> 24) & 0xff)
        out[1] = UInt8((timeHigh >> 16) & 0xff)
        out[2] = UInt8((timeHigh >> 8) & 0xff)
        out[3] = UInt8(timeHigh & 0xff)
        out[4] = UInt8((timeMid >> 8) & 0xff)
        out[5] = UInt8(timeMid & 0xff)
        let verLo = 0x6000 | timeLow
        out[6] = UInt8((verLo >> 8) & 0xff)
        out[7] = UInt8(verLo & 0xff)
        out[8] = 0x80 | UInt8((sessionClockSeq >> 8) & 0x3f)
        out[9] = UInt8(sessionClockSeq & 0xff)
        for i in 0..<6 { out[10 + i] = sessionNode[i] }
        return Self.bytesToUuid(out)
    }

    func generateV3(name: String, namespaceUuid: String = UuidNamespace.dns.uuidString) -> String {
        guard let nsBytes = Self.parseUuidBytes(namespaceUuid) else {
            return Self.nilUuid
        }
        var input = Data(nsBytes)
        input.append(Data(name.utf8))
        var bytes = Array(Insecure.MD5.hash(data: input))
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return Self.bytesToUuid(bytes)
    }

    func generateV5(name: String, namespaceUuid: String = UuidNamespace.dns.uuidString) -> String {
        guard let nsBytes = Self.parseUuidBytes(namespaceUuid) else {
            return Self.nilUuid
        }
        var input = Data(nsBytes)
        input.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return Self.bytesToUuid(bytes)
    }

    func generateV4() -> String {
        UUID().uuidString.lowercased()
    }

    func generateV7(timestampMs: Int64? = nil) -> String {
        var ms: Int64
        let randA: UInt16
        lock.lock()
        if let customMs = timestampMs {
            ms = max(0, customMs)
            let rnd = Self.randomBytes(count: 2)
            randA = ((UInt16(rnd[0]) << 8) | UInt16(rnd[1])) & 0x0fff
        } else {
            ms = Int64(Date().timeIntervalSince1970 * 1000)
            if ms <= lastV7Ms {
                ms = lastV7Ms
                v7Counter = (v7Counter + 1) & 0x0fff
                if v7Counter == 0 {
                    ms += 1
                    lastV7Ms = ms
                }
            } else {
                lastV7Ms = ms
                let rnd = Self.randomBytes(count: 2)
                v7Counter = ((UInt16(rnd[0]) << 8) | UInt16(rnd[1])) & 0x03ff
            }
            randA = v7Counter
        }
        lock.unlock()

        let tsU64 = UInt64(max(0, ms))
        let randB = Self.randomBytes(count: 8)
        var out = [UInt8](repeating: 0, count: 16)
        out[0] = UInt8((tsU64 >> 40) & 0xff)
        out[1] = UInt8((tsU64 >> 32) & 0xff)
        out[2] = UInt8((tsU64 >> 24) & 0xff)
        out[3] = UInt8((tsU64 >> 16) & 0xff)
        out[4] = UInt8((tsU64 >> 8) & 0xff)
        out[5] = UInt8(tsU64 & 0xff)
        out[6] = 0x70 | UInt8((randA >> 8) & 0x0f)
        out[7] = UInt8(randA & 0xff)
        for i in 0..<8 { out[8 + i] = randB[i] }
        out[8] = (out[8] & 0x3f) | 0x80
        return Self.bytesToUuid(out)
    }

    func generateV8(seed: String? = nil) -> String {
        var bytes: [UInt8]
        if let seed, !seed.isEmpty {
            bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        } else {
            bytes = Self.randomBytes(count: 16)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return Self.bytesToUuid(bytes)
    }

    func generateUlid(timestampMs: Int64? = nil) -> String {
        var ms: Int64
        var rand = [UInt8](repeating: 0, count: 10)
        lock.lock()
        if let customMs = timestampMs {
            ms = max(0, customMs)
            rand = Self.randomBytes(count: 10)
        } else {
            ms = Int64(Date().timeIntervalSince1970 * 1000)
            if ms <= lastUlidMs {
                ms = lastUlidMs
                rand = lastUlidRand
                for i in stride(from: 9, through: 0, by: -1) {
                    if rand[i] < 255 {
                        rand[i] += 1
                        break
                    }
                    rand[i] = 0
                }
            } else {
                rand = Self.randomBytes(count: 10)
            }
            lastUlidMs = ms
            lastUlidRand = rand
        }
        lock.unlock()

        var t = UInt64(max(0, ms))
        var timeChars = [Character](repeating: "0", count: 10)
        for i in stride(from: 9, through: 0, by: -1) {
            timeChars[i] = Self.crockfordChars[Int(t & 31)]
            t >>= 5
        }

        var randBits: UInt128 = 0
        for b in rand { randBits = (randBits << 8) | UInt128(b) }
        var randChars = [Character](repeating: "0", count: 16)
        for i in stride(from: 15, through: 0, by: -1) {
            randChars[i] = Self.crockfordChars[Int(randBits & 31)]
            randBits >>= 5
        }
        return String(timeChars) + String(randChars)
    }

    func generateNanoId(length: Int = 21) -> String {
        let len = max(4, min(128, length))
        let alphabet = Self.nanoIdAlphabet
        var result = String()
        result.reserveCapacity(len)
        while result.count < len {
            let chunk = Self.randomBytes(count: len * 2)
            for b in chunk where result.count < len {
                let idx = Int(b & 63)
                if idx < alphabet.count {
                    result.append(alphabet[idx])
                }
            }
        }
        return result
    }

    func generateKsuid(timestampMs: Int64? = nil) -> String {
        let nowSec = Int64(Date().timeIntervalSince1970)
        let sec = timestampMs.map { $0 / 1000 } ?? nowSec
        let offset = UInt32(max(0, sec - Self.ksuidEpochSec))
        let payload = Self.randomBytes(count: 16)
        var bytes: [UInt8] = [
            UInt8((offset >> 24) & 0xff),
            UInt8((offset >> 16) & 0xff),
            UInt8((offset >> 8) & 0xff),
            UInt8(offset & 0xff),
        ] + payload
        var chars = [Character](repeating: "0", count: 27)
        for pos in stride(from: 26, through: 0, by: -1) {
            var rem = 0
            for i in 0..<bytes.count {
                let cur = rem * 256 + Int(bytes[i])
                bytes[i] = UInt8(cur / 62)
                rem = cur % 62
            }
            chars[pos] = Self.base62Chars[rem]
        }
        return String(chars)
    }

    func generateObjectId(timestampMs: Int64? = nil) -> String {
        let sec = UInt32(max(0, (timestampMs ?? Int64(Date().timeIntervalSince1970 * 1000)) / 1000))
        lock.lock()
        objectIdCounter = (objectIdCounter + 1) & 0x00ff_ffff
        let cnt = objectIdCounter
        lock.unlock()

        var out = [UInt8](repeating: 0, count: 12)
        out[0] = UInt8((sec >> 24) & 0xff)
        out[1] = UInt8((sec >> 16) & 0xff)
        out[2] = UInt8((sec >> 8) & 0xff)
        out[3] = UInt8(sec & 0xff)
        for i in 0..<5 { out[4 + i] = objectIdProcess[i] }
        out[9] = UInt8((cnt >> 16) & 0xff)
        out[10] = UInt8((cnt >> 8) & 0xff)
        out[11] = UInt8(cnt & 0xff)
        return out.map { String(format: "%02x", $0) }.joined()
    }

    func generate(
        kind: IdKind,
        format: UuidVersionFormat = .standard,
        name: String = "example.com",
        namespace: UuidNamespace = .dns,
        seed: String? = nil,
        nanoLength: Int = 21,
        timestampMs: Int64? = nil
    ) -> String {
        let raw: String
        switch kind {
        case .v1: raw = generateV1(timestampMs: timestampMs)
        case .v3: raw = generateV3(name: name.isEmpty ? "example.com" : name, namespaceUuid: namespace.uuidString)
        case .v4: raw = generateV4()
        case .v5: raw = generateV5(name: name.isEmpty ? "example.com" : name, namespaceUuid: namespace.uuidString)
        case .v6: raw = generateV6(timestampMs: timestampMs)
        case .v7: raw = generateV7(timestampMs: timestampMs)
        case .v8: raw = generateV8(seed: seed)
        case .nilUuid: raw = Self.nilUuid
        case .maxUuid: raw = Self.maxUuid
        case .ulid: raw = generateUlid(timestampMs: timestampMs)
        case .nanoid: raw = generateNanoId(length: nanoLength)
        case .ksuid: raw = generateKsuid(timestampMs: timestampMs)
        case .objectid: raw = generateObjectId(timestampMs: timestampMs)
        }
        if let variants = formatVariants(raw) {
            return variants.value(for: format)
        }
        return raw
    }

    func formatVariants(_ uuid: String) -> UuidVariants? {
        guard let bytes = Self.parseUuidBytes(uuid) else { return nil }
        let standard = Self.bytesToUuid(bytes)
        let compact = standard.replacingOccurrences(of: "-", with: "")
        let data = Data(bytes)
        let b64 = data.base64EncodedString()
        let b64url = b64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var u128: UInt128 = 0
        for b in bytes { u128 = (u128 << 8) | UInt128(b) }
        let hexBytes = bytes.map { String(format: "0x%02x", $0) }.joined(separator: ", ")
        return UuidVariants(
            standard: standard,
            uppercase: standard.uppercased(),
            compact: compact,
            compactUpper: compact.uppercased(),
            braced: "{\(standard)}",
            urn: "urn:uuid:\(standard)",
            base64: b64,
            base64url: b64url,
            u128Decimal: String(u128),
            hexBytes: hexBytes
        )
    }

    func inspect(_ raw: String) -> InspectedIdentifier? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let bytes = Self.parseUuidBytes(trimmed) {
            let norm = Self.bytesToUuid(bytes)
            let variants = formatVariants(norm)
            if norm == Self.nilUuid {
                return InspectedIdentifier(
                    kind: "uuid", normalized: norm, label: "Nil UUID (全零)", version: "Nil (0)",
                    variant: "RFC 9562", sortable: false, timestampMs: nil, timestampIso: nil,
                    nodeHex: nil, clockSeq: nil, entropyBits: 0, variants: variants
                )
            }
            if norm == Self.maxUuid {
                return InspectedIdentifier(
                    kind: "uuid", normalized: norm, label: "Max / Omni UUID (全 F)", version: "Max (F)",
                    variant: "RFC 9562", sortable: false, timestampMs: nil, timestampIso: nil,
                    nodeHex: nil, clockSeq: nil, entropyBits: 0, variants: variants
                )
            }

            let ver = Int((bytes[6] >> 4) & 0x0f)
            let varByte = bytes[8]
            let variant: String
            if (varByte & 0x80) == 0 { variant = "NCS Backward Compatibility" }
            else if (varByte & 0xc0) == 0x80 { variant = "RFC 4122 / RFC 9562" }
            else if (varByte & 0xe0) == 0xc0 { variant = "Microsoft COM/DCOM" }
            else { variant = "Future / Reserved" }

            var tsMs: Int64?
            var nodeHex: String?
            var clockSeq: Int?
            var entropyBits = 122

            if ver == 1 {
                let tLow = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
                let tMid = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
                let tHi = UInt64(bytes[6] & 0x0f) << 8 | UInt64(bytes[7])
                let ts100ns = (tHi << 48) | (tMid << 32) | tLow
                tsMs = Int64(ts100ns / 10_000) - Self.gregorianEpochOffsetMs
                clockSeq = (Int(bytes[8] & 0x3f) << 8) | Int(bytes[9])
                nodeHex = bytes[10..<16].map { String(format: "%02x", $0) }.joined(separator: ":")
                entropyBits = 62
            } else if ver == 6 {
                let tHi = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
                let tMid = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
                let tLo = UInt64(bytes[6] & 0x0f) << 8 | UInt64(bytes[7])
                let ts100ns = (tHi << 28) | (tMid << 12) | tLo
                tsMs = Int64(ts100ns / 10_000) - Self.gregorianEpochOffsetMs
                clockSeq = (Int(bytes[8] & 0x3f) << 8) | Int(bytes[9])
                nodeHex = bytes[10..<16].map { String(format: "%02x", $0) }.joined(separator: ":")
                entropyBits = 62
            } else if ver == 7 {
                var ts: UInt64 = 0
                for i in 0..<6 { ts = (ts << 8) | UInt64(bytes[i]) }
                tsMs = Int64(ts)
                entropyBits = 74
            } else if ver == 3 || ver == 5 {
                entropyBits = 0
            }

            let labels = [
                1: "v1 · Gregorian Time-Based",
                2: "v2 · DCE Security",
                3: "v3 · Name-Based (MD5)",
                4: "v4 · Random",
                5: "v5 · Name-Based (SHA-1)",
                6: "v6 · Reordered Time-Based (Sortable)",
                7: "v7 · Unix Epoch Time-Ordered (Sortable)",
                8: "v8 · Custom / Experimental",
            ]

            let iso = tsMs.map { ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: Double($0) / 1000.0), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds]) }
            return InspectedIdentifier(
                kind: "uuid", normalized: norm, label: labels[ver] ?? "UUID v\(ver)", version: "v\(ver)",
                variant: variant, sortable: ver == 6 || ver == 7, timestampMs: tsMs, timestampIso: iso,
                nodeHex: nodeHex, clockSeq: clockSeq, entropyBits: entropyBits, variants: variants
            )
        }

        // ULID
        let upper = trimmed.uppercased()
        if upper.count == 26, let firstIdx = Self.crockfordChars.firstIndex(of: upper.first!), firstIdx <= 7 {
            var ts: UInt64 = 0
            var valid = true
            for (idx, ch) in upper.enumerated() {
                guard let pos = Self.crockfordChars.firstIndex(of: ch) else {
                    valid = false
                    break
                }
                if idx < 10 { ts = (ts << 5) | UInt64(pos) }
            }
            if valid {
                let ms = Int64(ts)
                let iso = ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
                return InspectedIdentifier(
                    kind: "ulid", normalized: upper, label: "ULID · Crockford Base32 (Sortable)", version: "ULID",
                    variant: "48-bit ms + 80-bit random", sortable: true, timestampMs: ms, timestampIso: iso,
                    nodeHex: nil, clockSeq: nil, entropyBits: 80, variants: nil
                )
            }
        }

        // KSUID
        if trimmed.count == 27, trimmed.allSatisfy({ Self.base62Chars.contains($0) }) {
            var bytes = [UInt8](repeating: 0, count: 20)
            var valid = true
            for ch in trimmed {
                guard let pos = Self.base62Chars.firstIndex(of: ch) else { valid = false; break }
                var carry = pos
                for i in stride(from: 19, through: 0, by: -1) {
                    let cur = Int(bytes[i]) * 62 + carry
                    bytes[i] = UInt8(cur & 0xff)
                    carry = cur >> 8
                }
                if carry != 0 { valid = false; break }
            }
            if valid {
                let secOffset = (Int64(bytes[0]) << 24) | (Int64(bytes[1]) << 16) | (Int64(bytes[2]) << 8) | Int64(bytes[3])
                let ms = (secOffset + Self.ksuidEpochSec) * 1000
                let iso = ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0), timeZone: .gmt, formatOptions: [.withInternetDateTime])
                return InspectedIdentifier(
                    kind: "ksuid", normalized: trimmed, label: "KSUID · Base62 (K-Sortable)", version: "KSUID",
                    variant: "32-bit sec + 128-bit random", sortable: true, timestampMs: ms, timestampIso: iso,
                    nodeHex: nil, clockSeq: nil, entropyBits: 128, variants: nil
                )
            }
        }

        // MongoDB ObjectID
        if trimmed.count == 24, trimmed.allSatisfy({ $0.isHexDigit }), let sec = UInt32(trimmed.prefix(8), radix: 16) {
            let ms = Int64(sec) * 1000
            let iso = ISO8601DateFormatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0), timeZone: .gmt, formatOptions: [.withInternetDateTime])
            return InspectedIdentifier(
                kind: "objectid", normalized: trimmed.lowercased(), label: "MongoDB ObjectID · 12-byte Hex", version: "ObjectID",
                variant: "32-bit sec + 5B rand + 3B counter", sortable: true, timestampMs: ms, timestampIso: iso,
                nodeHex: nil, clockSeq: nil, entropyBits: 64, variants: nil
            )
        }

        return nil
    }
}
