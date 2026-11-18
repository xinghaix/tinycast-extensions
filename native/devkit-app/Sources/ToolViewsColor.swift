import AppKit
import SwiftUI

enum ColorSubTab: String, CaseIterable, Sendable {
    case convert = "格式与调色"
    case contrast = "WCAG 对比度"
    case palette = "配色与色阶"
    case mixCvd = "渐变 & 色盲"
}

enum ColorSliderSpace: String, CaseIterable, Sendable {
    case rgb = "RGB"
    case hsl = "HSL"
    case hsv = "HSV"
    case oklch = "OKLCH"
    case cmyk = "CMYK"
}

// MARK: - Swatch & Checkerboard Helpers

struct CheckerboardPattern: View {
    var cellSize: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let light = Color(white: 0.92)
            let dark = Color(white: 0.78)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for r in 0..<rows {
                for c in 0..<cols where (r + c).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(c) * cellSize, y: CGFloat(r) * cellSize, width: cellSize, height: cellSize)
                    context.fill(Path(rect), with: .color(dark))
                }
            }
        }
    }
}

struct ColorSwatchTile: View {
    let color: ColorRGBA
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            CheckerboardPattern()
            HStack(spacing: 0) {
                Color(red: color.r, green: color.g, blue: color.b)
                if color.hasAlpha {
                    Color(red: color.r, green: color.g, blue: color.b, opacity: color.a)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
    }
}

// MARK: - Main Color Studio View

struct ColorToolView: View {
    @Environment(StudioState.self) private var studio

    @State private var activeTab: ColorSubTab = .convert
    @State private var sliderSpace: ColorSliderSpace = .rgb
    @State private var formatFilterGroup: ColorFormatEntry.Group? = nil
    @State private var rgba: ColorRGBA = ColorEngine.parse("#3B82F6") ?? ColorRGBA(r: 0.231, g: 0.510, b: 0.965)
    @State private var suppressInputSync: Bool = false
    @State private var autoCopyEyedropper: Bool = true
    @State private var colorHistory: [String] = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6"]

    // Slider backing states (keeps smooth drags without 8-bit hex rounding jitter)
    @State private var hslState: ColorHSL = ColorHSL(h: 217, s: 91, l: 60, a: 1)
    @State private var hsvState: ColorHSV = ColorHSV(h: 217, s: 76, v: 96, a: 1)
    @State private var oklchState: ColorOKLCH = ColorOKLCH(l: 0.623, c: 0.188, h: 259.8, a: 1)
    @State private var cmykState: ColorCMYK = ColorCMYK(c: 76, m: 47, y: 0, k: 4)

    // WCAG Contrast state
    @State private var contrastBgInput: String = "#FFFFFF"
    @State private var contrastBg: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1)
    @State private var contrastSwapUseFgAsCurrent: Bool = true

    // Mix & Gradient state
    @State private var mixEndInput: String = "#8B5CF6"
    @State private var mixEndColor: ColorRGBA = ColorEngine.parse("#8B5CF6") ?? ColorRGBA(r: 0.545, g: 0.361, b: 0.965)
    @State private var mixSpace: ColorEngine.MixSpace = .oklch
    @State private var mixSteps: Int = 7
    @State private var gradientAngle: Double = 135

    var body: some View {
        @Bindable var studio = studio
        let parsed = ColorEngine.parse(studio.colorInput)
        let matches = ColorEngine.nearestNamedMatches(to: rgba)
        let luminance = ColorEngine.relativeLuminance(rgba)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(
                    tool: .color,
                    subtitle: "Hex / RGB / HSL / HSV / OKLCH / Lab / HWB / CMYK / SwiftUI / Android 全格式互转、屏幕吸管取色、WCAG 对比度、Tailwind 色阶与色盲模拟"
                )

                // Hero Swatch & Input Panel
                StudioPanel {
                    HStack(alignment: .center, spacing: 12) {
                        ColorSwatchTile(color: rgba, cornerRadius: 12)
                            .frame(width: 68, height: 68)

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                TextField("输入任意色值：#3B82F6 / oklch(62% 0.21 259) / rgb(59 130 246 / 80%) / rebeccapurple / blue-500 / Color(0xFF...)", text: $studio.colorInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12.5, design: .monospaced))

                                ColorPicker("", selection: swiftColorBinding, supportsOpacity: true)
                                    .labelsHidden()
                                    .help("系统调色板")

                                StudioToolBarButton(title: "屏幕取色", icon: "eyedropper.halffull", tint: .pink) {
                                    launchEyedropper()
                                }
                                StudioToolBarButton(title: "随机色", icon: "dice") {
                                    let rnd = ColorRGBA(r: .random(in: 0...1), g: .random(in: 0...1), b: .random(in: 0...1), a: 1.0)
                                    applyColor(rnd, textOverride: rnd.hexAutoUpper)
                                }
                            }

                            HStack(spacing: 6) {
                                if parsed == nil && !studio.colorInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    BadgePill(text: "✗ 未能解析该色值格式", color: .red)
                                } else {
                                    BadgePill(text: "亮度 Y: \(String(format: "%.3f", luminance))", color: luminance > 0.5 ? .orange : .indigo)
                                    if let css = matches.css {
                                        BadgePill(text: "CSS ≈ \(css.name) (ΔE \(String(format: "%.1f", css.deltaE)))", color: .blue)
                                    }
                                    if let tw = matches.tailwind {
                                        BadgePill(text: "TW ≈ \(tw.name) (ΔE \(String(format: "%.1f", tw.deltaE)))", color: .teal)
                                    }
                                }

                                Spacer()

                                Toggle("取色自动复制 Hex", isOn: $autoCopyEyedropper)
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 11.5))
                            }
                        }
                    }

                    // Quick Strip: Presets + History Dots
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("最近:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            ForEach(colorHistory, id: \.self) { hex in
                                if let c = ColorEngine.parse(hex) {
                                    Button {
                                        applyColor(c, textOverride: hex, recordHistory: false)
                                    } label: {
                                        ColorSwatchTile(color: c, cornerRadius: 5)
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help("切换到 \(hex)")
                                }
                            }
                            Divider().frame(height: 16)
                            ForEach(ColorEngine.presets, id: \.hex) { preset in
                                if let c = ColorEngine.parse(preset.hex) {
                                    Button {
                                        applyColor(c, textOverride: preset.hex)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color(red: c.r, green: c.g, blue: c.b))
                                                .frame(width: 9, height: 9)
                                            Text(preset.title)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3.5)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Sub-Tab Switcher
                HStack(spacing: 6) {
                    ForEach(ColorSubTab.allCases, id: \.rawValue) { tab in
                        PillButton(title: tab.rawValue, active: activeTab == tab, color: .pink) {
                            activeTab = tab
                        }
                    }
                    Spacer()
                    CopyActionButton(text: rgba.hexAutoUpper, label: "复制 \(rgba.hexAutoUpper)") { _ in
                        studio.showToast("已复制 \(rgba.hexAutoUpper)")
                    }
                }

                switch activeTab {
                case .convert:
                    convertAndSlidersTab
                case .contrast:
                    contrastTab
                case .palette:
                    paletteAndHarmoniesTab
                case .mixCvd:
                    mixAndCvdTab
                }
            }
            .padding(16)
        }
        .onAppear {
            if let initial = ColorEngine.parse(studio.colorInput) {
                rgba = initial
                syncSubSpaces(from: initial)
            }
        }
        .onChange(of: studio.colorInput) { _, newValue in
            guard !suppressInputSync else {
                suppressInputSync = false
                return
            }
            if let c = ColorEngine.parse(newValue) {
                rgba = c
                syncSubSpaces(from: c)
                pushHistory(c.hexAutoUpper)
            }
        }
    }

    // MARK: - Tab 1: Sliders & Full Formats Matrix

    private var convertAndSlidersTab: some View {
        let allFormats = ColorEngine.formatAll(rgba)
        let visible = allFormats.filter { formatFilterGroup == nil || $0.group == formatFilterGroup }

        return VStack(alignment: .leading, spacing: 12) {
            StudioPanel(title: "多空间实时调色滑块") {
                HStack(spacing: 6) {
                    ForEach(ColorSliderSpace.allCases, id: \.rawValue) { sp in
                        PillButton(title: sp.rawValue, active: sliderSpace == sp, color: .indigo) {
                            sliderSpace = sp
                        }
                    }
                    Spacer()
                }

                sliderControlsView
            }

            HStack(spacing: 6) {
                PillButton(title: "全部分组 (\(allFormats.count))", active: formatFilterGroup == nil, color: .pink) {
                    formatFilterGroup = nil
                }
                ForEach(ColorFormatEntry.Group.allCases, id: \.rawValue) { grp in
                    PillButton(title: grp.rawValue, active: formatFilterGroup == grp, color: .pink) {
                        formatFilterGroup = grp
                    }
                }
                Spacer()
            }

            ForEach(ColorFormatEntry.Group.allCases, id: \.rawValue) { grp in
                let items = visible.filter { $0.group == grp }
                if !items.isEmpty {
                    StudioPanel(title: grp.rawValue) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(items) { item in
                                CopyableResultRow(title: item.title, value: item.value, badge: item.badge, badgeColor: .pink)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sliderControlsView: some View {
        switch sliderSpace {
        case .rgb:
            ColorChannelSlider(label: "R (红)", value: rgbChannelBinding(\.r, scale: 255), range: 0...255, display: "\(rgba.r255)", tint: .red)
            ColorChannelSlider(label: "G (绿)", value: rgbChannelBinding(\.g, scale: 255), range: 0...255, display: "\(rgba.g255)", tint: .green)
            ColorChannelSlider(label: "B (蓝)", value: rgbChannelBinding(\.b, scale: 255), range: 0...255, display: "\(rgba.b255)", tint: .blue)
            alphaSlider
        case .hsl:
            ColorChannelSlider(label: "H (色相)", value: hslBinding(\.h), range: 0...360, display: "\(Int(hslState.h.rounded()))°", tint: .orange)
            ColorChannelSlider(label: "S (饱和)", value: hslBinding(\.s), range: 0...100, display: "\(Int(hslState.s.rounded()))%", tint: .pink)
            ColorChannelSlider(label: "L (亮度)", value: hslBinding(\.l), range: 0...100, display: "\(Int(hslState.l.rounded()))%", tint: .purple)
            alphaSlider
        case .hsv:
            ColorChannelSlider(label: "H (色相)", value: hsvBinding(\.h), range: 0...360, display: "\(Int(hsvState.h.rounded()))°", tint: .orange)
            ColorChannelSlider(label: "S (饱和)", value: hsvBinding(\.s), range: 0...100, display: "\(Int(hsvState.s.rounded()))%", tint: .pink)
            ColorChannelSlider(label: "V (明度)", value: hsvBinding(\.v), range: 0...100, display: "\(Int(hsvState.v.rounded()))%", tint: .yellow)
            alphaSlider
        case .oklch:
            ColorChannelSlider(label: "L (感知亮度)", value: oklchLBinding, range: 0...100, display: String(format: "%.1f%%", oklchState.l * 100), tint: .indigo)
            ColorChannelSlider(label: "C (色度)", value: oklchBinding(\.c), range: 0...0.37, display: String(format: "%.4f", oklchState.c), tint: .purple)
            ColorChannelSlider(label: "H (色相)", value: oklchBinding(\.h), range: 0...360, display: String(format: "%.1f°", oklchState.h), tint: .orange)
            alphaSlider
        case .cmyk:
            ColorChannelSlider(label: "C (青)", value: cmykBinding(\.c), range: 0...100, display: "\(Int(cmykState.c.rounded()))%", tint: .cyan)
            ColorChannelSlider(label: "M (品红)", value: cmykBinding(\.m), range: 0...100, display: "\(Int(cmykState.m.rounded()))%", tint: .pink)
            ColorChannelSlider(label: "Y (黄)", value: cmykBinding(\.y), range: 0...100, display: "\(Int(cmykState.y.rounded()))%", tint: .yellow)
            ColorChannelSlider(label: "K (黑)", value: cmykBinding(\.k), range: 0...100, display: "\(Int(cmykState.k.rounded()))%", tint: .primary)
        }
    }

    private var alphaSlider: some View {
        ColorChannelSlider(
            label: "Alpha",
            value: Binding(
                get: { rgba.a * 100.0 },
                set: { newPct in
                    var updated = rgba
                    updated.a = min(max(newPct / 100.0, 0), 1)
                    applyColor(updated, textOverride: updated.hexAutoUpper, keepSubSpace: nil, recordHistory: false)
                }
            ),
            range: 0...100,
            display: "\(Int((rgba.a * 100.0).rounded()))%",
            tint: .secondary
        )
    }

    // MARK: - Tab 2: WCAG 2.1 & APCA Contrast Checker

    private var contrastTab: some View {
        let fg = contrastSwapUseFgAsCurrent ? rgba : contrastBg
        let bg = contrastSwapUseFgAsCurrent ? contrastBg : rgba
        let report = ColorEngine.evaluateContrast(foreground: fg, background: bg)
        let ratioStr = String(format: "%.2f : 1", report.ratio)
        let lcStr = String(format: "Lc %.1f", abs(report.apcaLc))
        let ratioColor: Color = report.aaaNormal ? .green : (report.aaNormal ? .blue : (report.aaLarge ? .orange : .red))
        let fixedAa = ColorEngine.autoFixForContrast(foreground: fg, background: bg, targetRatio: 4.5)
        let fixedAaa = ColorEngine.autoFixForContrast(foreground: fg, background: bg, targetRatio: 7.0)

        return VStack(alignment: .leading, spacing: 12) {
            StudioPanel(title: "前景与背景配对") {
                HStack(spacing: 10) {
                    Text(contrastSwapUseFgAsCurrent ? "当前主色作为文字(前景色)" : "当前主色作为底色(背景色)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StudioToolBarButton(title: "⇅ 互换前景 / 背景", icon: "arrow.left.arrow.right") {
                        contrastSwapUseFgAsCurrent.toggle()
                    }
                    StudioToolBarButton(title: "白色底 #FFFFFF", icon: "sun.max") {
                        contrastBgInput = "#FFFFFF"
                        contrastBg = ColorRGBA(r: 1, g: 1, b: 1)
                    }
                    StudioToolBarButton(title: "深色底 #0F172A", icon: "moon") {
                        contrastBgInput = "#0F172A"
                        contrastBg = ColorEngine.parse("#0F172A") ?? contrastBg
                    }
                }

                HStack(spacing: 10) {
                    ColorSwatchTile(color: contrastBg, cornerRadius: 7)
                        .frame(width: 28, height: 28)
                    Text("对照色:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("输入对比色 (如 #FFFFFF / #0F172A)", text: $contrastBgInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5, design: .monospaced))
                        .onChange(of: contrastBgInput) { _, val in
                            if let parsed = ColorEngine.parse(val) {
                                contrastBg = parsed
                            }
                        }
                    StudioToolBarButton(title: "屏幕取对照色", icon: "eyedropper") {
                        ColorEngine.pickFromScreen { picked in
                            guard let picked else { return }
                            contrastBg = picked
                            contrastBgInput = picked.hexAutoUpper
                        }
                    }
                }
            }

            StudioPanel {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WCAG 2.1 对比度")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(verbatim: ratioStr)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(ratioColor)
                        Text(verbatim: "APCA 感知对比度: \(lcStr)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            WcagStatusBadge(title: "正文 AA (≥4.5)", passed: report.aaNormal)
                            WcagStatusBadge(title: "正文 AAA (≥7.0)", passed: report.aaaNormal)
                        }
                        HStack(spacing: 6) {
                            WcagStatusBadge(title: "大字/图标 AA (≥3.0)", passed: report.aaLarge)
                            WcagStatusBadge(title: "大字 AAA (≥4.5)", passed: report.aaaLarge)
                        }
                    }
                }

                // Live UI Rendering Preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("大号标题预览 (20pt Bold · Great UX Readability)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: fg.r, green: fg.g, blue: fg.b, opacity: fg.a))
                    Text("正文内容预览：在真实背景上的可读性测试。如果前景色带透明度，已自动与背景混合后计算准确亮度。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: fg.r, green: fg.g, blue: fg.b, opacity: fg.a))
                    HStack(spacing: 8) {
                        Text("按钮文本 Button")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: fg.r, green: fg.g, blue: fg.b, opacity: fg.a)))
                            .foregroundStyle(Color(red: bg.r, green: bg.g, blue: bg.b))
                        Text(verbatim: "前景色 \(fg.hexAutoUpper)  在  背景色 \(bg.hexAutoUpper)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: fg.r, green: fg.g, blue: fg.b, opacity: fg.a).opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    ZStack {
                        CheckerboardPattern()
                        Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            }

            if !report.aaNormal || !report.aaaNormal {
                StudioPanel(title: "无障碍自动达标建议 (保持色相与色度，在 OKLCH 空间调整亮度)") {
                    if !report.aaNormal {
                        let aaRatio = ColorEngine.evaluateContrast(foreground: fixedAa, background: bg).ratio
                        CopyableResultRow(
                            title: "推荐达标 AA 文本色",
                            value: fixedAa.hexAutoUpper,
                            badge: String(format: "%.2f : 1", aaRatio),
                            badgeColor: .blue,
                            secondaryButton: ("应用到当前色", "checkmark.circle", {
                                if contrastSwapUseFgAsCurrent {
                                    applyColor(fixedAa, textOverride: fixedAa.hexAutoUpper)
                                } else {
                                    contrastBg = fixedAa
                                    contrastBgInput = fixedAa.hexAutoUpper
                                }
                            })
                        )
                    }
                    if !report.aaaNormal {
                        let aaaRatio = ColorEngine.evaluateContrast(foreground: fixedAaa, background: bg).ratio
                        CopyableResultRow(
                            title: "推荐高可读 AAA 文本色",
                            value: fixedAaa.hexAutoUpper,
                            badge: String(format: "%.2f : 1", aaaRatio),
                            badgeColor: .green,
                            secondaryButton: ("应用到当前色", "checkmark.circle", {
                                if contrastSwapUseFgAsCurrent {
                                    applyColor(fixedAaa, textOverride: fixedAaa.hexAutoUpper)
                                } else {
                                    contrastBg = fixedAaa
                                    contrastBgInput = fixedAaa.hexAutoUpper
                                }
                            })
                        )
                    }
                }
            }
        }
    }

    // MARK: - Tab 3: Tailwind Scale & Harmonies

    private var paletteAndHarmoniesTab: some View {
        let shades = ColorEngine.tailwindScale(for: rgba)
        let harmonies = ColorEngine.harmonies(for: rgba)

        let cssVars = shades.map { "  --color-primary-\($0.step): \($0.color.hexAutoLower);" }.joined(separator: "\n")
        let cssBlock = ":root {\n\(cssVars)\n}"
        let twJson = "{\n" + shades.map { "  \"\($0.step)\": \"\($0.color.hexAutoLower)\"" }.joined(separator: ",\n") + "\n}"

        return VStack(alignment: .leading, spacing: 12) {
            StudioPanel(title: "OKLCH 均匀色阶生成器 (Tailwind 50–950 规范)") {
                HStack(spacing: 4) {
                    ForEach(shades) { shade in
                        Button {
                            studio.copy(shade.color.hexAutoUpper, label: "已复制色阶 \(shade.step): \(shade.color.hexAutoUpper)")
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color(red: shade.color.r, green: shade.color.g, blue: shade.color.b))
                                        .frame(height: 52)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(shade.isBase ? Color.primary : Color.primary.opacity(0.08), lineWidth: shade.isBase ? 2 : 1)
                                        )
                                    if shade.isBase {
                                        let lum = ColorEngine.relativeLuminance(shade.color)
                                        Text("基准")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(lum > 0.35 ? Color.black : Color.white)
                                    }
                                }
                                Text("\(shade.step)")
                                    .font(.system(size: 10.5, weight: shade.isBase ? .bold : .semibold, design: .monospaced))
                                Text(shade.color.hex6Upper)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("复制 \(shade.color.hex6Upper)") {
                                studio.copy(shade.color.hex6Upper, label: "已复制 \(shade.color.hex6Upper)")
                            }
                            Button("将此色阶设为主色") {
                                applyColor(shade.color, textOverride: shade.color.hexAutoUpper)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text("点击任意色块直接复制 Hex；右键可为主色调切换基准色。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    CopyActionButton(text: cssBlock, label: "复制 CSS 变量 (:root)") { _ in
                        studio.showToast("已复制 11 级 CSS 变量")
                    }
                    CopyActionButton(text: twJson, label: "复制 Tailwind JSON") { _ in
                        studio.showToast("已复制 Tailwind 配色 JSON")
                    }
                }
            }

            StudioPanel(title: "色环配色和谐方案 (HSL 角度派生)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(harmonies) { grp in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(grp.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(grp.items) { item in
                                    Button {
                                        studio.copy(item.color.hexAutoUpper, label: "已复制 \(item.role): \(item.color.hexAutoUpper)")
                                    } label: {
                                        HStack(spacing: 8) {
                                            ColorSwatchTile(color: item.color, cornerRadius: 6)
                                                .frame(width: 28, height: 28)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.role)
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(item.color.hexAutoUpper)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(7)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07)))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("设为当前主色") {
                                            applyColor(item.color, textOverride: item.color.hexAutoUpper)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 4: Color Mixer / Gradient & CVD Simulation

    private var mixAndCvdTab: some View {
        let mixed = ColorEngine.mix(rgba, mixEndColor, steps: mixSteps, space: mixSpace)
        let cvds = ColorEngine.simulateCvd(rgba)

        let cssStops = mixed.enumerated().map { idx, col in
            let pct = Int((Double(idx) / Double(max(1, mixed.count - 1)) * 100.0).rounded())
            return "\(col.hexAutoLower) \(pct)%"
        }.joined(separator: ", ")
        let cssGrad = "background: linear-gradient(\(Int(gradientAngle.rounded()))deg, \(cssStops));"

        let swiftStops = mixed.map { "Color(red: \(String(format: "%.3f", $0.r)), green: \(String(format: "%.3f", $0.g)), blue: \(String(format: "%.3f", $0.b)))" }.joined(separator: ", ")
        let swiftGrad = "LinearGradient(colors: [\(swiftStops)], startPoint: .topLeading, endPoint: .bottomTrailing)"

        return VStack(alignment: .leading, spacing: 12) {
            StudioPanel(title: "双色阶混合器与 CSS / SwiftUI 渐变生成") {
                HStack(spacing: 8) {
                    Text("起点: \(rgba.hexAutoUpper)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    ColorSwatchTile(color: mixEndColor, cornerRadius: 5)
                        .frame(width: 22, height: 22)
                    TextField("终点颜色 (如 #8B5CF6)", text: $mixEndInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: 160)
                        .onChange(of: mixEndInput) { _, val in
                            if let parsed = ColorEngine.parse(val) {
                                mixEndColor = parsed
                            }
                        }
                    StudioToolBarButton(title: "吸管", icon: "eyedropper") {
                        ColorEngine.pickFromScreen { picked in
                            guard let picked else { return }
                            mixEndColor = picked
                            mixEndInput = picked.hexAutoUpper
                        }
                    }

                    Spacer()

                    ForEach(ColorEngine.MixSpace.allCases, id: \.rawValue) { sp in
                        PillButton(title: sp.rawValue, active: mixSpace == sp, color: .indigo) {
                            mixSpace = sp
                        }
                    }
                    ForEach([5, 7, 9, 11], id: \.self) { cnt in
                        PillButton(title: "\(cnt)阶", active: mixSteps == cnt, color: .pink) {
                            mixSteps = cnt
                        }
                    }
                }

                // Continuous interpolated gradient strip
                let swiftUiColors = mixed.map { Color(red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: swiftUiColors, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))

                // Stepped interactive swatches
                HStack(spacing: 4) {
                    ForEach(Array(mixed.enumerated()), id: \.offset) { _, col in
                        Button {
                            studio.copy(col.hexAutoUpper, label: "已复制混色 \(col.hexAutoUpper)")
                        } label: {
                            VStack(spacing: 3) {
                                ColorSwatchTile(color: col, cornerRadius: 6)
                                    .frame(height: 38)
                                Text(col.hex6Upper)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Text(verbatim: "CSS 角度: \(Int(gradientAngle.rounded()))°")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Slider(value: $gradientAngle, in: 0...360, step: 15)
                        .frame(maxWidth: 160)
                    Spacer()
                }

                CopyableResultRow(title: "CSS linear-gradient (\(mixSpace.rawValue))", value: cssGrad, badge: "CSS", badgeColor: .pink)
                CopyableResultRow(title: "SwiftUI LinearGradient", value: swiftGrad, badge: "SwiftUI", badgeColor: .orange)
            }

            StudioPanel(title: "色觉障碍视觉模拟 (Color Blindness / CVD)") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(cvds) { item in
                        HStack(spacing: 8) {
                            ColorSwatchTile(color: item.color, cornerRadius: 7)
                                .frame(width: 40, height: 40)
                            CopyableResultRow(
                                title: item.title,
                                value: item.color.hexAutoUpper,
                                badge: item.prevalence,
                                badgeColor: .teal
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bindings & State Synchronization

    private var swiftColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a) },
            set: { newSwiftColor in
                let ns = NSColor(newSwiftColor).usingColorSpace(.sRGB) ?? NSColor.systemBlue
                let c = ColorRGBA(
                    r: Double(ns.redComponent),
                    g: Double(ns.greenComponent),
                    b: Double(ns.blueComponent),
                    a: Double(ns.alphaComponent)
                )
                applyColor(c, textOverride: c.hexAutoUpper)
            }
        )
    }

    private func rgbChannelBinding(_ keyPath: WritableKeyPath<ColorRGBA, Double>, scale: Double) -> Binding<Double> {
        Binding(
            get: { rgba[keyPath: keyPath] * scale },
            set: { newVal in
                var updated = rgba
                updated[keyPath: keyPath] = min(max(newVal / scale, 0), 1)
                applyColor(updated, textOverride: updated.hexAutoUpper, recordHistory: false)
            }
        )
    }

    private func hslBinding(_ keyPath: WritableKeyPath<ColorHSL, Double>) -> Binding<Double> {
        Binding(
            get: { hslState[keyPath: keyPath] },
            set: { newVal in
                hslState[keyPath: keyPath] = newVal
                hslState.a = rgba.a
                let converted = ColorEngine.fromHSL(hslState)
                applyColor(converted, textOverride: converted.hexAutoUpper, keepSubSpace: .hsl, recordHistory: false)
            }
        )
    }

    private func hsvBinding(_ keyPath: WritableKeyPath<ColorHSV, Double>) -> Binding<Double> {
        Binding(
            get: { hsvState[keyPath: keyPath] },
            set: { newVal in
                hsvState[keyPath: keyPath] = newVal
                hsvState.a = rgba.a
                let converted = ColorEngine.fromHSV(hsvState)
                applyColor(converted, textOverride: converted.hexAutoUpper, keepSubSpace: .hsv, recordHistory: false)
            }
        )
    }

    private var oklchLBinding: Binding<Double> {
        Binding(
            get: { oklchState.l * 100.0 },
            set: { newPct in
                oklchState.l = min(max(newPct / 100.0, 0), 1)
                oklchState.a = rgba.a
                let converted = ColorEngine.fromOKLCH(oklchState)
                applyColor(converted, textOverride: converted.hexAutoUpper, keepSubSpace: .oklch, recordHistory: false)
            }
        )
    }

    private func oklchBinding(_ keyPath: WritableKeyPath<ColorOKLCH, Double>) -> Binding<Double> {
        Binding(
            get: { oklchState[keyPath: keyPath] },
            set: { newVal in
                oklchState[keyPath: keyPath] = newVal
                oklchState.a = rgba.a
                let converted = ColorEngine.fromOKLCH(oklchState)
                applyColor(converted, textOverride: converted.hexAutoUpper, keepSubSpace: .oklch, recordHistory: false)
            }
        )
    }

    private func cmykBinding(_ keyPath: WritableKeyPath<ColorCMYK, Double>) -> Binding<Double> {
        Binding(
            get: { cmykState[keyPath: keyPath] },
            set: { newVal in
                cmykState[keyPath: keyPath] = newVal
                let converted = ColorEngine.fromCMYK(cmykState, alpha: rgba.a)
                applyColor(converted, textOverride: converted.hexAutoUpper, keepSubSpace: .cmyk, recordHistory: false)
            }
        )
    }

    private func applyColor(
        _ newColor: ColorRGBA,
        textOverride: String? = nil,
        keepSubSpace: ColorSliderSpace? = nil,
        recordHistory: Bool = true
    ) {
        rgba = newColor
        syncSubSpaces(from: newColor, skip: keepSubSpace)
        let text = textOverride ?? newColor.hexAutoUpper
        if studio.colorInput != text {
            suppressInputSync = true
            studio.colorInput = text
        }
        if recordHistory {
            pushHistory(newColor.hexAutoUpper)
        }
    }

    private func syncSubSpaces(from c: ColorRGBA, skip: ColorSliderSpace? = nil) {
        if skip != .hsl { hslState = ColorEngine.toHSL(c) }
        if skip != .hsv { hsvState = ColorEngine.toHSV(c) }
        if skip != .oklch { oklchState = ColorEngine.toOKLCH(c) }
        if skip != .cmyk { cmykState = ColorEngine.toCMYK(c) }
    }

    private func pushHistory(_ hex: String) {
        let norm = hex.uppercased()
        if let idx = colorHistory.firstIndex(of: norm) {
            colorHistory.remove(at: idx)
        }
        colorHistory.insert(norm, at: 0)
        if colorHistory.count > 12 {
            colorHistory.removeLast(colorHistory.count - 12)
        }
    }

    private func launchEyedropper() {
        ColorEngine.pickFromScreen { picked in
            guard let picked else { return }
            applyColor(picked, textOverride: picked.hexAutoUpper)
            if autoCopyEyedropper {
                studio.copy(picked.hexAutoUpper, label: "已取色并复制 \(picked.hexAutoUpper)")
            } else {
                studio.showToast("已取色: \(picked.hexAutoUpper)")
            }
        }
    }
}

// MARK: - Subviews

private struct ColorChannelSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(tint)
            Text(verbatim: display)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct WcagStatusBadge: View {
    let title: String
    let passed: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill((passed ? Color.green : Color.red).opacity(0.14)))
        .foregroundStyle(passed ? .green : .red)
    }
}
