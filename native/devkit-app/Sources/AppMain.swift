import AppKit
import CryptoKit
import Darwin
import Foundation
import SwiftUI

// MARK: - Single Instance & Atomic Flock IPC

private struct InstanceLock: Codable {
    let pid: Int32
    let binarySha256: String
}

private struct OpenRequest: Codable {
    let requestId: String
    let timestamp: Double
    let tool: String?
    let selectedB64: String?
}

private let kOpenNotification = Notification.Name("com.tinycast.devkit.open")

// Disambiguate POSIX flock(2) from C `struct flock` imported by Darwin.
@_silgen_name("flock")
private func c_flock(_ fd: Int32, _ operation: Int32) -> Int32

// Kept open for the lifetime of the master process; the kernel releases LOCK_EX atomically on exit.
nonisolated(unsafe) private var gHeldLockFD: Int32 = -1

private func lockFilePath() -> String {
    "/tmp/tinycast-devkit-\(getuid()).lock"
}

private func requestFileURL() -> URL {
    URL(fileURLWithPath: "/tmp/tinycast-devkit-\(getuid())-request.json")
}

private func currentExecutableSha256() -> String {
    let rawPath = Bundle.main.executablePath
        ?? CommandLine.arguments.first
        ?? ProcessInfo.processInfo.arguments.first
        ?? ""
    guard !rawPath.isEmpty else { return "" }
    let resolved = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
    guard let data = try? Data(contentsOf: resolved) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func writeInstanceLock(_ lock: InstanceLock, to fd: Int32) {
    guard let data = try? JSONEncoder().encode(lock) else { return }
    Darwin.ftruncate(fd, 0)
    var written = 0
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        while written < data.count {
            let n = Darwin.pwrite(fd, base.advanced(by: written), data.count - written, off_t(written))
            if n <= 0 { break }
            written += n
        }
    }
    _ = Darwin.fsync(fd)
}

private func readInstanceLock(from fd: Int32) -> InstanceLock? {
    var buf = [UInt8](repeating: 0, count: 1024)
    let n = Darwin.pread(fd, &buf, buf.count, 0)
    guard n > 0 else { return nil }
    return try? JSONDecoder().decode(InstanceLock.self, from: Data(buf.prefix(n)))
}

private func decodeArgValue(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

private func decodeBase64Arg(_ flag: String, in args: [String]) -> String? {
    guard let b64 = decodeArgValue(flag, in: args), !b64.isEmpty,
          let data = Data(base64Encoded: b64) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func normalizeToolArg(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
    switch raw {
    case "workbench", "smart-clipboard", "smart": return "smart"
    case "uuid-generator", "uuid": return "uuid"
    case "timestamp-converter", "timestamp": return "timestamp"
    case "hash-generator", "hash": return "hash"
    case "encode-decode", "codec": return "codec"
    case "json-formatter", "json": return "json"
    case "color-converter", "color-picker", "color": return "color"
    case "regex-tester", "regex": return "regex"
    case "text-diff", "diff": return "diff"
    case "url-parser", "url", "curl": return "url"
    case "number-base", "radix", "bitwise": return "radix"
    case "cidr-calculator", "cidr", "subnet": return "cidr"
    case "data-converter", "data": return "data"
    case "sql-formatter", "sql": return "sql"
    case "cert-inspector", "cert", "tls", "ssh": return "cert"
    case "ocr-scanner", "ocr": return "ocr"
    case "image-converter", "image": return "image"
    case "currency-converter", "currency", "fx", "exchange", "rate": return "currency"
    case "password-generator", "password": return "password"
    case "text-transform", "text": return "text"
    case "qr-generator", "qr": return "qr"
    case "cron-inspector", "cron": return "cron"
    case "network-ports", "network": return "network"
    default: return ToolID(rawValue: raw)?.rawValue
    }
}

private func coordinateSingleInstance(tool: String?, selectedB64: String?) -> String {
    // Clean up legacy non-flock JSON lockfile if present from earlier builds
    let legacyURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tinycast-devkit-\(getuid()).json")
    try? FileManager.default.removeItem(at: legacyURL)

    let isLockTest = ProcessInfo.processInfo.environment["TINYCAST_LOCK_TEST"] == "1"
    let lockPath = isLockTest ? "/tmp/tinycast-devkit-\(getuid())-race-test.lock" : lockFilePath()
    let reqId = UUID().uuidString

    if !isLockTest {
        let req = OpenRequest(
            requestId: reqId,
            timestamp: Date().timeIntervalSince1970,
            tool: tool,
            selectedB64: selectedB64
        )
        if let reqData = try? JSONEncoder().encode(req) {
            try? reqData.write(to: requestFileURL(), options: .atomic)
        }
    }

    let fd = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else {
        return reqId
    }

    let myHash = isLockTest ? "" : currentExecutableSha256()

    if c_flock(fd, LOCK_EX | LOCK_NB) == 0 {
        if isLockTest {
            usleep(180_000)
            print("LOCK_MASTER")
            fflush(stdout)
            exit(0)
        }
        gHeldLockFD = fd
        writeInstanceLock(InstanceLock(pid: getpid(), binarySha256: myHash), to: fd)
        return reqId
    }

    if isLockTest {
        print("LOCK_SECONDARY")
        fflush(stdout)
        Darwin.close(fd)
        exit(0)
    }

    // Another instance holds LOCK_EX. Inspect whether it is an outdated binary on disk.
    var existing = readInstanceLock(from: fd)
    if existing == nil {
        usleep(15_000)
        existing = readInstanceLock(from: fd)
    }

    if let existing,
       existing.pid > 0,
       existing.pid != getpid(),
       !existing.binarySha256.isEmpty,
       !myHash.isEmpty,
       existing.binarySha256 != myHash {
        Darwin.kill(existing.pid, SIGTERM)
        for _ in 0..<40 {
            if c_flock(fd, LOCK_EX | LOCK_NB) == 0 {
                gHeldLockFD = fd
                writeInstanceLock(InstanceLock(pid: getpid(), binarySha256: myHash), to: fd)
                return reqId
            }
            usleep(25_000)
        }
    }

    let info: [String: String] = [
        "requestId": reqId,
        "tool": tool ?? "",
        "selectedB64": selectedB64 ?? "",
    ]
    DistributedNotificationCenter.default().postNotificationName(
        kOpenNotification,
        object: nil,
        userInfo: info,
        deliverImmediately: true
    )
    Darwin.close(fd)
    exit(0)
}

// MARK: - Self Test Suite

@MainActor
private func runSelfTests() -> Never {
    func check(_ cond: @autoclosure () -> Bool, _ msg: String) {
        if !cond() {
            fputs("SELF_TEST_FAIL: \(msg)\n", stderr)
            exit(1)
        }
    }

    // 1. UUID RFC 9562 vectors, monotonic batches, KSUID 160-bit round-trip
    let fixedTs: Int64 = 1_731_830_400_123
    check(UUIDEngine.shared.generateV3(name: "www.example.com") == "5df41881-3aed-3515-88a7-2f4a814cf09e", "UUID v3 vector")
    check(UUIDEngine.shared.generateV5(name: "www.example.com") == "2ed6657d-e927-568b-95e1-2665a8aea6a2", "UUID v5 vector")

    let v1 = UUIDEngine.shared.generateV1(timestampMs: fixedTs)
    let v6 = UUIDEngine.shared.generateV6(timestampMs: fixedTs)
    let v7 = UUIDEngine.shared.generateV7(timestampMs: fixedTs)
    check(UUIDEngine.shared.inspect(v1)?.timestampMs == fixedTs, "v1 timestamp extract")
    check(UUIDEngine.shared.inspect(v6)?.timestampMs == fixedTs, "v6 timestamp extract")
    check(UUIDEngine.shared.inspect(v7)?.timestampMs == fixedTs, "v7 timestamp extract")

    let v7Batch = (0..<20).map { _ in UUIDEngine.shared.generateV7() }
    for i in 1..<v7Batch.count { check(v7Batch[i] > v7Batch[i - 1], "v7 monotonic batch") }
    let ulidBatch = (0..<20).map { _ in UUIDEngine.shared.generateUlid() }
    for i in 1..<ulidBatch.count { check(ulidBatch[i] > ulidBatch[i - 1], "ULID monotonic batch") }

    let ksuid = UUIDEngine.shared.generateKsuid(timestampMs: 1_731_830_400_000)
    check(ksuid.count == 27, "KSUID length")
    check(UUIDEngine.shared.inspect(ksuid)?.timestampMs == 1_731_830_400_000, "KSUID timestamp round-trip")

    let oid = UUIDEngine.shared.generateObjectId(timestampMs: 1_731_830_400_000)
    check(oid.count == 24 && UUIDEngine.shared.inspect(oid)?.timestampMs == 1_731_830_400_000, "ObjectID round-trip")

    // 2. Hash vectors (SHA-256, SM3, SHA3-256, BLAKE3 single + multi-chunk, CRC32)
    let abcHashes = HashEngine.computeAll(data: Data("abc".utf8))
    let findHash: (String) -> String? = { id in abcHashes.first(where: { $0.id == id })?.hexLower }
    check(findHash("sha256") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 abc")
    check(findHash("sm3") == "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0", "SM3 abc")
    check(findHash("sha3-256") == "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532", "SHA3-256 abc")
    check(findHash("blake3") == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85", "BLAKE3 abc")
    check(findHash("crc32") == "352441c2", "CRC32 abc")
    check(HashEngine.blake3(Data(repeating: 0x41, count: 4096)).count == 32, "BLAKE3 multi-chunk")

    // 3. Codecs, Zlib, JWT, AES-GCM & CBC
    let sample = "你好 Tinycast 🚀 & <test>"
    check(CodecEngine.decodeBase32(CodecEngine.encodeBase32(Data(sample.utf8))).flatMap { String(data: $0, encoding: .utf8) } == sample, "Base32 round-trip")
    check(CodecEngine.decodeBase58(CodecEngine.encodeBase58(Data(sample.utf8))).flatMap { String(data: $0, encoding: .utf8) } == sample, "Base58 round-trip")
    let gzB64 = try! CodecEngine.runBidirectional(sample, op: .gzip, encode: true)
    check((try? CodecEngine.runBidirectional(gzB64, op: .gzip, encode: false)) == sample, "Gzip round-trip")
    let ctGcm = try! CodecEngine.encryptAes(sample, secret: "strong-pass", mode: .gcm, kdf: .pbkdf2)
    check((try? CodecEngine.decryptAes(ctGcm, secret: "strong-pass")) == sample, "AES-256-GCM round-trip")
    let ctCbc = try! CodecEngine.encryptAes(sample, secret: "strong-pass", mode: .cbc, kdf: .pbkdf2)
    check((try? CodecEngine.decryptAes(ctCbc, secret: "strong-pass")) == sample, "AES-256-CBC round-trip")

    // 4. Timestamp, JSON repair, Cron, QR
    check(TimestampEngine.parse("1731830400")?.detectedKind.contains("秒") == true, "Timestamp parse")
    let jsonAnalysis = JsonEngine.analyze("{ /* note */ app: 'Tinycast', list: [1, 2,], }")
    check(jsonAnalysis.valid && jsonAnalysis.repaired, "JSON repair")
    let cron = try! CronEngine.parse("*/15 9-17 * * 1-5", count: 5)
    check(cron.nextRuns.count == 5, "Cron nextRuns")
    let qr = QrEngine.generate(text: "https://github.com/abue-ammar/tinycast", level: .M)
    check(qr != nil && qr!.svg.hasPrefix("<svg"), "QR generation")

    // 5. Color parsing, conversions, WCAG, OKLCH shades, harmonies, CVD & smart routing
    check(ColorEngine.parse("#3B82F6")?.hex6Lower == "#3b82f6", "Color hex 6")
    check(ColorEngine.parse("#f0a")?.hex6Lower == "#ff00aa", "Color hex 3")
    check(ColorEngine.parse("20261118") == nil, "Plain digits without # must not misparse as hex color")
    check(ColorEngine.parse("rebeccapurple")?.hex6Lower == "#663399", "CSS named color")
    check(ColorEngine.parse("rgb(59 130 246 / 50%)")?.a255 == 128, "CSS4 rgb alpha")
    check(ColorEngine.parse("Color(0xFF3B82F6)")?.hex6Lower == "#3b82f6", "Android/Flutter 0xAARRGGBB")
    if let blue = ColorEngine.parse("#3B82F6"), let backOk = ColorEngine.parse(ColorEngine.formatAll(blue).first(where: { $0.id == "oklch" })?.value ?? "") {
        check(abs(blue.r - backOk.r) < 0.01 && abs(blue.g - backOk.g) < 0.01 && abs(blue.b - backOk.b) < 0.01, "OKLCH round-trip")
    } else {
        check(false, "OKLCH format parse")
    }
    let wcagBw = ColorEngine.evaluateContrast(foreground: ColorRGBA(r: 0, g: 0, b: 0), background: ColorRGBA(r: 1, g: 1, b: 1))
    check(abs(wcagBw.ratio - 21.0) < 0.05 && wcagBw.aaaNormal, "WCAG 21:1 B/W")
    let fixed = ColorEngine.autoFixForContrast(foreground: ColorRGBA(r: 0.7, g: 0.7, b: 0.7), background: ColorRGBA(r: 1, g: 1, b: 1), targetRatio: 4.5)
    check(ColorEngine.evaluateContrast(foreground: fixed, background: ColorRGBA(r: 1, g: 1, b: 1)).aaNormal, "WCAG autoFixForContrast")
    check(ColorEngine.tailwindScale(for: ColorRGBA(r: 0.231, g: 0.510, b: 0.965)).count == 11, "Tailwind 11 shades")
    check(ColorEngine.harmonies(for: ColorRGBA(r: 0.231, g: 0.510, b: 0.965)).count == 5, "Color harmonies")
    check(ColorEngine.simulateCvd(ColorRGBA(r: 0.231, g: 0.510, b: 0.965)).count == 5, "CVD simulations")
    check(SmartDetector.detect("#3B82F6") == .color, "SmartDetector color")

    // 6. Regex Engine
    let reRes = RegexEngine.evaluate(
        pattern: #"(?<user>[a-z]+)@(?<host>[a-z]+\.dev)"#,
        input: "mail: alice@tinycast.dev, bob@tinycast.dev",
        replacement: "${user}@example.org",
        flags: RegexFlags()
    )
    check(reRes.valid && reRes.totalMatchCount == 2, "Regex matches count")
    check(reRes.namedGroupNames == ["user", "host"], "Regex named groups")
    check(reRes.matches.first?.groups.first?.text == "alice", "Regex capture group value")
    check(reRes.replacedText.contains("alice@example.org"), "Regex replacement")
    check(!RegexEngine.evaluate(pattern: "[unclosed", input: "x", replacement: "", flags: RegexFlags()).valid, "Regex invalid pattern error")

    // 7. Text & JSON Semantic Diff Engine
    let semDiff = DiffEngine.computeDiff(
        left: #"{"b":2,"a":1,"nested":{"x":true,"y":10}}"#,
        right: #"{"nested":{"y":20,"x":true},"a":1,"c":3}"#,
        jsonSemantic: true,
        ignoreWhitespace: false,
        ignoreCase: false
    )
    check(semDiff.error == nil, "JSON semantic diff valid")
    check(semDiff.jsonChanges.contains(where: { $0.path == "$.nested.y" && $0.kind == "修改" }), "JSON path change")
    check(semDiff.jsonChanges.contains(where: { $0.path == "$.c" && $0.kind == "新增" }), "JSON path added")
    check(semDiff.jsonChanges.contains(where: { $0.path == "$.b" && $0.kind == "删除" }), "JSON path removed")

    let lineDiff = DiffEngine.computeDiff(left: "alpha\nbeta\ngamma", right: "alpha\nbeta2\ngamma", jsonSemantic: false, ignoreWhitespace: false, ignoreCase: false)
    check(lineDiff.addedCount == 1 && lineDiff.removedCount == 1, "Text line diff counts")

    // 8. URL Parser & cURL Converter
    let urlParsed = UrlCurlEngine.parseUrl("https://api.tinycast.dev:8443/v1/items?q=hello+world&tag=mac")
    check(urlParsed?.host == "api.tinycast.dev" && urlParsed?.port == "8443", "URL parse host/port")
    check(urlParsed?.params.first(where: { $0.key == "q" })?.value == "hello world", "URL decode query + space")
    let rebuilt = UrlCurlEngine.rebuildUrl(
        scheme: "https", host: "tinycast.dev", port: "", path: "/search",
        params: [UrlQueryParam(key: "a", value: "1 2"), UrlQueryParam(key: "off", value: "skip", enabled: false)],
        fragment: "top"
    )
    check(rebuilt == "https://tinycast.dev/search?a=1%202#top", "URL rebuild")
    let curlParsed = try! UrlCurlEngine.parseCurl(UrlCurlEngine.sampleCurl)
    check(curlParsed.method == "POST" && curlParsed.headers.count == 3, "cURL parse")
    check(UrlCurlEngine.toFetch(curlParsed).contains("await fetch("), "cURL to fetch")
    check(UrlCurlEngine.toPythonRequests(curlParsed).contains("import requests"), "cURL to python")

    // 9. Radix, Bitwise, chmod & CIDR
    let rad = RadixBitwiseEngine.parse("0xDEADBEEF")!
    check(RadixBitwiseEngine.represent(rad).decUnsigned == "3735928559", "Radix 0xDEADBEEF")
    check(RadixBitwiseEngine.toggleBit(0, at: 5) == 32, "Bit toggle")
    check(ChmodState.parse("755")?.symbolic == "rwxr-xr-x", "chmod 755 -> rwxr-xr-x")
    check(ChmodState.parse("rwsr-xr-x")?.octal4 == "4755", "chmod symbolic -> 4755")
    let c4 = CidrEngine.parseIpv4Cidr("10.0.12.34/22")!
    check(c4.network == "10.0.12.0" && c4.broadcast == "10.0.15.255" && c4.usableCount == 1022, "IPv4 /22 CIDR")
    check(CidrEngine.parseIpv4Cidr("192.168.1.4/31")?.usableCount == 2, "IPv4 /31 RFC3021")
    check(CidrEngine.ipv4Contains(cidr: "10.0.12.34/22", ip: "10.0.13.99") == true, "IPv4 contains")
    check(CidrEngine.splitIpv4("192.168.1.0/24", targetPrefix: 26).count == 4, "IPv4 subnet split")
    let c6 = CidrEngine.parseIpv6Cidr("2001:db8:85a3::8a2e:370:7334/48")!
    check(c6.cidrNotation == "2001:db8:85a3::/48", "IPv6 CIDR UInt128")

    // 10. Multi-format Data Converter & SQL Formatter/Binder
    let yamlConv = try! DataFormatEngine.convert(DataFormatEngine.sampleJson, from: .json, to: .yaml)
    check(yamlConv.detected == .json && yamlConv.output.contains("service: tinycast-devkit"), "JSON -> YAML")
    let backJson = try! DataFormatEngine.convert(yamlConv.output, from: .yaml, to: .json)
    check(backJson.output.contains("\"port\": 8080"), "YAML -> JSON")
    let tomlConv = try! DataFormatEngine.convert(yamlConv.output, from: .yaml, to: .toml)
    check(tomlConv.output.contains("[server]"), "YAML -> TOML")
    let mdTable = try! DataFormatEngine.convert(DataFormatEngine.sampleCsv, from: .csv, to: .markdownTable)
    check(mdTable.output.contains("| auth-api | gateway | 8081 | true |"), "CSV -> Markdown Table")
    let boundMyBatis = SqlEngine.bindParameters(sqlOrLog: SqlEngine.sampleMyBatisLog, manualParams: "", formatOutput: false)
    check(boundMyBatis.params.count == 5 && boundMyBatis.renderedSql.contains("tenant_id = 10042") && boundMyBatis.renderedSql.contains("'active'"), "SQL MyBatis bind")
    check(SqlEngine.format("select id,name from users where active=1;").contains("FROM users"), "SQL format")

    // 11. X.509 DER & OpenSSH Key Parser
    let selfDer = CertEngine.buildSelfTestDerCert()
    let parsedCert = try! CertEngine.parseX509Certificate(der: selfDer)
    check(parsedCert.subjectCommonName == "devkit.tinycast.test" && parsedCert.sanEntries.contains("DNS: tinycast.local"), "X.509 DER parse")
    let parsedSsh = CertEngine.parseSshPublicKey(CertEngine.sampleSshKey)
    check(parsedSsh?.algorithmLabel == "Ed25519" && parsedSsh?.sha256Fingerprint.hasPrefix("SHA256:") == true, "SSH public key parse")

    // 12. Vision QR Barcode Decode + ImageIO Convert/EXIF Strip
    let paddedQrPng: Data = {
        let img = qr!.image
        let side = 240
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        img.draw(in: NSRect(x: 24, y: 24, width: side - 48, height: side - 48))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }()
    let visionRes = try! VisionImageEngine.scanImageDataSync(paddedQrPng)
    check(visionRes.barcodes.contains(where: { $0.payload.contains("tinycast") }), "Vision barcode decode")
    let jpgConv = try! ImageToolEngine.convertImageDataSync(paddedQrPng, format: .jpeg, quality: 0.85, maxWidth: 120, scalePercent: nil, stripMetadata: true)
    check(jpgConv.width == 120 && jpgConv.height == 120 && jpgConv.dataUri.hasPrefix("data:image/jpeg;base64,"), "ImageIO convert + resize + DataURI")

    // 13. Hosts parser & SmartDetector expanded kinds
    let hosts = NetworkEngine.readHostsFile()
    check(hosts.contains(where: { $0.hostnames.contains("localhost") }), "Hosts /etc/hosts parse")
    check(SmartDetector.detect("10.0.12.34/22") == .cidr, "SmartDetector CIDR")
    check(SmartDetector.detect(UrlCurlEngine.sampleCurl) == .curl, "SmartDetector cURL")
    check(SmartDetector.detect(SqlEngine.sampleMyBatisLog) == .sql, "SmartDetector SQL")
    check(SmartDetector.detect(CertEngine.sampleSshKey) == .certOrSsh, "SmartDetector SSH")

    // 14. Currency & FX Calculator Engine
    check(CurrencyEngine.evaluateExpression("(100 + 50) * 2 / 3") == 100.0, "Currency expression math")
    check(CurrencyEngine.evaluateExpression("1,000 * 10%") == 100.0, "Currency percent & comma expression")
    check(CurrencyEngine.evaluateExpression("10 / 0") == nil, "Currency divide by zero guard")
    let usdParsed = CurrencyEngine.parseCurrencyQuery("$199.50")
    let jpyParsed = CurrencyEngine.parseCurrencyQuery("5000 JPY")
    let hkdParsed = CurrencyEngine.parseCurrencyQuery("HK$88")
    check(usdParsed?.amount == 199.5 && usdParsed?.code == "USD", "Currency parse $199.50")
    check(jpyParsed?.amount == 5000 && jpyParsed?.code == "JPY", "Currency parse 5000 JPY")
    check(hkdParsed?.amount == 88 && hkdParsed?.code == "HKD", "Currency parse HK$88")
    check(CurrencyEngine.parseCurrencyQuery("1731830400") == nil, "Plain timestamp must not parse as currency")
    let cnyMid = CurrencyEngine.convert(amount: 100, from: "USD", to: "CNY", snapshot: CurrencyEngine.offlineFallbackSnapshot)!
    let cnyFee = CurrencyEngine.convert(amount: 100, from: "USD", to: "CNY", snapshot: CurrencyEngine.offlineFallbackSnapshot, feePercent: 2.0)!
    check(cnyMid > 600 && cnyMid < 800, "Currency USD -> CNY conversion")
    check(abs(cnyFee - cnyMid * 1.02) < 1e-6, "Currency spread fee multiplier")
    check(SmartDetector.detect("$199.50") == .currency, "SmartDetector currency")

    // 15. All ToolID tabs + jump routing (23 tools)
    let studio = StudioState()
    check(ToolID.allCases.count == 23, "23 Studio tools registered")
    for tool in ToolID.allCases {
        studio.jump(to: tool, searchTerm: tool == .hash ? "md5" : (tool == .codec ? "jwt" : ""))
        check(studio.activeTool == tool, "Switch tool \(tool.rawValue)")
    }
    studio.applyLaunch(toolRaw: "color", handoffSelected: nil, clipboardText: "#10B981")
    check(studio.colorInput == "#10B981", "Launch clipboard handoff to color")
    check(studio.hashFilterHint == "md5", "Hash search hint propagation")
    check(studio.codecTabHint == .jwt, "JWT subtab routing")

    print("\nSELF_TEST_OK")
    exit(0)
}

// MARK: - Studio Shell Views

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct StudioRootView: View {
    @Environment(StudioState.self) private var studio
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var studio = studio

        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 218)

                Divider()

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
            }

            if let toast = studio.toastText {
                Text(toast)
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(studio.toastIsError ? Color.red.opacity(0.92) : Color(nsColor: .controlAccentColor).opacity(0.95))
                            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    )
                    .foregroundStyle(.white)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: studio.toastText)
        .background(VisualEffectBackground().ignoresSafeArea())
        .onAppear {
            studio.onFocusSearch = { searchFocused = true }
        }
    }

    private var sidebarView: some View {
        @Bindable var studio = studio
        let visibleTools = studio.filteredTools()

        return VStack(spacing: 10) {
            HStack {
                Spacer().frame(width: 68)
                Spacer()
                Button {
                    let clip = ClipboardService.readString()
                    if clip.isEmpty {
                        studio.showToast("剪贴板为空", isError: true)
                    } else {
                        studio.applyLaunch(toolRaw: studio.activeTool.rawValue, handoffSelected: nil, clipboardText: clip)
                        studio.showToast("已将剪贴板内容载入当前工具")
                    }
                } label: {
                    Image(systemName: "clipboard")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.borderless)
                .help("从剪贴板载入到当前工具")

                Button {
                    studio.isPinnedOnTop.toggle()
                    studio.onPinChange?(studio.isPinnedOnTop)
                    studio.showToast(studio.isPinnedOnTop ? "已置顶悬浮" : "已取消置顶")
                } label: {
                    Image(systemName: studio.isPinnedOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(studio.isPinnedOnTop ? Color.accentColor : Color.secondary)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.borderless)
                .help("置顶窗口 (Float on Top)")
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("搜索工具或算法 (⌘F)…", text: $studio.sidebarSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = visibleTools.first {
                            studio.jump(to: first, searchTerm: studio.sidebarSearch)
                        }
                    }
                if !studio.sidebarSearch.isEmpty {
                    Button {
                        studio.sidebarSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ToolGroup.allCases, id: \.rawValue) { group in
                        let items = visibleTools.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.rawValue)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)

                                ForEach(items) { tool in
                                    SidebarToolButton(
                                        tool: tool,
                                        selected: studio.activeTool == tool,
                                        action: {
                                            studio.jump(to: tool, searchTerm: studio.sidebarSearch)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch studio.activeTool {
        case .smart: SmartClipboardView()
        case .uuid: UuidToolView()
        case .timestamp: TimestampToolView()
        case .hash: HashToolView()
        case .codec: CodecToolView()
        case .json: JsonToolView()
        case .color: ColorToolView()
        case .regex: RegexToolView()
        case .diff: DiffToolView()
        case .url: UrlCurlToolView()
        case .radix: RadixToolView()
        case .cidr: CidrToolView()
        case .dataFormat: DataFormatToolView()
        case .sql: SqlToolView()
        case .cert: CertToolView()
        case .ocr: OcrScannerToolView()
        case .image: ImageConverterToolView()
        case .currency: CurrencyToolView()
        case .password: PasswordToolView()
        case .text: TextToolView()
        case .qr: QrToolView()
        case .cron: CronToolView()
        case .network: NetworkToolView()
        }
    }
}

private struct SidebarToolButton: View {
    let tool: ToolID
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? .white : tool.accentColor)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? tool.accentColor : tool.accentColor.opacity(0.14))
                    )
                Text(tool.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.11) : (hovered ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - AppDelegate & Menu Setup

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let studio = StudioState()
    var window: NSWindow!
    var initialRequestId: String = ""
    private var lastHandledRequestId: String = ""
    private var lastActiveAt: Date = Date()
    private var idleTimer: Timer?
    private var activityMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastHandledRequestId = initialRequestId

        // Register IPC observer before constructing views/windows so rapid second clicks are never missed.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenNotification(_:)),
            name: kOpenNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()

        let args = CommandLine.arguments
        let initialTool = normalizeToolArg(decodeArgValue("--tool", in: args))
        let initialSelected = decodeBase64Arg("--selected", in: args) ?? decodeArgValue("--selected-text", in: args)
        let clip = ClipboardService.readString()
        studio.applyLaunch(toolRaw: initialTool, handoffSelected: initialSelected, clipboardText: clip)

        let rootView = StudioRootView().environment(studio)
        let hosting = NSHostingController(rootView: rootView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Tinycast DevKit Studio"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.minSize = NSSize(width: 840, height: 540)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentViewController = hosting
        win.delegate = self
        win.center()
        self.window = win

        studio.onPinChange = { [weak win] pinned in
            win?.level = pinned ? .floating : .normal
        }

        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown, .scrollWheel]) { [weak self] ev in
            self?.lastActiveAt = Date()
            return ev
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let idleSeconds = Date().timeIntervalSince(self.lastActiveAt)
                if !self.studio.isPinnedOnTop && !NSApp.isActive && idleSeconds > 600 {
                    NSApp.terminate(nil)
                }
            }
        }

        applyPendingDiskRequestIfNewer()
        summonWindow()
    }

    @objc private func handleOpenNotification(_ note: Notification) {
        lastActiveAt = Date()
        let info = note.userInfo ?? [:]
        var reqId = (info["requestId"] as? String) ?? ""
        var toolRaw = info["tool"] as? String
        var selectedB64 = info["selectedB64"] as? String

        if reqId.isEmpty,
           let data = try? Data(contentsOf: requestFileURL()),
           let req = try? JSONDecoder().decode(OpenRequest.self, from: data) {
            reqId = req.requestId
            if toolRaw == nil || toolRaw?.isEmpty == true { toolRaw = req.tool }
            if selectedB64 == nil || selectedB64?.isEmpty == true { selectedB64 = req.selectedB64 }
        }

        if !reqId.isEmpty && reqId == lastHandledRequestId {
            summonWindow()
            return
        }
        if !reqId.isEmpty { lastHandledRequestId = reqId }

        let tool = normalizeToolArg(toolRaw)
        let selected = (selectedB64?.isEmpty == false)
            ? Data(base64Encoded: selectedB64!).flatMap { String(data: $0, encoding: .utf8) }
            : nil
        let clip = ClipboardService.readString()
        studio.applyLaunch(toolRaw: tool, handoffSelected: selected, clipboardText: clip)
        summonWindow()
    }

    private func applyPendingDiskRequestIfNewer() {
        guard let data = try? Data(contentsOf: requestFileURL()),
              let req = try? JSONDecoder().decode(OpenRequest.self, from: data),
              Date().timeIntervalSince1970 - req.timestamp < 3.0,
              req.requestId != lastHandledRequestId else {
            return
        }
        lastHandledRequestId = req.requestId
        let tool = normalizeToolArg(req.tool)
        let selected = req.selectedB64.flatMap { !$0.isEmpty ? Data(base64Encoded: $0) : nil }
            .flatMap { String(data: $0, encoding: .utf8) }
        let clip = ClipboardService.readString()
        studio.applyLaunch(toolRaw: tool, handoffSelected: selected, clipboardText: clip)
    }

    private func summonWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        lastActiveAt = Date()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Do NOT delete the .lock file — the kernel releases flock() automatically on process exit.
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        idleTimer?.invalidate()
    }

    @objc private func focusSearchAction() {
        studio.onFocusSearch?()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Tinycast DevKit")
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 DevKit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let findItem = NSMenuItem(title: "聚焦侧边栏搜索", action: #selector(focusSearchAction), keyEquivalent: "f")
        findItem.target = self
        editMenu.addItem(findItem)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Program Entry Point

@main
@MainActor
struct DevKitStudioMain {
    static func main() {
        if ProcessInfo.processInfo.environment["TINYCAST_STUDIO_DRY_RUN"] == "1" {
            exit(0)
        }
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            runSelfTests()
        }

        let tool = normalizeToolArg(decodeArgValue("--tool", in: args))
        let selectedB64 = decodeArgValue("--selected", in: args)
        let reqId = coordinateSingleInstance(tool: tool, selectedB64: selectedB64)

        let app = NSApplication.shared
        let delegate = StudioAppDelegate()
        delegate.initialRequestId = reqId
        app.delegate = delegate
        app.run()
    }
}
