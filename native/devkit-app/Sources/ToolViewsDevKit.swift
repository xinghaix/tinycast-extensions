import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Tool Chrome & Flow Wrap Layout

struct FlowWrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += (x > 0 ? spacing : 0) + sz.width
            lineHeight = max(lineHeight, sz.height)
            usedWidth = max(usedWidth, x)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineHeight = max(lineHeight, sz.height)
        }
    }
}

struct ToolHeader: View {
    let tool: ToolID
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tool.accentColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tool.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - 1. Smart Clipboard Workbench

struct SmartClipboardView: View {
    @Environment(StudioState.self) private var studio
    @State private var sampleIndex = 0

    private static let samples: [(label: String, text: String)] = [
        ("Unix 时间戳", "1731830400"),
        ("品牌蓝 色值", "#3B82F6"),
        ("OKLCH 现代色", "oklch(62.3% 0.188 259.8)"),
        ("UUID v7", UUIDEngine.shared.generateV7()),
        ("JSON 片段", "{\"service\":\"tinycast\",\"native\":true,\"version\":2,\"tags\":[\"swiftui\",\"appkit\"]}"),
        ("Base64 文本", "SGVsbG8sIFdvcmxkISAtIFRpbnljYXN0IERldktpdA=="),
        ("JWT Token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzQyIiwibmFtZSI6IlRpbnljYXN0IiwiaWF0IjoxNzMxODMwNDAwfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
        ("CIDR 网段", "10.0.12.34/22"),
        ("cURL 请求", UrlCurlEngine.sampleCurl),
        ("SQL 参数日志", SqlEngine.sampleMyBatisLog),
        ("SSH 公钥", CertEngine.sampleSshKey),
    ]

    var body: some View {
        @Bindable var studio = studio
        let input = studio.smartInput
        let kind = SmartDetector.detect(input)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .smart, subtitle: "自动识别剪贴板中的 UUID / 时间戳 / JWT / JSON / 颜色 / Base64 / Hex / URL 并给出即时结果")

                StudioPanel {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(kind.label)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                        .foregroundStyle(.purple)

                        Text(verbatim: "\(input.count) 字符 · \(input.utf8.count) 字节")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        Spacer()

                        StudioToolBarButton(title: "从剪贴板读取", icon: "clipboard") {
                            let clip = ClipboardService.readString()
                            if clip.isEmpty {
                                studio.showToast("剪贴板当前为空文本", isError: true)
                            } else {
                                studio.smartInput = clip
                                studio.showToast("已读取剪贴板内容")
                            }
                        }
                        StudioToolBarButton(title: "换个示例", icon: "wand.and.stars") {
                            let pick = Self.samples[sampleIndex % Self.samples.count]
                            sampleIndex += 1
                            studio.smartInput = pick.text
                            studio.showToast("已填入示例: \(pick.label)")
                        }
                        if !input.isEmpty {
                            StudioToolBarButton(title: "清空", icon: "trash") {
                                studio.smartInput = ""
                            }
                        }
                    }

                    EditorBoxView(text: $studio.smartInput, height: 100)
                }

                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    StudioPanel {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("粘贴任意内容或点击右上角「从剪贴板读取」")
                                    .font(.system(size: 13, weight: .medium))
                                Text("支持 UUID/ULID/KSUID、Unix 时间戳/日期、JWT、JSON、URL Query、Base64/Hex 以及纯文本即时计算。")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                } else {
                    detectedSection(for: input, kind: kind)
                    universalSection(for: input)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func detectedSection(for raw: String, kind: SmartClipboardKind) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let idInfo = UUIDEngine.shared.inspect(trimmed) {
            StudioPanel(title: "识别为唯一标识符 · \(idInfo.label)") {
                CopyableResultRow(
                    title: "规范化格式", value: idInfo.normalized, badge: idInfo.version, badgeColor: .indigo,
                    secondaryButton: ("前往 UUID 工具", "arrow.right.circle", {
                        studio.uuidSeedInput = trimmed
                        studio.jump(to: .uuid)
                    })
                )
                if let iso = idInfo.timestampIso, let tsMs = idInfo.timestampMs {
                    let local = TimestampEngine.formatDate(Date(timeIntervalSince1970: Double(tsMs) / 1000.0), format: "yyyy-MM-dd HH:mm:ss.SSS")
                    CopyableResultRow(title: "内嵌时间 (本地)", value: local, badge: "\(tsMs) ms", badgeColor: .orange)
                    CopyableResultRow(title: "内嵌时间 (UTC ISO)", value: iso, badge: "UTC", badgeColor: .orange)
                }
                if let comp = idInfo.variants?.compact {
                    CopyableResultRow(title: "无连字符形式", value: comp, badge: "32 hex")
                }
            }
        }

        if let parsedTs = TimestampEngine.parse(trimmed), !parsedTs.isLive {
            let report = TimestampEngine.buildReport(parsedTs)
            StudioPanel(title: "识别为时间表达 · \(parsedTs.detectedKind)") {
                HStack {
                    Text("相对当前: \(report.relativeLabel) · \(report.isoWeek)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StudioToolBarButton(title: "前往时间戳工具 →", icon: "clock") {
                        studio.timestampInput = trimmed
                        studio.jump(to: .timestamp)
                    }
                }
                ForEach(report.entries.prefix(6)) { entry in
                    CopyableResultRow(title: entry.title, value: entry.value, badge: entry.badge, badgeColor: .orange)
                }
            }
        }

        if let jwt = CodecEngine.decodeJwt(trimmed) {
            StudioPanel(title: "识别为 JWT Token") {
                HStack {
                    Text("算法: \(jwt.algorithm)" + (jwt.isExpired == true ? " · 已过期" : (jwt.isExpired == false ? " · 未过期" : "")))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(jwt.isExpired == true ? .red : .green)
                    Spacer()
                    StudioToolBarButton(title: "前往 JWT 验签 →", icon: "checkmark.shield") {
                        studio.codecInput = trimmed
                        studio.jump(to: .codec, searchTerm: "jwt")
                    }
                }
                CopyableResultRow(title: "Payload JSON", value: jwt.payloadJson, badge: jwt.algorithm, badgeColor: .purple)
                CopyableResultRow(title: "Header JSON", value: jwt.headerJson, badge: "Header", badgeColor: .purple)
            }
        }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let jsonRes = JsonEngine.analyze(trimmed)
            if jsonRes.valid {
                StudioPanel(title: jsonRes.repaired ? "识别为宽松 JSON (已自动修复)" : "识别为 JSON payload") {
                    HStack {
                        if let st = jsonRes.stats {
                            Text(verbatim: "\(st.rootType) · \(st.keyCount) keys · 深度 \(st.maxDepth)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StudioToolBarButton(title: "前往 JSON 工作台 →", icon: "curlybraces") {
                            studio.jsonInput = trimmed
                            studio.jump(to: .json)
                        }
                    }
                    if let p2 = jsonRes.pretty2 {
                        CopyableResultRow(title: "格式化 (2 空格)", value: p2, badge: "Pretty", badgeColor: .cyan)
                    }
                    if let min = jsonRes.minified {
                        CopyableResultRow(title: "单行压缩", value: min, badge: "Minify", badgeColor: .cyan)
                    }
                }
            }
        }

        if kind == .color, let colorVal = ColorEngine.parse(trimmed) {
            let formats = ColorEngine.formatAll(colorVal)
            let matches = ColorEngine.nearestNamedMatches(to: colorVal)
            StudioPanel(title: "识别为颜色值 · \(colorVal.hexAutoUpper)") {
                HStack(spacing: 12) {
                    ColorSwatchTile(color: colorVal, cornerRadius: 8)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        if let css = matches.css {
                            Text("最接近 CSS: \(css.name) (\(css.hex))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        if let tw = matches.tailwind {
                            Text("最接近 Tailwind: \(tw.name) (\(tw.hex))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StudioToolBarButton(title: "前往色值与取色 →", icon: "paintpalette") {
                        studio.colorInput = trimmed
                        studio.jump(to: .color)
                    }
                }
                ForEach(formats.filter { ["hex-auto-lower", "rgb-legacy", "hsl-legacy", "oklch", "swiftui", "android-argb"].contains($0.id) }) { entry in
                    CopyableResultRow(title: entry.title, value: entry.value, badge: entry.badge, badgeColor: .pink)
                }
            }
        }

        if kind == .certOrSsh {
            StudioPanel(title: "识别为 X.509 证书 / SSH 公钥") {
                HStack {
                    if let ssh = CertEngine.parseSshPublicKey(trimmed) {
                        Text("\(ssh.algorithmLabel) (\(ssh.bitLength)-bit) · \(ssh.sha256Fingerprint)")
                            .font(.system(size: 11.5, design: .monospaced))
                    } else {
                        Text("检测到 PEM/DER X.509 证书")
                            .font(.system(size: 11.5))
                    }
                    Spacer()
                    StudioToolBarButton(title: "前往证书 / SSH 解析 →", icon: "checkmark.seal", tint: .green) {
                        studio.certInput = trimmed
                        studio.jump(to: .cert)
                    }
                }
            }
        }

        if kind == .curl, let req = try? UrlCurlEngine.parseCurl(trimmed) {
            StudioPanel(title: "识别为 cURL 命令 · \(req.method)") {
                HStack {
                    Text(req.url)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    StudioToolBarButton(title: "转换为 Fetch / Python / Go →", icon: "link", tint: .cyan) {
                        studio.curlInput = trimmed
                        studio.urlTabHint = .curlConverter
                        studio.jump(to: .url)
                    }
                }
                CopyableResultRow(title: "JavaScript fetch 预览", value: UrlCurlEngine.toFetch(req), badge: req.method, badgeColor: .cyan)
            }
        }

        if kind == .url, let urlModel = UrlCurlEngine.parseUrl(trimmed) {
            StudioPanel(title: "识别为 URL · \(urlModel.params.count) 个 Query 参数") {
                HStack {
                    Text(urlModel.host.isEmpty ? urlModel.path : urlModel.host)
                        .font(.system(size: 11.5, design: .monospaced))
                    Spacer()
                    StudioToolBarButton(title: "编辑 URL 参数 →", icon: "link", tint: .cyan) {
                        studio.urlInput = trimmed
                        studio.urlTabHint = .urlParser
                        studio.jump(to: .url)
                    }
                }
                ForEach(urlModel.params.prefix(5)) { p in
                    CopyableResultRow(title: "Query: \(p.key)", value: p.value, badge: "Param", badgeColor: .cyan)
                }
            }
        }

        if kind == .cidr {
            if let v4 = CidrEngine.parseIpv4Cidr(trimmed) {
                StudioPanel(title: "识别为 IPv4 网段 · \(v4.cidrNotation)") {
                    HStack {
                        BadgePill(text: v4.scope, color: .teal)
                        BadgePill(text: "\(v4.usableCount) 可用 IP", color: .green)
                        Spacer()
                        StudioToolBarButton(title: "前往 CIDR 计算器 →", icon: "point.3.connected.trianglepath.dotted", tint: .teal) {
                            studio.cidrInput = trimmed
                            studio.jump(to: .cidr)
                        }
                    }
                    CopyableResultRow(title: "可用范围", value: "\(v4.firstHost) – \(v4.lastHost)", badge: v4.netmask, badgeColor: .teal)
                }
            } else if let v6 = CidrEngine.parseIpv6Cidr(trimmed) {
                StudioPanel(title: "识别为 IPv6 网段 · \(v6.cidrNotation)") {
                    HStack {
                        BadgePill(text: v6.scope, color: .teal)
                        Spacer()
                        StudioToolBarButton(title: "前往 CIDR 计算器 →", icon: "point.3.connected.trianglepath.dotted", tint: .teal) {
                            studio.cidrInput = trimmed
                            studio.jump(to: .cidr)
                        }
                    }
                    CopyableResultRow(title: "网段范围", value: "\(v6.compressedNetwork) – \(v6.compressedEnd)")
                }
            }
        }

        if kind == .sql {
            let bound = SqlEngine.bindParameters(sqlOrLog: trimmed, manualParams: "", formatOutput: true)
            StudioPanel(title: "识别为 SQL / ORM 日志") {
                HStack {
                    BadgePill(text: bound.detectedFormat, color: .blue)
                    Spacer()
                    StudioToolBarButton(title: "前往 SQL & 日志工具 →", icon: "cylinder.split.1x2", tint: .blue) {
                        studio.sqlInput = trimmed
                        studio.jump(to: .sql)
                    }
                }
                CopyableResultRow(title: "格式化 SQL 预览", value: bound.formattedSql, badge: "SQL", badgeColor: .blue)
            }
        }

        let plausibleCodecs = CodecEngine.runAllCodecs(trimmed).filter(\.plausible)
        if !plausibleCodecs.isEmpty && kind != .json {
            StudioPanel(title: "可解码候选") {
                ForEach(plausibleCodecs) { item in
                    CopyableResultRow(
                        title: item.title, value: item.output, badge: item.badge, badgeColor: .purple,
                        secondaryButton: ("编解码器", "arrow.right.circle", {
                            studio.codecInput = trimmed
                            studio.jump(to: .codec)
                        })
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func universalSection(for raw: String) -> some View {
        let hashes = HashEngine.computeAll(data: Data(raw.utf8), includeNonCrypto: false)
        let sha256 = hashes.first(where: { $0.id == "sha256" })?.digest ?? ""
        let md5 = hashes.first(where: { $0.id == "md5" })?.digest ?? ""
        let b64 = Data(raw.utf8).base64EncodedString()
        let qrPreview = raw.utf8.count <= 900 ? QrEngine.generate(text: raw, level: .M, size: 120) : nil

        StudioPanel(title: "通用速算与一键流转") {
            CopyableResultRow(
                title: "SHA-256", value: sha256, badge: "256b", badgeColor: .green,
                secondaryButton: ("更多 Hash", "lock.shield", {
                    studio.hashInput = raw
                    studio.jump(to: .hash)
                })
            )
            CopyableResultRow(title: "MD5", value: md5, badge: "128b", badgeColor: .green)
            CopyableResultRow(title: "Base64 编码", value: b64, badge: "UTF-8", badgeColor: .purple)

            if raw.count <= 80 && !raw.contains("\n") {
                CopyableResultRow(
                    title: "camelCase / snake_case", value: "\(TextEngine.camelCase(raw))  |  \(TextEngine.snakeCase(raw))", badge: "命名", badgeColor: .blue,
                    secondaryButton: ("全部文本工具", "doc.plaintext", {
                        studio.textInput = raw
                        studio.jump(to: .text)
                    })
                )
            }

            HStack(spacing: 12) {
                if let qr = qrPreview {
                    Image(nsImage: qr.image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 68, height: 68)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("将当前输入发送至专项工具继续编辑：")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        StudioToolBarButton(title: "文本大小写 & 行处理", icon: "doc.plaintext") {
                            studio.textInput = raw
                            studio.jump(to: .text)
                        }
                        StudioToolBarButton(title: "JSON 工具", icon: "curlybraces") {
                            studio.jsonInput = raw
                            studio.jump(to: .json)
                        }
                        StudioToolBarButton(title: "Regex 正则", icon: "text.magnifyingglass") {
                            studio.regexInput = raw
                            studio.jump(to: .regex)
                        }
                        StudioToolBarButton(title: "文本对比 (Diff)", icon: "arrow.left.arrow.right.square") {
                            studio.diffLeft = raw
                            studio.jump(to: .diff)
                        }
                        StudioToolBarButton(title: "生成大图二维码", icon: "qrcode") {
                            studio.qrInput = raw
                            studio.jump(to: .qr)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - 2. UUID & ID Generator + Inspector

enum UuidBatchJoin: String, CaseIterable, Sendable {
    case newline, json, csv, sqlIn

    var title: String {
        switch self {
        case .newline: return "按行"
        case .json: return "JSON"
        case .csv: return "CSV"
        case .sqlIn: return "SQL IN"
        }
    }
}

struct UuidToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var selectedKind: IdKind = .v7
    @State private var selectedFormat: UuidVersionFormat = .standard
    @State private var batchCount: Int = 1
    @State private var joinMode: UuidBatchJoin = .newline
    @State private var namespace: UuidNamespace = .dns
    @State private var nameSeed: String = "example.com"
    @State private var nanoLength: Int = 21
    @State private var generatedValues: [String] = [UUIDEngine.shared.generate(kind: .v7)]

    private var joinedOutput: String {
        switch joinMode {
        case .newline: return generatedValues.joined(separator: "\n")
        case .json:
            let data = try? JSONSerialization.data(withJSONObject: generatedValues, options: [.prettyPrinted])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        case .csv: return generatedValues.joined(separator: ", ")
        case .sqlIn: return "(" + generatedValues.map { "'\($0)'" }.joined(separator: ", ") + ")"
        }
    }

    var body: some View {
        @Bindable var studio = studio
        let inspectText = studio.uuidSeedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let inspected = UUIDEngine.shared.inspect(inspectText)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .uuid, subtitle: "全版本 RFC 9562 UUID (v1–v8/Nil/Max) + ULID / NanoID / KSUID / ObjectID 生成、批量与解析")

                StudioPanel(title: "1. ID 生成器 · \(selectedKind.title)") {
                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(IdKind.allCases, id: \.rawValue) { kind in
                            PillButton(title: kind.shortLabel, active: selectedKind == kind, color: .indigo) {
                                selectedKind = kind
                                regenerate()
                            }
                        }
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(UuidVersionFormat.allCases, id: \.rawValue) { fmt in
                            PillButton(title: fmt.title, active: selectedFormat == fmt, color: .blue) {
                                selectedFormat = fmt
                                regenerate()
                            }
                        }
                    }

                    if selectedKind.supportsSeed {
                        HStack(spacing: 8) {
                            if selectedKind.needsNamespace {
                                ForEach(UuidNamespace.allCases, id: \.rawValue) { ns in
                                    PillButton(title: ns.title, active: namespace == ns, color: .purple) {
                                        namespace = ns
                                        regenerate()
                                    }
                                }
                            }
                            TextField(selectedKind == .v8 ? "输入自定义种子字符串（留空随机）" : "输入名称（如 example.com）", text: $nameSeed)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: nameSeed) { _, _ in regenerate() }
                        }
                    }

                    if selectedKind == .nanoid {
                        HStack(spacing: 6) {
                            Text("NanoID 长度:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            ForEach([12, 16, 21, 32, 48], id: \.self) { len in
                                PillButton(title: "\(len)", active: nanoLength == len, color: .indigo) {
                                    nanoLength = len
                                    regenerate()
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("数量:")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        ForEach([1, 5, 10, 20, 50], id: \.self) { cnt in
                            PillButton(title: "\(cnt)", active: batchCount == cnt, color: .indigo) {
                                batchCount = cnt
                                regenerate()
                            }
                        }

                        if batchCount > 1 {
                            Divider().frame(height: 18)
                            ForEach(UuidBatchJoin.allCases, id: \.rawValue) { mode in
                                PillButton(title: mode.title, active: joinMode == mode, color: .teal) {
                                    joinMode = mode
                                }
                            }
                        }

                        Spacer()

                        StudioToolBarButton(title: "重新生成", icon: "arrow.clockwise", tint: .indigo) {
                            regenerate()
                        }
                        CopyActionButton(text: joinedOutput, label: batchCount > 1 ? "复制全部 (\(batchCount))" : "复制") { _ in
                            studio.showToast("已复制生成结果")
                        }
                    }

                    if batchCount == 1, let single = generatedValues.first {
                        CopyableResultRow(
                            title: selectedKind.title, value: single, badge: selectedFormat.title, badgeColor: .indigo,
                            secondaryButton: ("送入下方解析", "magnifyingglass", {
                                studio.uuidSeedInput = single
                            })
                        )
                    } else {
                        EditorBoxView(text: .constant(joinedOutput), isEditable: false, height: 150)
                    }
                }

                StudioPanel(title: "2. ID 解析器 & 全衍生格式") {
                    HStack(spacing: 8) {
                        TextField("粘贴任意 UUID (v1-v8/URN/{...}/32位) / ULID / KSUID / ObjectID 自动拆解…", text: $studio.uuidSeedInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5, design: .monospaced))
                        StudioToolBarButton(title: "剪贴板", icon: "clipboard") {
                            let clip = ClipboardService.readString()
                            if !clip.isEmpty { studio.uuidSeedInput = clip }
                        }
                        StudioToolBarButton(title: "解析当前生成", icon: "arrow.down.doc") {
                            studio.uuidSeedInput = generatedValues.first ?? ""
                        }
                    }

                    if let inspected {
                        FlowWrapLayout(spacing: 8, lineSpacing: 6) {
                            BadgePill(text: inspected.label, color: .indigo)
                            BadgePill(text: inspected.variant, color: .blue)
                            BadgePill(text: inspected.sortable ? "可按时间排序" : "随机/固定顺序", color: inspected.sortable ? .green : .secondary)
                            BadgePill(text: "随机熵 \(inspected.entropyBits) bits", color: .purple)
                            if let node = inspected.nodeHex {
                                BadgePill(text: "Node \(node)", color: .teal)
                            }
                            if let seq = inspected.clockSeq {
                                BadgePill(text: "ClockSeq \(seq)", color: .teal)
                            }
                        }

                        if let tsMs = inspected.timestampMs {
                            let local = TimestampEngine.formatDate(Date(timeIntervalSince1970: Double(tsMs) / 1000.0), format: "yyyy-MM-dd HH:mm:ss.SSS")
                            CopyableResultRow(title: "提取内嵌时间 (本地)", value: local, badge: "\(tsMs) ms", badgeColor: .orange)
                            if let iso = inspected.timestampIso {
                                CopyableResultRow(title: "提取内嵌时间 (UTC ISO 8601)", value: iso, badge: "UTC", badgeColor: .orange)
                            }
                        }

                        if let variants = inspected.variants {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(variants.allRows, id: \.0) { row in
                                    CopyableResultRow(title: row.0, value: row.1)
                                }
                            }
                        }
                    } else if !inspectText.isEmpty {
                        Text("无法识别为标准 UUID / ULID / KSUID / ObjectID，请检查格式或长度。")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    } else {
                        Text("在上方生成或粘贴任意 ID，即可查看版本、嵌入时间、随机熵和全部衍生编码。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private func regenerate() {
        let count = selectedKind == .nilUuid || selectedKind == .maxUuid ? min(batchCount, 5) : batchCount
        generatedValues = (0..<count).map { _ in
            UUIDEngine.shared.generate(
                kind: selectedKind,
                format: selectedFormat,
                name: nameSeed,
                namespace: namespace,
                seed: selectedKind == .v8 ? nameSeed : nil,
                nanoLength: nanoLength
            )
        }
    }
}

struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

// MARK: - 3. Timestamp Converter

struct TimestampToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var isLiveClock: Bool = true
    @State private var liveNow: Date = Date()
    @State private var selectedCategory: TimestampEntry.Category? = nil
    @State private var pickedDate: Date = Date()

    var body: some View {
        @Bindable var studio = studio
        let parsed = TimestampEngine.parse(studio.timestampInput, now: liveNow)
        let report = parsed.map { TimestampEngine.buildReport($0, now: liveNow) }
        let isLiveInput = studio.timestampInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .timestamp, subtitle: "实时时钟 + 自动识别 Unix s/ms/μs/ns、ISO 8601、紧凑日期、相对表达式 (+2h, today-1d) 与全球时区")

                // Live Clock Banner
                StudioPanel {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isLiveClock ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(isLiveClock ? "实时时钟" : "已暂停")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(TimestampEngine.formatDate(liveNow, format: "yyyy-MM-dd HH:mm:ss"))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            let nowSec = Int64(floor(liveNow.timeIntervalSince1970))
                            let nowMs = Int64((liveNow.timeIntervalSince1970 * 1000.0).rounded())
                            Text(verbatim: "Unix s: \(nowSec)   ·   ms: \(nowMs)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        StudioToolBarButton(title: isLiveClock ? "暂停" : "恢复", icon: isLiveClock ? "pause.fill" : "play.fill") {
                            isLiveClock.toggle()
                        }
                        StudioToolBarButton(title: "填入当前", icon: "arrow.down.circle") {
                            studio.timestampInput = "\(Int64(floor(liveNow.timeIntervalSince1970)))"
                        }
                        CopyActionButton(text: "\(Int64(floor(liveNow.timeIntervalSince1970)))", label: "复制秒") { _ in
                            studio.showToast("已复制当前 Unix 秒")
                        }
                        CopyActionButton(text: "\(Int64((liveNow.timeIntervalSince1970 * 1000.0).rounded()))", label: "复制毫秒") { _ in
                            studio.showToast("已复制当前 Unix 毫秒")
                        }
                    }
                }

                // Input + DatePicker + Quick Offset
                StudioPanel {
                    HStack(spacing: 8) {
                        TextField("输入 Unix s/ms/μs/ns、YYYY-MM-DD HH:mm:ss、ISO 8601、+2h、today+1d（留空跟随实时）", text: $studio.timestampInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5, design: .monospaced))
                        DatePicker("", selection: $pickedDate, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .onChange(of: pickedDate) { _, newDate in
                                studio.timestampInput = TimestampEngine.formatDate(newDate, format: "yyyy-MM-dd HH:mm:ss")
                            }
                        StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                            let clip = ClipboardService.readString()
                            if !clip.isEmpty { studio.timestampInput = clip }
                        }
                        if !isLiveInput {
                            StudioToolBarButton(title: "回到实时", icon: "arrow.uturn.backward") {
                                studio.timestampInput = ""
                            }
                        }
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach([
                            ("-7天", "-7d"), ("-1天", "-1d"), ("-1小时", "-1h"),
                            ("今日零点", "today"), ("今日末刻", "eod"),
                            ("+1小时", "+1h"), ("+1天", "+1d"), ("+7天", "+7d"),
                        ], id: \.0) { label, expr in
                            PillButton(title: label, active: false, color: .orange) {
                                let base = parsed?.date ?? liveNow
                                if expr == "today" || expr == "eod" {
                                    studio.timestampInput = expr
                                } else if let p = TimestampEngine.parse(expr, now: base) {
                                    studio.timestampInput = "\(Int64(floor(p.date.timeIntervalSince1970)))"
                                }
                            }
                        }
                    }
                }

                if let report {
                    HStack(spacing: 8) {
                        BadgePill(text: report.parsed.detectedKind, color: .orange)
                        BadgePill(text: report.relativeLabel, color: .blue)
                        BadgePill(text: "\(report.isoWeek) · Q\(report.quarter) · 第 \(report.dayOfYear) 天", color: .secondary)
                        Spacer()
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        PillButton(title: "全部", active: selectedCategory == nil, color: .orange) {
                            selectedCategory = nil
                        }
                        ForEach(TimestampEntry.Category.allCases, id: \.rawValue) { cat in
                            PillButton(title: cat.title, active: selectedCategory == cat, color: .orange) {
                                selectedCategory = cat
                            }
                        }
                    }

                    let filtered = report.entries.filter { selectedCategory == nil || $0.category == selectedCategory }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(filtered) { entry in
                            CopyableResultRow(title: entry.title, value: entry.value, badge: entry.badge, badgeColor: .orange)
                        }
                    }
                } else {
                    StudioPanel {
                        Text("无法解析该时间字符串。支持格式示例：1731830400、1731830400123、2026-11-17 18:30:00、20261117、now、today+1d、+2h。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
        .task(id: isLiveClock && studio.activeTool == .timestamp && isLiveInput) {
            guard isLiveClock && studio.activeTool == .timestamp else { return }
            while !Task.isCancelled {
                liveNow = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - 4. Hash & File Checksum View

struct HashToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var inputEncoding: HashInputEncoding = .utf8
    @State private var outputEncoding: HashOutputEncoding = .hex
    @State private var includeNonCrypto: Bool = true
    @State private var hmacKey: String = ""
    @State private var expectedHash: String = ""

    @State private var fileURL: URL? = nil
    @State private var fileSize: UInt64 = 0
    @State private var fileProgress: Double = 0
    @State private var isHashingFile: Bool = false
    @State private var fileResults: [HashResult] = []
    @State private var fileError: String? = nil

    var body: some View {
        @Bindable var studio = studio
        let filterQuery = studio.hashFilterHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let textComputation: (results: [HashResult], error: String?) = {
            do {
                let data = try HashEngine.decodeInput(studio.hashInput, encoding: inputEncoding)
                let keyData = hmacKey.isEmpty ? nil : Data(hmacKey.utf8)
                return (HashEngine.computeAll(data: data, outputEncoding: outputEncoding, hmacKey: keyData, includeNonCrypto: includeNonCrypto), nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }()

        let activeResults = fileURL != nil ? fileResults : textComputation.results
        let visibleResults = filterQuery.isEmpty
            ? activeResults
            : activeResults.filter { $0.name.lowercased().contains(filterQuery) || $0.id.lowercased().contains(filterQuery) }
        let matchedAlgo = expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : activeResults.first(where: { $0.matchesExpected(expectedHash) })

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .hash, subtitle: "MD5 / SHA-1/2/3 / Keccak / BLAKE3 / BLAKE2 / 国密 SM3 / RIPEMD-160 / HMAC / CRC32 & 大文件流式校验")

                StudioPanel {
                    HStack(spacing: 6) {
                        Text("输入:")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        ForEach(HashInputEncoding.allCases, id: \.rawValue) { enc in
                            PillButton(title: enc.title, active: inputEncoding == enc, color: .green) {
                                inputEncoding = enc
                            }
                        }

                        Divider().frame(height: 16)
                        Text("输出:")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        ForEach(HashOutputEncoding.allCases, id: \.rawValue) { out in
                            PillButton(title: out.title, active: outputEncoding == out, color: .blue) {
                                outputEncoding = out
                                if let url = fileURL { startFileHash(url) }
                            }
                        }

                        Spacer()

                        StudioToolBarButton(title: "选择文件", icon: "folder") {
                            chooseFile()
                        }
                        if fileURL == nil {
                            StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                                let clip = ClipboardService.readString()
                                if !clip.isEmpty { studio.hashInput = clip }
                            }
                        }
                    }

                    if let url = fileURL {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.green)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold))
                                if fileSize > 0 {
                                    Text("(\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StudioToolBarButton(title: "切换回文本模式", icon: "text.alignleft") {
                                    fileURL = nil
                                    fileResults = []
                                    fileError = nil
                                }
                            }
                            if isHashingFile {
                                ProgressView(value: fileProgress)
                                    .progressViewStyle(.linear)
                            }
                            if let fileError {
                                Text(fileError).font(.system(size: 12)).foregroundStyle(.red)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
                    } else {
                        EditorBoxView(text: $studio.hashInput, height: 100)
                            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                                guard let first = providers.first else { return false }
                                _ = first.loadObject(ofClass: URL.self) { url, _ in
                                    if let url {
                                        Task { @MainActor in startFileHash(url) }
                                    }
                                }
                                return true
                            }
                        if let err = textComputation.error {
                            Text(err).font(.system(size: 12)).foregroundStyle(.red)
                        }
                    }

                    HStack(spacing: 8) {
                        if fileURL == nil {
                            TextField("可选 HMAC 密钥 (仅作用于加密 Hash)", text: $hmacKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        TextField("期望校验值比对 (自动高亮匹配)", text: $expectedHash)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        TextField("筛选算法 (如 sha256, sm3, crc32)", text: $studio.hashFilterHint)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 210)
                        Toggle("非加密校验码", isOn: $includeNonCrypto)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                    }

                    if !expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let matchedAlgo {
                            BadgePill(text: "✓ 校验通过 · 匹配 \(matchedAlgo.name)", color: .green)
                        } else {
                            BadgePill(text: "✗ 未匹配当前输入生成的任何摘要", color: .orange)
                        }
                    }
                }

                ForEach(HashCategory.allCases, id: \.rawValue) { category in
                    let group = visibleResults.filter { $0.category == category }
                    if !group.isEmpty {
                        StudioPanel(title: category.title) {
                            ForEach(group) { item in
                                let isMatch = item.matchesExpected(expectedHash)
                                CopyableResultRow(
                                    title: "\(item.name) · \(item.bits)b",
                                    value: item.digest,
                                    badge: isMatch ? "✓ 校验匹配" : (item.isHmac ? "HMAC" : nil),
                                    badgeColor: isMatch ? .green : .orange
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要流式计算 Hash 与校验码的本地文件（支持 GB 级大文件）"
        if panel.runModal() == .OK, let url = panel.url {
            startFileHash(url)
        }
    }

    private func startFileHash(_ url: URL) {
        fileURL = url
        isHashingFile = true
        fileProgress = 0
        fileError = nil
        let enc = outputEncoding
        Task.detached(priority: .userInitiated) {
            do {
                let res = try HashEngine.hashFileStreaming(url: url, outputEncoding: enc) { pct in
                    Task { @MainActor in fileProgress = pct }
                }
                await MainActor.run {
                    fileSize = res.size
                    fileResults = res.results
                    isHashingFile = false
                }
            } catch {
                await MainActor.run {
                    fileError = error.localizedDescription
                    isHashingFile = false
                }
            }
        }
    }
}

// MARK: - 5. Codec, JWT & AES-256

struct CodecToolView: View {
    @Environment(StudioState.self) private var studio

    // Bidirectional tab state
    @State private var selectedOp: CodecOp = .base64
    @State private var bidirEncodeDirection: Bool = true
    @State private var matrixFilter: String = ""

    // JWT tab state
    @State private var jwtSecret: String = "secret"

    // AES tab state
    @State private var aesMode: AesMode = .gcm
    @State private var aesKdf: AesKeyDerivation = .pbkdf2
    @State private var aesSecret: String = "my-secret-passphrase"
    @State private var aesOutput: String = ""
    @State private var aesError: String? = nil

    var body: some View {
        @Bindable var studio = studio

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .codec, subtitle: "双向工作台、全算法自动识别速览、JWT Header/Payload 拆解验签 & 原生 AES-256-GCM/CBC")

                HStack(spacing: 6) {
                    ForEach(CodecSubTab.allCases, id: \.rawValue) { tab in
                        PillButton(title: tab.rawValue, active: studio.codecTabHint == tab, color: .purple) {
                            studio.codecTabHint = tab
                        }
                    }
                    Spacer()
                }

                switch studio.codecTabHint {
                case .bidirectional: bidirectionalView
                case .matrix: matrixView
                case .jwt: jwtView
                case .aes: aesView
                }
            }
            .padding(16)
        }
    }

    private var bidirectionalView: some View {
        @Bindable var studio = studio
        let computed: (out: String, err: String?) = {
            do {
                return (try CodecEngine.runBidirectional(studio.codecInput, op: selectedOp, encode: bidirEncodeDirection), nil)
            } catch {
                return ("", error.localizedDescription)
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            StudioPanel {
                FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(CodecOp.allCases, id: \.rawValue) { op in
                        PillButton(title: op.title, active: selectedOp == op, color: .purple) {
                            selectedOp = op
                        }
                    }
                }

                HStack(spacing: 8) {
                    PillButton(title: "编码 →", active: bidirEncodeDirection, color: .green) {
                        bidirEncodeDirection = true
                    }
                    PillButton(title: "← 解码", active: !bidirEncodeDirection, color: .blue) {
                        bidirEncodeDirection = false
                    }
                    StudioToolBarButton(title: "⇅ 互换输入输出", icon: "arrow.left.arrow.right") {
                        if !computed.out.isEmpty {
                            studio.codecInput = computed.out
                            bidirEncodeDirection.toggle()
                        }
                    }
                    StudioToolBarButton(title: "粘贴输入", icon: "clipboard") {
                        let clip = ClipboardService.readString()
                        if !clip.isEmpty { studio.codecInput = clip }
                    }
                    Spacer()
                    CopyActionButton(text: computed.out, label: "复制输出") { _ in
                        studio.showToast("已复制转换结果")
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                StudioPanel(title: "输入文本 (\(studio.codecInput.utf8.count) B)") {
                    EditorBoxView(text: $studio.codecInput, height: 260)
                }
                StudioPanel(title: "\(selectedOp.title) \(bidirEncodeDirection ? "编码结果" : "解码结果")") {
                    EditorBoxView(text: .constant(computed.out), isEditable: false, height: 260)
                    if let err = computed.err {
                        Text(err).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var matrixView: some View {
        @Bindable var studio = studio
        let all = CodecEngine.runAllCodecs(studio.codecInput)
        let q = matrixFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || $0.badge.lowercased().contains(q) }
        let plausible = visible.filter(\.plausible)
        let regular = visible.filter { !$0.plausible }

        return VStack(alignment: .leading, spacing: 10) {
            StudioPanel {
                HStack(spacing: 8) {
                    TextField("筛选算法…", text: $matrixFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Spacer()
                    StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                        let clip = ClipboardService.readString()
                        if !clip.isEmpty { studio.codecInput = clip }
                    }
                    StudioToolBarButton(title: "清空", icon: "trash") {
                        studio.codecInput = ""
                    }
                }
                EditorBoxView(text: $studio.codecInput, height: 95)
            }

            if !plausible.isEmpty {
                StudioPanel(title: "智能识别 / 可直接解码") {
                    ForEach(plausible) { entry in
                        CopyableResultRow(
                            title: entry.title, value: entry.output, badge: entry.badge, badgeColor: .green,
                            secondaryButton: ("设为输入", "arrow.up.left.square", { studio.codecInput = entry.output })
                        )
                    }
                }
            }

            StudioPanel(title: "全算法编码矩阵") {
                ForEach(regular) { entry in
                    CopyableResultRow(
                        title: entry.title, value: entry.output, badge: entry.badge, badgeColor: .purple,
                        secondaryButton: ("设为输入", "arrow.up.left.square", { studio.codecInput = entry.output })
                    )
                }
            }
        }
    }

    private var jwtView: some View {
        @Bindable var studio = studio
        let decoded = CodecEngine.decodeJwt(studio.codecInput)
        let verify = decoded.map { _ in CodecEngine.verifyJwtHmac(token: studio.codecInput, secret: jwtSecret) }

        return HStack(alignment: .top, spacing: 12) {
            StudioPanel(title: "JWT Token 与签名验证") {
                HStack {
                    StudioToolBarButton(title: "填入示例 JWT", icon: "wand.and.stars") {
                        studio.codecInput = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzQyIiwibmFtZSI6IlRpbnljYXN0IiwiaWF0IjoxNzMxODMwNDAwfQ.M8uM4qP2zN0wU6mY7uI6pR3hX5jK1tW7F4h3Z2qP5oY"
                    }
                    StudioToolBarButton(title: "剪贴板", icon: "clipboard") {
                        let clip = ClipboardService.readString()
                        if !clip.isEmpty { studio.codecInput = clip }
                    }
                }
                EditorBoxView(text: $studio.codecInput, height: 170)

                Text("HMAC 验签 Secret (HS256 / HS384 / HS512):")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("输入验签密钥…", text: $jwtSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))

                if let verify {
                    if verify.supported {
                        BadgePill(
                            text: verify.valid ? "✓ 签名有效 (\(verify.algorithm))" : "✗ 签名不匹配 (\(verify.algorithm))",
                            color: verify.valid ? .green : .red
                        )
                    } else {
                        BadgePill(text: "算法 \(verify.algorithm) · 当前支持 HS256/384/512 本地验签", color: .orange)
                    }
                }
            }

            StudioPanel(title: "拆解结果") {
                if let decoded {
                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        BadgePill(text: decoded.algorithm, color: .purple)
                        if let exp = decoded.isExpired {
                            BadgePill(text: exp ? "已过期" : "有效期内", color: exp ? .red : .green)
                        }
                        if let iat = decoded.issuedAt { BadgePill(text: "签发 \(iat)", color: .secondary) }
                        if let expAt = decoded.expiresAt { BadgePill(text: "过期 \(expAt)", color: .secondary) }
                    }
                    CopyableResultRow(title: "Header", value: decoded.headerJson, badge: "JSON", badgeColor: .purple)
                    CopyableResultRow(title: "Payload", value: decoded.payloadJson, badge: "Claims", badgeColor: .indigo)
                    CopyableResultRow(title: "Signature (Base64URL)", value: decoded.signatureB64Url, badge: decoded.algorithm)
                } else {
                    Text("请在左栏粘贴三段式 JWT Token (`header.payload.signature`)。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var aesView: some View {
        @Bindable var studio = studio
        return VStack(alignment: .leading, spacing: 10) {
            StudioPanel {
                HStack(spacing: 8) {
                    Picker("模式", selection: $aesMode) {
                        ForEach(AesMode.allCases, id: \.rawValue) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .frame(maxWidth: 230)

                    Picker("密钥派生", selection: $aesKdf) {
                        ForEach(AesKeyDerivation.allCases, id: \.rawValue) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    .frame(maxWidth: 250)

                    Spacer()
                }

                HStack(spacing: 8) {
                    TextField(aesKdf == .hex ? "输入 64 位十六进制密钥…" : "输入加密/解密口令…", text: $aesSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                    StudioToolBarButton(title: "随机 256-bit Hex 密钥", icon: "key") {
                        aesKdf = .hex
                        aesSecret = UUIDEngine.randomBytes(count: 32).map { String(format: "%02x", $0) }.joined()
                    }
                }

                HStack(spacing: 8) {
                    StudioToolBarButton(title: "🔒 加密 →", icon: "lock.fill", tint: .green) {
                        do {
                            aesOutput = try CodecEngine.encryptAes(studio.codecInput, secret: aesSecret, mode: aesMode, kdf: aesKdf)
                            aesError = nil
                        } catch {
                            aesError = error.localizedDescription
                        }
                    }
                    StudioToolBarButton(title: "🔓 ← 解密", icon: "lock.open.fill", tint: .blue) {
                        do {
                            aesOutput = try CodecEngine.decryptAes(studio.codecInput, secret: aesSecret, fallbackMode: aesMode, fallbackKdf: aesKdf)
                            aesError = nil
                        } catch {
                            aesError = error.localizedDescription
                        }
                    }
                    StudioToolBarButton(title: "密文放回左栏", icon: "arrow.uturn.left") {
                        if !aesOutput.isEmpty { studio.codecInput = aesOutput }
                    }
                    Spacer()
                    CopyActionButton(text: aesOutput, concealed: true, label: "复制结果") { _ in
                        studio.showToast("已安全复制 AES 输出")
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                StudioPanel(title: "左栏输入 (明文或 JSON 密文 Payload)") {
                    EditorBoxView(text: $studio.codecInput, height: 220)
                }
                StudioPanel(title: "右栏输出结果") {
                    EditorBoxView(text: .constant(aesOutput), isEditable: false, height: 220)
                    if let aesError {
                        Text(aesError).font(.system(size: 12)).foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

// MARK: - 6. JSON Tool

enum JsonOutputMode: String, CaseIterable, Sendable {
    case pretty2 = "2空格"
    case pretty4 = "4空格"
    case minified = "压缩"
    case sorted = "键排序"
    case ts = "TypeScript"
    case yaml = "YAML"
    case query = "Query参数"
    case escaped = "JSON转义"
}

struct JsonToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var mode: JsonOutputMode = .pretty2

    var body: some View {
        @Bindable var studio = studio
        let analysis = JsonEngine.analyze(studio.jsonInput)
        let outputText: String = {
            guard analysis.valid else { return "" }
            switch mode {
            case .pretty2: return analysis.pretty2 ?? ""
            case .pretty4: return analysis.pretty4 ?? ""
            case .minified: return analysis.minified ?? ""
            case .sorted: return analysis.sortedPretty ?? ""
            case .ts: return analysis.tsInterface ?? ""
            case .yaml: return analysis.yaml ?? ""
            case .query: return analysis.queryString ?? "(仅根节点为 JSON Object 时支持转换为 Query 参数)"
            case .escaped: return analysis.escapedString ?? ""
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            ToolHeader(tool: .json, subtitle: "格式化、压缩、键排序、容错修复单引号/注释/尾逗号、转 TypeScript / YAML / Query 参数")

            HStack(spacing: 8) {
                if analysis.valid {
                    BadgePill(
                        text: analysis.repaired ? "⚡ 已自动容错修复 (注释/单引号/尾逗号)" : "✓ 合法 JSON",
                        color: analysis.repaired ? .orange : .green
                    )
                    if let st = analysis.stats {
                        BadgePill(text: "\(st.rootType) · \(st.keyCount) keys · 深度 \(st.maxDepth) · \(st.minifiedLength)B", color: .cyan)
                    }
                } else if !studio.jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BadgePill(text: "✗ \(analysis.error ?? "解析失败")", color: .red)
                }

                Spacer()

                StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                    let clip = ClipboardService.readString()
                    if !clip.isEmpty { studio.jsonInput = clip }
                }
                StudioToolBarButton(title: "容错示例", icon: "wand.and.stars") {
                    studio.jsonInput = """
                    {
                      // 支持注释、单引号和尾逗号修复
                      app: 'Tinycast DevKit',
                      native: true,
                      modules: ['UUID', 'Hash', 'AES',],
                      meta: { fps: 120, memoryMB: 28 }
                    }
                    """
                }
                StudioToolBarButton(title: "清空", icon: "trash") {
                    studio.jsonInput = ""
                }
            }

            HStack(alignment: .top, spacing: 12) {
                StudioPanel(title: "输入 JSON / 宽松 JS 对象") {
                    EditorBoxView(text: $studio.jsonInput, height: 340)
                }

                StudioPanel(title: "输出预览") {
                    FlowWrapLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(JsonOutputMode.allCases, id: \.rawValue) { m in
                            PillButton(title: m.rawValue, active: mode == m, color: .cyan) {
                                mode = m
                            }
                        }
                    }

                    EditorBoxView(text: .constant(outputText), isEditable: false, height: 265)

                    HStack {
                        Spacer()
                        StudioToolBarButton(title: "保存到桌面", icon: "square.and.arrow.down") {
                            saveDesktop(content: outputText)
                        }
                        CopyActionButton(text: outputText, label: "复制结果") { _ in
                            studio.showToast("已复制 \(mode.rawValue) 结果")
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func saveDesktop(content: String) {
        guard !content.isEmpty else { return }
        let ext: String
        switch mode {
        case .ts: ext = "ts"
        case .yaml: ext = "yaml"
        case .query: ext = "txt"
        default: ext = "json"
        }
        let stamp = TimestampEngine.formatDate(Date(), format: "yyyyMMdd-HHmmss")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("tinycast-\(stamp).\(ext)")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            studio.showToast("已保存到桌面: \(url.lastPathComponent)")
        } catch {
            studio.showToast("保存失败: \(error.localizedDescription)", isError: true)
        }
    }
}
