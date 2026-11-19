import Foundation

// MARK: - 1. Radix & 64-Bit Bitwise Engine

enum BitwiseBinaryOp: String, CaseIterable, Sendable {
    case and = "AND (&)"
    case or = "OR (|)"
    case xor = "XOR (^)"
    case nand = "NAND (~&)"
    case shl = "左移 (<<)"
    case shr = "右移 (>>)"
}

struct RadixRepresentation: Sendable {
    let value: UInt64
    let binCompact: String
    let binGrouped64: String
    let oct: String
    let decUnsigned: String
    let decSigned64: Int64
    let decSigned32: Int32
    let decSigned16: Int16
    let decSigned8: Int8
    let hexUpper: String
    let hexLower: String
    let hex0x: String
    let beBytes: String
    let leBytes: String
    let swap64Hex: String
    let swap32Hex: String
}

struct ChmodState: Sendable, Equatable {
    var specialBits: Int // 4=setuid, 2=setgid, 1=sticky
    var ownerBits: Int   // 4=r, 2=w, 1=x
    var groupBits: Int
    var otherBits: Int

    static let defaultExec = ChmodState(specialBits: 0, ownerBits: 7, groupBits: 5, otherBits: 5)

    var octal3: String {
        "\(ownerBits)\(groupBits)\(otherBits)"
    }

    var octal4: String {
        "\(specialBits)\(ownerBits)\(groupBits)\(otherBits)"
    }

    var command: String {
        specialBits == 0 ? "chmod \(octal3)" : "chmod \(octal4)"
    }

    var symbolic: String {
        func triplet(_ perms: Int, specialActive: Bool, highChar: Character, lowChar: Character) -> String {
            let r: Character = (perms & 4) != 0 ? "r" : "-"
            let w: Character = (perms & 2) != 0 ? "w" : "-"
            let exec = (perms & 1) != 0
            let x: Character = specialActive ? (exec ? lowChar : highChar) : (exec ? "x" : "-")
            return String([r, w, x])
        }
        let u = triplet(ownerBits, specialActive: (specialBits & 4) != 0, highChar: "S", lowChar: "s")
        let g = triplet(groupBits, specialActive: (specialBits & 2) != 0, highChar: "S", lowChar: "s")
        let o = triplet(otherBits, specialActive: (specialBits & 1) != 0, highChar: "T", lowChar: "t")
        return u + g + o
    }

    static func parse(_ raw: String) -> ChmodState? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("chmod ") {
            s = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        // Octal: 3 or 4 digits 0-7
        if s.count == 3 || s.count == 4, s.allSatisfy({ ("0"..."7").contains($0) }) {
            let padded = s.count == 3 ? "0" + s : s
            let digits = padded.compactMap { Int(String($0)) }
            return ChmodState(specialBits: digits[0], ownerBits: digits[1], groupBits: digits[2], otherBits: digits[3])
        }
        // Symbolic: optional leading file-type char ('-' or 'd' or 'l') + 9 chars
        if s.count == 10, "-dlcbps".contains(s.first!) {
            s = String(s.dropFirst())
        }
        guard s.count == 9 else { return nil }
        let chars = Array(s)
        func parseTriplet(_ offset: Int, specialBit: Int, expectedSpecial: (Character, Character)) -> (Int, Int)? {
            var bits = 0
            var spec = 0
            if chars[offset] == "r" { bits |= 4 } else if chars[offset] != "-" { return nil }
            if chars[offset + 1] == "w" { bits |= 2 } else if chars[offset + 1] != "-" { return nil }
            let x = chars[offset + 2]
            if x == "x" {
                bits |= 1
            } else if x == expectedSpecial.0 { // lowercase s / t -> exec + special
                bits |= 1
                spec = specialBit
            } else if x == expectedSpecial.1 { // uppercase S / T -> special without exec
                spec = specialBit
            } else if x != "-" {
                return nil
            }
            return (bits, spec)
        }
        guard let (u, su) = parseTriplet(0, specialBit: 4, expectedSpecial: ("s", "S")),
              let (g, sg) = parseTriplet(3, specialBit: 2, expectedSpecial: ("s", "S")),
              let (o, so) = parseTriplet(6, specialBit: 1, expectedSpecial: ("t", "T")) else {
            return nil
        }
        return ChmodState(specialBits: su | sg | so, ownerBits: u, groupBits: g, otherBits: o)
    }
}

enum ByteUnit: String, CaseIterable, Identifiable, Sendable {
    case bit = "bit"
    case byte = "B"
    case kb = "KB (10³)"
    case kib = "KiB (2¹⁰)"
    case mb = "MB (10⁶)"
    case mib = "MiB (2²⁰)"
    case gb = "GB (10⁹)"
    case gib = "GiB (2³⁰)"
    case tb = "TB (10¹²)"
    case tib = "TiB (2⁴⁰)"

    var id: String { rawValue }

    var bytesMultiplier: Double {
        switch self {
        case .bit: return 1.0 / 8.0
        case .byte: return 1.0
        case .kb: return 1_000.0
        case .kib: return 1_024.0
        case .mb: return 1_000_000.0
        case .mib: return 1_048_576.0
        case .gb: return 1_000_000_000.0
        case .gib: return 1_073_741_824.0
        case .tb: return 1_000_000_000_000.0
        case .tib: return 1_099_511_627_776.0
        }
    }
}

struct ByteConversionRow: Identifiable, Sendable {
    let id: String
    let unit: String
    let value: String
}

enum RadixBitwiseEngine {
    static func parse(_ raw: String, radix hintRadix: Int? = nil) -> UInt64? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        let negative = cleaned.hasPrefix("-")
        let unsignedRaw = negative ? String(cleaned.dropFirst()) : (cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned)
        guard !unsignedRaw.isEmpty else { return nil }

        let detectedRadix: Int
        let digits: String
        let lower = unsignedRaw.lowercased()
        if lower.hasPrefix("0x") {
            detectedRadix = 16
            digits = String(lower.dropFirst(2))
        } else if lower.hasPrefix("0b") {
            detectedRadix = 2
            digits = String(lower.dropFirst(2))
        } else if lower.hasPrefix("0o") {
            detectedRadix = 8
            digits = String(lower.dropFirst(2))
        } else {
            detectedRadix = min(max(hintRadix ?? 10, 2), 36)
            digits = unsignedRaw
        }

        guard !digits.isEmpty else { return nil }
        if negative {
            guard let mag = Int64(digits, radix: detectedRadix) else {
                if let u = UInt64(digits, radix: detectedRadix), u == UInt64(Int64.max) + 1 {
                    return UInt64(bitPattern: Int64.min)
                }
                return nil
            }
            return UInt64(bitPattern: -mag)
        }
        return UInt64(digits, radix: detectedRadix)
    }

    static func represent(_ value: UInt64) -> RadixRepresentation {
        let rawBin = String(value, radix: 2)
        let padBin64 = String(repeating: "0", count: max(0, 64 - rawBin.count)) + rawBin
        let grouped = stride(from: 0, to: 64, by: 4).map { idx -> String in
            let start = padBin64.index(padBin64.startIndex, offsetBy: idx)
            let end = padBin64.index(start, offsetBy: 4)
            return String(padBin64[start..<end])
        }.joined(separator: " ")

        let hexPad = String(format: "%016llX", value)
        let hexCompact = String(value, radix: 16, uppercase: true)
        var beBytes: [String] = []
        for i in 0..<8 {
            let start = hexPad.index(hexPad.startIndex, offsetBy: i * 2)
            let end = hexPad.index(start, offsetBy: 2)
            beBytes.append(String(hexPad[start..<end]))
        }
        let leBytes = beBytes.reversed()

        return RadixRepresentation(
            value: value,
            binCompact: rawBin,
            binGrouped64: grouped,
            oct: String(value, radix: 8),
            decUnsigned: String(value),
            decSigned64: Int64(bitPattern: value),
            decSigned32: Int32(bitPattern: UInt32(truncatingIfNeeded: value)),
            decSigned16: Int16(bitPattern: UInt16(truncatingIfNeeded: value)),
            decSigned8: Int8(bitPattern: UInt8(truncatingIfNeeded: value)),
            hexUpper: hexCompact,
            hexLower: hexCompact.lowercased(),
            hex0x: "0x\(hexCompact)",
            beBytes: beBytes.joined(separator: " "),
            leBytes: leBytes.joined(separator: " "),
            swap64Hex: "0x" + String(format: "%016llX", value.byteSwapped),
            swap32Hex: "0x" + String(format: "%08X", UInt32(truncatingIfNeeded: value).byteSwapped)
        )
    }

    static func format(_ value: UInt64, radix: Int) -> String {
        let r = min(max(radix, 2), 36)
        return String(value, radix: r, uppercase: true)
    }

    static func toggleBit(_ value: UInt64, at bitIndex: Int) -> UInt64 {
        guard (0..<64).contains(bitIndex) else { return value }
        return value ^ (UInt64(1) << bitIndex)
    }

    static func compute(a: UInt64, b: UInt64, op: BitwiseBinaryOp) -> UInt64 {
        switch op {
        case .and: return a & b
        case .or: return a | b
        case .xor: return a ^ b
        case .nand: return ~(a & b)
        case .shl: return a << (b % 64)
        case .shr: return a >> (b % 64)
        }
    }

    static func convertBytes(amount: Double, unit: ByteUnit) -> [ByteConversionRow] {
        let totalBytes = amount * unit.bytesMultiplier
        return ByteUnit.allCases.map { target in
            let v = totalBytes / target.bytesMultiplier
            let formatted: String
            if abs(v - v.rounded()) < 1e-9 && abs(v) < 1e15 {
                formatted = String(format: "%.0f", v)
            } else if abs(v) >= 0.01 && abs(v) < 1e12 {
                formatted = String(format: "%.6f", v)
                    .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            } else {
                formatted = String(format: "%.6g", v)
            }
            return ByteConversionRow(id: target.rawValue, unit: target.rawValue, value: formatted)
        }
    }
}

// MARK: - 2. CIDR & IP Subnet Engine

struct Ipv4CidrResult: Sendable {
    let input: String
    let cidrNotation: String
    let address: String
    let prefix: Int
    let network: String
    let broadcast: String
    let firstHost: String
    let lastHost: String
    let netmask: String
    let wildcard: String
    let totalCount: UInt64
    let usableCount: UInt64
    let scope: String
    let intValue: UInt32
    let binaryOctets: String
}

struct Ipv4SubnetSlice: Identifiable, Sendable {
    let id: Int
    let index: Int
    let cidr: String
    let range: String
    let usableCount: UInt64
}

struct Ipv6CidrResult: Sendable {
    let input: String
    let cidrNotation: String
    let expandedAddress: String
    let compressedAddress: String
    let expandedNetwork: String
    let compressedNetwork: String
    let compressedEnd: String
    let prefix: Int
    let addressCountText: String
    let scope: String
}

enum CidrEngine {
    static func parseIpv4(_ s: String) -> UInt32? {
        let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, let byte = UInt8(part) else { return nil }
            out = (out << 8) | UInt32(byte)
        }
        return out
    }

    static func formatIpv4(_ ip: UInt32) -> String {
        "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }

    static func prefixFromMask(_ mask: UInt32) -> Int? {
        var seenZero = false
        var count = 0
        for bit in stride(from: 31, through: 0, by: -1) {
            let isOne = ((mask >> bit) & 1) == 1
            if isOne {
                if seenZero { return nil }
                count += 1
            } else {
                seenZero = true
            }
        }
        return count
    }

    static func classifyIpv4(_ ip: UInt32) -> String {
        let b1 = (ip >> 24) & 0xFF
        let b2 = (ip >> 16) & 0xFF
        if b1 == 10 { return "RFC 1918 私有网段 (Class A)" }
        if b1 == 172 && (16...31).contains(b2) { return "RFC 1918 私有网段 (Class B)" }
        if b1 == 192 && b2 == 168 { return "RFC 1918 私有网段 (Class C)" }
        if b1 == 127 { return "本机回环地址 (Loopback)" }
        if b1 == 169 && b2 == 254 { return "链路本地地址 (Link-Local)" }
        if b1 == 100 && (64...127).contains(b2) { return "运营商级 NAT (CGNAT RFC 6598)" }
        if (224...239).contains(b1) { return "多播地址 (Multicast)" }
        if b1 == 0 { return "保留网段 (0.0.0.0/8)" }
        if b1 >= 240 { return "保留网段 (Class E)" }
        return "公网可路由 IPv4"
    }

    static func parseIpv4Cidr(_ raw: String) -> Ipv4CidrResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let ipVal: UInt32
        let prefix: Int

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let ip = parseIpv4(String(parts[0])), let p = Int(parts[1]), (0...32).contains(p) else {
                return nil
            }
            ipVal = ip
            prefix = p
        } else if trimmed.contains(" ") {
            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 2, let ip = parseIpv4(parts[0]), let mask = parseIpv4(parts[1]), let p = prefixFromMask(mask) else {
                return nil
            }
            ipVal = ip
            prefix = p
        } else {
            guard let ip = parseIpv4(trimmed) else { return nil }
            ipVal = ip
            prefix = 24
        }

        let mask64: UInt64 = prefix == 0 ? 0 : (0xFFFF_FFFF << UInt64(32 - prefix)) & 0xFFFF_FFFF
        let mask32 = UInt32(mask64)
        let wildcard32 = ~mask32
        let net32 = ipVal & mask32
        let bcast32 = net32 | wildcard32

        let hostBits = 32 - prefix
        let totalCount: UInt64 = UInt64(1) << UInt64(hostBits)
        let usableCount: UInt64
        let firstHost: UInt32
        let lastHost: UInt32

        if prefix == 32 {
            usableCount = 1
            firstHost = net32
            lastHost = net32
        } else if prefix == 31 {
            usableCount = 2
            firstHost = net32
            lastHost = bcast32
        } else {
            usableCount = totalCount >= 2 ? (totalCount - 2) : 0
            firstHost = net32 &+ 1
            lastHost = bcast32 &- 1
        }

        let binOctets = [24, 16, 8, 0].map { shift -> String in
            let byte = (ipVal >> shift) & 0xFF
            let rawBin = String(byte, radix: 2)
            return String(repeating: "0", count: max(0, 8 - rawBin.count)) + rawBin
        }.joined(separator: ".")

        return Ipv4CidrResult(
            input: trimmed,
            cidrNotation: "\(formatIpv4(net32))/\(prefix)",
            address: formatIpv4(ipVal),
            prefix: prefix,
            network: formatIpv4(net32),
            broadcast: formatIpv4(bcast32),
            firstHost: formatIpv4(firstHost),
            lastHost: formatIpv4(lastHost),
            netmask: formatIpv4(mask32),
            wildcard: formatIpv4(wildcard32),
            totalCount: totalCount,
            usableCount: usableCount,
            scope: classifyIpv4(ipVal),
            intValue: ipVal,
            binaryOctets: binOctets
        )
    }

    static func ipv4Contains(cidr: String, ip: String) -> Bool? {
        guard let net = parseIpv4Cidr(cidr), let targetIp = parseIpv4(ip),
              let netBase = parseIpv4(net.network), let mask = parseIpv4(net.netmask) else {
            return nil
        }
        return (targetIp & mask) == netBase
    }

    static func splitIpv4(_ raw: String, targetPrefix: Int, limit: Int = 64) -> [Ipv4SubnetSlice] {
        guard let parent = parseIpv4Cidr(raw),
              targetPrefix > parent.prefix,
              (1...32).contains(targetPrefix),
              let base = parseIpv4(parent.network) else {
            return []
        }
        let deltaBits = targetPrefix - parent.prefix
        let totalSubnets: UInt64 = deltaBits >= 16 ? 64 : min(UInt64(1) << UInt64(deltaBits), UInt64(limit))
        let step: UInt64 = UInt64(1) << UInt64(32 - targetPrefix)
        let usable: UInt64 = targetPrefix == 32 ? 1 : (targetPrefix == 31 ? 2 : max(0, step - 2))

        var out: [Ipv4SubnetSlice] = []
        out.reserveCapacity(Int(totalSubnets))
        for i in 0..<totalSubnets {
            let start = UInt32(truncatingIfNeeded: UInt64(base) + i * step)
            let end = UInt32(truncatingIfNeeded: UInt64(start) + step - 1)
            let range = targetPrefix == 32 ? formatIpv4(start) : "\(formatIpv4(start)) – \(formatIpv4(end))"
            out.append(Ipv4SubnetSlice(
                id: Int(i),
                index: Int(i) + 1,
                cidr: "\(formatIpv4(start))/\(targetPrefix)",
                range: range,
                usableCount: usable
            ))
        }
        return out
    }

    // MARK: IPv6 using macOS 15 native UInt128

    static func parseIpv6Address(_ s: String) -> UInt128? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "%").first ?? ""
        guard !trimmed.isEmpty, trimmed.contains(":") else { return nil }

        let doubleColonParts = trimmed.components(separatedBy: "::")
        guard doubleColonParts.count <= 2 else { return nil }

        func parseGroupList(_ str: String) -> [UInt16]? {
            if str.isEmpty { return [] }
            let parts = str.split(separator: ":", omittingEmptySubsequences: false)
            var out: [UInt16] = []
            for p in parts {
                guard !p.isEmpty, p.count <= 4, let val = UInt16(p, radix: 16) else { return nil }
                out.append(val)
            }
            return out
        }

        let groups: [UInt16]
        if doubleColonParts.count == 2 {
            guard let left = parseGroupList(doubleColonParts[0]),
                  let right = parseGroupList(doubleColonParts[1]),
                  left.count + right.count < 8 else { return nil }
            let zeros = Array(repeating: UInt16(0), count: 8 - left.count - right.count)
            groups = left + zeros + right
        } else {
            guard let direct = parseGroupList(doubleColonParts[0]), direct.count == 8 else { return nil }
            groups = direct
        }

        var result: UInt128 = 0
        for g in groups {
            result = (result << 16) | UInt128(g)
        }
        return result
    }

    static func expandIpv6(_ addr: UInt128) -> String {
        let groups = (0..<8).map { i -> String in
            let shift = (7 - i) * 16
            let val = UInt16((addr >> shift) & 0xFFFF)
            return String(format: "%04x", val)
        }
        return groups.joined(separator: ":")
    }

    static func compressIpv6(_ addr: UInt128) -> String {
        let groups = (0..<8).map { i -> UInt16 in
            let shift = (7 - i) * 16
            return UInt16((addr >> shift) & 0xFFFF)
        }
        // Find longest run of >= 2 zeros (RFC 5952)
        var bestStart = -1
        var bestLen = 0
        var curStart = -1
        var curLen = 0
        for (i, g) in groups.enumerated() {
            if g == 0 {
                if curStart == -1 { curStart = i; curLen = 1 }
                else { curLen += 1 }
                if curLen > bestLen { bestStart = curStart; bestLen = curLen }
            } else {
                curStart = -1
                curLen = 0
            }
        }
        if bestLen < 2 { bestStart = -1; bestLen = 0 }

        var parts: [String] = []
        var i = 0
        while i < 8 {
            if i == bestStart {
                if i == 0 { parts.append("") }
                parts.append("")
                i += bestLen
                if i == 8 { parts.append("") }
                continue
            }
            parts.append(String(groups[i], radix: 16))
            i += 1
        }
        return parts.joined(separator: ":")
    }

    static func parseIpv6Cidr(_ raw: String) -> Ipv6CidrResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        let addrPart: String
        let prefix: Int
        if parts.count == 2 {
            guard let p = Int(parts[1]), (0...128).contains(p) else { return nil }
            addrPart = String(parts[0])
            prefix = p
        } else if parts.count == 1 {
            addrPart = trimmed
            prefix = 64
        } else {
            return nil
        }

        guard let addr = parseIpv6Address(addrPart) else { return nil }
        let mask: UInt128 = prefix == 0 ? 0 : (prefix == 128 ? UInt128.max : (~UInt128(0) << (128 - prefix)))
        let network = addr & mask
        let end = network | (~mask)

        let hostBits = 128 - prefix
        let countText: String
        if hostBits == 0 {
            countText = "1"
        } else if hostBits <= 32 {
            countText = "\(UInt64(1) << UInt64(hostBits))"
        } else {
            countText = "2^\(hostBits)"
        }

        let topByte = UInt8((addr >> 120) & 0xFF)
        let top16 = UInt16((addr >> 112) & 0xFFFF)
        let scope: String
        if addr == 1 { scope = "回环地址 (::1)" }
        else if addr == 0 { scope = "未指定地址 (::)" }
        else if (top16 & 0xFFC0) == 0xFE80 { scope = "链路本地 (fe80::/10)" }
        else if (topByte & 0xFE) == 0xFC { scope = "唯一本地地址 (ULA fc00::/7)" }
        else if topByte == 0xFF { scope = "多播地址 (ff00::/8)" }
        else if (addr >> 96) == 0x2001_0DB8 { scope = "文档示例网段 (RFC 3849)" }
        else if (top16 & 0xE000) == 0x2000 { scope = "全球单播 (2000::/3)" }
        else { scope = "IPv6 地址" }

        return Ipv6CidrResult(
            input: trimmed,
            cidrNotation: "\(compressIpv6(network))/\(prefix)",
            expandedAddress: expandIpv6(addr),
            compressedAddress: compressIpv6(addr),
            expandedNetwork: expandIpv6(network),
            compressedNetwork: compressIpv6(network),
            compressedEnd: compressIpv6(end),
            prefix: prefix,
            addressCountText: countText,
            scope: scope
        )
    }
}
