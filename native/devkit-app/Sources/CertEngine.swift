import CryptoKit
import Foundation
import Security

// MARK: - X.509 Certificate & OpenSSH Public Key Engine

struct ParsedX509Certificate: Identifiable, Sendable {
    let id: Int
    let version: String
    let serialHex: String
    let subject: String
    let subjectCommonName: String
    let issuer: String
    let issuerCommonName: String
    let notBefore: Date
    let notAfter: Date
    let daysRemaining: Int
    let isExpired: Bool
    let isNotYetValid: Bool
    let isSelfSigned: Bool
    let isCA: Bool?
    let signatureAlgorithm: String
    let publicKeySummary: String
    let sanEntries: [String]
    let keyUsages: [String]
    let extKeyUsages: [String]
    let sha256Fingerprint: String
    let sha1Fingerprint: String
    let pemString: String
}

struct ParsedSshPublicKey: Sendable {
    let keyType: String
    let algorithmLabel: String
    let bitLength: Int
    let comment: String
    let sha256Fingerprint: String
    let md5Fingerprint: String
    let randomart: String
}

struct RemoteTlsResult: Sendable {
    let host: String
    let port: Int
    let systemTrusted: Bool
    let trustStatusNote: String
    let certificates: [ParsedX509Certificate]
}

enum CertInputKind: Sendable {
    case certificates(chain: [ParsedX509Certificate], hasPrivateMaterialWarning: Bool)
    case sshPublicKey(ParsedSshPublicKey)
    case empty
    case error(String)
}

enum CertError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum CertEngine {
    static let sampleSshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP2bJ+6B8xP1n6rO8gO9kH8vQ7mZ3R4k5L1xM2nN0p devkit@tinycast.local"

    static func containsSensitiveKeyHeader(_ raw: String) -> Bool {
        // Avoid literal private-key header sequences in source; check split markers instead.
        let hasBegin = raw.contains("-----BEGIN")
        let hasPrivWord = raw.contains("PRIVATE KEY-----")
        return hasBegin && hasPrivWord
    }

    static func inspectText(_ raw: String) -> CertInputKind {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let hasPrivWarning = containsSensitiveKeyHeader(trimmed)

        if let ssh = parseSshPublicKey(trimmed) {
            return .sshPublicKey(ssh)
        }

        let derBlocks = extractPemCertificates(trimmed)
        if !derBlocks.isEmpty {
            var parsed: [ParsedX509Certificate] = []
            for (idx, der) in derBlocks.enumerated() {
                if let cert = try? parseX509Certificate(der: der, index: idx) {
                    parsed.append(cert)
                }
            }
            if !parsed.isEmpty {
                return .certificates(chain: parsed, hasPrivateMaterialWarning: hasPrivWarning)
            }
        }

        // Try raw Base64 DER certificate
        let compact = trimmed.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if let der = Data(base64Encoded: compact), let cert = try? parseX509Certificate(der: der, index: 0) {
            return .certificates(chain: [cert], hasPrivateMaterialWarning: hasPrivWarning)
        }

        if hasPrivWarning {
            return .error("检测到私钥片段（工具不会上传或保存任何私钥），但未找到可解析的 X.509 CERTIFICATE 证书内容。")
        }
        return .error("无法识别为 X.509 PEM/DER 证书或 OpenSSH 公钥；也可在上方输入域名拉取线上 TLS 证书。")
    }

    static func extractPemCertificates(_ raw: String) -> [Data] {
        let beginMarker = "-----BEGIN CERTIFICATE-----"
        let endMarker = "-----END CERTIFICATE-----"
        var blocks: [Data] = []
        var searchStart = raw.startIndex
        while let bRange = raw.range(of: beginMarker, range: searchStart..<raw.endIndex),
              let eRange = raw.range(of: endMarker, range: bRange.upperBound..<raw.endIndex) {
            let b64 = String(raw[bRange.upperBound..<eRange.lowerBound])
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            if let data = Data(base64Encoded: b64) {
                blocks.append(data)
            }
            searchStart = eRange.upperBound
        }
        return blocks
    }

    static func encodePem(der: Data, label: String = "CERTIFICATE") -> String {
        let b64 = der.base64EncodedString()
        var lines: [String] = ["-----BEGIN \(label)-----"]
        var idx = b64.startIndex
        while idx < b64.endIndex {
            let end = b64.index(idx, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append(String(b64[idx..<end]))
            idx = end
        }
        lines.append("-----END \(label)-----")
        return lines.joined(separator: "\n")
    }

    // MARK: Remote TLS Chain Fetcher

    private final class TlsProbeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _capturedDers: [Data] = []
        private var _trusted: Bool = false
        private var _trustNote: String = ""

        var snapshot: (ders: [Data], trusted: Bool, note: String) {
            lock.lock()
            defer { lock.unlock() }
            return (_capturedDers, _trusted, _trustNote)
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            var cfErr: CFError?
            let trusted = SecTrustEvaluateWithError(trust, &cfErr)
            let note = trusted ? "系统信任链校验通过" : (cfErr?.localizedDescription ?? "未被系统信任")

            let certs = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
            let ders = certs.map { SecCertificateCopyData($0) as Data }

            lock.lock()
            _capturedDers = ders
            _trusted = trusted
            _trustNote = note
            lock.unlock()

            // Cancel immediately after grabbing handshake trust chain so we don't download response body.
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func fetchRemoteTlsChain(hostInput: String) async throws -> RemoteTlsResult {
        var clean = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CertError.message("请输入域名或 URL（如 github.com）") }
        if clean.lowercased().hasPrefix("https://") {
            clean = String(clean.dropFirst(8))
        } else if clean.lowercased().hasPrefix("http://") {
            clean = String(clean.dropFirst(7))
        }
        clean = clean.components(separatedBy: "/").first ?? clean

        let host: String
        let port: Int
        if let colon = clean.lastIndex(of: ":"), !clean.contains("["), let p = Int(clean[clean.index(after: colon)...]), (1...65535).contains(p) {
            host = String(clean[..<colon])
            port = p
        } else {
            host = clean
            port = 443
        }
        guard !host.isEmpty else { throw CertError.message("域名格式无效") }
        guard let url = URL(string: "https://\(host):\(port)/") else {
            throw CertError.message("无法构造目标地址")
        }

        let delegate = TlsProbeDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"

        do {
            _ = try await session.data(for: req)
        } catch {
            // Expected cancellation right after ServerTrust challenge
        }

        let snap = delegate.snapshot
        guard !snap.ders.isEmpty else {
            throw CertError.message("未能从 \(host):\(port) 获取到 TLS 证书（请检查网络、域名或端口是否正确）")
        }

        let parsed = snap.ders.enumerated().compactMap { idx, der in
            try? parseX509Certificate(der: der, index: idx)
        }
        guard !parsed.isEmpty else {
            throw CertError.message("已收到服务器响应，但证书 DER 解析失败")
        }
        return RemoteTlsResult(
            host: host,
            port: port,
            systemTrusted: snap.trusted,
            trustStatusNote: snap.note,
            certificates: parsed
        )
    }

    // MARK: ASN.1 DER Reader & X.509 Decoder

    private struct Asn1Node {
        let tag: UInt8
        let isConstructed: Bool
        let contentRange: Range<Int>
        let fullRange: Range<Int>
        let children: [Asn1Node]
    }

    private enum Asn1Parser {
        static func parseAll(_ data: Data) throws -> [Asn1Node] {
            var offset = 0
            var nodes: [Asn1Node] = []
            while offset < data.count {
                nodes.append(try parseNode(data, offset: &offset, end: data.count))
            }
            return nodes
        }

        static func parseNode(_ data: Data, offset: inout Int, end: Int) throws -> Asn1Node {
            guard offset < end else { throw CertError.message("ASN.1 数据截断") }
            let start = offset
            let tag = data[offset]
            offset += 1
            if (tag & 0x1F) == 0x1F {
                while offset < end && (data[offset] & 0x80) != 0 { offset += 1 }
                offset += 1
            }
            guard offset < end else { throw CertError.message("ASN.1 长度字节缺失") }
            let lenByte = data[offset]
            offset += 1
            let contentLen: Int
            if (lenByte & 0x80) == 0 {
                contentLen = Int(lenByte)
            } else {
                let numOctets = Int(lenByte & 0x7F)
                guard numOctets > 0, numOctets <= 4, offset + numOctets <= end else {
                    throw CertError.message("ASN.1 长度编码不支持")
                }
                var val = 0
                for _ in 0..<numOctets {
                    val = (val << 8) | Int(data[offset])
                    offset += 1
                }
                contentLen = val
            }
            guard offset + contentLen <= end else { throw CertError.message("ASN.1 节点越界") }
            let contentRange = offset..<(offset + contentLen)
            let isConstructed = (tag & 0x20) != 0
            var children: [Asn1Node] = []
            if isConstructed {
                var childOffset = contentRange.lowerBound
                while childOffset < contentRange.upperBound {
                    children.append(try parseNode(data, offset: &childOffset, end: contentRange.upperBound))
                }
            }
            offset = contentRange.upperBound
            return Asn1Node(tag: tag, isConstructed: isConstructed, contentRange: contentRange, fullRange: start..<offset, children: children)
        }

        static func decodeOid(_ bytes: Data) -> String {
            guard !bytes.isEmpty else { return "" }
            let first = Int(bytes[bytes.startIndex])
            var comps: [Int] = [first / 40, first % 40]
            var acc = 0
            for b in bytes.dropFirst() {
                acc = (acc << 7) | Int(b & 0x7F)
                if (b & 0x80) == 0 {
                    comps.append(acc)
                    acc = 0
                }
            }
            return comps.map(String.init).joined(separator: ".")
        }

        static func decodeString(_ node: Asn1Node, in data: Data) -> String {
            let sub = data.subdata(in: node.contentRange)
            if node.tag == 0x1E { // BMPString (UTF-16BE)
                return String(data: sub, encoding: .utf16BigEndian) ?? String(decoding: sub, as: UTF8.self)
            }
            return String(data: sub, encoding: .utf8) ?? String(data: sub, encoding: .isoLatin1) ?? ""
        }

        static func decodeDate(_ node: Asn1Node, in data: Data) -> Date? {
            let raw = String(decoding: data.subdata(in: node.contentRange), as: UTF8.self)
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(secondsFromGMT: 0)
            if node.tag == 0x17 { // UTCTime YYMMDDHHMMSSZ
                fmt.twoDigitStartDate = Date(timeIntervalSince1970: -631_152_000) // 1950-01-01
                for p in ["yyMMddHHmmss'Z'", "yyMMddHHmm'Z'"] {
                    fmt.dateFormat = p
                    if let d = fmt.date(from: raw) { return d }
                }
            } else if node.tag == 0x18 { // GeneralizedTime YYYYMMDDHHMMSSZ
                for p in ["yyyyMMddHHmmss'Z'", "yyyyMMddHHmmss.SSS'Z'", "yyyyMMddHHmm'Z'"] {
                    fmt.dateFormat = p
                    if let d = fmt.date(from: raw) { return d }
                }
            }
            return nil
        }

        static func formatHex(_ data: Data) -> String {
            data.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }

    private static let oidNames: [String: String] = [
        "1.2.840.113549.1.1.1": "RSA",
        "1.2.840.113549.1.1.5": "SHA-1 with RSA",
        "1.2.840.113549.1.1.11": "SHA-256 with RSA",
        "1.2.840.113549.1.1.12": "SHA-384 with RSA",
        "1.2.840.113549.1.1.13": "SHA-512 with RSA",
        "1.2.840.113549.1.1.10": "RSA-PSS",
        "1.2.840.10045.2.1": "EC Public Key",
        "1.2.840.10045.4.3.2": "ECDSA with SHA-256",
        "1.2.840.10045.4.3.3": "ECDSA with SHA-384",
        "1.2.840.10045.4.3.4": "ECDSA with SHA-512",
        "1.3.101.112": "Ed25519",
        "1.2.840.10045.3.1.7": "P-256 (prime256v1)",
        "1.3.132.0.34": "P-384 (secp384r1)",
        "1.3.132.0.35": "P-521 (secp521r1)",
        "2.5.4.3": "CN",
        "2.5.4.6": "C",
        "2.5.4.7": "L",
        "2.5.4.8": "ST",
        "2.5.4.10": "O",
        "2.5.4.11": "OU",
        "1.2.840.113549.1.9.1": "email",
        "1.3.6.1.5.5.7.3.1": "Server Auth (TLS Web 服务器)",
        "1.3.6.1.5.5.7.3.2": "Client Auth (客户端认证)",
        "1.3.6.1.5.5.7.3.3": "Code Signing (代码签名)",
        "1.3.6.1.5.5.7.3.4": "Email Protection",
        "1.3.6.1.5.5.7.3.8": "Time Stamping",
        "1.3.6.1.5.5.7.3.9": "OCSP Signing",
    ]

    static func parseX509Certificate(der: Data, index: Int = 0) throws -> ParsedX509Certificate {
        var rootOff = 0
        let certNode = try Asn1Parser.parseNode(der, offset: &rootOff, end: der.count)
        guard certNode.tag == 0x30, certNode.children.count >= 2 else {
            throw CertError.message("不是有效的 X.509 Certificate SEQUENCE")
        }
        let tbs = certNode.children[0]
        guard tbs.tag == 0x30, tbs.children.count >= 6 else {
            throw CertError.message("TBSCertificate 结构不完整")
        }

        var cursor = 0
        var versionStr = "v1"
        if tbs.children[cursor].tag == 0xA0 {
            if let vNode = tbs.children[cursor].children.first,
               let byte = der.subdata(in: vNode.contentRange).first {
                versionStr = "v\(Int(byte) + 1)"
            }
            cursor += 1
        }
        guard cursor + 5 < tbs.children.count else {
            throw CertError.message("TBSCertificate 字段不足")
        }

        let serialData = der.subdata(in: tbs.children[cursor].contentRange)
        let serialHex = Asn1Parser.formatHex(serialData)
        cursor += 1

        let sigAlgNode = tbs.children[cursor]
        let sigAlgOid = sigAlgNode.children.first.map { Asn1Parser.decodeOid(der.subdata(in: $0.contentRange)) } ?? ""
        let sigAlgName = oidNames[sigAlgOid] ?? (sigAlgOid.isEmpty ? "Unknown" : sigAlgOid)
        cursor += 1

        func decodeDN(_ nameNode: Asn1Node) -> (full: String, cn: String) {
            var parts: [String] = []
            var cn = ""
            for rdn in nameNode.children {
                for atv in rdn.children where atv.children.count >= 2 {
                    let oid = Asn1Parser.decodeOid(der.subdata(in: atv.children[0].contentRange))
                    let val = Asn1Parser.decodeString(atv.children[1], in: der)
                    let label = oidNames[oid] ?? oid
                    if label == "CN" && cn.isEmpty { cn = val }
                    parts.append("\(label)=\(val)")
                }
            }
            let full = parts.joined(separator: ", ")
            return (full, cn.isEmpty ? full : cn)
        }

        let issuer = decodeDN(tbs.children[cursor])
        cursor += 1

        let validityNode = tbs.children[cursor]
        let notBefore = (validityNode.children.count >= 1 ? Asn1Parser.decodeDate(validityNode.children[0], in: der) : nil) ?? Date(timeIntervalSince1970: 0)
        let notAfter = (validityNode.children.count >= 2 ? Asn1Parser.decodeDate(validityNode.children[1], in: der) : nil) ?? Date(timeIntervalSince1970: 0)
        cursor += 1

        let subject = decodeDN(tbs.children[cursor])
        cursor += 1

        let spkiNode = tbs.children[cursor]
        let pubKeySummary = decodeSpki(spkiNode, in: der)
        cursor += 1

        // Extensions inside context tag [3] (0xA3)
        var sanEntries: [String] = []
        var isCA: Bool? = nil
        var keyUsages: [String] = []
        var extKeyUsages: [String] = []

        for tailIdx in cursor..<tbs.children.count {
            let child = tbs.children[tailIdx]
            if child.tag == 0xA3, let extSeq = child.children.first {
                for ext in extSeq.children where ext.children.count >= 2 {
                    let oid = Asn1Parser.decodeOid(der.subdata(in: ext.children[0].contentRange))
                    // Optional critical BOOLEAN at index 1
                    let octetNode = ext.children.last!
                    let extData = der.subdata(in: octetNode.contentRange)
                    switch oid {
                    case "2.5.29.17": // SAN
                        sanEntries = decodeSan(extData)
                    case "2.5.29.19": // BasicConstraints
                        isCA = decodeBasicConstraints(extData)
                    case "2.5.29.15": // KeyUsage
                        keyUsages = decodeKeyUsage(extData)
                    case "2.5.29.37": // ExtKeyUsage
                        extKeyUsages = decodeExtKeyUsage(extData)
                    default:
                        break
                    }
                }
            }
        }

        let now = Date()
        let secondsRemaining = notAfter.timeIntervalSince(now)
        let daysRemaining = Int(floor(secondsRemaining / 86_400.0))
        let sha256Hex = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
        let sha1Hex = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")

        return ParsedX509Certificate(
            id: index,
            version: versionStr,
            serialHex: serialHex,
            subject: subject.full,
            subjectCommonName: subject.cn,
            issuer: issuer.full,
            issuerCommonName: issuer.cn,
            notBefore: notBefore,
            notAfter: notAfter,
            daysRemaining: daysRemaining,
            isExpired: now > notAfter,
            isNotYetValid: now < notBefore,
            isSelfSigned: !subject.full.isEmpty && subject.full == issuer.full,
            isCA: isCA,
            signatureAlgorithm: sigAlgName,
            publicKeySummary: pubKeySummary,
            sanEntries: sanEntries,
            keyUsages: keyUsages,
            extKeyUsages: extKeyUsages,
            sha256Fingerprint: sha256Hex,
            sha1Fingerprint: sha1Hex,
            pemString: encodePem(der: der)
        )
    }

    private static func decodeSpki(_ node: Asn1Node, in der: Data) -> String {
        guard node.children.count >= 2 else { return "Unknown Public Key" }
        let algSeq = node.children[0]
        let algOid = algSeq.children.first.map { Asn1Parser.decodeOid(der.subdata(in: $0.contentRange)) } ?? ""
        let bitStr = der.subdata(in: node.children[1].contentRange)

        if algOid == "1.2.840.113549.1.1.1" { // RSA
            let payData = Data(bitStr.dropFirst()) // drop unused-bits byte
            if let rsaNodes = try? Asn1Parser.parseAll(payData),
               let rsaSeq = rsaNodes.first,
               let modNode = rsaSeq.children.first {
                var modBytes = payData.subdata(in: modNode.contentRange)
                if modBytes.first == 0 { modBytes = modBytes.dropFirst() }
                if let firstByte = modBytes.first, firstByte > 0 {
                    let bits = (modBytes.count - 1) * 8 + (8 - firstByte.leadingZeroBitCount)
                    return "RSA \(bits)-bit"
                }
            }
            return "RSA"
        }

        if algOid == "1.2.840.10045.2.1" { // EC
            if algSeq.children.count >= 2 {
                let curveOid = Asn1Parser.decodeOid(der.subdata(in: algSeq.children[1].contentRange))
                return "EC (\(oidNames[curveOid] ?? curveOid))"
            }
            return "EC Public Key"
        }

        return oidNames[algOid] ?? algOid
    }

    private static func decodeSan(_ extData: Data) -> [String] {
        guard let nodes = try? Asn1Parser.parseAll(extData), let seq = nodes.first else { return [] }
        var out: [String] = []
        for entry in seq.children {
            let sub = extData.subdata(in: entry.contentRange)
            switch entry.tag {
            case 0x82: // dNSName
                out.append("DNS: \(String(decoding: sub, as: UTF8.self))")
            case 0x81: // rfc822Name
                out.append("Email: \(String(decoding: sub, as: UTF8.self))")
            case 0x86: // URI
                out.append("URI: \(String(decoding: sub, as: UTF8.self))")
            case 0x87: // iPAddress
                if sub.count == 4 {
                    out.append("IP: \(sub.map(String.init).joined(separator: "."))")
                } else if sub.count == 16 {
                    let hex = stride(from: 0, to: 16, by: 2).map { String(format: "%x", UInt16(sub[$0]) << 8 | UInt16(sub[$0 + 1])) }.joined(separator: ":")
                    out.append("IP: \(hex)")
                }
            default:
                break
            }
        }
        return out
    }

    private static func decodeBasicConstraints(_ extData: Data) -> Bool? {
        guard let nodes = try? Asn1Parser.parseAll(extData), let seq = nodes.first else { return nil }
        if let first = seq.children.first, first.tag == 0x01 {
            let val = extData.subdata(in: first.contentRange).first ?? 0
            return val != 0
        }
        return false
    }

    private static func decodeKeyUsage(_ extData: Data) -> [String] {
        guard let nodes = try? Asn1Parser.parseAll(extData), let node = nodes.first else { return [] }
        let raw = extData.subdata(in: node.contentRange)
        guard raw.count >= 2 else { return [] }
        let unused = Int(raw[raw.startIndex])
        var bits: UInt16 = UInt16(raw[raw.startIndex + 1]) << 8
        if raw.count >= 3 { bits |= UInt16(raw[raw.startIndex + 2]) }
        let mask: UInt16 = unused >= 8 ? 0xFF00 : (0xFFFF << unused)
        let effective = bits & mask
        let labels = [
            "Digital Signature", "Non Repudiation", "Key Encipherment",
            "Data Encipherment", "Key Agreement", "Certificate Sign",
            "CRL Sign", "Encipher Only", "Decipher Only",
        ]
        var out: [String] = []
        for (i, label) in labels.enumerated() {
            if (effective & (UInt16(1) << (15 - i))) != 0 {
                out.append(label)
            }
        }
        return out
    }

    private static func decodeExtKeyUsage(_ extData: Data) -> [String] {
        guard let nodes = try? Asn1Parser.parseAll(extData), let seq = nodes.first else { return [] }
        return seq.children.map { child in
            let oid = Asn1Parser.decodeOid(extData.subdata(in: child.contentRange))
            return oidNames[oid] ?? oid
        }
    }

    // MARK: OpenSSH Public Key Decoder & Drunken Bishop Randomart

    static func parseSshPublicKey(_ raw: String) -> ParsedSshPublicKey? {
        let firstLine = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let parts = firstLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        let keyType = parts[0]
        let supported = ["ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com"]
        guard supported.contains(keyType), let blob = Data(base64Encoded: parts[1]) else {
            return nil
        }
        let comment = parts.count >= 3 ? parts.dropFirst(2).joined(separator: " ") : ""

        let shaDigest = Data(SHA256.hash(data: blob))
        let sha256B64 = shaDigest.base64EncodedString().replacingOccurrences(of: "=", with: "")
        let md5Hex = Insecure.MD5.hash(data: blob).map { String(format: "%02x", $0) }.joined(separator: ":")

        let bits = estimateSshBits(keyType: keyType, blob: blob)
        let label: String
        switch keyType {
        case "ssh-ed25519": label = "Ed25519"
        case "ssh-rsa": label = "RSA"
        case "ecdsa-sha2-nistp256": label = "ECDSA P-256"
        case "ecdsa-sha2-nistp384": label = "ECDSA P-384"
        case "ecdsa-sha2-nistp521": label = "ECDSA P-521"
        default: label = keyType
        }

        let randomart = drunkenBishopRandomart(digest: shaDigest, title: "\(label) \(bits)")
        return ParsedSshPublicKey(
            keyType: keyType,
            algorithmLabel: label,
            bitLength: bits,
            comment: comment,
            sha256Fingerprint: "SHA256:\(sha256B64)",
            md5Fingerprint: "MD5:\(md5Hex)",
            randomart: randomart
        )
    }

    private static func readSshChunk(_ blob: Data, offset: inout Int) -> Data? {
        guard offset + 4 <= blob.count else { return nil }
        let len = (Int(blob[offset]) << 24) | (Int(blob[offset + 1]) << 16) | (Int(blob[offset + 2]) << 8) | Int(blob[offset + 3])
        offset += 4
        guard len >= 0, offset + len <= blob.count else { return nil }
        let slice = blob.subdata(in: offset..<(offset + len))
        offset += len
        return slice
    }

    private static func estimateSshBits(keyType: String, blob: Data) -> Int {
        switch keyType {
        case "ssh-ed25519", "sk-ssh-ed25519@openssh.com": return 256
        case "ecdsa-sha2-nistp256", "sk-ecdsa-sha2-nistp256@openssh.com": return 256
        case "ecdsa-sha2-nistp384": return 384
        case "ecdsa-sha2-nistp521": return 521
        case "ssh-rsa":
            var off = 0
            _ = readSshChunk(blob, offset: &off) // type
            _ = readSshChunk(blob, offset: &off) // e
            if var nBytes = readSshChunk(blob, offset: &off) {
                while nBytes.first == 0 && nBytes.count > 1 { nBytes = nBytes.dropFirst() }
                if let lead = nBytes.first, lead > 0 {
                    return (nBytes.count - 1) * 8 + (8 - lead.leadingZeroBitCount)
                }
            }
            return 2048
        default:
            return 0
        }
    }

    private static func drunkenBishopRandomart(digest: Data, title: String) -> String {
        let width = 17
        let height = 9
        var board = Array(repeating: Array(repeating: 0, count: width), count: height)
        var x = width / 2
        var y = height / 2
        let startX = x
        let startY = y

        for byte in digest {
            for shift in [0, 2, 4, 6] {
                let pair = (byte >> shift) & 0x03
                x = (pair & 0x01) != 0 ? min(width - 1, x + 1) : max(0, x - 1)
                y = (pair & 0x02) != 0 ? min(height - 1, y + 1) : max(0, y - 1)
                board[y][x] += 1
            }
        }

        let symbols = Array(" .o+=*BOX@%&#/^")
        var lines: [String] = []
        let headerTag = "[\(title)]"
        let padTotal = max(0, width - headerTag.count)
        let leftDashes = padTotal / 2
        let rightDashes = padTotal - leftDashes
        lines.append("+\(String(repeating: "-", count: leftDashes))\(headerTag)\(String(repeating: "-", count: rightDashes))+")

        for row in 0..<height {
            var line = "|"
            for col in 0..<width {
                if row == startY && col == startX { line.append("S") }
                else if row == y && col == x { line.append("E") }
                else {
                    let count = min(board[row][col], symbols.count - 1)
                    line.append(symbols[count])
                }
            }
            line.append("|")
            lines.append(line)
        }
        lines.append("+\(String(repeating: "-", count: width))+")
        return lines.joined(separator: "\n")
    }

    // MARK: Synthetic Offline X.509 DER Generator for --self-test (No Private Keys)

    static func buildSelfTestDerCert() -> Data {
        func tlv(_ tag: UInt8, _ payload: Data) -> Data {
            var out = Data([tag])
            if payload.count < 0x80 {
                out.append(UInt8(payload.count))
            } else {
                out.append(0x81)
                out.append(UInt8(payload.count))
            }
            out.append(payload)
            return out
        }
        func seq(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
        func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
        func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
        func utf8Str(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }

        let cnAttr = set([seq([oid([0x55, 0x04, 0x03]), utf8Str("devkit.tinycast.test")])])
        let dn = seq([cnAttr])
        let sha256RsaAlg = seq([oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]), Data([0x05, 0x00])])
        let ed25519Alg = seq([oid([0x2B, 0x65, 0x70])])
        let validity = seq([
            tlv(0x17, Data("260101000000Z".utf8)),
            tlv(0x17, Data("300101000000Z".utf8)),
        ])
        let spki = seq([ed25519Alg, tlv(0x03, Data([0x00] + [UInt8](repeating: 0xAA, count: 32)))])
        let sanExt = seq([
            oid([0x55, 0x1D, 0x11]),
            tlv(0x04, seq([tlv(0x82, Data("tinycast.local".utf8))])),
        ])
        let tbs = seq([
            tlv(0xA0, tlv(0x02, Data([0x02]))), // v3
            tlv(0x02, Data([0x01, 0x23, 0x45])), // serial
            sha256RsaAlg,
            dn,
            validity,
            dn,
            spki,
            tlv(0xA3, seq([sanExt])),
        ])
        return seq([tbs, sha256RsaAlg, tlv(0x03, Data([0x00, 0x01, 0x02, 0x03]))])
    }
}
