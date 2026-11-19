import AppKit
import SwiftUI

// MARK: - 1. Regex Lab View

struct RegexToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var replacement: String = RegexEngine.presets[0].replacement
    @State private var flags: RegexFlags = RegexEngine.presets[0].flags
    @State private var outputTab: Int = 0 // 0 = Matches & Groups, 1 = Replacement, 2 = Split & Cheatsheet

    private static let groupColors: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]

    var body: some View {
        @Bindable var studio = studio
        let result = RegexEngine.evaluate(
            pattern: studio.regexPattern,
            input: studio.regexInput,
            replacement: replacement,
            flags: flags
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .regex, subtitle: "NSRegularExpression 实时匹配高亮、命名/索引捕获组拆解、模板替换与 Split 拆分")

                StudioPanel(title: "正则表达式 & Flags") {
                    HStack(spacing: 8) {
                        Text("/")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                        TextField("输入正则表达式… (支持 (?<name>...))", text: $studio.regexPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, design: .monospaced))
                        Text("/")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)

                        flagPill("i 忽略大小写", active: flags.caseInsensitive) { flags.caseInsensitive.toggle() }
                        flagPill("m 多行 ^$", active: flags.multiline) { flags.multiline.toggle() }
                        flagPill("s 单行 . 含换行", active: flags.dotMatchesAll) { flags.dotMatchesAll.toggle() }
                        flagPill("x 忽略空白", active: flags.verbose) { flags.verbose.toggle() }
                    }

                    HStack(spacing: 8) {
                        if result.valid {
                            BadgePill(
                                text: result.truncated ? "匹配 \(result.totalMatchCount) 处 (明细展示前 500 处)" : "匹配 \(result.totalMatchCount) 处",
                                color: result.totalMatchCount > 0 ? .green : .secondary
                            )
                            if !result.namedGroupNames.isEmpty {
                                BadgePill(text: "命名组: \(result.namedGroupNames.joined(separator: ", "))", color: .purple)
                            }
                        } else if let err = result.error {
                            BadgePill(text: "✗ \(err)", color: .red)
                        }

                        Spacer()

                        StudioToolBarButton(title: "复制 Regex", icon: "doc.on.doc") {
                            studio.copy(studio.regexPattern, label: "已复制正则表达式")
                        }
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(RegexEngine.presets) { preset in
                            PillButton(title: preset.title, active: studio.regexPattern == preset.pattern, color: .orange) {
                                studio.regexPattern = preset.pattern
                                studio.regexInput = preset.sample
                                replacement = preset.replacement
                                flags = preset.flags
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    StudioPanel(title: "测试文本 (Test String)") {
                        EditorBoxView(text: $studio.regexInput, height: 155)
                        HStack {
                            StudioToolBarButton(title: "从剪贴板读取", icon: "clipboard") {
                                let clip = ClipboardService.readString()
                                if !clip.isEmpty { studio.regexInput = clip }
                            }
                            if !studio.regexInput.isEmpty {
                                StudioToolBarButton(title: "清空", icon: "trash") {
                                    studio.regexInput = ""
                                }
                            }
                            Spacer()
                        }
                    }

                    StudioPanel(title: "实时高亮预览") {
                        ScrollView {
                            Text(highlightedText(input: studio.regexInput, result: result))
                                .font(.system(size: 12.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(minHeight: 155, maxHeight: 220)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.65)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                    }
                }

                StudioPanel {
                    HStack(spacing: 8) {
                        PillButton(title: "匹配与捕获组 (\(result.totalMatchCount))", active: outputTab == 0, color: .orange) { outputTab = 0 }
                        PillButton(title: "模板替换 ($1 / ${name})", active: outputTab == 1, color: .orange) { outputTab = 1 }
                        PillButton(title: "Split 拆分 (\(result.splitParts.count)) & 速查", active: outputTab == 2, color: .orange) { outputTab = 2 }
                        Spacer()
                    }

                    if outputTab == 0 {
                        if result.matches.isEmpty {
                            Text(result.valid ? "当前文本无匹配项，可点击上方预设模板快速测试。" : "请检查正则表达式语法。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(result.matches) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        CopyableResultRow(
                                            title: "匹配 #\(item.matchIndex) [\(item.rangeLocation)..<\(item.rangeLocation + item.rangeLength)]",
                                            value: item.matchedText,
                                            badge: item.groups.isEmpty ? nil : "\(item.groups.count) 个捕获组",
                                            badgeColor: Self.groupColors[item.id % Self.groupColors.count]
                                        )
                                        if !item.groups.isEmpty {
                                            FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                                                ForEach(item.groups) { grp in
                                                    let gLabel = grp.name.map { "$\(grp.index) (\($0))" } ?? "$\(grp.index)"
                                                    let gVal = grp.text ?? "<未捕获>"
                                                    Button {
                                                        if let txt = grp.text {
                                                            studio.copy(txt, label: "已复制捕获组 \(gLabel)")
                                                        }
                                                    } label: {
                                                        HStack(spacing: 4) {
                                                            Text(gLabel)
                                                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                                                .foregroundStyle(Self.groupColors[grp.index % Self.groupColors.count])
                                                            Text(gVal)
                                                                .font(.system(size: 11.5, design: .monospaced))
                                                                .lineLimit(1)
                                                        }
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(RoundedRectangle(cornerRadius: 6).fill(Self.groupColors[grp.index % Self.groupColors.count].opacity(0.10)))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                }
                            }
                        }
                    } else if outputTab == 1 {
                        HStack(spacing: 8) {
                            Text("替换模板:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("$1 / ${name} / 常量文本", text: $replacement)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12.5, design: .monospaced))
                            CopyActionButton(text: result.replacedText, label: "复制替换结果") { _ in
                                studio.showToast("已复制替换结果")
                            }
                        }
                        EditorBoxView(text: .constant(result.replacedText), isEditable: false, height: 150)
                    } else {
                        if !result.splitParts.isEmpty {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(result.splitParts.prefix(100).enumerated()), id: \.offset) { idx, part in
                                    CopyableResultRow(title: "Split[\(idx)]", value: part.isEmpty ? "(空字符串)" : part, badge: "\(part.count) 字符", badgeColor: .blue)
                                }
                            }
                        }
                        Divider()
                        Text("常用正则速查")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 6) {
                            ForEach(RegexEngine.cheatsheet, id: \.token) { tip in
                                HStack {
                                    Text(tip.token)
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text(tip.desc)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.035)))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func flagPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        PillButton(title: title, active: active, color: .orange, action: action)
    }

    private func highlightedText(input: String, result: RegexEvaluationResult) -> AttributedString {
        var attr = AttributedString(input)
        guard result.valid, !result.matches.isEmpty else { return attr }
        let ns = input as NSString
        for item in result.matches {
            let r = NSRange(location: item.rangeLocation, length: item.rangeLength)
            guard r.location != NSNotFound,
                  r.length > 0,
                  r.location + r.length <= ns.length,
                  let swiftRange = Range(r, in: input),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: attr),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: attr) else {
                continue
            }
            let c = Self.groupColors[item.id % Self.groupColors.count]
            attr[lower..<upper].backgroundColor = c.opacity(0.24)
            attr[lower..<upper].foregroundColor = c
        }
        return attr
    }
}

// MARK: - 2. Text & JSON Semantic Diff View

struct DiffToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var jsonSemantic: Bool = true
    @State private var sideBySide: Bool = true
    @State private var ignoreWhitespace: Bool = false
    @State private var ignoreCase: Bool = false
    @State private var onlyChanges: Bool = false

    var body: some View {
        @Bindable var studio = studio
        let diff = DiffEngine.computeDiff(
            left: studio.diffLeft,
            right: studio.diffRight,
            jsonSemantic: jsonSemantic,
            ignoreWhitespace: ignoreWhitespace,
            ignoreCase: ignoreCase
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .diff, subtitle: "行内字符级增删高亮、左右分栏 / 统一补丁视图，支持 JSON 键排序语义 Diff 与路径级变更清单")

                HStack(spacing: 8) {
                    PillButton(title: "JSON 语义对比", active: jsonSemantic, color: .blue) { jsonSemantic = true }
                    PillButton(title: "纯文本对比", active: !jsonSemantic, color: .blue) { jsonSemantic = false }
                    Divider().frame(height: 16)
                    PillButton(title: "左右分栏", active: sideBySide, color: .indigo) { sideBySide = true }
                    PillButton(title: "统一视图", active: !sideBySide, color: .indigo) { sideBySide = false }
                    Divider().frame(height: 16)
                    Toggle("仅显示变更", isOn: $onlyChanges).toggleStyle(.checkbox).font(.system(size: 11.5))
                    Toggle("忽略空白", isOn: $ignoreWhitespace).toggleStyle(.checkbox).font(.system(size: 11.5))
                    Toggle("忽略大小写", isOn: $ignoreCase).toggleStyle(.checkbox).font(.system(size: 11.5))
                    Spacer()
                }

                HStack(spacing: 8) {
                    if let err = diff.error {
                        BadgePill(text: "✗ \(err)", color: .red)
                    } else {
                        BadgePill(text: "+\(diff.addedCount) 新增", color: .green)
                        BadgePill(text: "-\(diff.removedCount) 删除", color: .red)
                        if jsonSemantic {
                            BadgePill(text: "\(diff.jsonChanges.count) 处 JSON 键路径变更", color: .blue)
                        }
                    }
                    Spacer()
                    StudioToolBarButton(title: "左右互换", icon: "arrow.left.arrow.right") {
                        let tmp = studio.diffLeft
                        studio.diffLeft = studio.diffRight
                        studio.diffRight = tmp
                    }
                    StudioToolBarButton(title: "重置示例", icon: "wand.and.stars") {
                        studio.diffLeft = DiffEngine.sampleLeft
                        studio.diffRight = DiffEngine.sampleRight
                        jsonSemantic = true
                    }
                    CopyActionButton(text: diff.unifiedPatch, label: "复制 Patch") { _ in
                        studio.showToast("已复制 Unified Diff Patch")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    StudioPanel(title: "左侧 / 原始文本 (Before)") {
                        EditorBoxView(text: $studio.diffLeft, height: 155)
                        HStack {
                            StudioToolBarButton(title: "粘贴到左侧", icon: "clipboard") {
                                let c = ClipboardService.readString()
                                if !c.isEmpty { studio.diffLeft = c }
                            }
                            Spacer()
                        }
                    }
                    StudioPanel(title: "右侧 / 目标文本 (After)") {
                        EditorBoxView(text: $studio.diffRight, height: 155)
                        HStack {
                            StudioToolBarButton(title: "粘贴到右侧", icon: "clipboard") {
                                let c = ClipboardService.readString()
                                if !c.isEmpty { studio.diffRight = c }
                            }
                            Spacer()
                        }
                    }
                }

                if diff.error == nil {
                    StudioPanel(title: sideBySide ? "分栏对比结果" : "统一 Diff 视图") {
                        if sideBySide {
                            let rows = onlyChanges
                                ? diff.sideBySideRows.filter { ($0.left?.kind != .unchanged) || ($0.right?.kind != .unchanged) }
                                : diff.sideBySideRows
                            if rows.isEmpty {
                                Text("两侧内容完全一致。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                    .padding(.vertical, 8)
                            } else {
                                LazyVStack(spacing: 1) {
                                    ForEach(rows.prefix(600)) { row in
                                        HStack(spacing: 0) {
                                            diffCell(row.left, sideIsRight: false)
                                            Divider()
                                            diffCell(row.right, sideIsRight: true)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            }
                        } else {
                            let lines = onlyChanges ? diff.unifiedLines.filter { $0.kind != .unchanged } : diff.unifiedLines
                            if lines.isEmpty {
                                Text("两侧内容完全一致。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                                    .padding(.vertical, 8)
                            } else {
                                LazyVStack(spacing: 1) {
                                    ForEach(lines.prefix(800)) { line in
                                        HStack(spacing: 8) {
                                            Text(line.leftLineNumber.map(String.init) ?? "")
                                                .frame(width: 30, alignment: .trailing)
                                                .foregroundStyle(.tertiary)
                                            Text(line.rightLineNumber.map(String.init) ?? "")
                                                .frame(width: 30, alignment: .trailing)
                                                .foregroundStyle(.tertiary)
                                            Text(line.kind == .added ? "+" : (line.kind == .removed ? "-" : " "))
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundStyle(line.kind == .added ? .green : (line.kind == .removed ? .red : .secondary))
                                            Text(attributedDiffLine(line))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .textSelection(.enabled)
                                        }
                                        .font(.system(size: 12, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(rowBackground(kind: line.kind))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            }
                        }
                    }

                    if jsonSemantic && !diff.jsonChanges.isEmpty {
                        StudioPanel(title: "JSON 键路径级结构差异 (\(diff.jsonChanges.count))") {
                            LazyVStack(spacing: 6) {
                                ForEach(diff.jsonChanges.prefix(100)) { item in
                                    let col: Color = item.kind == "新增" ? .green : (item.kind == "删除" ? .red : .orange)
                                    let desc = [
                                        item.before.map { "旧: \($0)" },
                                        item.after.map { "新: \($0)" },
                                    ].compactMap { $0 }.joined(separator: "  →  ")
                                    CopyableResultRow(title: item.path, value: desc, badge: item.kind, badgeColor: col)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func diffCell(_ line: DiffLine?, sideIsRight: Bool) -> some View {
        HStack(spacing: 6) {
            Text((sideIsRight ? line?.rightLineNumber : line?.leftLineNumber).map(String.init) ?? "")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            if let line {
                Text(attributedDiffLine(line))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(line.map { rowBackground(kind: $0.kind) } ?? Color.primary.opacity(0.02))
    }

    private func rowBackground(kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.11)
        case .removed: return Color.red.opacity(0.11)
        case .unchanged: return Color.clear
        }
    }

    private func attributedDiffLine(_ line: DiffLine) -> AttributedString {
        if line.segments.isEmpty { return AttributedString(" ") }
        var out = AttributedString()
        let tint: Color = line.kind == .added ? .green : (line.kind == .removed ? .red : .clear)
        for seg in line.segments {
            var part = AttributedString(seg.text)
            if seg.changed && line.kind != .unchanged {
                part.backgroundColor = tint.opacity(0.28)
            }
            out.append(part)
        }
        return out
    }
}

// MARK: - 3. URL Parser & cURL Converter View

struct UrlCurlToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var schemeField: String = "https"
    @State private var hostField: String = ""
    @State private var portField: String = ""
    @State private var pathField: String = ""
    @State private var fragmentField: String = ""
    @State private var queryParams: [UrlQueryParam] = []
    @State private var isInternalSync: Bool = false

    @State private var curlTarget: String = "fetch"

    private static let curlTargets: [(id: String, title: String)] = [
        ("fetch", "JavaScript fetch"),
        ("python", "Python requests"),
        ("httpie", "HTTPie CLI"),
        ("go", "Go net/http"),
        ("swift", "Swift URLSession"),
    ]

    var body: some View {
        @Bindable var studio = studio

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .url, subtitle: "URL 结构拆解、可视化增删改 Query 参数并实时编解码拼回；以及 cURL 命令转多语言请求代码")

                HStack(spacing: 8) {
                    ForEach(UrlSubTab.allCases, id: \.rawValue) { tab in
                        PillButton(title: tab.rawValue, active: studio.urlTabHint == tab, color: .cyan) {
                            studio.urlTabHint = tab
                        }
                    }
                    Spacer()
                }

                if studio.urlTabHint == .urlParser {
                    urlParserTab
                } else {
                    curlConverterTab
                }
            }
            .padding(16)
        }
        .onAppear { syncFromUrlString(studio.urlInput) }
        .onChange(of: studio.urlInput) { _, newVal in
            if !isInternalSync {
                syncFromUrlString(newVal)
            }
        }
    }

    @ViewBuilder
    private var urlParserTab: some View {
        @Bindable var studio = studio
        let parsed = UrlCurlEngine.parseUrl(studio.urlInput)

        StudioPanel(title: "URL / Query 输入") {
            EditorBoxView(text: $studio.urlInput, height: 78)
            HStack(spacing: 8) {
                StudioToolBarButton(title: "从剪贴板读取", icon: "clipboard") {
                    let c = ClipboardService.readString()
                    if !c.isEmpty { studio.urlInput = c }
                }
                StudioToolBarButton(title: "填入示例 URL", icon: "wand.and.stars") {
                    studio.urlInput = UrlCurlEngine.sampleUrl
                }
                Spacer()
                CopyActionButton(text: studio.urlInput, label: "复制完整 URL") { _ in
                    studio.showToast("已复制完整 URL")
                }
            }
        }

        if let parsed {
            StudioPanel(title: "结构组件与编辑") {
                HStack(spacing: 8) {
                    labeledField("Scheme", text: $schemeField, width: 76)
                    labeledField("Host", text: $hostField, width: nil)
                    labeledField("Port", text: $portField, width: 74)
                    labeledField("Path", text: $pathField, width: nil)
                    labeledField("Fragment (#)", text: $fragmentField, width: 130)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    if !parsed.origin.isEmpty {
                        CopyableResultRow(title: "Origin", value: parsed.origin, badge: "Base", badgeColor: .cyan)
                    }
                    CopyableResultRow(title: "Path 路径段", value: parsed.pathSegments.isEmpty ? "/" : parsed.pathSegments.joined(separator: " / "), badge: "\(parsed.pathSegments.count) 段", badgeColor: .blue)
                }
            }

            StudioPanel(title: "Query 参数表 (支持勾选启用、实时编辑 Key/Value 并重编 URL)") {
                if queryParams.isEmpty {
                    Text("当前 URL 无 Query 参数")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($queryParams) { $param in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $param.enabled)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .onChange(of: param.enabled) { _, _ in rebuildToUrlInput() }

                            TextField("Key", text: $param.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: 180)
                                .onChange(of: param.key) { _, _ in rebuildToUrlInput() }

                            Text("=")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)

                            TextField("Value (自动 Decode/Encode)", text: $param.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: param.value) { _, _ in rebuildToUrlInput() }

                            Button {
                                studio.copy(param.value, label: "已复制参数 \(param.key)")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)

                            Button {
                                queryParams.removeAll { $0.id == param.id }
                                rebuildToUrlInput()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack(spacing: 8) {
                    StudioToolBarButton(title: "新增参数", icon: "plus", tint: .cyan) {
                        queryParams.append(UrlQueryParam(key: "key", value: "value"))
                        rebuildToUrlInput()
                    }
                    let jsonParams = serializeParamsAsJson()
                    CopyActionButton(text: jsonParams, label: "复制参数 JSON") { _ in
                        studio.showToast("已复制 Query JSON")
                    }
                    Spacer()
                }
            }
        } else {
            StudioPanel {
                Text("请输入完整 URL（如 https://example.com?a=1）或 Query 参数串。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var curlConverterTab: some View {
        @Bindable var studio = studio
        let parsedCurl = Result { try UrlCurlEngine.parseCurl(studio.curlInput) }

        StudioPanel(title: "cURL 命令输入") {
            EditorBoxView(text: $studio.curlInput, height: 125)
            HStack(spacing: 8) {
                StudioToolBarButton(title: "粘贴 cURL", icon: "clipboard") {
                    let c = ClipboardService.readString()
                    if !c.isEmpty { studio.curlInput = c }
                }
                StudioToolBarButton(title: "填入示例", icon: "wand.and.stars") {
                    studio.curlInput = UrlCurlEngine.sampleCurl
                }
                Spacer()
            }
        }

        switch parsedCurl {
        case .success(let req):
            StudioPanel(title: "请求摘要 & 生成代码") {
                HStack(spacing: 8) {
                    BadgePill(text: req.method, color: .cyan)
                    BadgePill(text: "\(req.headers.count) Headers", color: .blue)
                    if req.body != nil { BadgePill(text: "含 Body", color: .orange) }
                    Spacer()
                    StudioToolBarButton(title: "把 URL 送到左侧解析 →", icon: "arrow.right.circle") {
                        studio.urlInput = req.url
                        studio.urlTabHint = .urlParser
                    }
                }

                FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Self.curlTargets, id: \.id) { target in
                        PillButton(title: target.title, active: curlTarget == target.id, color: .cyan) {
                            curlTarget = target.id
                        }
                    }
                }

                let code = UrlCurlEngine.generateCode(req, target: curlTarget)
                EditorBoxView(text: .constant(code), isEditable: false, height: 210)
                HStack {
                    Spacer()
                    CopyActionButton(text: code, label: "复制生成代码") { _ in
                        studio.showToast("已复制请求代码")
                    }
                }
            }
        case .failure(let err):
            StudioPanel {
                Text(err.localizedDescription)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.red)
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, width: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: text.wrappedValue) { _, _ in rebuildToUrlInput() }
        }
        .frame(width: width)
    }

    private func syncFromUrlString(_ raw: String) {
        guard let model = UrlCurlEngine.parseUrl(raw) else { return }
        isInternalSync = true
        schemeField = model.scheme
        hostField = model.host
        portField = model.port
        pathField = model.path
        fragmentField = model.fragment
        queryParams = model.params
        DispatchQueue.main.async {
            isInternalSync = false
        }
    }

    private func rebuildToUrlInput() {
        guard !isInternalSync else { return }
        let rebuilt = UrlCurlEngine.rebuildUrl(
            scheme: schemeField,
            host: hostField,
            port: portField,
            path: pathField,
            params: queryParams,
            fragment: fragmentField
        )
        if !rebuilt.isEmpty {
            isInternalSync = true
            studio.urlInput = rebuilt
            DispatchQueue.main.async {
                isInternalSync = false
            }
        }
    }

    private func serializeParamsAsJson() -> String {
        var obj: [String: Any] = [:]
        for p in queryParams where p.enabled && !p.key.isEmpty {
            if let existing = obj[p.key] {
                if var arr = existing as? [String] {
                    arr.append(p.value)
                    obj[p.key] = arr
                } else {
                    obj[p.key] = ["\(existing)", p.value]
                }
            } else {
                obj[p.key] = p.value
            }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - 4. Radix, 64-Bit Bitwise, Chmod & Bytes View

struct RadixToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var subTab: Int = 0 // 0 = Radix & Bits, 1 = Bitwise Op, 2 = chmod & Bytes
    @State private var inputRadix: Int? = nil
    @State private var customRadix: Int = 36

    // Bitwise calc
    @State private var opInputA: String = "0xFF0F"
    @State private var opInputB: String = "0x0FF0"
    @State private var bitOp: BitwiseBinaryOp = .and

    // Chmod & Bytes
    @State private var chmodState: ChmodState = .defaultExec
    @State private var chmodRawInput: String = "755"
    @State private var byteAmountInput: String = "4"
    @State private var byteUnit: ByteUnit = .gib

    var body: some View {
        @Bindable var studio = studio
        let parsed = RadixBitwiseEngine.parse(studio.radixInput, radix: inputRadix)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .radix, subtitle: "BIN/OCT/DEC/HEX 同步互转、可点击翻转 64-bit 二进制位格、大小端转换、chmod 权限与存储单位换算")

                HStack(spacing: 8) {
                    PillButton(title: "进制 & 64 位位格", active: subTab == 0, color: .mint) { subTab = 0 }
                    PillButton(title: "位运算计算器", active: subTab == 1, color: .mint) { subTab = 1 }
                    PillButton(title: "chmod & 存储换算", active: subTab == 2, color: .mint) { subTab = 2 }
                    Spacer()
                }

                if subTab == 0 {
                    StudioPanel(title: "整数输入 (支持 0x / 0b / 0o 前缀或有符号负数)") {
                        HStack(spacing: 8) {
                            TextField("如 0xDEADBEEF, -1, 0b101010, 65535", text: $studio.radixInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13.5, design: .monospaced))

                            Menu {
                                Button("自动识别前缀 (默认10进制)") { inputRadix = nil }
                                Divider()
                                ForEach([2, 8, 10, 16, 36], id: \.self) { r in
                                    Button("按 Base \(r) 解析") { inputRadix = r }
                                }
                            } label: {
                                Text(inputRadix.map { "Base \($0)" } ?? "自动识别")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .frame(width: 110)

                            StudioToolBarButton(title: "清零", icon: "xmark.circle") { studio.radixInput = "0" }
                            StudioToolBarButton(title: "按位取反 ~", icon: "arrow.up.arrow.down") {
                                if let v = parsed { studio.radixInput = "0x" + String(~v, radix: 16, uppercase: true) }
                            }
                            StudioToolBarButton(title: "<< 1", icon: "chevron.left") {
                                if let v = parsed { studio.radixInput = "0x" + String(v << 1, radix: 16, uppercase: true) }
                            }
                            StudioToolBarButton(title: ">> 1", icon: "chevron.right") {
                                if let v = parsed { studio.radixInput = "0x" + String(v >> 1, radix: 16, uppercase: true) }
                            }
                        }

                        if let v = parsed {
                            let rep = RadixBitwiseEngine.represent(v)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                CopyableResultRow(title: "Hex (十六进制)", value: rep.hex0x, badge: "Base 16", badgeColor: .mint)
                                CopyableResultRow(title: "Unsigned Dec (无符号)", value: rep.decUnsigned, badge: "UInt64", badgeColor: .blue)
                                CopyableResultRow(title: "Signed Int64 (补码)", value: "\(rep.decSigned64)", badge: "Int64", badgeColor: .orange)
                                CopyableResultRow(title: "Octal (八进制)", value: "0o\(rep.oct)", badge: "Base 8", badgeColor: .purple)
                                CopyableResultRow(title: "Int32 / Int16 / Int8", value: "\(rep.decSigned32) / \(rep.decSigned16) / \(rep.decSigned8)", badge: "低位截取", badgeColor: .secondary)
                                CopyableResultRow(title: "大端 / 小端字节序 (Hex)", value: "BE: \(rep.beBytes)\nLE: \(rep.leBytes)", badge: "Swap64: \(rep.swap64Hex)", badgeColor: .teal)
                            }

                            HStack(spacing: 8) {
                                Text("自定义进制 (\(customRadix)):")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Stepper("", value: $customRadix, in: 2...36)
                                    .labelsHidden()
                                CopyableResultRow(title: "Base \(customRadix)", value: RadixBitwiseEngine.format(v, radix: customRadix), badge: "2–36", badgeColor: .indigo)
                            }
                        } else {
                            Text("无法解析当前数值（超出 UInt64 / Int64 范围或包含非法字符）")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }

                    if let v = parsed {
                        StudioPanel(title: "64-Bit 可交互二进制位格 (点击任意位 Bit 0–63 实时翻转)") {
                            VStack(spacing: 8) {
                                ForEach([3, 2, 1, 0], id: \.self) { rowIdx in
                                    HStack(spacing: 8) {
                                        ForEach([3, 2, 1, 0], id: \.self) { nibbleOffset in
                                            let highBit = rowIdx * 16 + nibbleOffset * 4 + 3
                                            let lowBit = highBit - 3
                                            VStack(spacing: 3) {
                                                Text(verbatim: "\(highBit)..<\(lowBit)")
                                                    .font(.system(size: 9, design: .monospaced))
                                                    .foregroundStyle(.tertiary)
                                                HStack(spacing: 2) {
                                                    ForEach((lowBit...highBit).reversed(), id: \.self) { bit in
                                                        let isOn = ((v >> bit) & 1) == 1
                                                        Button {
                                                            let toggled = RadixBitwiseEngine.toggleBit(v, at: bit)
                                                            studio.radixInput = "0x" + String(toggled, radix: 16, uppercase: true)
                                                            inputRadix = nil
                                                        } label: {
                                                            Text(isOn ? "1" : "0")
                                                                .font(.system(size: 11.5, weight: isOn ? .bold : .regular, design: .monospaced))
                                                                .frame(width: 19, height: 22)
                                                                .background(RoundedRectangle(cornerRadius: 4).fill(isOn ? Color.mint.opacity(0.24) : Color.primary.opacity(0.05)))
                                                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isOn ? Color.mint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1))
                                                                .foregroundStyle(isOn ? Color.mint : Color.secondary)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Bit \(bit)")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else if subTab == 1 {
                    bitwiseCalculatorTab
                } else {
                    chmodAndBytesTab
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var bitwiseCalculatorTab: some View {
        let aVal = RadixBitwiseEngine.parse(opInputA)
        let bVal = RadixBitwiseEngine.parse(opInputB)

        StudioPanel(title: "双操作数位运算 (A op B)") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("操作数 A (支持 0x/0b/十进制)").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("0xFF0F", text: $opInputA)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("操作数 B").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("0x0FF0", text: $opInputB)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                }
            }

            FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                ForEach(BitwiseBinaryOp.allCases, id: \.rawValue) { op in
                    PillButton(title: op.rawValue, active: bitOp == op, color: .mint) { bitOp = op }
                }
            }

            if let aVal, let bVal {
                let res = RadixBitwiseEngine.compute(a: aVal, b: bVal, op: bitOp)
                let rep = RadixBitwiseEngine.represent(res)
                CopyableResultRow(title: "Hex 结果", value: rep.hex0x, badge: bitOp.rawValue, badgeColor: .mint)
                CopyableResultRow(title: "无符号十进制 / 有符号 Int64", value: "\(rep.decUnsigned) (Int64: \(rep.decSigned64))", badge: "DEC", badgeColor: .blue)
                CopyableResultRow(title: "二进制 (64-bit)", value: rep.binGrouped64, badge: "BIN", badgeColor: .purple)
            } else {
                Text("请确保 A 与 B 均为合法整数。")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var chmodAndBytesTab: some View {
        StudioPanel(title: "Unix 文件权限 (chmod) 交互矩阵") {
            HStack(spacing: 10) {
                TextField("输入八进制 (755) 或符号 (rwxr-xr-x)", text: $chmodRawInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: 260)
                    .onChange(of: chmodRawInput) { _, val in
                        if let parsed = ChmodState.parse(val) {
                            chmodState = parsed
                        }
                    }

                ForEach(["755", "644", "600", "777", "4755"], id: \.self) { preset in
                    PillButton(title: preset, active: chmodState.octal3 == preset || chmodState.octal4 == preset, color: .mint) {
                        if let parsed = ChmodState.parse(preset) {
                            chmodState = parsed
                            chmodRawInput = preset
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                permColumn(title: "Owner (所有者)", bits: Binding(
                    get: { chmodState.ownerBits },
                    set: { chmodState.ownerBits = $0; chmodRawInput = chmodState.octal4 == "0\(chmodState.octal3)" ? chmodState.octal3 : chmodState.octal4 }
                ))
                permColumn(title: "Group (所属组)", bits: Binding(
                    get: { chmodState.groupBits },
                    set: { chmodState.groupBits = $0; chmodRawInput = chmodState.octal4 == "0\(chmodState.octal3)" ? chmodState.octal3 : chmodState.octal4 }
                ))
                permColumn(title: "Other (其他人)", bits: Binding(
                    get: { chmodState.otherBits },
                    set: { chmodState.otherBits = $0; chmodRawInput = chmodState.octal4 == "0\(chmodState.octal3)" ? chmodState.octal3 : chmodState.octal4 }
                ))
            }

            HStack(spacing: 14) {
                Toggle("SetUID (4000)", isOn: Binding(
                    get: { (chmodState.specialBits & 4) != 0 },
                    set: { on in chmodState.specialBits = on ? (chmodState.specialBits | 4) : (chmodState.specialBits & ~4) }
                )).toggleStyle(.checkbox)
                Toggle("SetGID (2000)", isOn: Binding(
                    get: { (chmodState.specialBits & 2) != 0 },
                    set: { on in chmodState.specialBits = on ? (chmodState.specialBits | 2) : (chmodState.specialBits & ~2) }
                )).toggleStyle(.checkbox)
                Toggle("Sticky Bit (1000)", isOn: Binding(
                    get: { (chmodState.specialBits & 1) != 0 },
                    set: { on in chmodState.specialBits = on ? (chmodState.specialBits | 1) : (chmodState.specialBits & ~1) }
                )).toggleStyle(.checkbox)
            }
            .font(.system(size: 12))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                CopyableResultRow(title: "chmod 命令", value: chmodState.command, badge: chmodState.octal4, badgeColor: .mint)
                CopyableResultRow(title: "符号表示 (ls -l)", value: chmodState.symbolic, badge: "Symbolic", badgeColor: .blue)
            }
        }

        StudioPanel(title: "存储容量单位换算 (SI 十进制 1000 vs IEC 二进制 1024)") {
            HStack(spacing: 8) {
                TextField("数值", text: $byteAmountInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 140)
                Picker("", selection: $byteUnit) {
                    ForEach(ByteUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .frame(width: 150)
                Spacer()
            }
            if let amt = Double(byteAmountInput.trimmingCharacters(in: .whitespaces)) {
                let rows = RadixBitwiseEngine.convertBytes(amount: amt, unit: byteUnit)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(rows) { row in
                        CopyableResultRow(title: row.unit, value: row.value)
                    }
                }
            }
        }
    }

    private func permColumn(title: String, bits: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Toggle("Read (r / 4)", isOn: Binding(get: { (bits.wrappedValue & 4) != 0 }, set: { bits.wrappedValue = $0 ? (bits.wrappedValue | 4) : (bits.wrappedValue & ~4) }))
                .toggleStyle(.checkbox)
            Toggle("Write (w / 2)", isOn: Binding(get: { (bits.wrappedValue & 2) != 0 }, set: { bits.wrappedValue = $0 ? (bits.wrappedValue | 2) : (bits.wrappedValue & ~2) }))
                .toggleStyle(.checkbox)
            Toggle("Execute (x / 1)", isOn: Binding(get: { (bits.wrappedValue & 1) != 0 }, set: { bits.wrappedValue = $0 ? (bits.wrappedValue | 1) : (bits.wrappedValue & ~1) }))
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 12))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
    }
}

// MARK: - 5. CIDR & Subnet Calculator View

struct CidrToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var probeIpInput: String = "10.0.15.200"
    @State private var splitDelta: Int = 2

    private static let presets = [
        "10.0.12.34/22",
        "192.168.1.0/24",
        "172.16.0.0/16",
        "100.64.0.0/10",
        "192.168.10.1 255.255.255.0",
        "2001:db8:85a3::/48",
    ]

    var body: some View {
        @Bindable var studio = studio
        let v4 = CidrEngine.parseIpv4Cidr(studio.cidrInput)
        let v6 = (v4 == nil && studio.cidrInput.contains(":")) ? CidrEngine.parseIpv6Cidr(studio.cidrInput) : nil

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .cidr, subtitle: "IPv4 (CIDR 与子网掩码格式) 及 IPv6 (UInt128) 网段、广播/可用主机范围计算、IP 归属测试与子网划分")

                StudioPanel(title: "输入网段 (IPv4 CIDR / 掩码 / IPv6 CIDR)") {
                    HStack(spacing: 8) {
                        TextField("如 10.0.12.34/22, 192.168.1.0 255.255.255.0, 2001:db8::/32", text: $studio.cidrInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13.5, design: .monospaced))

                        StudioToolBarButton(title: "粘贴", icon: "clipboard") {
                            let c = ClipboardService.readString()
                            if !c.isEmpty { studio.cidrInput = c }
                        }
                    }

                    FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Self.presets, id: \.self) { p in
                            PillButton(title: p, active: studio.cidrInput.trimmingCharacters(in: .whitespaces) == p, color: .teal) {
                                studio.cidrInput = p
                            }
                        }
                    }
                }

                if let v4 {
                    StudioPanel(title: "IPv4 前缀滑块与二进制边界 (/0 – /32)") {
                        HStack(spacing: 10) {
                            Text(verbatim: "/\(v4.prefix)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .frame(width: 36, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { Double(v4.prefix) },
                                    set: { newVal in
                                        studio.cidrInput = "\(v4.address)/\(Int(newVal.rounded()))"
                                    }
                                ),
                                in: 0...32,
                                step: 1
                            )
                            BadgePill(text: v4.scope, color: .teal)
                        }

                        // Colored 32-bit binary boundary visualization
                        let cleanBits = v4.binaryOctets.replacingOccurrences(of: ".", with: "")
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { octet in
                                HStack(spacing: 1) {
                                    ForEach(0..<8, id: \.self) { bitInOctet in
                                        let globalBit = octet * 8 + bitInOctet
                                        let chIdx = cleanBits.index(cleanBits.startIndex, offsetBy: globalBit)
                                        let isNetwork = globalBit < v4.prefix
                                        Text(String(cleanBits[chIdx]))
                                            .font(.system(size: 11, weight: isNetwork ? .bold : .regular, design: .monospaced))
                                            .foregroundStyle(isNetwork ? Color.teal : Color.orange)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            }
                            Spacer()
                            Text("青色=网络位(\(v4.prefix)) · 橙色=主机位(\(32 - v4.prefix))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    StudioPanel(title: "子网计算明细") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            CopyableResultRow(title: "规范 CIDR 网段", value: v4.cidrNotation, badge: "Network", badgeColor: .teal)
                            CopyableResultRow(title: "子网掩码 (Netmask)", value: v4.netmask, badge: "/\(v4.prefix)", badgeColor: .blue)
                            CopyableResultRow(title: "可用主机范围", value: "\(v4.firstHost) – \(v4.lastHost)", badge: "\(v4.usableCount) 可用", badgeColor: .green)
                            CopyableResultRow(title: "广播地址 (Broadcast)", value: v4.broadcast, badge: "总 \(v4.totalCount) IP", badgeColor: .orange)
                            CopyableResultRow(title: "反掩码 / 通配符 (Wildcard)", value: v4.wildcard, badge: "ACL/OSPF", badgeColor: .purple)
                            CopyableResultRow(title: "32 位整数 (Integer)", value: "\(v4.intValue) (0x\(String(v4.intValue, radix: 16, uppercase: true)))", badge: "UInt32", badgeColor: .secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        StudioPanel(title: "IP 归属检查") {
                            HStack(spacing: 8) {
                                TextField("输入待检测 IPv4 地址", text: $probeIpInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12.5, design: .monospaced))
                                if let inside = CidrEngine.ipv4Contains(cidr: studio.cidrInput, ip: probeIpInput) {
                                    BadgePill(
                                        text: inside ? "✓ 属于 \(v4.cidrNotation)" : "✗ 不在网段内",
                                        color: inside ? .green : .red
                                    )
                                } else {
                                    BadgePill(text: "请输入合法 IPv4", color: .secondary)
                                }
                            }
                        }

                        if v4.prefix < 32 {
                            StudioPanel(title: "等分划分子网") {
                                HStack(spacing: 6) {
                                    Text("目标掩码:")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                    ForEach(1...min(4, 32 - v4.prefix), id: \.self) { delta in
                                        let target = v4.prefix + delta
                                        PillButton(title: "/\(target) (\(1 << delta)段)", active: splitDelta == delta, color: .teal) {
                                            splitDelta = delta
                                        }
                                    }
                                }
                                let effectiveTarget = min(32, v4.prefix + min(splitDelta, 32 - v4.prefix))
                                let slices = CidrEngine.splitIpv4(studio.cidrInput, targetPrefix: effectiveTarget, limit: 32)
                                LazyVStack(spacing: 5) {
                                    ForEach(slices) { sl in
                                        CopyableResultRow(title: "子网 #\(sl.index)", value: "\(sl.cidr)  (\(sl.range))", badge: "\(sl.usableCount) 可用", badgeColor: .teal)
                                    }
                                }
                            }
                        }
                    }
                } else if let v6 {
                    StudioPanel(title: "IPv6 (128-bit) 网段分析") {
                        HStack {
                            BadgePill(text: v6.scope, color: .teal)
                            BadgePill(text: "总地址数: \(v6.addressCountText)", color: .purple)
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            CopyableResultRow(title: "压缩 CIDR 网段", value: v6.cidrNotation, badge: "RFC 5952", badgeColor: .teal)
                            CopyableResultRow(title: "输入地址压缩格式", value: v6.compressedAddress)
                            CopyableResultRow(title: "输入地址完整 8 组展开", value: v6.expandedAddress)
                            CopyableResultRow(title: "网络起始 (Start)", value: v6.compressedNetwork)
                            CopyableResultRow(title: "网络结束 (End)", value: v6.compressedEnd)
                            CopyableResultRow(title: "完整网络前缀 (Expanded)", value: v6.expandedNetwork)
                        }
                    }
                } else {
                    StudioPanel {
                        Text("无法解析当前 CIDR / IP，请检查输入格式（例如 10.0.12.34/22 或 2001:db8::/32）。")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
    }
}
