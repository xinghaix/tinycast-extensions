import Foundation

// MARK: - 1. Regex Tester Engine

struct RegexFlags: Sendable, Equatable {
    var caseInsensitive: Bool = false
    var multiline: Bool = false
    var dotMatchesAll: Bool = false
    var verbose: Bool = false

    var nsOptions: NSRegularExpression.Options {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        if multiline { opts.insert(.anchorsMatchLines) }
        if dotMatchesAll { opts.insert(.dotMatchesLineSeparators) }
        if verbose { opts.insert(.allowCommentsAndWhitespace) }
        return opts
    }
}

struct RegexCaptureGroup: Identifiable, Sendable {
    let id: Int
    let index: Int
    let name: String?
    let text: String?
    let rangeLocation: Int
    let rangeLength: Int
}

struct RegexMatchItem: Identifiable, Sendable {
    let id: Int
    let matchIndex: Int
    let matchedText: String
    let rangeLocation: Int
    let rangeLength: Int
    let groups: [RegexCaptureGroup]
}

struct RegexEvaluationResult: Sendable {
    let valid: Bool
    let error: String?
    let matches: [RegexMatchItem]
    let totalMatchCount: Int
    let truncated: Bool
    let namedGroupNames: [String]
    let replacedText: String
    let splitParts: [String]
}

struct RegexPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let pattern: String
    let replacement: String
    let sample: String
    let flags: RegexFlags
}

enum RegexEngine {
    static let presets: [RegexPreset] = [
        RegexPreset(
            id: "email",
            title: "邮箱地址",
            pattern: #"(?<user>[a-zA-Z0-9._%+-]+)@(?<domain>[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#,
            replacement: "$user@[REDACTED]",
            sample: "联系团队: dev@tinycast.app, support+urgent@example.co.uk 或无效 alice@",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "cn-phone",
            title: "中国手机号",
            pattern: #"(?<!\d)(?<prefix>1[3-9]\d)(\d{4})(?<tail>\d{4})(?!\d)"#,
            replacement: "${prefix}****${tail}",
            sample: "客服: 13800138000, 备用 18612345678, 非手机号 213800138000",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "url",
            title: "HTTP/HTTPS URL",
            pattern: #"(?<scheme>https?)://(?<host>[^\s/:?#]+)(?::(?<port>\d+))?(?<path>/[^\s?#]*)?(?:\?(?<query>[^\s#]*))?"#,
            replacement: "$1://$2$4",
            sample: "Docs: https://github.com/xinghaix/tinycast-extensions?tab=readme#install\nLocal: http://127.0.0.1:8080/api/v1/health?verbose=1",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "ipv4",
            title: "IPv4 地址",
            pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|1?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|1?\d\d?)\b"#,
            replacement: "[IP]",
            sample: "Gateway 192.168.1.1 -> Server 10.0.12.34, bad 999.1.2.3",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "semver",
            title: "SemVer 版本号",
            pattern: #"v?(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>[0-9A-Za-z.-]+))?"#,
            replacement: "v${major}.${minor}.${patch}",
            sample: "Releases: v1.0.0, 2.3.4-beta.1, 10.2.0-rc2",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "iso-date",
            title: "日期 YYYY-MM-DD",
            pattern: #"(?<year>\d{4})-(?<month>0[1-9]|1[0-2])-(?<day>0[1-9]|[12]\d|3[01])"#,
            replacement: "${year}/${month}/${day}",
            sample: "Created 2026-11-19, updated 2026-02-28 (ignore 2026-13-40)",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "hex-color",
            title: "HEX 色值",
            pattern: #"#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b"#,
            replacement: "$0",
            sample: "palette: #3B82F6, #10b981cc, #fff, not #zzzzzz",
            flags: RegexFlags()
        ),
        RegexPreset(
            id: "cjk",
            title: "中文字符片段",
            pattern: #"[\u4e00-\u9fa5]+"#,
            replacement: "[$0]",
            sample: "Tinycast 原生工具箱 v1.1 支持离线 OCR 识字。",
            flags: RegexFlags()
        ),
    ]

    static let cheatsheet: [(token: String, desc: String)] = [
        (#"\d / \D"#, "数字 / 非数字"),
        (#"\w / \s"#, "字母数字下划线 / 空白"),
        (#"(?<name>...)"#, "命名捕获组"),
        (#"(?:...)"#, "非捕获分组"),
        (#"(?=...) / (?!...)"#, "正/负向先行断言"),
        (#"(?<=...) / (?<!...)"#, "正/负向后行断言"),
        (#"$1 / ${name}"#, "替换模板引用捕获组"),
        (#"+? / *?"#, "非贪婪懒惰匹配"),
    ]

    static func extractNamedGroupNames(from pattern: String) -> [String] {
        guard !pattern.isEmpty else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        let chars = Array(pattern)
        var i = 0
        var inCharClass = false
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                i += 2
                continue
            }
            if ch == "[" && !inCharClass {
                inCharClass = true
                i += 1
                continue
            }
            if ch == "]" && inCharClass {
                inCharClass = false
                i += 1
                continue
            }
            if !inCharClass && ch == "(" && i + 3 < chars.count && chars[i + 1] == "?" && chars[i + 2] == "<" {
                let next = chars[i + 3]
                // Exclude lookbehinds `(?<=` and `(?<!`
                if next != "=" && next != "!" {
                    var j = i + 3
                    var name = ""
                    while j < chars.count && chars[j] != ">" {
                        name.append(chars[j])
                        j += 1
                    }
                    if j < chars.count && !name.isEmpty && seen.insert(name).inserted {
                        names.append(name)
                    }
                }
            }
            i += 1
        }
        return names
    }

    static func evaluate(pattern: String, input: String, replacement: String, flags: RegexFlags) -> RegexEvaluationResult {
        guard !pattern.isEmpty else {
            return RegexEvaluationResult(
                valid: false,
                error: "请输入正则表达式",
                matches: [],
                totalMatchCount: 0,
                truncated: false,
                namedGroupNames: [],
                replacedText: input,
                splitParts: input.isEmpty ? [] : [input]
            )
        }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: flags.nsOptions)
        } catch {
            return RegexEvaluationResult(
                valid: false,
                error: error.localizedDescription,
                matches: [],
                totalMatchCount: 0,
                truncated: false,
                namedGroupNames: [],
                replacedText: input,
                splitParts: []
            )
        }

        let nsInput = input as NSString
        let fullRange = NSRange(location: 0, length: nsInput.length)
        let rawMatches = regex.matches(in: input, options: [], range: fullRange)
        let namedGroups = extractNamedGroupNames(from: pattern)

        // Reverse map (location, length) -> group name so each numbered group also carries its name if any
        let capLimit = 500
        var items: [RegexMatchItem] = []
        items.reserveCapacity(min(rawMatches.count, capLimit))

        for (mIdx, match) in rawMatches.prefix(capLimit).enumerated() {
            var nameByRange: [String: String] = [:]
            for gName in namedGroups {
                let r = match.range(withName: gName)
                if r.location != NSNotFound {
                    let key = "\(r.location):\(r.length)"
                    if nameByRange[key] == nil {
                        nameByRange[key] = gName
                    }
                }
            }

            var groups: [RegexCaptureGroup] = []
            if match.numberOfRanges > 1 {
                for gIdx in 1..<match.numberOfRanges {
                    let r = match.range(at: gIdx)
                    let text: String? = r.location != NSNotFound ? nsInput.substring(with: r) : nil
                    let gName = r.location != NSNotFound ? nameByRange["\(r.location):\(r.length)"] : nil
                    groups.append(RegexCaptureGroup(
                        id: gIdx,
                        index: gIdx,
                        name: gName,
                        text: text,
                        rangeLocation: r.location,
                        rangeLength: r.length
                    ))
                }
            }

            let mText = nsInput.substring(with: match.range)
            items.append(RegexMatchItem(
                id: mIdx,
                matchIndex: mIdx + 1,
                matchedText: mText,
                rangeLocation: match.range.location,
                rangeLength: match.range.length,
                groups: groups
            ))
        }

        let replaced = applyReplacement(input: input, matches: rawMatches, template: replacement, namedGroupNames: namedGroups)

        // Split using all matched ranges
        var splitParts: [String] = []
        var cursor = 0
        for m in rawMatches.prefix(2000) {
            let loc = m.range.location
            let len = m.range.length
            if loc >= cursor {
                splitParts.append(nsInput.substring(with: NSRange(location: cursor, length: loc - cursor)))
                cursor = loc + len
            }
        }
        splitParts.append(nsInput.substring(with: NSRange(location: cursor, length: max(0, nsInput.length - cursor))))

        return RegexEvaluationResult(
            valid: true,
            error: nil,
            matches: items,
            totalMatchCount: rawMatches.count,
            truncated: rawMatches.count > capLimit,
            namedGroupNames: namedGroups,
            replacedText: replaced,
            splitParts: splitParts
        )
    }

    private static func applyReplacement(
        input: String,
        matches: [NSTextCheckingResult],
        template: String,
        namedGroupNames: [String]
    ) -> String {
        guard !matches.isEmpty else { return input }
        let nsInput = input as NSString
        let tChars = Array(template)
        let sortedNamed = namedGroupNames.sorted { $0.count > $1.count }

        func expandTemplate(for match: NSTextCheckingResult) -> String {
            var expanded = ""
            var i = 0
            while i < tChars.count {
                let ch = tChars[i]
                if ch == "\\" && i + 1 < tChars.count {
                    let next = tChars[i + 1]
                    if next == "n" { expanded.append("\n"); i += 2; continue }
                    if next == "t" { expanded.append("\t"); i += 2; continue }
                    if next == "r" { expanded.append("\r"); i += 2; continue }
                    expanded.append(next)
                    i += 2
                    continue
                }
                if ch == "$" && i + 1 < tChars.count {
                    let next = tChars[i + 1]
                    if next == "$" {
                        expanded.append("$")
                        i += 2
                        continue
                    }
                    if next == "{" {
                        var j = i + 2
                        while j < tChars.count && tChars[j] != "}" { j += 1 }
                        if j < tChars.count {
                            let token = String(tChars[(i + 2)..<j])
                            if let idx = Int(token), idx >= 0, idx < match.numberOfRanges {
                                let r = match.range(at: idx)
                                if r.location != NSNotFound { expanded += nsInput.substring(with: r) }
                            } else {
                                let r = match.range(withName: token)
                                if r.location != NSNotFound { expanded += nsInput.substring(with: r) }
                            }
                            i = j + 1
                            continue
                        }
                    }
                    if next.isNumber {
                        var j = i + 1
                        while j < tChars.count && tChars[j].isNumber { j += 1 }
                        if let idx = Int(String(tChars[(i + 1)..<j])), idx < match.numberOfRanges {
                            let r = match.range(at: idx)
                            if r.location != NSNotFound { expanded += nsInput.substring(with: r) }
                        }
                        i = j
                        continue
                    }
                    let tail = String(tChars[(i + 1)...])
                    if let matchedName = sortedNamed.first(where: { name in
                        guard tail.hasPrefix(name) else { return false }
                        let afterIdx = tail.index(tail.startIndex, offsetBy: name.count)
                        return afterIdx == tail.endIndex || !(tail[afterIdx].isLetter || tail[afterIdx].isNumber || tail[afterIdx] == "_")
                    }) {
                        let r = match.range(withName: matchedName)
                        if r.location != NSNotFound { expanded += nsInput.substring(with: r) }
                        i += 1 + matchedName.count
                        continue
                    }
                }
                expanded.append(ch)
                i += 1
            }
            return expanded
        }

        var out = ""
        var cursor = 0
        for match in matches {
            let loc = match.range.location
            let len = match.range.length
            guard loc != NSNotFound, loc >= cursor, loc + len <= nsInput.length else { continue }
            out += nsInput.substring(with: NSRange(location: cursor, length: loc - cursor))
            out += expandTemplate(for: match)
            cursor = loc + len
        }
        out += nsInput.substring(with: NSRange(location: cursor, length: max(0, nsInput.length - cursor)))
        return out
    }
}

// MARK: - 2. Text & JSON Semantic Diff Engine

enum DiffLineKind: String, Sendable {
    case unchanged
    case added
    case removed
}

struct DiffInlineSegment: Identifiable, Sendable {
    let id: Int
    let text: String
    let changed: Bool
}

struct DiffLine: Identifiable, Sendable {
    let id: Int
    let kind: DiffLineKind
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let text: String
    let segments: [DiffInlineSegment]
}

struct DiffRowPair: Identifiable, Sendable {
    let id: Int
    let left: DiffLine?
    let right: DiffLine?
}

struct JsonChangeItem: Identifiable, Sendable {
    let id: Int
    let path: String
    let kind: String // "added", "removed", "changed", "type"
    let before: String?
    let after: String?
}

struct DiffResult: Sendable {
    let unifiedLines: [DiffLine]
    let sideBySideRows: [DiffRowPair]
    let addedCount: Int
    let removedCount: Int
    let changedPairsCount: Int
    let unifiedPatch: String
    let jsonChanges: [JsonChangeItem]
    let normalizedLeft: String
    let normalizedRight: String
    let error: String?
}

enum DiffEngine {
    static let sampleLeft = """
    {
      "service": "tinycast-api",
      "version": "1.0.0",
      "timeoutMs": 3000,
      "features": {
        "nativeStudio": true,
        "ocr": false
      },
      "endpoints": [
        "https://api.example.com/v1",
        "https://backup.example.com/v1"
      ]
    }
    """

    static let sampleRight = """
    {
      "endpoints": [
        "https://api.example.com/v2",
        "https://backup.example.com/v1",
        "https://edge.example.com/v2"
      ],
      "features": {
        "ocr": true,
        "nativeStudio": true,
        "certInspector": true
      },
      "service": "tinycast-api",
      "version": "1.1.0",
      "retryCount": 2
    }
    """

    static func computeDiff(
        left: String,
        right: String,
        jsonSemantic: Bool,
        ignoreWhitespace: Bool,
        ignoreCase: Bool
    ) -> DiffResult {
        var normLeft = left
        var normRight = right
        var jsonChanges: [JsonChangeItem] = []

        if jsonSemantic {
            let lAna = JsonEngine.analyze(left)
            let rAna = JsonEngine.analyze(right)
            guard lAna.valid, let lSorted = lAna.sortedPretty else {
                return DiffResult(
                    unifiedLines: [], sideBySideRows: [], addedCount: 0, removedCount: 0,
                    changedPairsCount: 0, unifiedPatch: "", jsonChanges: [],
                    normalizedLeft: left, normalizedRight: right,
                    error: "左侧不是有效 JSON: \(lAna.error ?? "解析失败")"
                )
            }
            guard rAna.valid, let rSorted = rAna.sortedPretty else {
                return DiffResult(
                    unifiedLines: [], sideBySideRows: [], addedCount: 0, removedCount: 0,
                    changedPairsCount: 0, unifiedPatch: "", jsonChanges: [],
                    normalizedLeft: left, normalizedRight: right,
                    error: "右侧不是有效 JSON: \(rAna.error ?? "解析失败")"
                )
            }
            normLeft = lSorted
            normRight = rSorted
            if let lObj = try? JSONSerialization.jsonObject(with: Data(lSorted.utf8), options: [.fragmentsAllowed]),
               let rObj = try? JSONSerialization.jsonObject(with: Data(rSorted.utf8), options: [.fragmentsAllowed]) {
                var counter = 0
                collectJsonDiffs(path: "$", left: lObj, right: rObj, out: &jsonChanges, counter: &counter)
            }
        }

        let leftLines = splitLinesPreservingEmpty(normLeft)
        let rightLines = splitLinesPreservingEmpty(normRight)

        let compareKey: (String) -> String = { line in
            var s = line
            if ignoreWhitespace {
                s = s.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }
            if ignoreCase {
                s = s.lowercased()
            }
            return s
        }

        let leftKeys = leftLines.map(compareKey)
        let rightKeys = rightLines.map(compareKey)

        enum RawOp {
            case equal(Int, Int)
            case remove(Int)
            case add(Int)
        }

        let rawOps = computeLineOps(leftKeys: leftKeys, rightKeys: rightKeys)

        func buildOps() -> [RawOp] {
            rawOps.map { op in
                switch op {
                case .equal(let li, let ri): return .equal(li, ri)
                case .remove(let li): return .remove(li)
                case .add(let ri): return .add(ri)
                }
            }
        }

        let ops = buildOps()
        var unified: [DiffLine] = []
        var sideRows: [DiffRowPair] = []
        var added = 0
        var removed = 0
        var changedPairs = 0

        var idx = 0
        var nextId = 0
        var rowId = 0

        while idx < ops.count {
            switch ops[idx] {
            case .equal(let li, let ri):
                let lineText = rightLines[ri]
                let dLine = DiffLine(
                    id: nextId,
                    kind: .unchanged,
                    leftLineNumber: li + 1,
                    rightLineNumber: ri + 1,
                    text: lineText,
                    segments: lineText.isEmpty ? [] : [DiffInlineSegment(id: 0, text: lineText, changed: false)]
                )
                nextId += 1
                unified.append(dLine)
                sideRows.append(DiffRowPair(id: rowId, left: dLine, right: dLine))
                rowId += 1
                idx += 1

            case .remove, .add:
                var remIndices: [Int] = []
                var addIndices: [Int] = []
                while idx < ops.count {
                    if case .remove(let li) = ops[idx] {
                        remIndices.append(li)
                        idx += 1
                    } else if case .add(let ri) = ops[idx] {
                        addIndices.append(ri)
                        idx += 1
                    } else {
                        break
                    }
                }

                let pairCount = min(remIndices.count, addIndices.count)
                changedPairs += pairCount
                removed += remIndices.count
                added += addIndices.count

                var remLines: [DiffLine] = []
                var addLines: [DiffLine] = []

                for p in 0..<pairCount {
                    let li = remIndices[p]
                    let ri = addIndices[p]
                    let (lSegs, rSegs) = inlineSegments(left: leftLines[li], right: rightLines[ri])
                    remLines.append(DiffLine(
                        id: nextId, kind: .removed, leftLineNumber: li + 1, rightLineNumber: nil,
                        text: leftLines[li], segments: lSegs
                    ))
                    nextId += 1
                    addLines.append(DiffLine(
                        id: nextId, kind: .added, leftLineNumber: nil, rightLineNumber: ri + 1,
                        text: rightLines[ri], segments: rSegs
                    ))
                    nextId += 1
                }

                for p in pairCount..<remIndices.count {
                    let li = remIndices[p]
                    let t = leftLines[li]
                    remLines.append(DiffLine(
                        id: nextId, kind: .removed, leftLineNumber: li + 1, rightLineNumber: nil,
                        text: t, segments: [DiffInlineSegment(id: 0, text: t, changed: true)]
                    ))
                    nextId += 1
                }

                for p in pairCount..<addIndices.count {
                    let ri = addIndices[p]
                    let t = rightLines[ri]
                    addLines.append(DiffLine(
                        id: nextId, kind: .added, leftLineNumber: nil, rightLineNumber: ri + 1,
                        text: t, segments: [DiffInlineSegment(id: 0, text: t, changed: true)]
                    ))
                    nextId += 1
                }

                unified.append(contentsOf: remLines)
                unified.append(contentsOf: addLines)

                let maxBlock = max(remLines.count, addLines.count)
                for row in 0..<maxBlock {
                    sideRows.append(DiffRowPair(
                        id: rowId,
                        left: row < remLines.count ? remLines[row] : nil,
                        right: row < addLines.count ? addLines[row] : nil
                    ))
                    rowId += 1
                }
            }
        }

        // Build standard unified patch text
        var patchLines = ["--- left", "+++ right"]
        for line in unified {
            switch line.kind {
            case .unchanged: patchLines.append(" \(line.text)")
            case .removed: patchLines.append("-\(line.text)")
            case .added: patchLines.append("+\(line.text)")
            }
        }

        return DiffResult(
            unifiedLines: unified,
            sideBySideRows: sideRows,
            addedCount: added,
            removedCount: removed,
            changedPairsCount: changedPairs,
            unifiedPatch: patchLines.joined(separator: "\n"),
            jsonChanges: jsonChanges,
            normalizedLeft: normLeft,
            normalizedRight: normRight,
            error: nil
        )
    }

    private enum InternalOp {
        case equal(Int, Int)
        case remove(Int)
        case add(Int)
    }

    private static func computeLineOps(leftKeys: [String], rightKeys: [String]) -> [InternalOp] {
        let m = leftKeys.count
        let n = rightKeys.count
        var prefix = 0
        while prefix < m && prefix < n && leftKeys[prefix] == rightKeys[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (m - prefix) && suffix < (n - prefix) &&
              leftKeys[m - 1 - suffix] == rightKeys[n - 1 - suffix] {
            suffix += 1
        }

        var ops: [InternalOp] = []
        ops.reserveCapacity(max(m, n))
        for i in 0..<prefix {
            ops.append(.equal(i, i))
        }

        let midM = m - prefix - suffix
        let midN = n - prefix - suffix

        if midM == 0 {
            for j in 0..<midN { ops.append(.add(prefix + j)) }
        } else if midN == 0 {
            for i in 0..<midM { ops.append(.remove(prefix + i)) }
        } else if midM * midN <= 640_000 {
            let rowStride = midN + 1
            var dp = [Int32](repeating: 0, count: (midM + 1) * rowStride)
            for i in stride(from: midM - 1, through: 0, by: -1) {
                let rowOff = i * rowStride
                let nextOff = (i + 1) * rowStride
                for j in stride(from: midN - 1, through: 0, by: -1) {
                    if leftKeys[prefix + i] == rightKeys[prefix + j] {
                        dp[rowOff + j] = dp[nextOff + j + 1] + 1
                    } else {
                        let a = dp[nextOff + j]
                        let b = dp[rowOff + j + 1]
                        dp[rowOff + j] = a >= b ? a : b
                    }
                }
            }
            var i = 0
            var j = 0
            while i < midM && j < midN {
                if leftKeys[prefix + i] == rightKeys[prefix + j] {
                    ops.append(.equal(prefix + i, prefix + j))
                    i += 1
                    j += 1
                } else if dp[(i + 1) * rowStride + j] >= dp[i * rowStride + (j + 1)] {
                    ops.append(.remove(prefix + i))
                    i += 1
                } else {
                    ops.append(.add(prefix + j))
                    j += 1
                }
            }
            while i < midM { ops.append(.remove(prefix + i)); i += 1 }
            while j < midN { ops.append(.add(prefix + j)); j += 1 }
        } else {
            // Greedy anchor matching for huge files to prevent quadratic memory spikes
            var rightIndexMap: [String: [Int]] = [:]
            for j in 0..<midN {
                rightIndexMap[rightKeys[prefix + j], default: []].append(j)
            }
            var nextRightPos = [String: Int]()
            var jCursor = 0
            for i in 0..<midM {
                let key = leftKeys[prefix + i]
                let list = rightIndexMap[key] ?? []
                var startIdx = nextRightPos[key] ?? 0
                while startIdx < list.count && list[startIdx] < jCursor {
                    startIdx += 1
                }
                if startIdx < list.count {
                    let matchedJ = list[startIdx]
                    nextRightPos[key] = startIdx + 1
                    while jCursor < matchedJ {
                        ops.append(.add(prefix + jCursor))
                        jCursor += 1
                    }
                    ops.append(.equal(prefix + i, prefix + matchedJ))
                    jCursor = matchedJ + 1
                } else {
                    ops.append(.remove(prefix + i))
                }
            }
            while jCursor < midN {
                ops.append(.add(prefix + jCursor))
                jCursor += 1
            }
        }

        for s in 0..<suffix {
            ops.append(.equal(m - suffix + s, n - suffix + s))
        }
        return ops
    }

    private static func splitLinesPreservingEmpty(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    private static func inlineSegments(left: String, right: String) -> ([DiffInlineSegment], [DiffInlineSegment]) {
        let lChars = Array(left)
        let rChars = Array(right)
        var p = 0
        while p < lChars.count && p < rChars.count && lChars[p] == rChars[p] {
            p += 1
        }
        var s = 0
        while s < (lChars.count - p) && s < (rChars.count - p) &&
              lChars[lChars.count - 1 - s] == rChars[rChars.count - 1 - s] {
            s += 1
        }

        func build(_ chars: [Character]) -> [DiffInlineSegment] {
            var segs: [DiffInlineSegment] = []
            if p > 0 {
                segs.append(DiffInlineSegment(id: 0, text: String(chars[0..<p]), changed: false))
            }
            let midEnd = chars.count - s
            if midEnd > p {
                segs.append(DiffInlineSegment(id: 1, text: String(chars[p..<midEnd]), changed: true))
            }
            if s > 0 {
                segs.append(DiffInlineSegment(id: 2, text: String(chars[midEnd..<chars.count]), changed: false))
            }
            return segs
        }

        return (build(lChars), build(rChars))
    }

    private static func jsonValueString(_ v: Any) -> String {
        if v is NSNull { return "null" }
        if let num = v as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "true" : "false" }
            return "\(num)"
        }
        if let str = v as? String { return "\"\(str)\"" }
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes]),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "\(v)"
    }

    private static func collectJsonDiffs(path: String, left: Any, right: Any, out: inout [JsonChangeItem], counter: inout Int) {
        if let lDict = left as? [String: Any], let rDict = right as? [String: Any] {
            let allKeys = Set(lDict.keys).union(rDict.keys).sorted()
            for key in allKeys {
                let childPath = path == "$" ? "$.\(key)" : "\(path).\(key)"
                switch (lDict[key], rDict[key]) {
                case (nil, let rv?):
                    out.append(JsonChangeItem(id: counter, path: childPath, kind: "新增", before: nil, after: jsonValueString(rv)))
                    counter += 1
                case (let lv?, nil):
                    out.append(JsonChangeItem(id: counter, path: childPath, kind: "删除", before: jsonValueString(lv), after: nil))
                    counter += 1
                case (let lv?, let rv?):
                    collectJsonDiffs(path: childPath, left: lv, right: rv, out: &out, counter: &counter)
                case (nil, nil):
                    break
                }
            }
            return
        }

        if let lArr = left as? [Any], let rArr = right as? [Any] {
            let maxCount = max(lArr.count, rArr.count)
            for idx in 0..<maxCount {
                let childPath = "\(path)[\(idx)]"
                if idx >= lArr.count {
                    out.append(JsonChangeItem(id: counter, path: childPath, kind: "新增", before: nil, after: jsonValueString(rArr[idx])))
                    counter += 1
                } else if idx >= rArr.count {
                    out.append(JsonChangeItem(id: counter, path: childPath, kind: "删除", before: jsonValueString(lArr[idx]), after: nil))
                    counter += 1
                } else {
                    collectJsonDiffs(path: childPath, left: lArr[idx], right: rArr[idx], out: &out, counter: &counter)
                }
            }
            return
        }

        let ls = jsonValueString(left)
        let rs = jsonValueString(right)
        if ls != rs {
            out.append(JsonChangeItem(id: counter, path: path, kind: "修改", before: ls, after: rs))
            counter += 1
        }
    }
}

// MARK: - 3. URL & cURL Converter Engine

struct UrlQueryParam: Identifiable, Sendable, Equatable {
    let id: UUID
    var key: String
    var value: String
    var enabled: Bool

    init(id: UUID = UUID(), key: String, value: String, enabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
    }
}

struct ParsedUrlModel: Sendable {
    let original: String
    let scheme: String
    let user: String
    let password: String
    let host: String
    let port: String
    let path: String
    let pathSegments: [String]
    let fragment: String
    let origin: String
    let params: [UrlQueryParam]
}

struct ParsedCurlRequest: Sendable {
    let method: String
    let url: String
    let headers: [(key: String, value: String)]
    let body: String?
    let basicAuth: String?
    let formFields: [(key: String, value: String)]
    let followRedirects: Bool
    let insecure: Bool
}

enum UrlCurlEngine {
    static let sampleUrl = "https://api.tinycast.dev:8443/v1/search?q=swift+native&page=2&tag=macos&tag=swiftui&filter=%7B%22active%22%3Atrue%7D#results"

    static let sampleCurl = #"""
    curl -X POST 'https://api.example.com/v2/tokens?env=prod' \
      -H 'Authorization: Bearer tok_live_example_123' \
      -H 'Content-Type: application/json' \
      -H 'X-Request-ID: 01a1e8c8-b663-70b9-a00a-b1631241e33f' \
      -d '{"service":"tinycast","scopes":["read","write"]}'
    """#

    static func parseUrl(_ raw: String) -> ParsedUrlModel? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Handle bare query string (`?a=1&b=2` or `a=1&b=2`) as well as full URLs
        let isFullUrl = trimmed.contains("://")
        let candidate = isFullUrl ? trimmed : (trimmed.hasPrefix("?") ? "https://example.invalid/\(trimmed)" : (trimmed.contains("=") && !trimmed.contains("/") ? "https://example.invalid/?\(trimmed)" : "https://\(trimmed)"))

        guard let comps = URLComponents(string: candidate) ?? encodeLooseUrl(candidate) else {
            return nil
        }

        let scheme = isFullUrl ? (comps.scheme ?? "") : ""
        let host = (isFullUrl || !trimmed.contains("=") || trimmed.contains("/")) && comps.host != "example.invalid" ? (comps.host ?? "") : ""
        let port = comps.port.map(String.init) ?? ""
        let origin: String = {
            guard !scheme.isEmpty, !host.isEmpty else { return "" }
            return port.isEmpty ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
        }()

        // Decode + as space in query pairs cleanly while supporting URLComponents
        var params: [UrlQueryParam] = []
        if let rawQuery = comps.percentEncodedQuery, !rawQuery.isEmpty {
            for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
                let str = String(pair)
                if let eq = str.firstIndex(of: "=") {
                    let k = decodeQueryComponent(String(str[..<eq]))
                    let v = decodeQueryComponent(String(str[str.index(after: eq)...]))
                    params.append(UrlQueryParam(key: k, value: v))
                } else {
                    params.append(UrlQueryParam(key: decodeQueryComponent(str), value: ""))
                }
            }
        }

        let pathSegments = comps.path.split(separator: "/").map(String.init)
        return ParsedUrlModel(
            original: trimmed,
            scheme: scheme,
            user: comps.user ?? "",
            password: comps.password ?? "",
            host: host,
            port: port,
            path: comps.path,
            pathSegments: pathSegments,
            fragment: comps.fragment ?? "",
            origin: origin,
            params: params
        )
    }

    static func rebuildUrl(
        scheme: String,
        host: String,
        port: String,
        path: String,
        params: [UrlQueryParam],
        fragment: String
    ) -> String {
        var comps = URLComponents()
        let cleanScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanScheme.isEmpty { comps.scheme = cleanScheme }
        if !cleanHost.isEmpty { comps.host = cleanHost }
        if let p = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(p) {
            comps.port = p
        }
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPath.isEmpty {
            comps.path = cleanPath.hasPrefix("/") || cleanHost.isEmpty ? cleanPath : "/\(cleanPath)"
        }
        let activeParams = params.filter { $0.enabled && (!$0.key.isEmpty || !$0.value.isEmpty) }
        if !activeParams.isEmpty {
            comps.percentEncodedQuery = activeParams.map { item in
                let k = encodeQueryComponent(item.key)
                let v = encodeQueryComponent(item.value)
                return item.value.isEmpty && !item.key.isEmpty ? "\(k)=" : "\(k)=\(v)"
            }.joined(separator: "&")
        }
        let cleanFrag = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanFrag.isEmpty { comps.fragment = cleanFrag }
        return comps.string ?? ""
    }

    private static func decodeQueryComponent(_ raw: String) -> String {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
    }

    private static func encodeQueryComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func encodeLooseUrl(_ raw: String) -> URLComponents? {
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else { return nil }
        return URLComponents(string: encoded)
    }

    // MARK: cURL Parsing & Code Generation

    static func parseCurl(_ raw: String) throws -> ParsedCurlRequest {
        let tokens = tokenizeShell(raw)
        guard !tokens.isEmpty else {
            throw CodecError.message("请输入 curl 命令")
        }

        var idx = 0
        if tokens[0].lowercased() == "curl" { idx = 1 }

        var methodExplicit: String?
        var url = ""
        var headers: [(String, String)] = []
        var dataParts: [String] = []
        var basicAuth: String?
        var formFields: [(String, String)] = []
        var forceGet = false
        var followRedirects = false
        var insecure = false
        var useJsonDefaults = false

        while idx < tokens.count {
            let tok = tokens[idx]
            func nextVal() -> String? {
                guard idx + 1 < tokens.count else { return nil }
                idx += 1
                return tokens[idx]
            }

            if tok == "-X" || tok == "--request" {
                methodExplicit = nextVal()?.uppercased()
            } else if tok.hasPrefix("-X") && tok.count > 2 {
                methodExplicit = String(tok.dropFirst(2)).uppercased()
            } else if tok == "-H" || tok == "--header" {
                if let h = nextVal(), let colon = h.firstIndex(of: ":") {
                    let k = String(h[..<colon]).trimmingCharacters(in: .whitespaces)
                    let v = String(h[h.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    headers.append((k, v))
                }
            } else if tok == "-d" || tok == "--data" || tok == "--data-raw" || tok == "--data-binary" || tok == "--data-ascii" || tok == "--data-urlencode" {
                if let d = nextVal() { dataParts.append(d) }
            } else if tok == "--json" {
                useJsonDefaults = true
                if let d = nextVal() { dataParts.append(d) }
            } else if tok == "-u" || tok == "--user" {
                basicAuth = nextVal()
            } else if tok == "-A" || tok == "--user-agent" {
                if let ua = nextVal() { headers.append(("User-Agent", ua)) }
            } else if tok == "-b" || tok == "--cookie" {
                if let ck = nextVal() { headers.append(("Cookie", ck)) }
            } else if tok == "-e" || tok == "--referer" {
                if let rf = nextVal() { headers.append(("Referer", rf)) }
            } else if tok == "-F" || tok == "--form" {
                if let f = nextVal(), let eq = f.firstIndex(of: "=") {
                    formFields.append((String(f[..<eq]), String(f[f.index(after: eq)...])))
                }
            } else if tok == "-G" || tok == "--get" {
                forceGet = true
            } else if tok == "-L" || tok == "--location" {
                followRedirects = true
            } else if tok == "-k" || tok == "--insecure" {
                insecure = true
            } else if tok == "--url" {
                url = nextVal() ?? url
            } else if tok == "-I" || tok == "--head" {
                methodExplicit = "HEAD"
            } else if !tok.hasPrefix("-") && url.isEmpty {
                url = tok
            } else if tok.hasPrefix("http://") || tok.hasPrefix("https://") {
                url = tok
            }
            idx += 1
        }

        if useJsonDefaults {
            if !headers.contains(where: { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                headers.append(("Content-Type", "application/json"))
            }
            if !headers.contains(where: { $0.0.caseInsensitiveCompare("Accept") == .orderedSame }) {
                headers.append(("Accept", "application/json"))
            }
        }

        if let basicAuth, !headers.contains(where: { $0.0.caseInsensitiveCompare("Authorization") == .orderedSame }) {
            let b64 = Data(basicAuth.utf8).base64EncodedString()
            headers.append(("Authorization", "Basic \(b64)"))
        }

        guard !url.isEmpty else {
            throw CodecError.message("未在 curl 命令中找到目标 URL")
        }

        let body: String? = dataParts.isEmpty ? nil : dataParts.joined(separator: "&")
        var method = methodExplicit ?? ((body != nil || !formFields.isEmpty) ? "POST" : "GET")
        var finalUrl = url

        if forceGet, let body, !body.isEmpty {
            method = "GET"
            let sep = finalUrl.contains("?") ? "&" : "?"
            finalUrl += "\(sep)\(body)"
        }

        return ParsedCurlRequest(
            method: method,
            url: finalUrl,
            headers: headers,
            body: forceGet ? nil : body,
            basicAuth: basicAuth,
            formFields: formFields,
            followRedirects: followRedirects,
            insecure: insecure
        )
    }

    static func tokenizeShell(_ raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\\\r\n", with: " ")
            .replacingOccurrences(of: "\\\n", with: " ")
        let chars = Array(normalized)
        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == "'" {
                hasToken = true
                i += 1
                while i < chars.count && chars[i] != "'" {
                    current.append(chars[i])
                    i += 1
                }
                i += 1
            } else if ch == "\"" {
                hasToken = true
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        let next = chars[i + 1]
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            current.append(next)
                            i += 2
                            continue
                        }
                    }
                    current.append(chars[i])
                    i += 1
                }
                i += 1
            } else if ch == "\\" && i + 1 < chars.count {
                hasToken = true
                current.append(chars[i + 1])
                i += 2
            } else if ch.isWhitespace {
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
                i += 1
            } else {
                hasToken = true
                current.append(ch)
                i += 1
            }
        }
        if hasToken {
            tokens.append(current)
        }
        return tokens
    }

    static func generateCode(_ req: ParsedCurlRequest, target: String) -> String {
        switch target {
        case "fetch":
            return toFetch(req)
        case "python":
            return toPythonRequests(req)
        case "httpie":
            return toHttpie(req)
        case "go":
            return toGoHttp(req)
        case "swift":
            return toSwiftUrlSession(req)
        default:
            return toFetch(req)
        }
    }

    private static func jsQuoted(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]),
           let str = String(data: d, encoding: .utf8) {
            return String(str.dropFirst().dropLast())
        }
        return "\"\(s)\""
    }

    static func toFetch(_ req: ParsedCurlRequest) -> String {
        var opts: [String] = []
        opts.append("  method: \(jsQuoted(req.method)),")
        if !req.headers.isEmpty {
            let hLines = req.headers.map { "    \(jsQuoted($0.key)): \(jsQuoted($0.value))," }.joined(separator: "\n")
            opts.append("  headers: {\n\(hLines)\n  },")
        }
        if let body = req.body {
            if let data = body.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil,
               body.trimmingCharacters(in: .whitespaces).hasPrefix("{") || body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                opts.append("  body: JSON.stringify(\(body)),")
            } else {
                opts.append("  body: \(jsQuoted(body)),")
            }
        }
        return """
        const response = await fetch(\(jsQuoted(req.url)), {
        \(opts.joined(separator: "\n"))
        });
        const data = await response.json();
        """
    }

    static func toPythonRequests(_ req: ParsedCurlRequest) -> String {
        var lines = ["import requests", ""]
        lines.append("url = \(jsQuoted(req.url))")
        if !req.headers.isEmpty {
            lines.append("headers = {")
            for h in req.headers {
                lines.append("    \(jsQuoted(h.key)): \(jsQuoted(h.value)),")
            }
            lines.append("}")
        }
        var callArgs = ["\(jsQuoted(req.method))", "url"]
        if !req.headers.isEmpty { callArgs.append("headers=headers") }
        if let body = req.body {
            let isJsonHeader = req.headers.contains {
                $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame && $0.value.lowercased().contains("json")
            }
            if isJsonHeader,
               let data = body.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                _ = obj
                lines.append("payload = \(body)")
                callArgs.append("json=payload")
            } else {
                lines.append("data = \(jsQuoted(body))")
                callArgs.append("data=data")
            }
        }
        if req.insecure { callArgs.append("verify=False") }
        lines.append("resp = requests.request(\(callArgs.joined(separator: ", ")))")
        lines.append("print(resp.status_code, resp.text)")
        return lines.joined(separator: "\n")
    }

    static func toHttpie(_ req: ParsedCurlRequest) -> String {
        var parts = ["http"]
        if req.insecure { parts.append("--verify=no") }
        if req.followRedirects { parts.append("--follow") }
        parts.append(req.method)
        parts.append("'\(req.url)'")
        for h in req.headers {
            parts.append("'\(h.key):\(h.value)'")
        }
        if let body = req.body {
            parts.append("--raw '\(body.replacingOccurrences(of: "'", with: "'\\''"))'")
        }
        return parts.joined(separator: " \\\n  ")
    }

    static func toGoHttp(_ req: ParsedCurlRequest) -> String {
        let bodyExpr = req.body != nil ? "strings.NewReader(\(jsQuoted(req.body!)))" : "nil"
        var lines = [
            "package main",
            "",
            "import (",
            "    \"fmt\"",
            "    \"io\"",
            "    \"net/http\"",
        ]
        if req.body != nil { lines.append("    \"strings\"") }
        lines.append(")")
        lines.append("")
        lines.append("func main() {")
        lines.append("    req, err := http.NewRequest(\(jsQuoted(req.method)), \(jsQuoted(req.url)), \(bodyExpr))")
        lines.append("    if err != nil { panic(err) }")
        for h in req.headers {
            lines.append("    req.Header.Set(\(jsQuoted(h.key)), \(jsQuoted(h.value)))")
        }
        lines.append("    resp, err := http.DefaultClient.Do(req)")
        lines.append("    if err != nil { panic(err) }")
        lines.append("    defer resp.Body.Close()")
        lines.append("    body, _ := io.ReadAll(resp.Body)")
        lines.append("    fmt.Println(resp.StatusCode, string(body))")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func toSwiftUrlSession(_ req: ParsedCurlRequest) -> String {
        var lines = [
            "import Foundation",
            "",
            "var request = URLRequest(url: URL(string: \(jsQuoted(req.url)))!)",
            "request.httpMethod = \(jsQuoted(req.method))",
        ]
        for h in req.headers {
            lines.append("request.setValue(\(jsQuoted(h.value)), forHTTPHeaderField: \(jsQuoted(h.key)))")
        }
        if let body = req.body {
            lines.append("request.httpBody = Data(\(jsQuoted(body)).utf8)")
        }
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        lines.append("print((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))")
        return lines.joined(separator: "\n")
    }
}
