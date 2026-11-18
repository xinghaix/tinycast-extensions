import AppKit
import Darwin
import SwiftUI

// MARK: - 7. Password & Secret Generator

struct PasswordToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var usePassphrase: Bool = false
    @State private var pwLength: Double = 20
    @State private var useUpper: Bool = true
    @State private var useLower: Bool = true
    @State private var useDigits: Bool = true
    @State private var useSymbols: Bool = true
    @State private var excludeAmbiguous: Bool = false

    @State private var phraseWords: Int = 5
    @State private var phraseSep: String = "-"
    @State private var phraseCap: Bool = false
    @State private var concealedCopy: Bool = true

    @State private var customResult: (value: String, entropy: Int) = {
        let initial = PasswordEngine.generatePassword(length: 20)
        return (initial.password, initial.entropyBits)
    }()
    @State private var presets: [PasswordPreset] = PasswordEngine.presets()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .password, subtitle: "SecRandomCopyBytes 加密随机数生成器：长度滑块、字符集定制、Diceware 助记词与隐私剪贴板保护")

                StudioPanel(title: "1. 定制生成器") {
                    HStack(spacing: 8) {
                        PillButton(title: "随机密码", active: !usePassphrase, color: .pink) {
                            usePassphrase = false
                            regenerateCustom()
                        }
                        PillButton(title: "Diceware 助记词短语", active: usePassphrase, color: .pink) {
                            usePassphrase = true
                            regenerateCustom()
                        }
                        Spacer()
                        Toggle("🔒 隐私复制 (不记录历史)", isOn: $concealedCopy)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                        StudioToolBarButton(title: "全部刷新", icon: "arrow.clockwise", tint: .pink) {
                            regenerateCustom()
                            presets = PasswordEngine.presets()
                        }
                    }

                    if !usePassphrase {
                        HStack(spacing: 10) {
                            Text(verbatim: "长度: \(Int(pwLength))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 68, alignment: .leading)
                            Slider(value: $pwLength, in: 6...128, step: 1) { _ in
                                regenerateCustom()
                            }
                            .onChange(of: pwLength) { _, _ in regenerateCustom() }

                            ForEach([12, 16, 20, 24, 32], id: \.self) { len in
                                PillButton(title: "\(len)", active: Int(pwLength) == len, color: .pink) {
                                    pwLength = Double(len)
                                }
                            }
                        }

                        FlowWrapLayout(spacing: 12, lineSpacing: 6) {
                            Toggle("大写 A-Z", isOn: $useUpper).toggleStyle(.checkbox)
                                .onChange(of: useUpper) { _, _ in regenerateCustom() }
                            Toggle("小写 a-z", isOn: $useLower).toggleStyle(.checkbox)
                                .onChange(of: useLower) { _, _ in regenerateCustom() }
                            Toggle("数字 0-9", isOn: $useDigits).toggleStyle(.checkbox)
                                .onChange(of: useDigits) { _, _ in regenerateCustom() }
                            Toggle("符号 !@#$", isOn: $useSymbols).toggleStyle(.checkbox)
                                .onChange(of: useSymbols) { _, _ in regenerateCustom() }
                            Toggle("排除易混淆 (0O1lI)", isOn: $excludeAmbiguous).toggleStyle(.checkbox)
                                .onChange(of: excludeAmbiguous) { _, _ in regenerateCustom() }
                        }
                        .font(.system(size: 12))
                    } else {
                        HStack(spacing: 8) {
                            Text(verbatim: "词数: \(phraseWords)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            ForEach([3, 4, 5, 6, 8], id: \.self) { cnt in
                                PillButton(title: "\(cnt)词", active: phraseWords == cnt, color: .pink) {
                                    phraseWords = cnt
                                    regenerateCustom()
                                }
                            }
                            Divider().frame(height: 16)
                            Text("分隔:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            ForEach(["-", "_", ".", " "], id: \.self) { sep in
                                PillButton(title: sep == " " ? "空格" : sep, active: phraseSep == sep, color: .purple) {
                                    phraseSep = sep
                                    regenerateCustom()
                                }
                            }
                            Toggle("首字母大写", isOn: $phraseCap)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12))
                                .onChange(of: phraseCap) { _, _ in regenerateCustom() }
                        }
                    }

                    let strength = PasswordEngine.classify(customResult.entropy)
                    let strengthColor: Color = customResult.entropy >= 100 ? .green : (customResult.entropy >= 70 ? .blue : .orange)
                    CopyableResultRow(
                        title: usePassphrase ? "定制助记词" : "定制随机密码 · \(Int(pwLength)) 位",
                        value: customResult.value,
                        badge: "\(customResult.entropy) bits · \(strength)",
                        badgeColor: strengthColor,
                        concealed: concealedCopy,
                        secondaryButton: ("换一个", "arrow.clockwise", { regenerateCustom() })
                    )
                }

                StudioPanel(title: "2. 常用密码与密钥预设") {
                    LazyVStack(spacing: 8) {
                        ForEach(presets) { item in
                            let col: Color = item.entropyBits >= 100 ? .green : (item.entropyBits >= 70 ? .blue : .orange)
                            CopyableResultRow(
                                title: "\(item.title) · \(item.description)",
                                value: item.value,
                                badge: "\(item.entropyBits)b · \(item.strength)",
                                badgeColor: col,
                                concealed: concealedCopy
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func regenerateCustom() {
        if usePassphrase {
            let res = PasswordEngine.generatePassphrase(wordCount: phraseWords, separator: phraseSep, capitalize: phraseCap)
            customResult = (res.passphrase, res.entropyBits)
        } else {
            let res = PasswordEngine.generatePassword(
                length: Int(pwLength),
                useUpper: useUpper,
                useLower: useLower,
                useDigits: useDigits,
                useSymbols: useSymbols,
                excludeAmbiguous: excludeAmbiguous
            )
            customResult = (res.password, res.entropyBits)
        }
    }
}

// MARK: - 8. Text Case & Line Processing

struct TextToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var selectedAction: String = "trim"
    @State private var transformedOutput: String = ""

    private static let lineActions: [(id: String, title: String)] = [
        ("trim", "去首尾空格"),
        ("dropEmpty", "去空行"),
        ("dedupe", "行去重"),
        ("sortAsc", "字典升序"),
        ("sortDesc", "字典降序"),
        ("reverse", "行反转"),
        ("number", "加行号"),
        ("csv", "合并 CSV"),
        ("jsonArray", "转 JSON 数组"),
        ("collapse", "折叠多余空白"),
    ]

    var body: some View {
        @Bindable var studio = studio
        let stats = TextEngine.stats(studio.textInput)
        let previewOut = TextEngine.lineTransform(studio.textInput, action: selectedAction)
        let caseSource = studio.textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cases = TextEngine.caseConversions(caseSource.isEmpty ? "hello tinycast studio" : String(caseSource.prefix(200)))

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .text, subtitle: "实时字数统计、行去重/排序/编号/JSON 数组转换 & 11 种编程命名规范一键转换")

                HStack(spacing: 8) {
                    BadgePill(text: "\(stats.chars) 字符", color: .blue)
                    BadgePill(text: "\(stats.charsNoSpaces) 非空白字符", color: .blue)
                    BadgePill(text: "\(stats.bytesUtf8) UTF-8 字节", color: .indigo)
                    BadgePill(text: "\(stats.words) 词 · \(stats.lines) 行", color: .teal)
                    Spacer()
                    StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                        let clip = ClipboardService.readString()
                        if !clip.isEmpty { studio.textInput = clip }
                    }
                    StudioToolBarButton(title: "清空", icon: "trash") {
                        studio.textInput = ""
                    }
                }

                StudioPanel(title: "行批处理工作台") {
                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Self.lineActions, id: \.id) { act in
                            PillButton(title: act.title, active: selectedAction == act.id, color: .blue) {
                                selectedAction = act.id
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("左栏输入 (支持多行)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            EditorBoxView(text: $studio.textInput, height: 170)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("右栏处理结果")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                StudioToolBarButton(title: "↙ 回填左栏继续链式处理", icon: "arrow.uturn.left") {
                                    studio.textInput = previewOut
                                }
                                CopyActionButton(text: previewOut, label: "复制") { _ in
                                    studio.showToast("已复制行处理结果")
                                }
                            }
                            EditorBoxView(text: .constant(previewOut), isEditable: false, height: 170)
                        }
                    }
                }

                StudioPanel(title: "编程命名规范与 Slug 转换\(caseSource.isEmpty ? "（当前展示示例预览）" : "")") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(cases, id: \.id) { c in
                            CopyableResultRow(title: c.title, value: c.value, badge: c.id, badgeColor: .blue)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 9. Offline QR Generator

struct QrToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var level: QrCorrectionLevel = .M
    @State private var wifiSsid: String = ""
    @State private var wifiPass: String = ""
    @State private var wifiAuth: String = "WPA"
    @State private var showWifiBuilder: Bool = false

    var body: some View {
        @Bindable var studio = studio
        let qr = QrEngine.generate(text: studio.qrInput, level: level, size: 280)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .qr, subtitle: "原生 CoreImage CIQRCodeGenerator 离线生成高清晰度二维码，支持 Wi-Fi 配置与矢量 SVG / PNG 导出")

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        StudioPanel(title: "内容与纠错等级") {
                            HStack {
                                ForEach(QrCorrectionLevel.allCases, id: \.rawValue) { lv in
                                    PillButton(title: lv.title, active: level == lv, color: .primary) {
                                        level = lv
                                    }
                                }
                                Spacer()
                            }

                            EditorBoxView(text: $studio.qrInput, height: 150)

                            HStack(spacing: 8) {
                                StudioToolBarButton(title: "粘贴内容", icon: "clipboard") {
                                    let clip = ClipboardService.readString()
                                    if !clip.isEmpty { studio.qrInput = clip }
                                }
                                StudioToolBarButton(title: showWifiBuilder ? "收起 Wi-Fi 生成器" : "Wi-Fi 二维码助手", icon: "wifi") {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        showWifiBuilder.toggle()
                                    }
                                }
                                Spacer()
                                CopyActionButton(text: studio.qrInput, label: "复制原文本") { _ in
                                    studio.showToast("已复制二维码原文")
                                }
                            }
                        }

                        if showWifiBuilder {
                            StudioPanel(title: "Wi-Fi 配网二维码配置") {
                                TextField("Wi-Fi 名称 (SSID)", text: $wifiSsid)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Wi-Fi 密码", text: $wifiPass)
                                    .textFieldStyle(.roundedBorder)
                                HStack {
                                    ForEach(["WPA", "WEP", "nopass"], id: \.self) { auth in
                                        PillButton(title: auth == "nopass" ? "无密码" : auth, active: wifiAuth == auth) {
                                            wifiAuth = auth
                                        }
                                    }
                                    Spacer()
                                    StudioToolBarButton(title: "填入 Wi-Fi 字符串", icon: "arrow.up.circle.fill", tint: .blue) {
                                        let esc: (String) -> String = {
                                            $0.replacingOccurrences(of: "\\", with: "\\\\")
                                                .replacingOccurrences(of: ";", with: "\\;")
                                                .replacingOccurrences(of: ",", with: "\\,")
                                                .replacingOccurrences(of: ":", with: "\\:")
                                        }
                                        let pwPart = wifiAuth == "nopass" ? "" : "P:\(esc(wifiPass));"
                                        studio.qrInput = "WIFI:T:\(wifiAuth);S:\(esc(wifiSsid));\(pwPart);"
                                        studio.showToast("已生成 Wi-Fi 配网字符串")
                                    }
                                }
                            }
                        }
                    }

                    StudioPanel(title: "实时二维码预览") {
                        VStack(spacing: 12) {
                            if let qr {
                                Image(nsImage: qr.image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 240, height: 240)
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

                                HStack(spacing: 8) {
                                    BadgePill(text: "\(qr.moduleCount) × \(qr.moduleCount) 模块", color: .secondary)
                                    BadgePill(text: "\(studio.qrInput.utf8.count) bytes · 纠错 \(level.rawValue)", color: .secondary)
                                }

                                HStack(spacing: 8) {
                                    StudioToolBarButton(title: "保存 SVG 到桌面", icon: "square.and.arrow.down") {
                                        saveQrSvg(qr.svg)
                                    }
                                    StudioToolBarButton(title: "保存 PNG 到桌面", icon: "photo") {
                                        saveQrPng()
                                    }
                                }
                                CopyActionButton(text: qr.svg, label: "复制矢量 SVG 代码") { _ in
                                    studio.showToast("已复制 SVG 源码")
                                }
                            } else {
                                Text("请在左栏输入文本或 URL 以生成二维码（UTF-8 内容建议不超过 ~2900 字节）")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 268, height: 268)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: 315)
                }
            }
            .padding(16)
        }
    }

    private func saveQrSvg(_ svg: String) {
        let stamp = TimestampEngine.formatDate(Date(), format: "yyyyMMdd-HHmmss")
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/qr-\(stamp).svg")
        do {
            try svg.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            studio.showToast("已保存 SVG 到桌面")
        } catch {
            studio.showToast("保存 SVG 失败: \(error.localizedDescription)", isError: true)
        }
    }

    private func saveQrPng() {
        guard let hiRes = QrEngine.generate(text: studio.qrInput, level: level, size: 800),
              let tiff = hiRes.image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            studio.showToast("导出 PNG 失败", isError: true)
            return
        }
        let stamp = TimestampEngine.formatDate(Date(), format: "yyyyMMdd-HHmmss")
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/qr-\(stamp).png")
        do {
            try png.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            studio.showToast("已保存高分辨率 PNG 到桌面")
        } catch {
            studio.showToast("保存 PNG 失败: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - 10. Cron Expression Inspector

struct CronToolView: View {
    @Environment(StudioState.self) private var studio

    var body: some View {
        @Bindable var studio = studio
        let parsedResult: Result<ParsedCron, Error> = Result { try CronEngine.parse(studio.cronInput) }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .cron, subtitle: "支持 5 段 (Unix/Crontab)、6 段 (秒级 Quartz/Spring) 及 @daily / @hourly 等常用宏")

                StudioPanel {
                    HStack(spacing: 8) {
                        TextField("例如: */15 9-18 * * 1-5 或 0 30 8 * * 1-5 或 @daily", text: $studio.cronInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        CopyActionButton(text: studio.cronInput, label: "复制表达式") { _ in
                            studio.showToast("已复制 Cron 表达式")
                        }
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(CronEngine.presets, id: \.expression) { preset in
                            PillButton(
                                title: "\(preset.title) (\(preset.expression))",
                                active: studio.cronInput.trimmingCharacters(in: .whitespacesAndNewlines) == preset.expression,
                                color: .orange
                            ) {
                                studio.cronInput = preset.expression
                            }
                        }
                        PillButton(title: "@daily", active: studio.cronInput.lowercased() == "@daily", color: .orange) {
                            studio.cronInput = "@daily"
                        }
                        PillButton(title: "@hourly", active: studio.cronInput.lowercased() == "@hourly", color: .orange) {
                            studio.cronInput = "@hourly"
                        }
                    }
                }

                switch parsedResult {
                case .success(let cron):
                    StudioPanel(title: "中文语义与各字段拆解") {
                        HStack(spacing: 8) {
                            BadgePill(text: cron.hasSeconds ? "6 段 (秒级)" : "5 段 (标准)", color: .orange)
                            Text(cron.description)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if cron.normalized != cron.expression {
                                BadgePill(text: "展开: \(cron.normalized)", color: .secondary)
                            }
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], spacing: 8) {
                            ForEach(cron.fields) { field in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(field.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(field.raw)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    Text(field.summary)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                            }
                        }
                    }

                    StudioPanel(title: "未来 10 次触发时间 (本地时区 · \(TimeZone.current.identifier))") {
                        let now = Date()
                        ForEach(Array(cron.nextRuns.enumerated()), id: \.offset) { idx, runDate in
                            let formatted = TimestampEngine.formatDate(runDate, format: "yyyy-MM-dd HH:mm:ss (EEE)")
                            let rel = TimestampEngine.formatRelative(target: runDate, now: now)
                            CopyableResultRow(
                                title: "第 \(idx + 1) 次触发",
                                value: formatted,
                                badge: rel,
                                badgeColor: .orange
                            )
                        }
                    }
                case .failure(let err):
                    StudioPanel {
                        Text(err.localizedDescription)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - 11. Local Network & Listening Ports

struct NetworkToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var interfaces: [NetworkInterfaceEntry] = NetworkEngine.readLocalInterfaces()
    @State private var ports: [ListeningPortEntry] = []
    @State private var isLoadingPorts: Bool = false
    @State private var publicIp: String? = nil
    @State private var isFetchingPublicIp: Bool = false
    @State private var publicIpError: String? = nil
    @State private var filterText: String = ""

    var body: some View {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredPorts = q.isEmpty
            ? ports
            : ports.filter {
                $0.port.lowercased().contains(q)
                    || $0.command.lowercased().contains(q)
                    || "\($0.pid)".contains(q)
                    || $0.endpoint.lowercased().contains(q)
            }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .network, subtitle: "实时枚举本机活动网卡 IPv4/IPv6、按需查询公网出口 IP，及监控并安全终止 TCP 监听进程")

                HStack(spacing: 8) {
                    TextField("搜索端口 / 进程名 / PID…", text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)

                    StudioToolBarButton(title: "刷新网卡与端口", icon: "arrow.clockwise", tint: .teal) {
                        refreshAll()
                    }
                    StudioToolBarButton(title: isFetchingPublicIp ? "查询中…" : "查询公网 IP", icon: "globe") {
                        queryPublicIp()
                    }
                    Spacer()
                    BadgePill(text: "\(ports.count) 个监听端口", color: .teal)
                }

                StudioPanel(title: "本机网络接口与公网 IP") {
                    if let publicIp {
                        CopyableResultRow(title: "公网出口 IP (ipify.org)", value: publicIp, badge: "Public", badgeColor: .green)
                    } else if let publicIpError {
                        Text("公网 IP 查询失败: \(publicIpError)")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }

                    if interfaces.isEmpty {
                        Text("未检测到活动非回环网卡")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(interfaces) { item in
                                CopyableResultRow(title: "\(item.iface) · \(item.family)", value: item.address, badge: item.family, badgeColor: .teal)
                            }
                        }
                    }
                }

                StudioPanel(title: "TCP 监听端口 (lsof -iTCP -sTCP:LISTEN)") {
                    if isLoadingPorts && ports.isEmpty {
                        ProgressView("正在扫描监听端口…")
                            .padding(.vertical, 12)
                    } else if filteredPorts.isEmpty {
                        Text(ports.isEmpty ? "当前未发现 TCP 监听端口" : "没有匹配 \"\(filterText)\" 的监听端口")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredPorts) { entry in
                                PortRowView(entry: entry, onKill: { confirmKill(entry) })
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .task(id: studio.activeTool == .network) {
            if studio.activeTool == .network {
                refreshAll()
            }
        }
    }

    private func refreshAll() {
        interfaces = NetworkEngine.readLocalInterfaces()
        isLoadingPorts = true
        Task {
            let list = await NetworkEngine.listListeningPorts()
            await MainActor.run {
                ports = list
                isLoadingPorts = false
            }
        }
    }

    private func queryPublicIp() {
        guard !isFetchingPublicIp else { return }
        isFetchingPublicIp = true
        publicIpError = nil
        Task {
            do {
                let ip = try await NetworkEngine.fetchPublicIp()
                await MainActor.run {
                    publicIp = ip
                    isFetchingPublicIp = false
                }
            } catch {
                await MainActor.run {
                    publicIpError = error.localizedDescription
                    isFetchingPublicIp = false
                }
            }
        }
    }

    private func confirmKill(_ entry: ListeningPortEntry) {
        if entry.pid == ProcessInfo.processInfo.processIdentifier {
            studio.showToast("不能终止 DevKit 自身进程", isError: true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "结束监听进程 \(entry.command)？"
        alert.informativeText = "将向 PID \(entry.pid) (端口 :\(entry.port)) 发送 SIGTERM 信号。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "结束进程")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let rc = Darwin.kill(entry.pid, SIGTERM)
            if rc == 0 {
                studio.showToast("已向 \(entry.command) (PID \(entry.pid)) 发送 SIGTERM")
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    refreshAll()
                }
            } else {
                let msg = String(cString: strerror(errno))
                studio.showToast("终止失败: \(msg)", isError: true)
            }
        }
    }
}

private struct PortRowView: View {
    @Environment(StudioState.self) private var studio
    let entry: ListeningPortEntry
    let onKill: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(":\(entry.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.teal.opacity(0.15)))
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.command)
                        .font(.system(size: 12.5, weight: .semibold))
                    BadgePill(text: "PID \(entry.pid)", color: .secondary)
                }
                Text(entry.endpoint)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .onTapGesture { copyUrl() }
            }

            Spacer()

            StudioToolBarButton(title: copied ? "已复制" : "复制 URL", icon: copied ? "checkmark" : "doc.on.doc", tint: copied ? .green : .accentColor) {
                copyUrl()
            }
            StudioToolBarButton(title: "打开", icon: "safari") {
                if let url = URL(string: entry.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            StudioToolBarButton(title: "结束进程", icon: "xmark.octagon", tint: .red, action: onKill)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func copyUrl() {
        studio.copy(entry.url, label: "已复制 \(entry.url)")
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            copied = false
        }
    }
}
