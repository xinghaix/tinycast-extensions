import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 1. Multi-Format Data Converter View

struct DataFormatToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var sourceFormat: DataFormatKind? = nil // nil = auto-detect
    @State private var targetFormat: DataFormatKind = .yaml

    var body: some View {
        @Bindable var studio = studio
        let result = Result { try DataFormatEngine.convert(studio.dataFormatInput, from: sourceFormat, to: targetFormat) }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .dataFormat, subtitle: "JSON / YAML / TOML / .env / CSV / Markdown 表格 双向无损互转（保留键顺序，支持一键导出）")

                StudioPanel {
                    HStack(spacing: 8) {
                        Text("源格式:")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        PillButton(title: "自动识别", active: sourceFormat == nil, color: .indigo) { sourceFormat = nil }
                        ForEach(DataFormatKind.allCases) { fmt in
                            PillButton(title: fmt.rawValue, active: sourceFormat == fmt, color: .indigo) { sourceFormat = fmt }
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Text("目标格式:")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(DataFormatKind.allCases) { fmt in
                            PillButton(title: fmt.rawValue, active: targetFormat == fmt, color: .purple) { targetFormat = fmt }
                        }
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        if case .success(let ok) = result {
                            BadgePill(text: "识别源: \(ok.detected.rawValue) → \(targetFormat.rawValue)", color: .indigo)
                        } else if case .failure(let err) = result {
                            BadgePill(text: "✗ \(err.localizedDescription)", color: .red)
                        }
                        Spacer()
                        StudioToolBarButton(title: "示例 JSON", icon: "wand.and.stars") {
                            sourceFormat = nil
                            studio.dataFormatInput = DataFormatEngine.sampleJson
                            targetFormat = .yaml
                        }
                        StudioToolBarButton(title: "示例 CSV→MD表", icon: "tablecells") {
                            sourceFormat = nil
                            studio.dataFormatInput = DataFormatEngine.sampleCsv
                            targetFormat = .markdownTable
                        }
                        StudioToolBarButton(title: "示例 .env", icon: "gearshape") {
                            sourceFormat = nil
                            studio.dataFormatInput = DataFormatEngine.sampleEnv
                            targetFormat = .json
                        }
                        StudioToolBarButton(title: "结果作为输入 ⇄", icon: "arrow.left.arrow.right") {
                            if case .success(let ok) = result {
                                studio.dataFormatInput = ok.output
                                sourceFormat = targetFormat
                                targetFormat = ok.detected
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    StudioPanel(title: "输入内容") {
                        EditorBoxView(text: $studio.dataFormatInput, height: 340)
                        HStack {
                            StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                                let c = ClipboardService.readString()
                                if !c.isEmpty { studio.dataFormatInput = c }
                            }
                            if !studio.dataFormatInput.isEmpty {
                                StudioToolBarButton(title: "清空", icon: "trash") { studio.dataFormatInput = "" }
                            }
                            Spacer()
                        }
                    }

                    StudioPanel(title: "转换输出 (\(targetFormat.rawValue))") {
                        let outText: String = {
                            switch result {
                            case .success(let ok): return ok.output
                            case .failure(let err): return "转换失败: \(err.localizedDescription)"
                            }
                        }()
                        EditorBoxView(text: .constant(outText), isEditable: false, height: 340)
                        HStack {
                            Spacer()
                            if case .success(let ok) = result {
                                StudioToolBarButton(title: "保存文件", icon: "square.and.arrow.down") {
                                    saveConvertedFile(ok.output, ext: targetFormat.fileExtension)
                                }
                                CopyActionButton(text: ok.output, label: "复制结果") { _ in
                                    studio.showToast("已复制 \(targetFormat.rawValue) 结果")
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func saveConvertedFile(_ content: String, ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "converted.\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                studio.showToast("已保存到 \(url.lastPathComponent)")
            } catch {
                studio.showToast("保存失败: \(error.localizedDescription)", isError: true)
            }
        }
    }
}

// MARK: - 2. SQL Formatter & ORM Log Parameter Binder View

struct SqlToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var mode: Int = 0 // 0 = Format/Minify, 1 = Bind Params
    @State private var caseStyle: SqlCaseStyle = .upper
    @State private var indentSpaces: Int = 2
    @State private var minifyMode: Bool = false

    @State private var manualParamsInput: String = ""
    @State private var formatBoundOutput: Bool = true

    var body: some View {
        @Bindable var studio = studio

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .sql, subtitle: "SQL 关键词规范化排版 / 压缩，以及 MyBatis / GORM / Prisma 日志占位符 (?, $1, :name, #{name}) 一键参数回填")

                HStack(spacing: 8) {
                    PillButton(title: "SQL 格式化 & 压缩", active: mode == 0, color: .blue) { mode = 0 }
                    PillButton(title: "ORM 日志 / 参数还原", active: mode == 1, color: .blue) { mode = 1 }
                    Spacer()

                    if mode == 0 {
                        StudioToolBarButton(title: "填入示例 SQL", icon: "wand.and.stars") {
                            studio.sqlInput = SqlEngine.sampleSql
                            minifyMode = false
                        }
                    } else {
                        StudioToolBarButton(title: "MyBatis 日志示例", icon: "wand.and.stars") {
                            studio.sqlInput = SqlEngine.sampleMyBatisLog
                            manualParamsInput = ""
                        }
                        StudioToolBarButton(title: "PostgreSQL $1 示例", icon: "number") {
                            studio.sqlInput = "SELECT * FROM orders WHERE user_id = $1 AND state = $2 AND deleted_at IS $3;"
                            manualParamsInput = "[42, \"paid\", null]"
                        }
                    }
                }

                if mode == 0 {
                    formatTab
                } else {
                    bindTab
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var formatTab: some View {
        @Bindable var studio = studio
        let output = minifyMode
            ? SqlEngine.minify(studio.sqlInput)
            : SqlEngine.format(studio.sqlInput, keywordCase: caseStyle, indentSpaces: indentSpaces)

        StudioPanel {
            HStack(spacing: 8) {
                PillButton(title: "美化排版", active: !minifyMode, color: .blue) { minifyMode = false }
                PillButton(title: "单行压缩", active: minifyMode, color: .blue) { minifyMode = true }
                Divider().frame(height: 16)
                Text("关键词:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                ForEach(SqlCaseStyle.allCases, id: \.rawValue) { st in
                    PillButton(title: st.rawValue, active: caseStyle == st, color: .indigo) { caseStyle = st }
                }
                if !minifyMode {
                    Divider().frame(height: 16)
                    PillButton(title: "2 空格", active: indentSpaces == 2, color: .teal) { indentSpaces = 2 }
                    PillButton(title: "4 空格", active: indentSpaces == 4, color: .teal) { indentSpaces = 4 }
                }
                Spacer()
            }
        }

        HStack(alignment: .top, spacing: 12) {
            StudioPanel(title: "输入 SQL") {
                EditorBoxView(text: $studio.sqlInput, height: 320)
                HStack {
                    StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                        let c = ClipboardService.readString()
                        if !c.isEmpty { studio.sqlInput = c }
                    }
                    StudioToolBarButton(title: "清空", icon: "trash") { studio.sqlInput = "" }
                    Spacer()
                }
            }
            StudioPanel(title: minifyMode ? "压缩后 SQL" : "格式化 SQL") {
                EditorBoxView(text: .constant(output), isEditable: false, height: 320)
                HStack {
                    Spacer()
                    CopyActionButton(text: output, label: "复制 SQL") { _ in
                        studio.showToast("已复制 SQL")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bindTab: some View {
        @Bindable var studio = studio
        let bound = SqlEngine.bindParameters(
            sqlOrLog: studio.sqlInput,
            manualParams: manualParamsInput,
            formatOutput: formatBoundOutput
        )

        StudioPanel(title: "1. 粘贴完整 ORM 日志 (如 Preparing / Parameters) 或带占位符 SQL") {
            EditorBoxView(text: $studio.sqlInput, height: 125)
            HStack(spacing: 8) {
                Text("手工参数 (可选 · 支持 JSON 数组 / 逗号列表 / key=val):")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("结果同时美化排版", isOn: $formatBoundOutput)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
            }
            TextField(#"如: [10042, "active", true, null] 或 10042, active 或 tenant_id=10042"#, text: $manualParamsInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, design: .monospaced))
        }

        StudioPanel(title: "2. 还原结果 (可执行 SQL)") {
            HStack(spacing: 8) {
                BadgePill(text: bound.detectedFormat, color: .blue)
                BadgePill(text: "解析出 \(bound.params.count) 个参数", color: bound.params.isEmpty ? .orange : .green)
                if let warn = bound.warning {
                    Text(warn)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }
                Spacer()
                CopyActionButton(text: formatBoundOutput ? bound.formattedSql : bound.renderedSql, label: "复制可执行 SQL") { _ in
                    studio.showToast("已复制可执行 SQL")
                }
            }

            if !bound.params.isEmpty {
                FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Array(bound.params.enumerated()), id: \.offset) { idx, p in
                        BadgePill(text: "#\(idx + 1): \(p)", color: .indigo)
                    }
                }
            }

            EditorBoxView(text: .constant(formatBoundOutput ? bound.formattedSql : bound.renderedSql), isEditable: false, height: 220)
        }
    }
}

// MARK: - 3. TLS / X.509 Certificate & SSH Public Key Inspector View

struct CertToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var hostInput: String = "github.com"
    @State private var isFetchingRemote: Bool = false
    @State private var remoteStatus: RemoteTlsResult? = nil
    @State private var remoteError: String? = nil
    @State private var selectedChainIndex: Int = 0

    var body: some View {
        @Bindable var studio = studio
        let parsedKind = CertEngine.inspectText(studio.certInput)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .cert, subtitle: "离线 ASN.1 DER 解析 X.509 PEM/DER 证书链与 SAN/有效期，拉取远程 HTTPS 证书，以及 OpenSSH 公钥指纹 & Randomart")

                StudioPanel(title: "远程 HTTPS 域名抓取 (仅用户主动点击时发起 TLS 握手)") {
                    HStack(spacing: 8) {
                        TextField("输入域名或 host:port (如 github.com, api.openai.com:443)", text: $hostInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                            .onSubmit { fetchRemote() }

                        StudioToolBarButton(title: isFetchingRemote ? "拉取中…" : "拉取 TLS 证书链", icon: "network.badge.shield.half.filled", tint: .green) {
                            fetchRemote()
                        }
                    }

                    if let r = remoteStatus {
                        HStack(spacing: 8) {
                            BadgePill(
                                text: r.systemTrusted ? "✓ \(r.host):\(r.port) 信任链完整有效" : "⚠ \(r.host):\(r.port) 未被系统信任",
                                color: r.systemTrusted ? .green : .orange
                            )
                            Text(r.trustStatusNote)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    } else if let err = remoteError {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }

                StudioPanel(title: "PEM 证书 / OpenSSH 公钥内容 (支持拖入 .crt / .pem / .cer / .pub 文件)") {
                    EditorBoxView(text: $studio.certInput, height: 110)
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                            handleDrop(providers: providers)
                        }

                    HStack(spacing: 8) {
                        StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                            let c = ClipboardService.readString()
                            if !c.isEmpty {
                                remoteStatus = nil
                                remoteError = nil
                                selectedChainIndex = 0
                                studio.certInput = c
                            }
                        }
                        StudioToolBarButton(title: "打开证书文件", icon: "doc") { openCertFile() }
                        StudioToolBarButton(title: "SSH 公钥示例", icon: "key") {
                            remoteStatus = nil
                            remoteError = nil
                            studio.certInput = CertEngine.sampleSshKey
                        }
                        StudioToolBarButton(title: "X.509 示例", icon: "checkmark.seal") {
                            remoteStatus = nil
                            remoteError = nil
                            selectedChainIndex = 0
                            studio.certInput = CertEngine.encodePem(der: CertEngine.buildSelfTestDerCert())
                        }
                        Spacer()
                        if !studio.certInput.isEmpty {
                            StudioToolBarButton(title: "清空", icon: "trash") {
                                remoteStatus = nil
                                studio.certInput = ""
                            }
                        }
                    }
                }

                switch parsedKind {
                case .empty:
                    EmptyView()

                case .error(let msg):
                    StudioPanel {
                        Text(msg)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.orange)
                    }

                case .sshPublicKey(let ssh):
                    sshKeyPanel(ssh)

                case .certificates(let chain, let hasPrivWarn):
                    certChainPanel(chain: chain, hasPrivWarn: hasPrivWarn)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func certChainPanel(chain: [ParsedX509Certificate], hasPrivWarn: Bool) -> some View {
        let safeIdx = min(max(0, selectedChainIndex), max(0, chain.count - 1))
        let cert = chain[safeIdx]

        if hasPrivWarn {
            StudioPanel {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("检测到私钥内容段；本工具 100% 本地运行，不会上传或落盘您的私钥。")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }

        if chain.count > 1 {
            StudioPanel(title: "证书链层级 (\(chain.count) 级)") {
                FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(chain) { item in
                        let roleTag = item.id == 0 ? "叶证书" : (item.isSelfSigned ? "根证书" : "中间 CA #\(item.id)")
                        PillButton(title: "\(roleTag): \(item.subjectCommonName)", active: safeIdx == item.id, color: .green) {
                            selectedChainIndex = item.id
                        }
                    }
                }
            }
        }

        StudioPanel(title: "证书详情 · \(cert.subjectCommonName)") {
            HStack(spacing: 8) {
                if cert.isExpired {
                    BadgePill(text: "✗ 已过期 (\(-cert.daysRemaining) 天前)", color: .red)
                } else if cert.isNotYetValid {
                    BadgePill(text: "⚠ 尚未生效", color: .orange)
                } else if cert.daysRemaining <= 30 {
                    BadgePill(text: "⚠ 即将到期 (剩余 \(cert.daysRemaining) 天)", color: .orange)
                } else {
                    BadgePill(text: "✓ 有效期内 (剩余 \(cert.daysRemaining) 天)", color: .green)
                }

                BadgePill(text: "X.509 \(cert.version)", color: .blue)
                BadgePill(text: cert.publicKeySummary, color: .purple)
                if cert.isCA == true { BadgePill(text: "CA 证书", color: .indigo) }
                if cert.isSelfSigned { BadgePill(text: "自签名", color: .orange) }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                CopyableResultRow(title: "Subject (使用者)", value: cert.subject)
                CopyableResultRow(title: "Issuer (签发机构)", value: cert.issuer)
                CopyableResultRow(title: "生效时间 (Not Before)", value: TimestampEngine.formatDate(cert.notBefore, format: "yyyy-MM-dd HH:mm:ss zzz"))
                CopyableResultRow(title: "过期时间 (Not After)", value: TimestampEngine.formatDate(cert.notAfter, format: "yyyy-MM-dd HH:mm:ss zzz"))
                CopyableResultRow(title: "签名算法", value: cert.signatureAlgorithm)
                CopyableResultRow(title: "序列号 (Serial)", value: cert.serialHex)
            }

            CopyableResultRow(title: "SHA-256 指纹", value: cert.sha256Fingerprint, badge: "SHA-256", badgeColor: .green)
            CopyableResultRow(title: "SHA-1 指纹", value: cert.sha1Fingerprint, badge: "SHA-1", badgeColor: .secondary)

            if !cert.sanEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备用名称 SAN (\(cert.sanEntries.count))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(cert.sanEntries, id: \.self) { san in
                            Button {
                                studio.copy(san, label: "已复制 SAN")
                            } label: {
                                Text(san)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.11)))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !cert.keyUsages.isEmpty || !cert.extKeyUsages.isEmpty {
                let usageText = (cert.keyUsages + cert.extKeyUsages).joined(separator: " · ")
                CopyableResultRow(title: "密钥用途 (Key Usage / EKU)", value: usageText)
            }

            HStack {
                Spacer()
                CopyActionButton(text: cert.pemString, label: "复制此证书 PEM") { _ in
                    studio.showToast("已复制当前证书 PEM")
                }
            }
        }
    }

    @ViewBuilder
    private func sshKeyPanel(_ ssh: ParsedSshPublicKey) -> some View {
        StudioPanel(title: "OpenSSH 公钥分析") {
            HStack(spacing: 8) {
                BadgePill(text: ssh.algorithmLabel, color: .green)
                if ssh.bitLength > 0 { BadgePill(text: "\(ssh.bitLength)-bit", color: .blue) }
                if !ssh.comment.isEmpty { BadgePill(text: "备注: \(ssh.comment)", color: .purple) }
            }

            CopyableResultRow(title: "OpenSSH SHA256 指纹", value: ssh.sha256Fingerprint, badge: "标准", badgeColor: .green)
            CopyableResultRow(title: "Legacy MD5 指纹", value: ssh.md5Fingerprint, badge: "兼容", badgeColor: .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Drunken Bishop Visual Randomart")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    CopyActionButton(text: ssh.randomart, label: "复制 Randomart")
                }
                Text(ssh.randomart)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    private func fetchRemote() {
        guard !isFetchingRemote else { return }
        isFetchingRemote = true
        remoteError = nil
        let target = hostInput
        Task {
            do {
                let res = try await CertEngine.fetchRemoteTlsChain(hostInput: target)
                await MainActor.run {
                    remoteStatus = res
                    selectedChainIndex = 0
                    studio.certInput = res.certificates.map(\.pemString).joined(separator: "\n")
                    isFetchingRemote = false
                    studio.showToast("已抓取 \(res.certificates.count) 级证书")
                }
            } catch {
                await MainActor.run {
                    remoteError = error.localizedDescription
                    isFetchingRemote = false
                }
            }
        }
    }

    private func openCertFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            loadCertFileData(data)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { urlData, _ in
            guard let urlData,
                  let url = URL(dataRepresentation: urlData, relativeTo: nil),
                  let fileData = try? Data(contentsOf: url) else { return }
            Task { @MainActor in
                loadCertFileData(fileData)
            }
        }
        return true
    }

    @MainActor
    private func loadCertFileData(_ data: Data) {
        remoteStatus = nil
        remoteError = nil
        selectedChainIndex = 0
        if let str = String(data: data, encoding: .utf8),
           str.contains("-----BEGIN") || CertEngine.parseSshPublicKey(str) != nil {
            studio.certInput = str
        } else if (try? CertEngine.parseX509Certificate(der: data)) != nil {
            studio.certInput = CertEngine.encodePem(der: data)
        } else {
            studio.showToast("该文件不是支持的 PEM / DER / SSH 公钥格式", isError: true)
        }
    }
}
