import Foundation

struct TimestampEntry: Identifiable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case unix, standard, timezone, calendar, code

        var title: String {
            switch self {
            case .unix: return "Unix 时间戳"
            case .standard: return "标准日期格式"
            case .timezone: return "全球多时区"
            case .calendar: return "日历与边界"
            case .code: return "代码片段"
            }
        }
    }

    let id: String
    let category: Category
    let title: String
    let value: String
    let badge: String
}

struct ParsedTimestamp: Sendable {
    let date: Date
    let detectedKind: String
    let exactNanoseconds: Int128?
    let isLive: Bool
}

struct TimestampReport: Sendable {
    let parsed: ParsedTimestamp
    let entries: [TimestampEntry]
    let relativeLabel: String
    let isoWeek: String
    let dayOfYear: Int
    let quarter: Int
    let isLeapYear: Bool
}

enum TimestampEngine {
    static let worldTimezones: [(zone: String, label: String)] = [
        ("UTC", "UTC · 协调世界时"),
        ("Asia/Shanghai", "Asia/Shanghai · 北京/上海"),
        ("Asia/Tokyo", "Asia/Tokyo · 东京"),
        ("America/New_York", "America/New_York · 纽约"),
        ("America/Los_Angeles", "America/Los_Angeles · 洛杉矶"),
        ("Europe/London", "Europe/London · 伦敦"),
        ("Europe/Berlin", "Europe/Berlin · 柏林"),
        ("Asia/Singapore", "Asia/Singapore · 新加坡"),
    ]

    static func formatDate(_ date: Date, format: String, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    static func formatIso(_ date: Date, timeZone: TimeZone) -> String {
        let opts: ISO8601DateFormatter.Options = [.withInternetDateTime, .withFractionalSeconds]
        return ISO8601DateFormatter.string(from: date, timeZone: timeZone, formatOptions: opts)
    }

    static func formatInTimezone(_ date: Date, identifier: String) -> (formatted: String, offset: String) {
        guard let tz = TimeZone(identifier: identifier) else {
            return ("Invalid Timezone", identifier)
        }
        let formatted = formatDate(date, format: "yyyy-MM-dd HH:mm:ss", timeZone: tz)
        let sec = tz.secondsFromGMT(for: date)
        let sign = sec >= 0 ? "+" : "-"
        let absSec = abs(sec)
        let h = absSec / 3600
        let m = (absSec % 3600) / 60
        let offset = m == 0 ? "GMT\(sign)\(h)" : String(format: "GMT%@%d:%02d", sign, h, m)
        return (formatted, offset)
    }

    static func formatRelative(target: Date, now: Date) -> String {
        let diff = target.timeIntervalSince(now)
        let absSec = Int(abs(diff).rounded())
        if absSec < 2 { return "刚刚 (Just now)" }
        let suffix = diff >= 0 ? "后" : "前"
        if absSec < 60 { return "\(absSec) 秒\(suffix)" }
        let mins = absSec / 60
        if mins < 60 { return "\(mins) 分钟\(suffix)" }
        let hours = mins / 60
        let rem = mins % 60
        if hours < 24 { return rem > 0 ? "\(hours) 小时 \(rem) 分钟\(suffix)" : "\(hours) 小时\(suffix)" }
        let days = hours / 24
        if days < 30 { return "\(days) 天\(suffix)" }
        let months = days / 30
        if months < 12 { return "\(months) 个月\(suffix)" }
        let years = String(format: "%.1f", Double(days) / 365.25).replacingOccurrences(of: ".0", with: "")
        return "\(years) 年\(suffix)"
    }

    static func parse(_ raw: String, now: Date = Date()) -> ParsedTimestamp? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return ParsedTimestamp(date: now, detectedKind: "当前实时时间 (Live)", exactNanoseconds: nil, isLive: true)
        }

        // Compact 14-digit YYYYMMDDHHmmss
        if input.count == 14, input.allSatisfy(\.isNumber) {
            if let dt = strictParse(input, format: "yyyyMMddHHmmss") {
                return ParsedTimestamp(date: dt, detectedKind: "紧凑日期时间 (YYYYMMDDHHmmss)", exactNanoseconds: nil, isLive: false)
            }
        }
        // Compact 8-digit YYYYMMDD
        if input.count == 8, input.allSatisfy(\.isNumber) {
            if let dt = strictParse(input, format: "yyyyMMdd") {
                return ParsedTimestamp(date: dt, detectedKind: "紧凑日期 (YYYYMMDD)", exactNanoseconds: nil, isLive: false)
            }
        }

        // Numeric Unix timestamp (integer or decimal)
        if let numMatch = input.wholeMatch(of: /^-?\d+(?:\.\d+)?$/) {
            let text = String(numMatch.output)
            if !text.contains("."), let big = Int128(text) {
                let absVal = big < 0 ? -big : big
                if absVal >= 100_000_000_000_000_000 {
                    let sec = Double(big) / 1_000_000_000.0
                    return ParsedTimestamp(date: Date(timeIntervalSince1970: sec), detectedKind: "Unix 纳秒 (ns)", exactNanoseconds: big, isLive: false)
                }
                if absVal >= 100_000_000_000_000 {
                    let sec = Double(big) / 1_000_000.0
                    return ParsedTimestamp(date: Date(timeIntervalSince1970: sec), detectedKind: "Unix 微秒 (μs)", exactNanoseconds: big * 1000, isLive: false)
                }
                if absVal >= 100_000_000_000 {
                    let sec = Double(big) / 1000.0
                    return ParsedTimestamp(date: Date(timeIntervalSince1970: sec), detectedKind: "Unix 毫秒 (ms)", exactNanoseconds: nil, isLive: false)
                }
                return ParsedTimestamp(date: Date(timeIntervalSince1970: Double(big)), detectedKind: "Unix 秒 (s)", exactNanoseconds: nil, isLive: false)
            } else if let val = Double(text), val.isFinite {
                let isMs = abs(val) >= 1e11
                return ParsedTimestamp(
                    date: Date(timeIntervalSince1970: isMs ? val / 1000.0 : val),
                    detectedKind: isMs ? "Unix 毫秒 (浮点)" : "Unix 秒 (浮点)",
                    exactNanoseconds: nil,
                    isLive: false
                )
            }
        }

        // Anchor keywords
        if let anchor = parseAnchor(input, now: now) {
            return ParsedTimestamp(date: anchor, detectedKind: "相对时间 (\(input))", exactNanoseconds: nil, isLive: false)
        }

        // Relative offset: +2h, -30m, +7d
        if let m = input.wholeMatch(of: /^([+-])\s*(\d+)\s*([a-zA-Z]+)$/) {
            let sign = m.1 == "-" ? -1 : 1
            let amount = Int(m.2) ?? 0
            if let shifted = applyOffset(base: now, sign: sign, amount: amount, unit: String(m.3)) {
                return ParsedTimestamp(date: shifted, detectedKind: "相对偏移 (now \(m.1)\(amount)\(m.3))", exactNanoseconds: nil, isLive: false)
            }
        }

        // Anchor + offset: today+1d, now - 2h
        if let m = input.wholeMatch(of: /(?i)^(now|today|tomorrow|yesterday|sod|eod|sow|som|eom|soy|eoy)\s*([+-])\s*(\d+)\s*([a-zA-Z]+)$/) {
            if let base = parseAnchor(String(m.1), now: now) {
                let sign = m.2 == "-" ? -1 : 1
                let amount = Int(m.3) ?? 0
                if let shifted = applyOffset(base: base, sign: sign, amount: amount, unit: String(m.4)) {
                    return ParsedTimestamp(date: shifted, detectedKind: "相对表达式 (\(input))", exactNanoseconds: nil, isLive: false)
                }
            }
        }

        // ISO 8601
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let dt = iso1.date(from: input) {
            return ParsedTimestamp(date: dt, detectedKind: "ISO 8601", exactNanoseconds: nil, isLive: false)
        }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let dt = iso2.date(from: input) {
            return ParsedTimestamp(date: dt, detectedKind: "ISO 8601", exactNanoseconds: nil, isLive: false)
        }

        // Common local / HTTP date formats
        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss.SSS",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
        ]
        for fmt in formats {
            if let dt = strictParse(input, format: fmt) {
                return ParsedTimestamp(date: dt, detectedKind: "日期时间字符串", exactNanoseconds: nil, isLive: false)
            }
        }
        return nil
    }

    private static func strictParse(_ text: String, format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        f.isLenient = false
        return f.date(from: text)
    }

    private static func parseAnchor(_ raw: String, now: Date) -> Date? {
        let cal = Calendar.current
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "now": return now
        case "today", "start of day", "sod": return cal.startOfDay(for: now)
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
        case "yesterday": return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
        case "end of day", "eod":
            return cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        case "start of week", "sow":
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return cal.date(from: comps)
        case "start of month", "som":
            let comps = cal.dateComponents([.year, .month], from: now)
            return cal.date(from: comps)
        case "end of month", "eom":
            if let som = cal.date(from: cal.dateComponents([.year, .month], from: now)),
               let next = cal.date(byAdding: .month, value: 1, to: som) {
                return next.addingTimeInterval(-0.001)
            }
            return nil
        case "start of year", "soy":
            return cal.date(from: cal.dateComponents([.year], from: now))
        case "end of year", "eoy":
            if let soy = cal.date(from: cal.dateComponents([.year], from: now)),
               let next = cal.date(byAdding: .year, value: 1, to: soy) {
                return next.addingTimeInterval(-0.001)
            }
            return nil
        default:
            return nil
        }
    }

    private static func applyOffset(base: Date, sign: Int, amount: Int, unit: String) -> Date? {
        let delta = sign * amount
        let cal = Calendar.current
        switch unit {
        case "ms": return base.addingTimeInterval(Double(delta) / 1000.0)
        case "s", "sec", "secs", "second", "seconds": return base.addingTimeInterval(Double(delta))
        case "m", "min", "mins", "minute", "minutes": return base.addingTimeInterval(Double(delta) * 60)
        case "h", "hr", "hrs", "hour", "hours": return base.addingTimeInterval(Double(delta) * 3600)
        case "d", "day", "days": return cal.date(byAdding: .day, value: delta, to: base)
        case "w", "wk", "wks", "week", "weeks": return cal.date(byAdding: .day, value: delta * 7, to: base)
        case "M", "mo", "month", "months": return cal.date(byAdding: .month, value: delta, to: base)
        case "y", "yr", "yrs", "year", "years": return cal.date(byAdding: .year, value: delta, to: base)
        default: return nil
        }
    }

    static func buildReport(_ parsed: ParsedTimestamp, now: Date = Date()) -> TimestampReport {
        let date = parsed.date
        let secDouble = date.timeIntervalSince1970
        let ms = Int64((secDouble * 1000.0).rounded())
        let sec = Int64(floor(secDouble))
        let us = parsed.exactNanoseconds.map { $0 / 1000 } ?? Int128(ms) * 1000
        let ns = parsed.exactNanoseconds ?? Int128(ms) * 1_000_000

        let cal = Calendar.current
        let isoCal = Calendar(identifier: .iso8601)
        let year = cal.component(.year, from: date)
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let doy = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let isoWeekNum = isoCal.component(.weekOfYear, from: date)
        let isoYear = isoCal.component(.yearForWeekOfYear, from: date)
        let isoWeek = String(format: "%04d-W%02d", isoYear, isoWeekNum)
        let quarter = ((cal.component(.month, from: date) - 1) / 3) + 1
        let relative = formatRelative(target: date, now: now)

        let dayStart = cal.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(86_399.999)
        let localTzName = TimeZone.current.identifier

        var entries: [TimestampEntry] = [
            TimestampEntry(id: "unix-s", category: .unix, title: "Unix 秒 (Seconds)", value: "\(sec)", badge: "s"),
            TimestampEntry(id: "unix-ms", category: .unix, title: "Unix 毫秒 (Milliseconds)", value: "\(ms)", badge: "ms"),
            TimestampEntry(id: "unix-us", category: .unix, title: "Unix 微秒 (Microseconds)", value: "\(us)", badge: "μs"),
            TimestampEntry(id: "unix-ns", category: .unix, title: "Unix 纳秒 (Nanoseconds)", value: "\(ns)", badge: "ns"),
            TimestampEntry(id: "unix-hex", category: .unix, title: "Unix 十六进制 (Hex)", value: String(format: "0x%x", UInt32(truncatingIfNeeded: sec)), badge: "hex"),

            TimestampEntry(id: "iso-utc", category: .standard, title: "ISO 8601 (UTC)", value: formatIso(date, timeZone: .gmt), badge: "UTC"),
            TimestampEntry(id: "iso-local", category: .standard, title: "ISO 8601 (本地时区)", value: formatIso(date, timeZone: .current), badge: localTzName),
            TimestampEntry(id: "local-dt", category: .standard, title: "本地时间 (YYYY-MM-DD HH:mm:ss)", value: formatDate(date, format: "yyyy-MM-dd HH:mm:ss"), badge: "Local"),
            TimestampEntry(id: "local-ms", category: .standard, title: "本地精确时间 (含毫秒)", value: formatDate(date, format: "yyyy-MM-dd HH:mm:ss.SSS"), badge: "ms"),
            TimestampEntry(id: "utc-dt", category: .standard, title: "UTC 时间 (YYYY-MM-DD HH:mm:ss)", value: formatDate(date, format: "yyyy-MM-dd HH:mm:ss", timeZone: .gmt), badge: "UTC"),
            TimestampEntry(id: "rfc-2822", category: .standard, title: "RFC 2822 / HTTP 日期", value: formatDate(date, format: "EEE, dd MMM yyyy HH:mm:ss 'GMT'", timeZone: .gmt), badge: "RFC"),
            TimestampEntry(id: "compact-dt", category: .standard, title: "紧凑格式 (YYYYMMDDHHmmss)", value: formatDate(date, format: "yyyyMMddHHmmss"), badge: "14位"),

            TimestampEntry(id: "relative", category: .calendar, title: "相对当前", value: relative, badge: "Rel"),
            TimestampEntry(id: "calendar-meta", category: .calendar, title: "日历信息 (ISO 周 / 年内第几天)", value: "\(isoWeek) · Q\(quarter) · 第 \(doy) 天\(isLeap ? " (闰年)" : "")", badge: isoWeek),
            TimestampEntry(id: "day-start", category: .calendar, title: "当天 00:00:00 时间戳 (s)", value: "\(Int64(dayStart.timeIntervalSince1970))", badge: "Start"),
            TimestampEntry(id: "day-end", category: .calendar, title: "当天 23:59:59 时间戳 (s)", value: "\(Int64(dayEnd.timeIntervalSince1970))", badge: "End"),
        ]

        for tz in worldTimezones {
            let res = formatInTimezone(date, identifier: tz.zone)
            entries.append(TimestampEntry(id: "tz-\(tz.zone)", category: .timezone, title: tz.label, value: res.formatted, badge: res.offset))
        }

        entries.append(contentsOf: [
            TimestampEntry(id: "code-js", category: .code, title: "JavaScript / TypeScript", value: "new Date(\(ms))", badge: "JS"),
            TimestampEntry(id: "code-py", category: .code, title: "Python (datetime)", value: "datetime.fromtimestamp(\(sec), tz=timezone.utc)", badge: "Py"),
            TimestampEntry(id: "code-go", category: .code, title: "Go (time.Unix)", value: "time.Unix(\(sec), 0)", badge: "Go"),
            TimestampEntry(id: "code-sql", category: .code, title: "MySQL / PostgreSQL", value: "FROM_UNIXTIME(\(sec))", badge: "SQL"),
        ])

        return TimestampReport(
            parsed: parsed,
            entries: entries,
            relativeLabel: relative,
            isoWeek: isoWeek,
            dayOfYear: doy,
            quarter: quarter,
            isLeapYear: isLeap
        )
    }
}
