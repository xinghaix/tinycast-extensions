import AppKit
import SwiftUI

struct CurrencyToolView: View {
    @Environment(StudioState.self) private var studio
    @State private var snapshot: ExchangeRateSnapshot = CurrencyEngine.loadDiskCache() ?? CurrencyEngine.offlineFallbackSnapshot
    @State private var sourceMode: CurrencySourceMode = .auto
    @State private var isFetching: Bool = false
    @State private var fetchError: String? = nil

    @State private var feePercent: Double = 0.0
    @State private var pinnedCodes: [String] = CurrencyEngine.loadPinnedCodes()
    @State private var searchText: String = ""
    @State private var categoryFilter: CurrencyCategory = .all

    // History chart state (Frankfurter central-bank history)
    @State private var showHistoryChart: Bool = false
    @State private var historyDays: Int = 30
    @State private var historySeries: CurrencyHistorySeries? = nil
    @State private var isLoadingHistory: Bool = false
    @State private var historyError: String? = nil

    private static let feePresets: [(label: String, pct: Double)] = [
        ("0% 中间价", 0.0),
        ("+1%", 1.0),
        ("+1.5%", 1.5),
        ("+2%", 2.0),
        ("+3%", 3.0),
    ]

    var body: some View {
        @Bindable var studio = studio
        let parsedQuery = CurrencyEngine.parseCurrencyQuery(studio.currencyAmountInput)
        let evaluatedAmount = CurrencyEngine.evaluateExpression(studio.currencyAmountInput)
            ?? parsedQuery?.amount
            ?? 0
        let baseMeta = CurrencyEngine.meta(for: studio.currencyBaseCode)
        let targetMeta = CurrencyEngine.meta(for: studio.currencyTargetCode)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolHeader(
                    tool: .currency,
                    subtitle: "多国法币 (166+) / 加密货币 / 贵金属汇率互转 · 表达式计算 · 银行点差估算 · 4 小时本地缓存 & 历史走势图"
                )

                sourceStatusBar

                amountAndFeePanel(evaluatedAmount: evaluatedAmount, baseMeta: baseMeta)

                primaryPairAndChartPanel(
                    evaluatedAmount: evaluatedAmount,
                    baseMeta: baseMeta,
                    targetMeta: targetMeta
                )

                pinnedComparisonPanel(evaluatedAmount: evaluatedAmount, baseMeta: baseMeta)

                allCurrenciesDirectoryPanel(evaluatedAmount: evaluatedAmount, baseMeta: baseMeta)

                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("数据源声明：\(snapshot.attribution) · 汇率仅供参考，实际交易请以银行/机构牌价为准。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .task(id: studio.activeTool == .currency) {
            if studio.activeTool == .currency {
                if !snapshot.isCacheFresh || snapshot.fetchedAtUnix == 0 {
                    await refreshRates(silentIfFresh: true)
                }
            }
        }
        .onChange(of: studio.currencyAmountInput) { _, newVal in
            if let q = CurrencyEngine.parseCurrencyQuery(newVal), q.code != studio.currencyBaseCode {
                studio.currencyBaseCode = q.code
                if q.code == studio.currencyTargetCode {
                    studio.currencyTargetCode = (q.code == "CNY" ? "USD" : "CNY")
                }
            }
        }
        .onChange(of: studio.currencyBaseCode) { _, _ in
            if showHistoryChart { loadHistoryIfNeeded() }
        }
        .onChange(of: studio.currencyTargetCode) { _, _ in
            if showHistoryChart { loadHistoryIfNeeded() }
        }
    }

    // MARK: - 1. Source & Status Bar

    private var sourceStatusBar: some View {
        HStack(spacing: 8) {
            BadgePill(text: snapshot.providerName, color: .green)
            BadgePill(
                text: snapshot.fetchedAtUnix == 0
                    ? "离线参考价 (\(snapshot.rateDate))"
                    : (snapshot.isCacheFresh ? "缓存有效 · \(snapshot.rateDate)" : "缓存已过期 · \(snapshot.rateDate)"),
                color: snapshot.fetchedAtUnix == 0 ? .orange : (snapshot.isCacheFresh ? .teal : .orange)
            )
            BadgePill(text: "\(snapshot.rates.count) 币种", color: .blue)

            Spacer()

            Menu {
                ForEach(CurrencySourceMode.allCases) { mode in
                    Button {
                        sourceMode = mode
                        Task { await refreshRates(silentIfFresh: false) }
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if sourceMode == mode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11))
                    Text(sourceMode.rawValue)
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            StudioToolBarButton(
                title: isFetching ? "获取中…" : "刷新实时汇率",
                icon: "arrow.clockwise",
                tint: .green
            ) {
                Task { await refreshRates(silentIfFresh: false) }
            }
        }
    }

    // MARK: - 2. Amount Expression & Fee Panel

    @ViewBuilder
    private func amountAndFeePanel(evaluatedAmount: Double, baseMeta: CurrencyMeta) -> some View {
        @Bindable var studio = studio

        StudioPanel(title: "1. 基准货币与金额表达式 (支持 + - * / () % 四则运算或直接输入 $199.5 / 5000 JPY)") {
            HStack(spacing: 10) {
                currencyPickerMenu(selectedCode: $studio.currencyBaseCode, meta: baseMeta, accent: .green)

                HStack(spacing: 6) {
                    Text(baseMeta.symbol)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("输入金额或表达式，如 199 * 3 + 50", text: $studio.currencyAmountInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    if !studio.currencyAmountInput.isEmpty {
                        Button {
                            studio.currencyAmountInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

                if studio.currencyAmountInput.contains(where: { "+-*/×÷()%".contains($0) }) {
                    BadgePill(
                        text: "= \(CurrencyEngine.formatAmount(evaluatedAmount, code: baseMeta.code)) \(baseMeta.code)",
                        color: .green
                    )
                }
            }

            if let fetchError {
                Text("⚠ \(fetchError)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Text("快捷:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(["1", "100", "500", "1000", "10000"], id: \.self) { amt in
                    PillButton(title: amt, active: studio.currencyAmountInput.trimmingCharacters(in: .whitespaces) == amt, color: .green) {
                        studio.currencyAmountInput = amt
                    }
                }

                Divider().frame(height: 14)

                Text("银行点差:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(Self.feePresets, id: \.pct) { item in
                    PillButton(title: item.label, active: abs(feePercent - item.pct) < 0.001, color: .orange) {
                        feePercent = item.pct
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - 3. Primary Pair & History Trend Chart Panel

    @ViewBuilder
    private func primaryPairAndChartPanel(
        evaluatedAmount: Double,
        baseMeta: CurrencyMeta,
        targetMeta: CurrencyMeta
    ) -> some View {
        @Bindable var studio = studio
        let converted = CurrencyEngine.convert(
            amount: evaluatedAmount,
            from: baseMeta.code,
            to: targetMeta.code,
            snapshot: snapshot,
            feePercent: feePercent
        )
        let unitRate = CurrencyEngine.convert(
            amount: 1.0,
            from: baseMeta.code,
            to: targetMeta.code,
            snapshot: snapshot,
            feePercent: feePercent
        )
        let inverseRate = CurrencyEngine.convert(
            amount: 1.0,
            from: targetMeta.code,
            to: baseMeta.code,
            snapshot: snapshot,
            feePercent: 0
        )

        StudioPanel(title: "2. 重点货币对互转 & 历史走势") {
            HStack(spacing: 10) {
                Button {
                    let oldBase = studio.currencyBaseCode
                    studio.currencyBaseCode = studio.currencyTargetCode
                    studio.currencyTargetCode = oldBase
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("对调基准与目标货币")

                currencyPickerMenu(selectedCode: $studio.currencyTargetCode, meta: targetMeta, accent: .blue)

                Spacer()

                StudioToolBarButton(
                    title: showHistoryChart ? "收起走势图" : "查看 30/90 天历史走势",
                    icon: "chart.xyaxis.line",
                    tint: .blue
                ) {
                    showHistoryChart.toggle()
                    if showHistoryChart { loadHistoryIfNeeded() }
                }
            }

            if let converted {
                let formatted = CurrencyEngine.formatAmount(converted, code: targetMeta.code)
                let plainCopy = CurrencyEngine.formatCopyPlain(converted, code: targetMeta.code)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(CurrencyEngine.formatAmount(evaluatedAmount, code: baseMeta.code)) \(baseMeta.code) (\(baseMeta.nameZh))  =")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(targetMeta.symbol) \(formatted)")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .onTapGesture {
                                    studio.copy(plainCopy, label: "已复制 \(targetMeta.code) 金额")
                                }
                            Text("\(targetMeta.code) · \(targetMeta.nameZh)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if let unitRate, let inverseRate {
                            Text(
                                "1 \(baseMeta.code) = \(CurrencyEngine.formatUnitRate(unitRate)) \(targetMeta.code)"
                                    + "   |   "
                                    + "1 \(targetMeta.code) = \(CurrencyEngine.formatUnitRate(inverseRate)) \(baseMeta.code)"
                                    + (feePercent > 0 ? " (含 +\(String(format: "%.1f", feePercent))% 点差)" : "")
                            )
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        CopyActionButton(text: plainCopy, label: "复制纯数字") { _ in
                            studio.showToast("已复制 \(plainCopy)")
                        }
                        CopyActionButton(text: "\(targetMeta.symbol)\(formatted) \(targetMeta.code)", label: "复制带币种") { _ in
                            studio.showToast("已复制带符号金额")
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.green.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.green.opacity(0.24), lineWidth: 1))
            } else {
                Text("当前数据源暂不支持 \(baseMeta.code) → \(targetMeta.code)，请切换为「fawazahmed0 CDN」或更换币种。")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            if showHistoryChart {
                historyChartSection(baseCode: baseMeta.code, targetCode: targetMeta.code)
            }
        }
    }

    @ViewBuilder
    private func historyChartSection(baseCode: String, targetCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Text("历史走势 (\(baseCode) → \(targetCode))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                PillButton(title: "近 30 天", active: historyDays == 30, color: .blue) {
                    historyDays = 30
                    loadHistoryIfNeeded()
                }
                PillButton(title: "近 90 天", active: historyDays == 90, color: .blue) {
                    historyDays = 90
                    loadHistoryIfNeeded()
                }
                Spacer()
                if let s = historySeries, s.base == baseCode, s.target == targetCode {
                    let sign = s.changePct >= 0 ? "+" : ""
                    BadgePill(text: "最低 \(CurrencyEngine.formatUnitRate(s.minRate))", color: .secondary)
                    BadgePill(text: "均价 \(CurrencyEngine.formatUnitRate(s.avgRate))", color: .blue)
                    BadgePill(text: "最高 \(CurrencyEngine.formatUnitRate(s.maxRate))", color: .secondary)
                    BadgePill(
                        text: "\(sign)\(String(format: "%.2f", s.changePct))%",
                        color: s.changePct >= 0 ? .green : .red
                    )
                }
            }

            if isLoadingHistory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在拉取 Frankfurter 历史央行汇率…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else if let err = historyError {
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
            } else if let s = historySeries, s.points.count >= 2 {
                RateSparklineChart(series: s)
                    .frame(height: 120)
            }
        }
    }

    // MARK: - 4. Pinned Multi-Currency Board

    @ViewBuilder
    private func pinnedComparisonPanel(evaluatedAmount: Double, baseMeta: CurrencyMeta) -> some View {
        @Bindable var studio = studio
        let visiblePinned = pinnedCodes.filter { snapshot.rates[$0] != nil }

        StudioPanel(title: "3. 常用固定货币对比板 (左键点击数值复制，右侧切换基准或取消固定)") {
            if visiblePinned.isEmpty {
                Text("暂无固定币种，可在下方全部货币列表中点击图钉图标固定。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(visiblePinned, id: \.self) { code in
                        let m = CurrencyEngine.meta(for: code)
                        let val = CurrencyEngine.convert(
                            amount: evaluatedAmount,
                            from: baseMeta.code,
                            to: code,
                            snapshot: snapshot,
                            feePercent: feePercent
                        )
                        let unit = CurrencyEngine.convert(
                            amount: 1.0,
                            from: baseMeta.code,
                            to: code,
                            snapshot: snapshot,
                            feePercent: feePercent
                        )
                        let plainVal = val.map { CurrencyEngine.formatCopyPlain($0, code: code) } ?? "—"
                        let dispVal = val.map { CurrencyEngine.formatAmount($0, code: code) } ?? "—"

                        HStack(spacing: 8) {
                            Text(m.flag)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(m.code)
                                        .font(.system(size: 12.5, weight: .bold))
                                    Text(m.nameZh)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let unit {
                                    Text("1 \(baseMeta.code) = \(CurrencyEngine.formatUnitRate(unit)) \(m.code)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            Text("\(m.symbol) \(dispVal)")
                                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)

                            Button {
                                studio.currencyBaseCode = code
                            } label: {
                                Image(systemName: "arrow.up.left.square")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("将 \(m.code) 设为基准币种")

                            Button {
                                togglePin(code)
                            } label: {
                                Image(systemName: "pin.slash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("取消固定")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(code == baseMeta.code ? Color.green.opacity(0.10) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(code == baseMeta.code ? Color.green.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if val != nil {
                                studio.copy(plainVal, label: "已复制 \(m.code): \(dispVal)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. All Supported Currencies Search & Pin Directory

    @ViewBuilder
    private func allCurrenciesDirectoryPanel(evaluatedAmount: Double, baseMeta: CurrencyMeta) -> some View {
        @Bindable var studio = studio
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let orderedCodes: [String] = {
            let catalogOrder = CurrencyEngine.catalog.map(\.code).filter { snapshot.rates[$0] != nil }
            let catalogSet = Set(catalogOrder)
            let extras = snapshot.rates.keys.filter { !catalogSet.contains($0) }.sorted()
            return catalogOrder + extras
        }()

        let filteredMetas: [CurrencyMeta] = orderedCodes.compactMap { code in
            let meta = CurrencyEngine.meta(for: code)
            if categoryFilter != .all && meta.category != categoryFilter {
                return nil
            }
            if !q.isEmpty {
                let matches = meta.code.lowercased().contains(q)
                    || meta.nameZh.lowercased().contains(q)
                    || meta.nameEn.lowercased().contains(q)
                if !matches { return nil }
            }
            return meta
        }

        StudioPanel(title: "4. 全部支持币种检索与固定 (\(filteredMetas.count) 种)") {
            HStack(spacing: 8) {
                TextField("搜索币种代码或名称，如 CHF / 泰铢 / BTC / 黄金…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                ForEach(CurrencyCategory.allCases) { cat in
                    PillButton(title: cat.rawValue, active: categoryFilter == cat, color: .green) {
                        categoryFilter = cat
                    }
                }
                Spacer()
            }

            LazyVStack(spacing: 6) {
                ForEach(filteredMetas.prefix(120)) { meta in
                    let isPinned = pinnedCodes.contains(meta.code)
                    let val = CurrencyEngine.convert(
                        amount: evaluatedAmount,
                        from: baseMeta.code,
                        to: meta.code,
                        snapshot: snapshot,
                        feePercent: feePercent
                    )
                    let plain = val.map { CurrencyEngine.formatCopyPlain($0, code: meta.code) } ?? "—"
                    let disp = val.map { CurrencyEngine.formatAmount($0, code: meta.code) } ?? "—"

                    CopyableResultRow(
                        title: "\(meta.flag) \(meta.code) · \(meta.nameZh) (\(meta.nameEn))",
                        value: "\(meta.symbol) \(disp)",
                        badge: meta.category.rawValue,
                        badgeColor: meta.category == .crypto ? .orange : (meta.category == .metal ? .yellow : .green),
                        secondaryButton: (isPinned ? "已固定" : "固定到上方", isPinned ? "pin.fill" : "pin", {
                            togglePin(meta.code)
                        })
                    )
                    .onLongPressGesture {
                        studio.copy(plain, label: "已复制 \(meta.code)")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func currencyPickerMenu(selectedCode: Binding<String>, meta: CurrencyMeta, accent: Color) -> some View {
        let menuCodes: [String] = {
            let preferred = Set(pinnedCodes + CurrencyEngine.catalog.map(\.code))
            let primaryList = CurrencyEngine.catalog.map(\.code).filter { snapshot.rates[$0] != nil }
            let extraPinned = pinnedCodes.filter { snapshot.rates[$0] != nil && !primaryList.contains($0) }
            let current = snapshot.rates[selectedCode.wrappedValue] != nil && !preferred.contains(selectedCode.wrappedValue) ? [selectedCode.wrappedValue] : []
            return primaryList + extraPinned + current
        }()

        return Menu {
            ForEach(menuCodes, id: \.self) { code in
                let itemMeta = CurrencyEngine.meta(for: code)
                Button {
                    selectedCode.wrappedValue = code
                } label: {
                    Text("\(itemMeta.flag) \(itemMeta.code) · \(itemMeta.nameZh)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(meta.flag)
                    .font(.system(size: 16))
                Text(meta.code)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(meta.nameZh)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func togglePin(_ code: String) {
        if let idx = pinnedCodes.firstIndex(of: code) {
            pinnedCodes.remove(at: idx)
        } else {
            pinnedCodes.append(code)
        }
        CurrencyEngine.savePinnedCodes(pinnedCodes)
    }

    @MainActor
    private func refreshRates(silentIfFresh: Bool) async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        do {
            let fresh = try await CurrencyEngine.fetchLatestRates(source: sourceMode)
            snapshot = fresh
            isFetching = false
            if !silentIfFresh {
                studio.showToast("✓ 已更新 \(fresh.rates.count) 个币种汇率 (\(fresh.providerName))")
            }
        } catch {
            isFetching = false
            fetchError = error.localizedDescription
            if !silentIfFresh {
                studio.showToast(error.localizedDescription, isError: true)
            }
        }
    }

    private func loadHistoryIfNeeded() {
        let base = studio.currencyBaseCode
        let target = studio.currencyTargetCode
        let days = historyDays
        isLoadingHistory = true
        historyError = nil
        Task {
            do {
                let series = try await CurrencyEngine.fetchHistory(base: base, target: target, days: days)
                await MainActor.run {
                    historySeries = series
                    isLoadingHistory = false
                }
            } catch {
                await MainActor.run {
                    historySeries = nil
                    historyError = error.localizedDescription
                    isLoadingHistory = false
                }
            }
        }
    }
}

private struct RateSparklineChart: View {
    let series: CurrencyHistorySeries

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { ctx, size in
                let pts = series.points
                guard pts.count >= 2 else { return }
                let minV = series.minRate
                let maxV = series.maxRate
                let span = max(maxV - minV, maxV * 0.0001, 1e-9)
                let padX: CGFloat = 6
                let padY: CGFloat = 10
                let w = max(1, size.width - padX * 2)
                let h = max(1, size.height - padY * 2)

                let cgPoints: [CGPoint] = pts.enumerated().map { idx, pt in
                    let x = padX + w * CGFloat(idx) / CGFloat(pts.count - 1)
                    let normY = (pt.rate - minV) / span
                    let y = padY + h * (1.0 - CGFloat(normY))
                    return CGPoint(x: x, y: y)
                }

                var areaPath = Path()
                areaPath.move(to: CGPoint(x: cgPoints.first!.x, y: size.height))
                for p in cgPoints { areaPath.addLine(to: p) }
                areaPath.addLine(to: CGPoint(x: cgPoints.last!.x, y: size.height))
                areaPath.closeSubpath()

                let lineColor: Color = series.changePct >= 0 ? .green : .red
                ctx.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(colors: [lineColor.opacity(0.24), lineColor.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                var linePath = Path()
                linePath.move(to: cgPoints.first!)
                for p in cgPoints.dropFirst() { linePath.addLine(to: p) }
                ctx.stroke(linePath, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = cgPoints.last {
                    let dot = CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)
                    ctx.fill(Path(ellipseIn: dot), with: .color(lineColor))
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))

            HStack {
                Text(series.points.first?.date ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("共 \(series.points.count) 个交易日样本")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(series.points.last?.date ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
