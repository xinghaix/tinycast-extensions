import CommonCrypto
import CryptoKit
import Foundation
import zlib

enum HashInputEncoding: String, CaseIterable, Sendable {
    case utf8, hex, base64
    var title: String {
        switch self {
        case .utf8: return "UTF-8"
        case .hex: return "Hex"
        case .base64: return "Base64"
        }
    }
}

enum HashOutputEncoding: String, CaseIterable, Sendable {
    case hex, hexUpper = "HEX", base64, base64url, sri
    var title: String {
        switch self {
        case .hex: return "hex"
        case .hexUpper: return "HEX"
        case .base64: return "Base64"
        case .base64url: return "Base64URL"
        case .sri: return "SRI"
        }
    }
}

enum HashCategory: String, CaseIterable, Sendable {
    case standard, modern, checksum
    var title: String {
        switch self {
        case .standard: return "常用密码学 Hash (CryptoKit)"
        case .modern: return "现代 & 国密摘要 (SHA-3 / BLAKE3 / BLAKE2 / SM3)"
        case .checksum: return "快速校验码 & 非加密 Hash"
        }
    }
}

struct HashResult: Identifiable, Sendable {
    let id: String
    let name: String
    let category: HashCategory
    let bits: Int
    let digest: String
    let hexLower: String
    let hexUpper: String
    let base64: String
    let base64url: String
    let sri: String
    let isHmac: Bool

    func matchesExpected(_ raw: String) -> Bool {
        let norm = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !norm.isEmpty else { return false }
        let lower = norm.lowercased()
        return hexLower == lower || base64 == norm || base64url == norm || sri == norm
    }
}

enum HashEngineError: LocalizedError {
    case invalidHex
    case invalidBase64
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidHex: return "无效的 Hex 字节输入（长度须为偶数且仅含 0-9a-f）"
        case .invalidBase64: return "无效的 Base64 输入"
        case .unreadableFile(let path): return "无法读取文件: \(path)"
        }
    }
}

enum HashEngine {
    static func decodeInput(_ text: String, encoding: HashInputEncoding) throws -> Data {
        switch encoding {
        case .utf8:
            return Data(text.utf8)
        case .hex:
            var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
            let cleaned = s.replacingOccurrences(of: #"[\s:-]"#, with: "", options: .regularExpression)
            guard cleaned.count % 2 == 0, cleaned.allSatisfy({ $0.isHexDigit }) else {
                throw HashEngineError.invalidHex
            }
            var data = Data(capacity: cleaned.count / 2)
            var idx = cleaned.startIndex
            while idx < cleaned.endIndex {
                let next = cleaned.index(idx, offsetBy: 2)
                guard let b = UInt8(cleaned[idx..<next], radix: 16) else { throw HashEngineError.invalidHex }
                data.append(b)
                idx = next
            }
            return data
        case .base64:
            let cleaned = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let padded = cleaned.padding(toLength: ((cleaned.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let data = Data(base64Encoded: padded) else {
                throw HashEngineError.invalidBase64
            }
            return data
        }
    }

    static func computeAll(
        data: Data,
        outputEncoding: HashOutputEncoding = .hex,
        hmacKey: Data? = nil,
        includeNonCrypto: Bool = true
    ) -> [HashResult] {
        let isHmac = hmacKey.map { !$0.isEmpty } ?? false
        let key = isHmac ? hmacKey : nil
        var results: [HashResult] = []

        func append(_ id: String, _ name: String, _ category: HashCategory, _ bits: Int, _ raw: Data) {
            results.append(formatResult(id: id, name: isHmac ? "HMAC-\(name)" : name, category: category, bits: bits, bytes: raw, outputEncoding: outputEncoding, isHmac: isHmac))
        }

        if let key {
            let sym = SymmetricKey(data: key)
            append("md5", "MD5", .standard, 128, Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: sym)))
            append("sha1", "SHA-1", .standard, 160, Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: sym)))
            append("sha224", "SHA-224", .standard, 224, commonHmac(alg: CCHmacAlgorithm(kCCHmacAlgSHA224), len: Int(CC_SHA224_DIGEST_LENGTH), key: key, data: data))
            append("sha256", "SHA-256", .standard, 256, Data(HMAC<SHA256>.authenticationCode(for: data, using: sym)))
            append("sha384", "SHA-384", .standard, 384, Data(HMAC<SHA384>.authenticationCode(for: data, using: sym)))
            append("sha512", "SHA-512", .standard, 512, Data(HMAC<SHA512>.authenticationCode(for: data, using: sym)))

            append("sm3", "SM3 (国密)", .modern, 256, genericHmac(blockSize: 64, key: key, data: data, hashFn: sm3))
            append("blake3", "BLAKE3 (256-bit)", .modern, 256, genericHmac(blockSize: 64, key: key, data: data, hashFn: blake3))
            append("sha3-224", "SHA3-224", .modern, 224, genericHmac(blockSize: 144, key: key, data: data, hashFn: { keccakSponge($0, rateBytes: 144, suffix: 0x06, outLen: 28) }))
            append("sha3-256", "SHA3-256", .modern, 256, genericHmac(blockSize: 136, key: key, data: data, hashFn: { keccakSponge($0, rateBytes: 136, suffix: 0x06, outLen: 32) }))
            append("sha3-384", "SHA3-384", .modern, 384, genericHmac(blockSize: 104, key: key, data: data, hashFn: { keccakSponge($0, rateBytes: 104, suffix: 0x06, outLen: 48) }))
            append("sha3-512", "SHA3-512", .modern, 512, genericHmac(blockSize: 72, key: key, data: data, hashFn: { keccakSponge($0, rateBytes: 72, suffix: 0x06, outLen: 64) }))
            append("keccak-256", "Keccak-256 (Ethereum)", .modern, 256, genericHmac(blockSize: 136, key: key, data: data, hashFn: { keccakSponge($0, rateBytes: 136, suffix: 0x01, outLen: 32) }))
            append("blake2b-256", "BLAKE2b-256", .modern, 256, blake2b(data, key: key, outLen: 32))
            append("blake2b-512", "BLAKE2b-512", .modern, 512, blake2b(data, key: key, outLen: 64))
            append("blake2s-256", "BLAKE2s-256", .modern, 256, blake2s(data, key: key, outLen: 32))
            append("ripemd160", "RIPEMD-160", .modern, 160, genericHmac(blockSize: 64, key: key, data: data, hashFn: ripemd160))
        } else {
            append("md5", "MD5", .standard, 128, Data(Insecure.MD5.hash(data: data)))
            append("sha1", "SHA-1", .standard, 160, Data(Insecure.SHA1.hash(data: data)))
            append("sha224", "SHA-224", .standard, 224, sha224(data))
            append("sha256", "SHA-256", .standard, 256, Data(SHA256.hash(data: data)))
            append("sha384", "SHA-384", .standard, 384, Data(SHA384.hash(data: data)))
            append("sha512", "SHA-512", .standard, 512, Data(SHA512.hash(data: data)))

            append("sm3", "SM3 (国密)", .modern, 256, sm3(data))
            append("blake3", "BLAKE3 (256-bit)", .modern, 256, blake3(data))
            append("sha3-224", "SHA3-224", .modern, 224, keccakSponge(data, rateBytes: 144, suffix: 0x06, outLen: 28))
            append("sha3-256", "SHA3-256", .modern, 256, keccakSponge(data, rateBytes: 136, suffix: 0x06, outLen: 32))
            append("sha3-384", "SHA3-384", .modern, 384, keccakSponge(data, rateBytes: 104, suffix: 0x06, outLen: 48))
            append("sha3-512", "SHA3-512", .modern, 512, keccakSponge(data, rateBytes: 72, suffix: 0x06, outLen: 64))
            append("keccak-256", "Keccak-256 (Ethereum)", .modern, 256, keccakSponge(data, rateBytes: 136, suffix: 0x01, outLen: 32))
            append("blake2b-256", "BLAKE2b-256", .modern, 256, blake2b(data, outLen: 32))
            append("blake2b-512", "BLAKE2b-512", .modern, 512, blake2b(data, outLen: 64))
            append("blake2s-256", "BLAKE2s-256", .modern, 256, blake2s(data, outLen: 32))
            append("ripemd160", "RIPEMD-160", .modern, 160, ripemd160(data))

            if includeNonCrypto {
                append("crc32", "CRC32 (IEEE 802.3)", .checksum, 32, crc32Data(data))
                append("crc32c", "CRC32C (Castagnoli)", .checksum, 32, crc32cData(data))
                append("adler32", "Adler-32", .checksum, 32, adler32Data(data))
                append("fnv1a-32", "FNV-1a 32-bit", .checksum, 32, fnv1a32(data))
                append("fnv1a-64", "FNV-1a 64-bit", .checksum, 64, fnv1a64(data))
                append("murmur3-32", "MurmurHash3 (x86 32)", .checksum, 32, murmur3_32(data))
            }
        }
        return results
    }

    static func hashFileStreaming(
        url: URL,
        outputEncoding: HashOutputEncoding = .hex,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> (size: UInt64, results: [HashResult]) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw HashEngineError.unreadableFile(url.path)
        }
        defer { try? handle.close() }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let totalSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0

        var md5Hasher = Insecure.MD5()
        var sha1Hasher = Insecure.SHA1()
        var sha256Hasher = SHA256()
        var sha384Hasher = SHA384()
        var sha512Hasher = SHA512()
        var sm3Hasher = SM3State()
        var crcVal: uLong = zlib.crc32(0, nil, 0)
        var adlerVal: uLong = zlib.adler32(0, nil, 0)

        let chunkSize = 1024 * 1024
        var readBytes: UInt64 = 0

        while true {
            var eof = false
            autoreleasepool {
                let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
                if chunk.isEmpty {
                    eof = true
                    return
                }
                md5Hasher.update(data: chunk)
                sha1Hasher.update(data: chunk)
                sha256Hasher.update(data: chunk)
                sha384Hasher.update(data: chunk)
                sha512Hasher.update(data: chunk)
                sm3Hasher.update(chunk)
                chunk.withUnsafeBytes { ptr in
                    if let base = ptr.bindMemory(to: Bytef.self).baseAddress {
                        crcVal = zlib.crc32(crcVal, base, uInt(chunk.count))
                        adlerVal = zlib.adler32(adlerVal, base, uInt(chunk.count))
                    }
                }
                readBytes += UInt64(chunk.count)
            }
            if totalSize > 0 {
                onProgress?(min(1.0, Double(readBytes) / Double(totalSize)))
            }
            if eof { break }
        }
        onProgress?(1.0)

        let crcData = withUnsafeBytes(of: UInt32(truncatingIfNeeded: crcVal).bigEndian) { Data($0) }
        let adlerData = withUnsafeBytes(of: UInt32(truncatingIfNeeded: adlerVal).bigEndian) { Data($0) }

        let list = [
            formatResult(id: "md5", name: "MD5", category: .standard, bits: 128, bytes: Data(md5Hasher.finalize()), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "sha1", name: "SHA-1", category: .standard, bits: 160, bytes: Data(sha1Hasher.finalize()), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "sha256", name: "SHA-256", category: .standard, bits: 256, bytes: Data(sha256Hasher.finalize()), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "sha384", name: "SHA-384", category: .standard, bits: 384, bytes: Data(sha384Hasher.finalize()), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "sha512", name: "SHA-512", category: .standard, bits: 512, bytes: Data(sha512Hasher.finalize()), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "sm3", name: "SM3 (国密)", category: .modern, bits: 256, bytes: sm3Hasher.finalize(), outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "crc32", name: "CRC32 (IEEE 802.3)", category: .checksum, bits: 32, bytes: crcData, outputEncoding: outputEncoding, isHmac: false),
            formatResult(id: "adler32", name: "Adler-32", category: .checksum, bits: 32, bytes: adlerData, outputEncoding: outputEncoding, isHmac: false),
        ]
        return (totalSize, list)
    }

    private static func formatResult(
        id: String, name: String, category: HashCategory, bits: Int,
        bytes: Data, outputEncoding: HashOutputEncoding, isHmac: Bool
    ) -> HashResult {
        let hexLower = bytes.map { String(format: "%02x", $0) }.joined()
        let hexUpper = hexLower.uppercased()
        let b64 = bytes.base64EncodedString()
        let b64url = b64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let sri = "\(id.replacingOccurrences(of: "-", with: ""))-\(b64)"
        let digest: String
        switch outputEncoding {
        case .hex: digest = hexLower
        case .hexUpper: digest = hexUpper
        case .base64: digest = b64
        case .base64url: digest = b64url
        case .sri: digest = sri
        }
        return HashResult(
            id: id, name: name, category: category, bits: bits,
            digest: digest, hexLower: hexLower, hexUpper: hexUpper,
            base64: b64, base64url: b64url, sri: sri, isHmac: isHmac
        )
    }

    // MARK: - Standard CommonCrypto

    private static func sha224(_ data: Data) -> Data {
        var out = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA224(ptr.baseAddress, CC_LONG(data.count), &out)
        }
        return Data(out)
    }

    private static func commonHmac(alg: CCHmacAlgorithm, len: Int, key: Data, data: Data) -> Data {
        var out = [UInt8](repeating: 0, count: len)
        key.withUnsafeBytes { kPtr in
            data.withUnsafeBytes { dPtr in
                CCHmac(alg, kPtr.baseAddress, key.count, dPtr.baseAddress, data.count, &out)
            }
        }
        return Data(out)
    }

    private static func genericHmac(blockSize: Int, key: Data, data: Data, hashFn: (Data) -> Data) -> Data {
        let normKey = key.count > blockSize ? hashFn(key) : key
        var kPad = [UInt8](repeating: 0, count: blockSize)
        normKey.copyBytes(to: &kPad, count: min(blockSize, normKey.count))

        var iPad = Data(capacity: blockSize + data.count)
        var oPad = Data(capacity: blockSize + 64)
        for i in 0..<blockSize {
            iPad.append(kPad[i] ^ 0x36)
            oPad.append(kPad[i] ^ 0x5c)
        }
        iPad.append(data)
        oPad.append(hashFn(iPad))
        return hashFn(oPad)
    }

    // MARK: - SM3 (GM/T 0004-2012)

    struct SM3State {
        private var V: [UInt32] = [
            0x7380_166f, 0x4914_b2b9, 0x1724_42d7, 0xda8a_0600,
            0xa96f_30bc, 0x1631_38aa, 0xe38d_ee4d, 0xb0fb_0e4e,
        ]
        private var buffer = [UInt8]()
        private var totalBytes: UInt64 = 0

        mutating func update(_ data: Data) {
            totalBytes += UInt64(data.count)
            buffer.append(contentsOf: data)
            var offset = 0
            while offset + 64 <= buffer.count {
                compressBlock(buffer[offset..<(offset + 64)])
                offset += 64
            }
            if offset > 0 { buffer.removeFirst(offset) }
        }

        mutating func finalize() -> Data {
            var tail = buffer
            tail.append(0x80)
            while (tail.count + 8) % 64 != 0 { tail.append(0) }
            let bitLen = totalBytes &* 8
            for shift in stride(from: 56, through: 0, by: -8) {
                tail.append(UInt8(truncatingIfNeeded: bitLen >> shift))
            }
            var offset = 0
            while offset < tail.count {
                compressBlock(tail[offset..<(offset + 64)])
                offset += 64
            }
            var out = Data(capacity: 32)
            for word in V {
                var be = word.bigEndian
                withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
            }
            return out
        }

        private mutating func compressBlock(_ block: ArraySlice<UInt8>) {
            var W = [UInt32](repeating: 0, count: 68)
            var W1 = [UInt32](repeating: 0, count: 64)
            let base = block.startIndex
            for j in 0..<16 {
                let i = base + j * 4
                W[j] = (UInt32(block[i]) << 24) | (UInt32(block[i + 1]) << 16) | (UInt32(block[i + 2]) << 8) | UInt32(block[i + 3])
            }
            for j in 16..<68 {
                let x = W[j - 16] ^ W[j - 9] ^ rotl(W[j - 3], 15)
                let p1 = x ^ rotl(x, 15) ^ rotl(x, 23)
                W[j] = p1 ^ rotl(W[j - 13], 7) ^ W[j - 6]
            }
            for j in 0..<64 { W1[j] = W[j] ^ W[j + 4] }

            var A = V[0], B = V[1], C = V[2], D = V[3]
            var E = V[4], F = V[5], G = V[6], H = V[7]

            for j in 0..<64 {
                let Tj: UInt32 = j < 16 ? 0x79cc_4519 : 0x7a87_9d8a
                let ss1 = rotl(rotl(A, 12) &+ E &+ rotl(Tj, j), 7)
                let ss2 = ss1 ^ rotl(A, 12)
                let ff: UInt32 = j < 16 ? (A ^ B ^ C) : ((A & B) | (A & C) | (B & C))
                let gg: UInt32 = j < 16 ? (E ^ F ^ G) : ((E & F) | (~E & G))
                let tt1 = ff &+ D &+ ss2 &+ W1[j]
                let tt2 = gg &+ H &+ ss1 &+ W[j]
                D = C
                C = rotl(B, 9)
                B = A
                A = tt1
                H = G
                G = rotl(F, 19)
                F = E
                E = tt2 ^ rotl(tt2, 9) ^ rotl(tt2, 17)
            }
            V[0] ^= A; V[1] ^= B; V[2] ^= C; V[3] ^= D
            V[4] ^= E; V[5] ^= F; V[6] ^= G; V[7] ^= H
        }

        private func rotl(_ x: UInt32, _ n: Int) -> UInt32 {
            let k = UInt32(n & 31)
            return k == 0 ? x : (x << k) | (x >> (32 - k))
        }
    }

    static func sm3(_ data: Data) -> Data {
        var s = SM3State()
        s.update(data)
        return s.finalize()
    }

    // MARK: - Keccak-f[1600] (SHA-3 & Keccak-256)

    private static let keccakRoundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808a, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808b, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008a, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000a,
        0x0000_0000_8000_808b, 0x8000_0000_0000_008b, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800a, 0x8000_0000_8000_000a,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let keccakRotOffsets: [Int] = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14,
    ]

    static func keccakSponge(_ data: Data, rateBytes: Int, suffix: UInt8, outLen: Int) -> Data {
        var padded = Array(data)
        padded.append(suffix)
        while padded.count % rateBytes != 0 { padded.append(0) }
        padded[padded.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        let rateWords = rateBytes / 8
        for blockStart in stride(from: 0, to: padded.count, by: rateBytes) {
            for w in 0..<rateWords {
                let off = blockStart + w * 8
                var lane: UInt64 = 0
                for b in 0..<8 { lane |= UInt64(padded[off + b]) << (b * 8) }
                state[w] ^= lane
            }
            keccakF1600(&state)
        }

        var out = Data(capacity: outLen)
        while out.count < outLen {
            for w in 0..<rateWords where out.count < outLen {
                var lane = state[w].littleEndian
                withUnsafeBytes(of: &lane) { ptr in
                    let take = min(8, outLen - out.count)
                    out.append(contentsOf: ptr.prefix(take))
                }
            }
            if out.count < outLen { keccakF1600(&state) }
        }
        return out
    }

    private static func keccakF1600(_ a: inout [UInt64]) {
        var b = [UInt64](repeating: 0, count: 25)
        var c = [UInt64](repeating: 0, count: 5)
        var d = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            for x in 0..<5 { d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1) }
            for i in 0..<25 { a[i] ^= d[i % 5] }
            for y in 0..<5 {
                for x in 0..<5 {
                    let idx = x + 5 * y
                    let newX = y
                    let newY = (2 * x + 3 * y) % 5
                    b[newX + 5 * newY] = rotl64(a[idx], keccakRotOffsets[idx])
                }
            }
            for y in 0..<5 {
                let row = y * 5
                for x in 0..<5 {
                    a[row + x] = b[row + x] ^ ((~b[row + (x + 1) % 5]) & b[row + (x + 2) % 5])
                }
            }
            a[0] ^= keccakRoundConstants[round]
        }
    }

    // MARK: - BLAKE2b & BLAKE2s (RFC 7693)

    private static let blake2bIV: [UInt64] = [
        0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b, 0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
        0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f, 0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179,
    ]
    private static let blake2sIV: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
        0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    private static let blake2Sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    ]

    static func blake2b(_ data: Data, key: Data? = nil, outLen: Int = 32) -> Data {
        let keyBytes = Array((key ?? Data()).prefix(64))
        var h = blake2bIV
        h[0] ^= 0x0101_0000 ^ UInt64(keyBytes.count << 8) ^ UInt64(outLen)

        var stream = [UInt8]()
        if !keyBytes.isEmpty {
            stream.append(contentsOf: keyBytes)
            stream.append(contentsOf: repeatElement(0, count: 128 - keyBytes.count))
        }
        stream.append(contentsOf: data)
        if stream.isEmpty { stream = [UInt8](repeating: 0, count: 128) }
        else {
            let rem = stream.count % 128
            if rem != 0 { stream.append(contentsOf: repeatElement(0, count: 128 - rem)) }
        }

        let totalDataLen = UInt64((keyBytes.isEmpty ? 0 : 128) + data.count)
        let blocks = stream.count / 128
        for b in 0..<blocks {
            let isLast = b == blocks - 1
            let t0: UInt64 = isLast ? totalDataLen : UInt64((b + 1) * 128)
            var m = [UInt64](repeating: 0, count: 16)
            let base = b * 128
            for i in 0..<16 {
                var w: UInt64 = 0
                for j in 0..<8 { w |= UInt64(stream[base + i * 8 + j]) << (j * 8) }
                m[i] = w
            }
            var v = [UInt64](repeating: 0, count: 16)
            for i in 0..<8 { v[i] = h[i]; v[i + 8] = blake2bIV[i] }
            v[12] ^= t0
            if isLast { v[14] = ~v[14] }
            func g(_ a: Int, _ bIdx: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
                v[a] = v[a] &+ v[bIdx] &+ x
                v[d] = rotr64(v[d] ^ v[a], 32)
                v[c] = v[c] &+ v[d]
                v[bIdx] = rotr64(v[bIdx] ^ v[c], 24)
                v[a] = v[a] &+ v[bIdx] &+ y
                v[d] = rotr64(v[d] ^ v[a], 16)
                v[c] = v[c] &+ v[d]
                v[bIdx] = rotr64(v[bIdx] ^ v[c], 63)
            }
            for r in 0..<12 {
                let s = blake2Sigma[r]
                g(0, 4, 8, 12, m[s[0]], m[s[1]])
                g(1, 5, 9, 13, m[s[2]], m[s[3]])
                g(2, 6, 10, 14, m[s[4]], m[s[5]])
                g(3, 7, 11, 15, m[s[6]], m[s[7]])
                g(0, 5, 10, 15, m[s[8]], m[s[9]])
                g(1, 6, 11, 12, m[s[10]], m[s[11]])
                g(2, 7, 8, 13, m[s[12]], m[s[13]])
                g(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
        }
        var out = Data(capacity: outLen)
        for i in 0..<8 where out.count < outLen {
            var le = h[i].littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0.prefix(outLen - out.count)) }
        }
        return out
    }

    static func blake2s(_ data: Data, key: Data? = nil, outLen: Int = 32) -> Data {
        let keyBytes = Array((key ?? Data()).prefix(32))
        var h = blake2sIV
        h[0] ^= 0x0101_0000 ^ UInt32(keyBytes.count << 8) ^ UInt32(outLen)

        var stream = [UInt8]()
        if !keyBytes.isEmpty {
            stream.append(contentsOf: keyBytes)
            stream.append(contentsOf: repeatElement(0, count: 64 - keyBytes.count))
        }
        stream.append(contentsOf: data)
        if stream.isEmpty { stream = [UInt8](repeating: 0, count: 64) }
        else {
            let rem = stream.count % 64
            if rem != 0 { stream.append(contentsOf: repeatElement(0, count: 64 - rem)) }
        }

        let totalDataLen = UInt32((keyBytes.isEmpty ? 0 : 64) + data.count)
        let blocks = stream.count / 64
        for b in 0..<blocks {
            let isLast = b == blocks - 1
            let t0: UInt32 = isLast ? totalDataLen : UInt32((b + 1) * 64)
            var m = [UInt32](repeating: 0, count: 16)
            let base = b * 64
            for i in 0..<16 {
                var w: UInt32 = 0
                for j in 0..<4 { w |= UInt32(stream[base + i * 4 + j]) << (j * 8) }
                m[i] = w
            }
            var v = [UInt32](repeating: 0, count: 16)
            for i in 0..<8 { v[i] = h[i]; v[i + 8] = blake2sIV[i] }
            v[12] ^= t0
            if isLast { v[14] = ~v[14] }
            func g(_ a: Int, _ bIdx: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
                v[a] = v[a] &+ v[bIdx] &+ x
                v[d] = rotr32(v[d] ^ v[a], 16)
                v[c] = v[c] &+ v[d]
                v[bIdx] = rotr32(v[bIdx] ^ v[c], 12)
                v[a] = v[a] &+ v[bIdx] &+ y
                v[d] = rotr32(v[d] ^ v[a], 8)
                v[c] = v[c] &+ v[d]
                v[bIdx] = rotr32(v[bIdx] ^ v[c], 7)
            }
            for r in 0..<10 {
                let s = blake2Sigma[r]
                g(0, 4, 8, 12, m[s[0]], m[s[1]])
                g(1, 5, 9, 13, m[s[2]], m[s[3]])
                g(2, 6, 10, 14, m[s[4]], m[s[5]])
                g(3, 7, 11, 15, m[s[6]], m[s[7]])
                g(0, 5, 10, 15, m[s[8]], m[s[9]])
                g(1, 6, 11, 12, m[s[10]], m[s[11]])
                g(2, 7, 8, 13, m[s[12]], m[s[13]])
                g(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
        }
        var out = Data(capacity: outLen)
        for i in 0..<8 where out.count < outLen {
            var le = h[i].littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0.prefix(outLen - out.count)) }
        }
        return out
    }

    // MARK: - RIPEMD-160

    static func ripemd160(_ data: Data) -> Data {
        var padded = Array(data)
        let bitLen = UInt64(data.count) &* 8
        padded.append(0x80)
        while (padded.count + 8) % 64 != 0 { padded.append(0) }
        for s in stride(from: 0, to: 64, by: 8) { padded.append(UInt8(truncatingIfNeeded: bitLen >> s)) }

        var h: [UInt32] = [0x6745_2301, 0xefcd_ab89, 0x98ba_dcfe, 0x1032_5476, 0xc3d2_e1f0]
        let zl = [
            0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
            7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,
            3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,
            1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,
            4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13,
        ]
        let zr = [
            5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,
            6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,
            15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,
            8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,
            12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11,
        ]
        let sl = [
            11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,
            7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,
            11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,
            11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,
            9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6,
        ]
        let sr = [
            8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,
            9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,
            9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,
            15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,
            8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11,
        ]
        let kl: [UInt32] = [0x0000_0000, 0x5a82_7999, 0x6ed9_eba1, 0x8f1b_bcdc, 0xa953_fd4e]
        let kr: [UInt32] = [0x50a2_8be6, 0x5c4d_d124, 0x6d70_3ef3, 0x7a6d_76e9, 0x0000_0000]

        func f(_ j: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
            switch j >> 4 {
            case 0: return x ^ y ^ z
            case 1: return (x & y) | (~x & z)
            case 2: return (x | ~y) ^ z
            case 3: return (x & z) | (y & ~z)
            default: return x ^ (y | ~z)
            }
        }

        for off in stride(from: 0, to: padded.count, by: 64) {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let p = off + i * 4
                x[i] = UInt32(padded[p]) | (UInt32(padded[p + 1]) << 8) | (UInt32(padded[p + 2]) << 16) | (UInt32(padded[p + 3]) << 24)
            }
            var al = h[0], bl = h[1], cl = h[2], dl = h[3], el = h[4]
            var ar = h[0], br = h[1], cr = h[2], dr = h[3], er = h[4]
            for j in 0..<80 {
                let rnd = j >> 4
                var tl = al &+ f(j, bl, cl, dl) &+ x[zl[j]] &+ kl[rnd]
                tl = rotl32(tl, sl[j]) &+ el
                al = el; el = dl; dl = rotl32(cl, 10); cl = bl; bl = tl

                var tr = ar &+ f(79 - j, br, cr, dr) &+ x[zr[j]] &+ kr[rnd]
                tr = rotl32(tr, sr[j]) &+ er
                ar = er; er = dr; dr = rotl32(cr, 10); cr = br; br = tr
            }
            let t = h[1] &+ cl &+ dr
            h[1] = h[2] &+ dl &+ er
            h[2] = h[3] &+ el &+ ar
            h[3] = h[4] &+ al &+ br
            h[4] = h[0] &+ bl &+ cr
            h[0] = t
        }

        var out = Data(capacity: 20)
        for w in h {
            var le = w.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        return out
    }

    // MARK: - Non-Crypto Checksums

    private static let crc32cTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0x82f6_3b78 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32Data(_ data: Data) -> Data {
        let crc = data.withUnsafeBytes { ptr -> UInt32 in
            guard let base = ptr.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(truncatingIfNeeded: zlib.crc32(0, base, uInt(data.count)))
        }
        return withUnsafeBytes(of: crc.bigEndian) { Data($0) }
    }

    static func crc32cData(_ data: Data) -> Data {
        var crc: UInt32 = 0xffff_ffff
        for b in data {
            crc = crc32cTable[Int((crc ^ UInt32(b)) & 0xff)] ^ (crc >> 8)
        }
        return withUnsafeBytes(of: (crc ^ 0xffff_ffff).bigEndian) { Data($0) }
    }

    static func adler32Data(_ data: Data) -> Data {
        let val = data.withUnsafeBytes { ptr -> UInt32 in
            guard let base = ptr.bindMemory(to: Bytef.self).baseAddress else { return 1 }
            return UInt32(truncatingIfNeeded: zlib.adler32(1, base, uInt(data.count)))
        }
        return withUnsafeBytes(of: val.bigEndian) { Data($0) }
    }

    static func fnv1a32(_ data: Data) -> Data {
        var hash: UInt32 = 0x811c_9dc5
        for b in data {
            hash ^= UInt32(b)
            hash = hash &* 0x0100_0193
        }
        return withUnsafeBytes(of: hash.bigEndian) { Data($0) }
    }

    static func fnv1a64(_ data: Data) -> Data {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data {
            hash ^= UInt64(b)
            hash = hash &* 0x0100_0000_01b3
        }
        return withUnsafeBytes(of: hash.bigEndian) { Data($0) }
    }

    static func murmur3_32(_ data: Data, seed: UInt32 = 0) -> Data {
        let bytes = Array(data)
        let len = bytes.count
        let nblocks = len / 4
        var h1 = seed
        let c1: UInt32 = 0xcc9e_2d51
        let c2: UInt32 = 0x1b87_3593

        for i in 0..<nblocks {
            let p = i * 4
            var k1 = UInt32(bytes[p]) | (UInt32(bytes[p + 1]) << 8) | (UInt32(bytes[p + 2]) << 16) | (UInt32(bytes[p + 3]) << 24)
            k1 = k1 &* c1
            k1 = rotl32(k1, 15)
            k1 = k1 &* c2
            h1 ^= k1
            h1 = rotl32(h1, 13)
            h1 = h1 &* 5 &+ 0xe654_6b64
        }

        let tail = nblocks * 4
        var k1: UInt32 = 0
        switch len & 3 {
        case 3:
            k1 ^= UInt32(bytes[tail + 2]) << 16
            fallthrough
        case 2:
            k1 ^= UInt32(bytes[tail + 1]) << 8
            fallthrough
        case 1:
            k1 ^= UInt32(bytes[tail])
            k1 = k1 &* c1
            k1 = rotl32(k1, 15)
            k1 = k1 &* c2
            h1 ^= k1
        default: break
        }
        h1 ^= UInt32(truncatingIfNeeded: len)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85eb_ca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2_ae35
        h1 ^= h1 >> 16
        return withUnsafeBytes(of: h1.bigEndian) { Data($0) }
    }

    private static func rotl32(_ x: UInt32, _ n: Int) -> UInt32 {
        let k = UInt32(n & 31)
        return k == 0 ? x : (x << k) | (x >> (32 - k))
    }

    private static func rotl64(_ x: UInt64, _ n: Int) -> UInt64 {
        let k = UInt64(n & 63)
        return k == 0 ? x : (x << k) | (x >> (64 - k))
    }

    private static func rotr32(_ x: UInt32, _ n: Int) -> UInt32 {
        let k = UInt32(n & 31)
        return k == 0 ? x : (x >> k) | (x << (32 - k))
    }

    private static func rotr64(_ x: UInt64, _ n: Int) -> UInt64 {
        let k = UInt64(n & 63)
        return k == 0 ? x : (x >> k) | (x << (64 - k))
    }

    // MARK: - BLAKE3 (256-bit)

    static func blake3(_ data: Data) -> Data {
        let iv = blake2sIV
        let msgPerm = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
        let chunkStart: UInt32 = 1 << 0
        let chunkEnd: UInt32 = 1 << 1
        let parentFlag: UInt32 = 1 << 2
        let rootFlag: UInt32 = 1 << 3

        func compress(cv: [UInt32], block: ArraySlice<UInt8>, counter: UInt64, flags: UInt32) -> [UInt32] {
            var padded = [UInt8](repeating: 0, count: 64)
            for (idx, b) in block.enumerated() { padded[idx] = b }
            var m = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let p = i * 4
                m[i] = UInt32(padded[p]) | (UInt32(padded[p + 1]) << 8) | (UInt32(padded[p + 2]) << 16) | (UInt32(padded[p + 3]) << 24)
            }
            return compressWords(cv: cv, m: m, blockLen: UInt32(block.count), counter: counter, flags: flags)
        }

        func compressWords(cv: [UInt32], m initialM: [UInt32], blockLen: UInt32, counter: UInt64, flags: UInt32) -> [UInt32] {
            var m = initialM
            var s: [UInt32] = [
                cv[0], cv[1], cv[2], cv[3], cv[4], cv[5], cv[6], cv[7],
                iv[0], iv[1], iv[2], iv[3],
                UInt32(truncatingIfNeeded: counter),
                UInt32(truncatingIfNeeded: counter >> 32),
                blockLen, flags,
            ]
            func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ mx: UInt32, _ my: UInt32) {
                s[a] = s[a] &+ s[b] &+ mx
                s[d] = rotr32(s[d] ^ s[a], 16)
                s[c] = s[c] &+ s[d]
                s[b] = rotr32(s[b] ^ s[c], 12)
                s[a] = s[a] &+ s[b] &+ my
                s[d] = rotr32(s[d] ^ s[a], 8)
                s[c] = s[c] &+ s[d]
                s[b] = rotr32(s[b] ^ s[c], 7)
            }
            for round in 0..<7 {
                g(0, 4, 8, 12, m[0], m[1]); g(1, 5, 9, 13, m[2], m[3])
                g(2, 6, 10, 14, m[4], m[5]); g(3, 7, 11, 15, m[6], m[7])
                g(0, 5, 10, 15, m[8], m[9]); g(1, 6, 11, 12, m[10], m[11])
                g(2, 7, 8, 13, m[12], m[13]); g(3, 4, 9, 14, m[14], m[15])
                if round < 6 { m = msgPerm.map { m[$0] } }
            }
            for i in 0..<8 {
                s[i] ^= s[i + 8]
                s[i + 8] ^= cv[i]
            }
            return s
        }

        func wordsToData(_ words: ArraySlice<UInt32>) -> Data {
            var out = Data(capacity: words.count * 4)
            for w in words {
                var le = w.littleEndian
                withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
            }
            return out
        }

        func parentCV(left: [UInt32], right: [UInt32], isRoot: Bool) -> [UInt32] {
            let m = Array(left.prefix(8) + right.prefix(8))
            let full = compressWords(cv: iv, m: m, blockLen: 64, counter: 0, flags: parentFlag | (isRoot ? rootFlag : 0))
            return Array(full.prefix(8))
        }

        let bytes = Array(data)
        let chunkLen = 1024
        let totalChunks = max(1, (bytes.count + chunkLen - 1) / chunkLen)
        var cvStack = [[UInt32]]()

        for chunkIdx in 0..<totalChunks {
            let start = chunkIdx * chunkLen
            let end = min(bytes.count, start + chunkLen)
            let chunk = bytes[start..<end]
            var cv = iv
            var off = chunk.startIndex
            let blockCount = max(1, (chunk.count + 63) / 64)
            for bIdx in 0..<blockCount {
                let bEnd = min(chunk.endIndex, off + 64)
                let blk = chunk[off..<bEnd]
                var fl: UInt32 = 0
                if bIdx == 0 { fl |= chunkStart }
                if bIdx == blockCount - 1 { fl |= chunkEnd }
                let isSingleChunkRoot = totalChunks == 1 && bIdx == blockCount - 1
                let out = compress(cv: cv, block: blk, counter: UInt64(chunkIdx), flags: fl | (isSingleChunkRoot ? rootFlag : 0))
                if isSingleChunkRoot { return wordsToData(out.prefix(8)) }
                cv = Array(out.prefix(8))
                off = bEnd
            }

            var idx = chunkIdx + 1
            while chunkIdx < totalChunks - 1 && (idx & 1) == 0 && !cvStack.isEmpty {
                let left = cvStack.removeLast()
                cv = parentCV(left: left, right: cv, isRoot: false)
                idx >>= 1
            }
            cvStack.append(cv)
        }

        while cvStack.count > 1 {
            let right = cvStack.removeLast()
            let left = cvStack.removeLast()
            cvStack.append(parentCV(left: left, right: right, isRoot: cvStack.isEmpty))
        }
        return wordsToData(cvStack[0].prefix(8))
    }
}
