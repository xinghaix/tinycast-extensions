import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Image Drop & File Loader Helper

@MainActor
private func loadDroppedImageData(providers: [NSItemProvider], onLoaded: @escaping @MainActor (Data) -> Void) -> Bool {
    if let fileProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
        fileProvider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { urlData, _ in
            guard let urlData,
                  let url = URL(dataRepresentation: urlData, relativeTo: nil),
                  let bytes = try? Data(contentsOf: url) else { return }
            Task { @MainActor in onLoaded(bytes) }
        }
        return true
    }
    if let imgProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
        imgProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in onLoaded(data) }
        }
        return true
    }
    return false
}

// MARK: - 1. Apple Vision Offline OCR & Barcode Scanner View

struct OcrScannerToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var imageData: Data? = nil
    @State private var previewImage: NSImage? = nil
    @State private var scanResult: VisionScanResult? = nil
    @State private var editableText: String = ""
    @State private var isScanning: Bool = false
    @State private var scanError: String? = nil

    @State private var accurateMode: Bool = true
    @State private var selectedLangId: String = "zh-en"
    @State private var isDropTargeted: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .ocr, subtitle: "调用 Apple Vision 系统原生框架，100% 本地离线识别截图文字（中英日代码）与二维码/条形码")

                StudioPanel {
                    HStack(spacing: 8) {
                        StudioToolBarButton(title: "框选截屏识字", icon: "camera.viewfinder", tint: .purple) {
                            runScreenCapture()
                        }
                        StudioToolBarButton(title: "读取剪贴板图片", icon: "clipboard") {
                            if let d = ImageToolEngine.readClipboardImageData() {
                                acceptImageData(d)
                            } else {
                                studio.showToast("剪贴板中未检测到图片数据", isError: true)
                            }
                        }
                        StudioToolBarButton(title: "选择本地图片", icon: "photo") {
                            openImageFile()
                        }
                        Spacer()
                        Toggle("高精度模型", isOn: $accurateMode)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                            .onChange(of: accurateMode) { _, _ in reRunIfLoaded() }
                    }

                    HStack(spacing: 6) {
                        Text("识别语言:")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(VisionImageEngine.languagePresets, id: \.id) { preset in
                            PillButton(title: preset.title, active: selectedLangId == preset.id, color: .purple) {
                                selectedLangId = preset.id
                                reRunIfLoaded()
                            }
                        }
                        Spacer()
                        if let res = scanResult {
                            BadgePill(text: "\(res.imageWidth)×\(res.imageHeight) · \(res.elapsedMs) ms", color: .purple)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    StudioPanel(title: "待识别图片 (支持直接拖入图片文件)") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    isDropTargeted ? Color.purple : Color.primary.opacity(0.14),
                                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isDropTargeted ? Color.purple.opacity(0.08) : Color.primary.opacity(0.02))
                                )

                            if let nsImg = previewImage {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "text.viewfinder")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.purple.opacity(0.7))
                                    Text("点击「框选截屏识字」或拖入图片到此处")
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("支持 PNG / JPEG / HEIC / TIFF / WebP / 二维码截图")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(20)
                            }
                        }
                        .frame(minHeight: 240, maxHeight: 320)
                        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                            loadDroppedImageData(providers: providers) { data in
                                acceptImageData(data)
                            }
                        }

                        if let err = scanError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }

                    StudioPanel(title: "识别结果 (可编辑)") {
                        if isScanning {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Apple Vision 离线识别中…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            EditorBoxView(text: $editableText, height: 240)
                            HStack(spacing: 8) {
                                CopyActionButton(text: editableText, label: "复制全文") { _ in
                                    studio.showToast("已复制识别文本")
                                }
                                if !editableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    StudioToolBarButton(title: "送到智能工作台 →", icon: "sparkles") {
                                        studio.smartInput = editableText
                                        studio.jump(to: .smart)
                                    }
                                    StudioToolBarButton(title: "去格式工具 →", icon: "doc.plaintext") {
                                        studio.textInput = editableText
                                        studio.jump(to: .text)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                if let res = scanResult, !res.barcodes.isEmpty {
                    StudioPanel(title: "检测到二维码 / 条形码 (\(res.barcodes.count))") {
                        LazyVStack(spacing: 8) {
                            ForEach(res.barcodes) { code in
                                CopyableResultRow(
                                    title: code.symbology,
                                    value: code.payload,
                                    badge: code.payload.lowercased().hasPrefix("http") ? "URL" : "Barcode",
                                    badgeColor: .green,
                                    secondaryButton: code.payload.lowercased().hasPrefix("http")
                                        ? ("打开链接", "safari", {
                                            if let url = URL(string: code.payload) { NSWorkspace.shared.open(url) }
                                        })
                                        : ("智能解析", "sparkles", {
                                            studio.smartInput = code.payload
                                            studio.jump(to: .smart)
                                        })
                                )
                            }
                        }
                    }
                }

                if let res = scanResult, !res.lines.isEmpty {
                    StudioPanel(title: "逐行识别明细 (\(res.lines.count) 行 · 点击任意行复制)") {
                        LazyVStack(spacing: 6) {
                            ForEach(res.lines) { line in
                                CopyableResultRow(
                                    title: "第 \(line.id + 1) 行",
                                    value: line.text,
                                    badge: String(format: "%.0f%%", line.confidence * 100),
                                    badgeColor: line.confidence >= 0.85 ? .green : .orange
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func runScreenCapture() {
        Task {
            guard let captured = await VisionImageEngine.captureScreenRegion() else {
                await MainActor.run {
                    studio.showToast("已取消截屏或未授予屏幕录制权限")
                }
                return
            }
            await MainActor.run {
                acceptImageData(captured)
            }
        }
    }

    private func openImageFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            acceptImageData(data)
        }
    }

    @MainActor
    private func acceptImageData(_ data: Data) {
        imageData = data
        previewImage = NSImage(data: data)
        scanError = nil
        runOcr(on: data)
    }

    private func reRunIfLoaded() {
        if let d = imageData {
            runOcr(on: d)
        }
    }

    @MainActor
    private func runOcr(on data: Data) {
        isScanning = true
        let accurate = accurateMode
        let langs = VisionImageEngine.languagePresets.first(where: { $0.id == selectedLangId })?.codes ?? ["zh-Hans", "zh-Hant", "en-US"]
        Task {
            do {
                let res = try await VisionImageEngine.scanImageData(data, accurate: accurate, languages: langs)
                await MainActor.run {
                    scanResult = res
                    editableText = res.fullText
                    isScanning = false
                    studio.showToast("识别完成: \(res.lines.count) 行文本, \(res.barcodes.count) 个二维码/条码")
                }
            } catch {
                await MainActor.run {
                    scanError = error.localizedDescription
                    isScanning = false
                }
            }
        }
    }
}

// MARK: - 2. Image Converter, Resizer, EXIF Stripper & DataURI View

private enum ImageResizeOption: String, CaseIterable, Identifiable {
    case original = "原尺寸"
    case w1920 = "限制宽 1920px"
    case w1280 = "限制宽 1280px"
    case w800 = "限制宽 800px"
    case pct50 = "50% 缩放"
    case custom = "自定义宽度"

    var id: String { rawValue }
}

struct ImageConverterToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var sourceData: Data? = nil
    @State private var sourceInfo: ImageSourceInfo? = nil
    @State private var previewImage: NSImage? = nil

    @State private var exportFormat: ImageExportFormat = .png
    @State private var quality: Double = 0.85
    @State private var resizeOption: ImageResizeOption = .original
    @State private var customMaxWidthText: String = "1024"
    @State private var stripMetadata: Bool = true
    @State private var showExifDetails: Bool = false
    @State private var isDropTargeted: Bool = false

    @State private var convertResult: ImageConvertResult? = nil
    @State private var convertError: String? = nil
    @State private var isConverting: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(tool: .image, subtitle: "基于原生 ImageIO + CoreGraphics 离线转换格式 (PNG/JPEG/HEIC/TIFF/GIF/WebP)、尺寸缩放、EXIF/GPS 隐私剥离与 DataURI 编码")

                HStack(spacing: 8) {
                    StudioToolBarButton(title: "选择本地图片", icon: "photo", tint: .pink) { openImageFile() }
                    StudioToolBarButton(title: "从剪贴板读取图片", icon: "clipboard") {
                        if let d = ImageToolEngine.readClipboardImageData() {
                            acceptImage(d)
                        } else {
                            studio.showToast("剪贴板中无图片或 DataURI", isError: true)
                        }
                    }
                    if let srcInfo = sourceInfo {
                        BadgePill(text: "\(srcInfo.formatName) · \(srcInfo.width)×\(srcInfo.height) · \(ImageToolEngine.humanByteSize(srcInfo.byteSize))", color: .blue)
                        if srcInfo.hasGpsMetadata {
                            BadgePill(text: "⚠ 含 GPS 定位信息", color: .red)
                        } else if srcInfo.exifCount > 0 {
                            BadgePill(text: "含 \(srcInfo.exifCount) 项 EXIF/TIFF 属性", color: .orange)
                        } else {
                            BadgePill(text: "无敏感 EXIF/GPS 元数据", color: .green)
                        }
                    }
                    Spacer()
                }

                HStack(alignment: .top, spacing: 12) {
                    StudioPanel(title: "源图片与隐私检查 (支持直接拖入)") {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    isDropTargeted ? Color.pink : Color.primary.opacity(0.14),
                                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(isDropTargeted ? Color.pink.opacity(0.08) : Color.primary.opacity(0.02))
                                )

                            if let nsImg = previewImage {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.pink.opacity(0.75))
                                    Text("拖入或选择图片，或从剪贴板粘贴截图")
                                        .font(.system(size: 12.5, weight: .medium))
                                    Text("默认自动勾选「剥离 EXIF 与 GPS 位置信息」防止发图泄密")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(20)
                            }
                        }
                        .frame(minHeight: 205, maxHeight: 260)
                        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                            loadDroppedImageData(providers: providers) { d in acceptImage(d) }
                        }

                        if let info = sourceInfo, !info.metadataEntries.isEmpty {
                            HStack {
                                Button {
                                    showExifDetails.toggle()
                                } label: {
                                    Label(showExifDetails ? "收起 EXIF 元数据明细 (\(info.metadataEntries.count))" : "查看 EXIF / GPS 元数据明细 (\(info.metadataEntries.count))", systemImage: showExifDetails ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            if showExifDetails {
                                ScrollView {
                                    LazyVStack(spacing: 4) {
                                        ForEach(info.metadataEntries.prefix(80)) { entry in
                                            HStack(spacing: 8) {
                                                BadgePill(text: entry.section, color: entry.section == "GPS" ? .red : .secondary)
                                                Text(entry.key)
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .frame(width: 150, alignment: .leading)
                                                Text(entry.value)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 150)
                            }
                        }
                    }

                    StudioPanel(title: "导出配置") {
                        Text("目标格式:")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(ImageExportFormat.allCases) { fmt in
                                let label = (fmt == .webp && ImageToolEngine.cwebpExecutablePath == nil) ? "WebP (需cwebp)" : fmt.rawValue
                                PillButton(title: label, active: exportFormat == fmt, color: .pink) {
                                    exportFormat = fmt
                                    triggerConvert()
                                }
                            }
                        }

                        if exportFormat.supportsQualitySlider {
                            HStack(spacing: 8) {
                                Text(verbatim: "画质: \(Int((quality * 100).rounded()))%")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .frame(width: 82, alignment: .leading)
                                Slider(value: $quality, in: 0.1...1.0, step: 0.05) { editing in
                                    if !editing { triggerConvert() }
                                }
                            }
                        }

                        Text("尺寸缩放:")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        FlowWrapLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(ImageResizeOption.allCases) { opt in
                                PillButton(title: opt.rawValue, active: resizeOption == opt, color: .indigo) {
                                    resizeOption = opt
                                    triggerConvert()
                                }
                            }
                        }

                        if resizeOption == .custom {
                            HStack(spacing: 8) {
                                Text("最大宽度 (px):")
                                    .font(.system(size: 11.5))
                                TextField("1024", text: $customMaxWidthText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                    .onSubmit { triggerConvert() }
                                StudioToolBarButton(title: "应用", icon: "checkmark") { triggerConvert() }
                            }
                        }

                        Toggle("🔒 剥离 EXIF、GPS 与相机元数据（防隐私泄漏）", isOn: $stripMetadata)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                            .onChange(of: stripMetadata) { _, _ in triggerConvert() }

                        Divider()

                        if isConverting {
                            ProgressView("正在处理图片…").controlSize(.small)
                        } else if let err = convertError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        } else if let res = convertResult {
                            let pct = res.originalBytes > 0
                                ? Int(((Double(res.outputBytes - res.originalBytes) / Double(res.originalBytes)) * 100.0).rounded())
                                : 0
                            let deltaStr = pct <= 0 ? "\(pct)% 体积" : "+\(pct)% 体积"

                            HStack(spacing: 6) {
                                BadgePill(text: "\(res.width)×\(res.height) · \(ImageToolEngine.humanByteSize(res.outputBytes))", color: .green)
                                BadgePill(text: deltaStr, color: pct <= 0 ? .green : .orange)
                                if res.strippedMetadata { BadgePill(text: "已脱敏", color: .teal) }
                            }

                            FlowWrapLayout(spacing: 8, lineSpacing: 8) {
                                StudioToolBarButton(title: "保存图片文件", icon: "square.and.arrow.down", tint: .pink) {
                                    saveExportedImage(res)
                                }
                                StudioToolBarButton(title: "复制图片对象", icon: "photo.badge.checkmark", tint: .blue) {
                                    copyExportedImage(res)
                                }
                                CopyActionButton(text: res.dataUri, label: "复制 DataURI (\(res.dataUri.count)B)") { _ in
                                    studio.showToast("已复制 Base64 DataURI")
                                }
                                CopyActionButton(text: "<img src=\"\(res.dataUri)\" alt=\"image\" />", label: "复制 HTML <img>") { _ in
                                    studio.showToast("已复制 HTML <img> 标签")
                                }
                            }
                        } else {
                            Text("载入图片后将自动生成导出预览与压缩比统计。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func openImageFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            acceptImage(data)
        }
    }

    @MainActor
    private func acceptImage(_ data: Data) {
        sourceData = data
        previewImage = NSImage(data: data)
        sourceInfo = ImageToolEngine.inspectImageData(data)
        showExifDetails = false
        triggerConvert()
    }

    @MainActor
    private func triggerConvert() {
        guard let data = sourceData else { return }
        isConverting = true
        convertError = nil

        let fmt = exportFormat
        let q = quality
        let strip = stripMetadata
        let maxW: Int?
        let scalePct: Int?

        switch resizeOption {
        case .original: maxW = nil; scalePct = nil
        case .w1920: maxW = 1920; scalePct = nil
        case .w1280: maxW = 1280; scalePct = nil
        case .w800: maxW = 800; scalePct = nil
        case .pct50: maxW = nil; scalePct = 50
        case .custom: maxW = Int(customMaxWidthText.trimmingCharacters(in: .whitespaces)); scalePct = nil
        }

        Task {
            do {
                let res = try await ImageToolEngine.convertImageData(
                    data,
                    format: fmt,
                    quality: q,
                    maxWidth: maxW,
                    scalePercent: scalePct,
                    stripMetadata: strip
                )
                await MainActor.run {
                    convertResult = res
                    isConverting = false
                }
            } catch {
                await MainActor.run {
                    convertError = error.localizedDescription
                    convertResult = nil
                    isConverting = false
                }
            }
        }
    }

    private func saveExportedImage(_ res: ImageConvertResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tinycast-converted.\(res.format.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try res.outputData.write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                studio.showToast("已保存 \(url.lastPathComponent)")
            } catch {
                studio.showToast("保存失败: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func copyExportedImage(_ res: ImageConvertResult) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let pbType = NSPasteboard.PasteboardType(res.format.utTypeIdentifier)
        pb.setData(res.outputData, forType: pbType)
        if let img = NSImage(data: res.outputData) {
            pb.writeObjects([img])
        }
        studio.showToast("已复制转换后的 \(res.format.rawValue) 图片")
    }
}
