import Foundation

// MARK: - Currency Metadata, Offline Fallback, Multi-Source API & Expression Engine

enum CurrencyCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case fiat = "法定货币"
    case crypto = "加密货币"
    case metal = "贵金属"

    var id: String { rawValue }
}

struct CurrencyMeta: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let nameZh: String
    let nameEn: String
    let symbol: String
    let flag: String
    let category: CurrencyCategory
    let decimals: Int
}

enum CurrencySourceMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "自动多源容灾 (推荐)"
    case fawazCdn = "fawazahmed0 CDN (340+ 含加密/黄金)"
    case exchangeRateApi = "ExchangeRate-API (166 法币)"
    case frankfurter = "Frankfurter (央行参考价)"

    var id: String { rawValue }
}

struct ExchangeRateSnapshot: Codable, Sendable {
    let base: String
    let rates: [String: Double]
    let providerName: String
    let attribution: String
    let rateDate: String
    let fetchedAtUnix: Double

    var isCacheFresh: Bool {
        Date().timeIntervalSince1970 - fetchedAtUnix < 14_400 // 4 hours
    }
}

struct HistoryPoint: Identifiable, Sendable {
    let id: String
    let date: String
    let rate: Double
}

struct CurrencyHistorySeries: Sendable {
    let base: String
    let target: String
    let points: [HistoryPoint]
    let minRate: Double
    let maxRate: Double
    let avgRate: Double
    let changePct: Double
}

enum CurrencyError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum CurrencyEngine {
    static let defaultPinnedCodes: [String] = [
        "CNY", "USD", "HKD", "JPY", "EUR", "GBP", "TWD", "KRW", "SGD", "AUD",
    ]

    private static let pinnedDefaultsKey = "tinycast.devkit.pinnedCurrencies"

    static let catalog: [CurrencyMeta] = [
        CurrencyMeta(code: "CNY", nameZh: "人民币", nameEn: "Chinese Yuan", symbol: "¥", flag: "🇨🇳", category: .fiat, decimals: 2),
        CurrencyMeta(code: "USD", nameZh: "美元", nameEn: "US Dollar", symbol: "$", flag: "🇺🇸", category: .fiat, decimals: 2),
        CurrencyMeta(code: "HKD", nameZh: "港币", nameEn: "Hong Kong Dollar", symbol: "HK$", flag: "🇭🇰", category: .fiat, decimals: 2),
        CurrencyMeta(code: "JPY", nameZh: "日元", nameEn: "Japanese Yen", symbol: "¥", flag: "🇯🇵", category: .fiat, decimals: 0),
        CurrencyMeta(code: "EUR", nameZh: "欧元", nameEn: "Euro", symbol: "€", flag: "🇪🇺", category: .fiat, decimals: 2),
        CurrencyMeta(code: "GBP", nameZh: "英镑", nameEn: "British Pound", symbol: "£", flag: "🇬🇧", category: .fiat, decimals: 2),
        CurrencyMeta(code: "TWD", nameZh: "新台币", nameEn: "New Taiwan Dollar", symbol: "NT$", flag: "🇹🇼", category: .fiat, decimals: 2),
        CurrencyMeta(code: "KRW", nameZh: "韩元", nameEn: "South Korean Won", symbol: "₩", flag: "🇰🇷", category: .fiat, decimals: 0),
        CurrencyMeta(code: "SGD", nameZh: "新加坡元", nameEn: "Singapore Dollar", symbol: "S$", flag: "🇸🇬", category: .fiat, decimals: 2),
        CurrencyMeta(code: "AUD", nameZh: "澳元", nameEn: "Australian Dollar", symbol: "A$", flag: "🇦🇺", category: .fiat, decimals: 2),
        CurrencyMeta(code: "CAD", nameZh: "加元", nameEn: "Canadian Dollar", symbol: "C$", flag: "🇨🇦", category: .fiat, decimals: 2),
        CurrencyMeta(code: "CHF", nameZh: "瑞士法郎", nameEn: "Swiss Franc", symbol: "CHF", flag: "🇨🇭", category: .fiat, decimals: 2),
        CurrencyMeta(code: "MOP", nameZh: "澳门元", nameEn: "Macanese Pataca", symbol: "MOP$", flag: "🇲🇴", category: .fiat, decimals: 2),
        CurrencyMeta(code: "THB", nameZh: "泰铢", nameEn: "Thai Baht", symbol: "฿", flag: "🇹🇭", category: .fiat, decimals: 2),
        CurrencyMeta(code: "MYR", nameZh: "马来西亚林吉特", nameEn: "Malaysian Ringgit", symbol: "RM", flag: "🇲🇾", category: .fiat, decimals: 2),
        CurrencyMeta(code: "VND", nameZh: "越南盾", nameEn: "Vietnamese Dong", symbol: "₫", flag: "🇻🇳", category: .fiat, decimals: 0),
        CurrencyMeta(code: "IDR", nameZh: "印尼盾", nameEn: "Indonesian Rupiah", symbol: "Rp", flag: "🇮🇩", category: .fiat, decimals: 0),
        CurrencyMeta(code: "PHP", nameZh: "菲律宾比索", nameEn: "Philippine Peso", symbol: "₱", flag: "🇵🇭", category: .fiat, decimals: 2),
        CurrencyMeta(code: "INR", nameZh: "印度卢比", nameEn: "Indian Rupee", symbol: "₹", flag: "🇮🇳", category: .fiat, decimals: 2),
        CurrencyMeta(code: "RUB", nameZh: "俄罗斯卢布", nameEn: "Russian Ruble", symbol: "₽", flag: "🇷🇺", category: .fiat, decimals: 2),
        CurrencyMeta(code: "AED", nameZh: "阿联酋迪拉姆", nameEn: "UAE Dirham", symbol: "د.إ", flag: "🇦🇪", category: .fiat, decimals: 2),
        CurrencyMeta(code: "SAR", nameZh: "沙特里亚尔", nameEn: "Saudi Riyal", symbol: "﷼", flag: "🇸🇦", category: .fiat, decimals: 2),
        CurrencyMeta(code: "TRY", nameZh: "土耳其里拉", nameEn: "Turkish Lira", symbol: "₺", flag: "🇹🇷", category: .fiat, decimals: 2),
        CurrencyMeta(code: "BRL", nameZh: "巴西雷亚尔", nameEn: "Brazilian Real", symbol: "R$", flag: "🇧🇷", category: .fiat, decimals: 2),
        CurrencyMeta(code: "MXN", nameZh: "墨西哥比索", nameEn: "Mexican Peso", symbol: "MX$", flag: "🇲🇽", category: .fiat, decimals: 2),
        CurrencyMeta(code: "NZD", nameZh: "新西兰元", nameEn: "New Zealand Dollar", symbol: "NZ$", flag: "🇳🇿", category: .fiat, decimals: 2),
        CurrencyMeta(code: "SEK", nameZh: "瑞典克朗", nameEn: "Swedish Krona", symbol: "kr", flag: "🇸🇪", category: .fiat, decimals: 2),
        CurrencyMeta(code: "NOK", nameZh: "挪威克朗", nameEn: "Norwegian Krone", symbol: "kr", flag: "🇳🇴", category: .fiat, decimals: 2),
        CurrencyMeta(code: "DKK", nameZh: "丹麦克朗", nameEn: "Danish Krone", symbol: "kr", flag: "🇩🇰", category: .fiat, decimals: 2),
        CurrencyMeta(code: "PLN", nameZh: "波兰兹罗提", nameEn: "Polish Zloty", symbol: "zł", flag: "🇵🇱", category: .fiat, decimals: 2),
        CurrencyMeta(code: "CZK", nameZh: "捷克克朗", nameEn: "Czech Koruna", symbol: "Kč", flag: "🇨🇿", category: .fiat, decimals: 2),
        CurrencyMeta(code: "HUF", nameZh: "匈牙利福林", nameEn: "Hungarian Forint", symbol: "Ft", flag: "🇭🇺", category: .fiat, decimals: 0),
        CurrencyMeta(code: "RON", nameZh: "罗马尼亚列伊", nameEn: "Romanian Leu", symbol: "lei", flag: "🇷🇴", category: .fiat, decimals: 2),
        CurrencyMeta(code: "ZAR", nameZh: "南非兰特", nameEn: "South African Rand", symbol: "R", flag: "🇿🇦", category: .fiat, decimals: 2),
        CurrencyMeta(code: "ILS", nameZh: "以色列新谢克尔", nameEn: "Israeli New Shekel", symbol: "₪", flag: "🇮🇱", category: .fiat, decimals: 2),
        CurrencyMeta(code: "ARS", nameZh: "阿根廷比索", nameEn: "Argentine Peso", symbol: "ARS", flag: "🇦🇷", category: .fiat, decimals: 2),
        CurrencyMeta(code: "CLP", nameZh: "智利比索", nameEn: "Chilean Peso", symbol: "CLP", flag: "🇨🇱", category: .fiat, decimals: 0),
        CurrencyMeta(code: "COP", nameZh: "哥伦比亚比索", nameEn: "Colombian Peso", symbol: "COP", flag: "🇨🇴", category: .fiat, decimals: 0),
        CurrencyMeta(code: "EGP", nameZh: "埃及镑", nameEn: "Egyptian Pound", symbol: "E£", flag: "🇪🇬", category: .fiat, decimals: 2),
        CurrencyMeta(code: "UAH", nameZh: "乌克兰格里夫纳", nameEn: "Ukrainian Hryvnia", symbol: "₴", flag: "🇺🇦", category: .fiat, decimals: 2),
        CurrencyMeta(code: "PKR", nameZh: "巴基斯坦卢比", nameEn: "Pakistani Rupee", symbol: "₨", flag: "🇵🇰", category: .fiat, decimals: 2),
        CurrencyMeta(code: "KZT", nameZh: "哈萨克斯坦坚戈", nameEn: "Kazakhstani Tenge", symbol: "₸", flag: "🇰🇿", category: .fiat, decimals: 2),
        CurrencyMeta(code: "BTC", nameZh: "比特币", nameEn: "Bitcoin", symbol: "₿", flag: "🪙", category: .crypto, decimals: 6),
        CurrencyMeta(code: "ETH", nameZh: "以太坊", nameEn: "Ethereum", symbol: "Ξ", flag: "💎", category: .crypto, decimals: 5),
        CurrencyMeta(code: "USDT", nameZh: "泰达币", nameEn: "Tether USD", symbol: "₮", flag: "💵", category: .crypto, decimals: 2),
        CurrencyMeta(code: "SOL", nameZh: "Solana", nameEn: "Solana", symbol: "SOL", flag: "◎", category: .crypto, decimals: 4),
        CurrencyMeta(code: "XAU", nameZh: "黄金 (盎司)", nameEn: "Gold Ounce", symbol: "XAU", flag: "🥇", category: .metal, decimals: 4),
        CurrencyMeta(code: "XAG", nameZh: "白银 (盎司)", nameEn: "Silver Ounce", symbol: "XAG", flag: "🥈", category: .metal, decimals: 3),
    ]

    private static let catalogByCode: [String: CurrencyMeta] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.code, $0) }
    )

    private static let knownCryptoCodes: Set<String> = [
        "BTC", "ETH", "USDT", "USDC", "BNB", "SOL", "XRP", "ADA", "DOGE", "TRX",
        "DOT", "MATIC", "LTC", "AVAX", "LINK", "UNI", "ATOM", "AAVE", "TON", "SUI",
        "ARB", "OP", "NEAR", "APT", "PEPE", "SHIB", "BCH", "ETC", "XLM", "ALGO",
    ]

    private static let knownMetalCodes: Set<String> = [
        "XAU", "XAG", "XPT", "XPD",
    ]

    // Built-in reference snapshot (USD base) so immediate launch, offline use & --self-test always work.
    static let offlineFallbackSnapshot = ExchangeRateSnapshot(
        base: "USD",
        rates: [
            "USD": 1.0,
            "CNY": 6.6672,
            "HKD": 7.8467,
            "JPY": 159.42,
            "EUR": 0.91174,
            "GBP": 0.75939,
            "TWD": 31.85,
            "KRW": 1332.33,
            "SGD": 1.2896,
            "AUD": 1.4856,
            "CAD": 1.4305,
            "CHF": 0.84272,
            "MOP": 8.082,
            "THB": 34.45,
            "MYR": 4.116,
            "VND": 25410.0,
            "IDR": 18254.0,
            "PHP": 63.669,
            "INR": 93.44,
            "RUB": 98.5,
            "AED": 3.6725,
            "SAR": 3.75,
            "TRY": 34.6,
            "BRL": 5.8186,
            "MXN": 18.5759,
            "NZD": 1.819,
            "SEK": 10.1596,
            "NOK": 9.6686,
            "DKK": 6.8147,
            "PLN": 4.0224,
            "CZK": 22.234,
            "HUF": 335.89,
            "RON": 4.8748,
            "ZAR": 17.95,
            "ILS": 3.2639,
            "ARS": 1552.21,
            "CLP": 972.0,
            "COP": 4380.0,
            "EGP": 49.3,
            "UAH": 41.4,
            "PKR": 277.8,
            "KZT": 495.0,
            "BTC": 0.000015501,
            "ETH": 0.00055311,
            "USDT": 1.001,
            "SOL": 0.0046,
            "XAU": 0.0002646,
            "XAG": 0.032,
        ],
        providerName: "内置离线参考汇率",
        attribution: "内置参考汇率（可点击上方「刷新实时汇率」联网更新）",
        rateDate: "2026-11-18",
        fetchedAtUnix: 0
    )

    static func meta(for rawCode: String) -> CurrencyMeta {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let hit = catalogByCode[code] {
            return hit
        }
        let zhLocale = Locale(identifier: "zh_CN")
        let enLocale = Locale(identifier: "en_US")
        let zhName = zhLocale.localizedString(forCurrencyCode: code)
        let enName = enLocale.localizedString(forCurrencyCode: code)
        let category: CurrencyCategory = knownMetalCodes.contains(code)
            ? .metal
            : ((knownCryptoCodes.contains(code) || (zhName == nil && enName == nil)) ? .crypto : .fiat)
        let flag = category == .metal ? "🪙" : (category == .crypto ? "💠" : "🏳️")
        let decimals = category == .fiat ? 2 : 6
        return CurrencyMeta(
            code: code,
            nameZh: zhName ?? code,
            nameEn: enName ?? code,
            symbol: code,
            flag: flag,
            category: category,
            decimals: decimals
        )
    }

    // MARK: Persistence & Disk Cache

    private static var diskCacheUrl: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent("tinycast-devkit", isDirectory: true)
            .appendingPathComponent("exchange-rates-v1.json")
    }

    static func loadDiskCache() -> ExchangeRateSnapshot? {
        guard let url = diskCacheUrl,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ExchangeRateSnapshot.self, from: data),
              !decoded.rates.isEmpty else {
            return nil
        }
        return decoded
    }

    static func saveDiskCache(_ snapshot: ExchangeRateSnapshot) {
        guard let url = diskCacheUrl else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func loadPinnedCodes() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey)
        if let saved, !saved.isEmpty {
            return saved
        }
        return defaultPinnedCodes
    }

    static func savePinnedCodes(_ codes: [String]) {
        UserDefaults.standard.set(codes, forKey: pinnedDefaultsKey)
    }

    // MARK: Multi-Source Keyless Live API Fetcher

    private static func makeEphemeralSession(timeout: TimeInterval = 8) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout + 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }

    static func fetchLatestRates(source: CurrencySourceMode = .auto) async throws -> ExchangeRateSnapshot {
        let snap: ExchangeRateSnapshot
        switch source {
        case .auto:
            var errors: [String] = []
            if let s = try? await fetchFawaz(urlString: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json", mirrorLabel: "fawazahmed0 CDN (jsDelivr)") {
                snap = s
            } else if let s = try? await fetchFawaz(urlString: "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json", mirrorLabel: "fawazahmed0 CDN (Cloudflare)") {
                snap = s
            } else if let s = try? await fetchExchangeRateApi() {
                snap = s
            } else {
                do {
                    snap = try await fetchFrankfurter()
                } catch {
                    errors.append(error.localizedDescription)
                    throw CurrencyError.message("所有公开汇率数据源暂不可达，请检查网络连接（已保留离线/缓存汇率）")
                }
            }

        case .fawazCdn:
            do {
                snap = try await fetchFawaz(
                    urlString: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json",
                    mirrorLabel: "fawazahmed0 CDN (jsDelivr)"
                )
            } catch {
                snap = try await fetchFawaz(
                    urlString: "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json",
                    mirrorLabel: "fawazahmed0 CDN (Cloudflare)"
                )
            }

        case .exchangeRateApi:
            snap = try await fetchExchangeRateApi()

        case .frankfurter:
            snap = try await fetchFrankfurter()
        }

        saveDiskCache(snap)
        return snap
    }

    private static func fetchFawaz(urlString: String, mirrorLabel: String) async throws -> ExchangeRateSnapshot {
        guard let url = URL(string: urlString) else {
            throw CurrencyError.message("无效 URL")
        }
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurrencyError.message("\(mirrorLabel) 返回错误状态")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usdMap = obj["usd"] as? [String: Any] else {
            throw CurrencyError.message("\(mirrorLabel) 返回结构异常")
        }
        var rates: [String: Double] = ["USD": 1.0]
        for (rawKey, rawVal) in usdMap {
            if let num = (rawVal as? NSNumber)?.doubleValue, num > 0, num.isFinite {
                rates[rawKey.uppercased()] = num
            }
        }
        guard rates.count >= 50 else {
            throw CurrencyError.message("\(mirrorLabel) 币种数量异常")
        }
        let dateStr = (obj["date"] as? String) ?? TimestampEngine.formatDate(Date(), format: "yyyy-MM-dd")
        return ExchangeRateSnapshot(
            base: "USD",
            rates: rates,
            providerName: mirrorLabel,
            attribution: "Public CDN · fawazahmed0/currency-api",
            rateDate: dateStr,
            fetchedAtUnix: Date().timeIntervalSince1970
        )
    }

    private static func fetchExchangeRateApi() async throws -> ExchangeRateSnapshot {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            throw CurrencyError.message("无效 URL")
        }
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurrencyError.message("ExchangeRate-API 响应失败")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["result"] as? String) == "success",
              let rawRates = obj["rates"] as? [String: Any] else {
            throw CurrencyError.message("ExchangeRate-API 数据格式异常")
        }
        var rates: [String: Double] = ["USD": 1.0]
        for (k, v) in rawRates {
            if let d = (v as? NSNumber)?.doubleValue, d > 0, d.isFinite {
                rates[k.uppercased()] = d
            }
        }
        let dateStr: String = {
            if let unix = (obj["time_last_update_unix"] as? NSNumber)?.doubleValue {
                return TimestampEngine.formatDate(Date(timeIntervalSince1970: unix), format: "yyyy-MM-dd HH:mm")
            }
            return TimestampEngine.formatDate(Date(), format: "yyyy-MM-dd")
        }()
        return ExchangeRateSnapshot(
            base: "USD",
            rates: rates,
            providerName: "ExchangeRate-API Open Access",
            attribution: "Rates by ExchangeRate-API",
            rateDate: dateStr,
            fetchedAtUnix: Date().timeIntervalSince1970
        )
    }

    private static func fetchFrankfurter() async throws -> ExchangeRateSnapshot {
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD") else {
            throw CurrencyError.message("无效 URL")
        }
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurrencyError.message("Frankfurter API 响应失败")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawRates = obj["rates"] as? [String: Any] else {
            throw CurrencyError.message("Frankfurter API 数据格式异常")
        }
        var rates: [String: Double] = ["USD": 1.0]
        for (k, v) in rawRates {
            if let d = (v as? NSNumber)?.doubleValue, d > 0, d.isFinite {
                rates[k.uppercased()] = d
            }
        }
        let dateStr = (obj["date"] as? String) ?? TimestampEngine.formatDate(Date(), format: "yyyy-MM-dd")
        return ExchangeRateSnapshot(
            base: "USD",
            rates: rates,
            providerName: "Frankfurter (央行参考价)",
            attribution: "Open Source · Frankfurter API",
            rateDate: dateStr,
            fetchedAtUnix: Date().timeIntervalSince1970
        )
    }

    static func fetchHistory(base: String, target: String, days: Int = 30) async throws -> CurrencyHistorySeries {
        let cleanBase = base.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleanBase != cleanTarget else {
            throw CurrencyError.message("基准币种与目标币种相同")
        }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(7, days), to: end) ?? end
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: start)
        let endStr = fmt.string(from: end)

        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(startStr)..\(endStr)?base=\(cleanBase)&symbols=\(cleanTarget)") else {
            throw CurrencyError.message("无法构造历史汇率查询 URL")
        }

        let session = makeEphemeralSession(timeout: 10)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurrencyError.message("历史走势数据源 (Frankfurter) 暂不支持 \(cleanBase)/\(cleanTarget) 货币对（常见主要法币均支持）")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ratesObj = obj["rates"] as? [String: Any] else {
            throw CurrencyError.message("历史汇率返回解析失败")
        }

        var points: [HistoryPoint] = []
        for dateKey in ratesObj.keys.sorted() {
            if let dayMap = ratesObj[dateKey] as? [String: Any],
               let num = (dayMap[cleanTarget] as? NSNumber)?.doubleValue,
               num > 0, num.isFinite {
                points.append(HistoryPoint(id: dateKey, date: dateKey, rate: num))
            }
        }
        guard !points.isEmpty else {
            throw CurrencyError.message("该区间未返回有效历史数据（Frankfurter 仅收录主流法币）")
        }

        let vals = points.map(\.rate)
        let minVal = vals.min() ?? 0
        let maxVal = vals.max() ?? 0
        let avgVal = vals.reduce(0, +) / Double(vals.count)
        let firstVal = points.first?.rate ?? 1
        let lastVal = points.last?.rate ?? firstVal
        let changePct = firstVal > 0 ? ((lastVal - firstVal) / firstVal) * 100.0 : 0

        return CurrencyHistorySeries(
            base: cleanBase,
            target: cleanTarget,
            points: points,
            minRate: minVal,
            maxRate: maxVal,
            avgRate: avgVal,
            changePct: changePct
        )
    }

    // MARK: Conversion & Formatting

    static func convert(
        amount: Double,
        from: String,
        to: String,
        snapshot: ExchangeRateSnapshot,
        feePercent: Double = 0
    ) -> Double? {
        guard amount.isFinite else { return nil }
        let fromCode = from.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let toCode = to.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let fromRate = snapshot.rates[fromCode], fromRate > 0,
              let toRate = snapshot.rates[toCode], toRate > 0 else {
            return nil
        }
        let midResult = (fromCode == toCode) ? amount : (amount / fromRate) * toRate
        let multiplier = (feePercent == 0 || fromCode == toCode) ? 1.0 : (1.0 + feePercent / 100.0)
        let final = midResult * multiplier
        return final.isFinite ? final : nil
    }

    static func formatAmount(_ value: Double, code: String, includeSymbol: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        let meta = meta(for: code)
        let absVal = abs(value)
        let maxFrac: Int
        if absVal == 0 {
            maxFrac = 2
        } else if absVal < 0.001 {
            maxFrac = 8
        } else if absVal < 1.0 {
            maxFrac = max(4, meta.decimals)
        } else if meta.category == .crypto || meta.category == .metal {
            maxFrac = max(4, meta.decimals)
        } else if meta.decimals == 0 && absVal >= 10 {
            maxFrac = 2
        } else {
            maxFrac = 2
        }

        let fmt = NumberFormatter()
        fmt.locale = Locale(identifier: "en_US")
        fmt.numberStyle = .decimal
        fmt.usesGroupingSeparator = true
        fmt.minimumFractionDigits = (meta.decimals == 0 && absVal >= 10) ? 0 : min(2, maxFrac)
        fmt.maximumFractionDigits = maxFrac
        let numStr = fmt.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFrac)f", value)
        if includeSymbol {
            return "\(meta.symbol) \(numStr)"
        }
        return numStr
    }

    static func formatCopyPlain(_ value: Double, code: String) -> String {
        formatAmount(value, code: code, includeSymbol: false).replacingOccurrences(of: ",", with: "")
    }

    static func formatUnitRate(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        if value >= 1000 { return String(format: "%.2f", value) }
        if value >= 1 { return String(format: "%.4f", value) }
        if value >= 0.0001 { return String(format: "%.6f", value) }
        return String(format: "%.8f", value)
    }

    // MARK: Arithmetic Expression Evaluator (`100 + 50 * 2`, `(1,200 - 200) / 4`, `1000 * 10%`)

    static func evaluateExpression(_ raw: String) -> Double? {
        let stripped = stripLeadingOrTrailingCurrencyDecorators(raw)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        var parser = ExprParser(Array(stripped))
        guard let val = parser.parseExpression(), parser.isAtEnd, val.isFinite else {
            return nil
        }
        return val
    }

    private static func stripLeadingOrTrailingCurrencyDecorators(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for sym in ["US$", "HK$", "NT$", "MOP$", "NZ$", "MX$", "C$", "A$", "S$", "R$", "RM", "$", "€", "£", "¥", "￥", "₩", "฿", "₹", "₽", "₺", "₫", "₱", "₪", "₴", "₿"] {
            if s.hasPrefix(sym) {
                s = String(s.dropFirst(sym.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return s
    }

    private struct ExprParser {
        let chars: [Character]
        var index: Int = 0

        init(_ chars: [Character]) {
            self.chars = chars
        }

        var isAtEnd: Bool {
            var k = index
            while k < chars.count && chars[k].isWhitespace { k += 1 }
            return k >= chars.count
        }

        private mutating func skipWS() {
            while index < chars.count && chars[index].isWhitespace { index += 1 }
        }

        private mutating func peek() -> Character? {
            skipWS()
            return index < chars.count ? chars[index] : nil
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = (op == "+") ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }

        private mutating func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard abs(rhs) > 1e-18 else { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }

        private mutating func parseFactor() -> Double? {
            guard let ch = peek() else { return nil }
            if ch == "+" {
                index += 1
                return parseFactor()
            }
            if ch == "-" {
                index += 1
                return parseFactor().map { -$0 }
            }
            if ch == "(" {
                index += 1
                guard var val = parseExpression(), peek() == ")" else { return nil }
                index += 1
                if peek() == "%" {
                    index += 1
                    val *= 0.01
                }
                return val
            }

            let start = index
            var sawDigit = false
            var sawDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    sawDigit = true
                    index += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit, var val = Double(String(chars[start..<index])) else { return nil }
            if peek() == "%" {
                index += 1
                val *= 0.01
            }
            return val
        }
    }

    // MARK: Smart Currency Text Detection (`$199.50`, `HK$500`, `100 USD`, `5000 JPY`, `0.5 BTC`)

    private static let symbolPrefixMap: [(prefix: String, code: String)] = [
        ("US$", "USD"), ("HK$", "HKD"), ("NT$", "TWD"), ("MOP$", "MOP"),
        ("NZ$", "NZD"), ("MX$", "MXN"), ("S$", "SGD"), ("A$", "AUD"),
        ("C$", "CAD"), ("R$", "BRL"), ("RM", "MYR"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("￥", "CNY"),
        ("¥", "CNY"), ("₩", "KRW"), ("฿", "THB"), ("₹", "INR"),
        ("₽", "RUB"), ("₺", "TRY"), ("₫", "VND"), ("₱", "PHP"),
        ("₪", "ILS"), ("₴", "UAH"), ("₿", "BTC"),
    ]

    private static let knownDetectableCodes: Set<String> = Set(
        catalog.map(\.code) + Array(knownCryptoCodes) + Array(knownMetalCodes)
    )

    static func parseCurrencyQuery(_ raw: String) -> (amount: Double, code: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), trimmed.count <= 48 else { return nil }
        // Exclude hex color codes & timestamps cleanly
        guard !trimmed.hasPrefix("#") else { return nil }

        // 1. Prefix symbol forms: `$199.50`, `HK$ 500`, `€88`, `￥299`
        for item in symbolPrefixMap {
            if trimmed.hasPrefix(item.prefix) {
                let rest = String(trimmed.dropFirst(item.prefix.count))
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if rest.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil,
                   let val = Double(rest), val.isFinite {
                    return (val, item.code)
                }
            }
        }

        // 2. Number + Code or Code + Number: `100 USD`, `1,250.5 CNY`, `USD 100`, `0.5 BTC`
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        if let m = matchFirst(#"^(\d+(?:\.\d+)?)\s*([A-Za-z]{3,4})$"#, in: cleaned),
           let val = Double(m[0]), val.isFinite {
            let code = m[1].uppercased()
            if knownDetectableCodes.contains(code) {
                return (val, code)
            }
        }
        if let m = matchFirst(#"^([A-Za-z]{3,4})\s*(\d+(?:\.\d+)?)$"#, in: cleaned),
           let val = Double(m[1]), val.isFinite {
            let code = m[0].uppercased()
            if knownDetectableCodes.contains(code) {
                return (val, code)
            }
        }
        return nil
    }

    private static func matchFirst(_ pattern: String, in input: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: input, range: NSRange(location: 0, length: (input as NSString).length)) else {
            return nil
        }
        let ns = input as NSString
        return (1..<match.numberOfRanges).compactMap { idx in
            let r = match.range(at: idx)
            return r.location != NSNotFound ? ns.substring(with: r) : nil
        }
    }
}
