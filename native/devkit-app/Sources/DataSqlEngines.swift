import Foundation

// MARK: - 1. Multi-Format Data Converter (JSON / YAML / TOML / .env / CSV / Markdown Table)

enum DataFormatKind: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON"
    case yaml = "YAML"
    case toml = "TOML"
    case env = ".env"
    case csv = "CSV"
    case markdownTable = "Markdown 表格"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .yaml: return "yaml"
        case .toml: return "toml"
        case .env: return "env"
        case .csv: return "csv"
        case .markdownTable: return "md"
        }
    }
}

enum DataValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([DataValue])
    case object([(String, DataValue)])

    static func == (lhs: DataValue, rhs: DataValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    var scalarString: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d):
            if d.isFinite && abs(d - d.rounded()) < 1e-12 && abs(d) < 1e15 {
                return String(format: "%.1f", d)
            }
            return String(d)
        case .string(let s): return s
        case .array(let arr):
            return DataFormatEngine.serialize(.array(arr), as: .json, pretty: false)
        case .object(let obj):
            return DataFormatEngine.serialize(.object(obj), as: .json, pretty: false)
        }
    }
}

enum DataFormatError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

enum DataFormatEngine {
    static let sampleJson = """
    {
      "service": "tinycast-devkit",
      "version": 2,
      "enabled": true,
      "server": {
        "host": "127.0.0.1",
        "port": 8080
      },
      "tags": ["swiftui", "appkit", "macos"]
    }
    """

    static let sampleCsv = """
    name,role,port,active
    auth-api,gateway,8081,true
    worker-ocr,vision,8082,true
    legacy-sync,cron,9000,false
    """

    static let sampleEnv = """
    APP_NAME=tinycast-api
    APP_ENV=production
    PORT=8443
    DEBUG=false
    JWT_ISSUER="https://auth.tinycast.dev"
    """

    static func detectFormat(_ raw: String) -> DataFormatKind {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .json }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }

        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if lines.count >= 2, lines[0].contains("|"), lines[1].contains("|"),
           lines[1].range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?$"#, options: .regularExpression) != nil {
            return .markdownTable
        }

        let nonCommentLines = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("//") }
        if !nonCommentLines.isEmpty {
            let envLike = nonCommentLines.allSatisfy {
                $0.range(of: #"^(export\s+)?[A-Za-z_][A-Za-z0-9_.]*\s*="#, options: .regularExpression) != nil
            }
            if envLike {
                let allUpperUnderscore = nonCommentLines.allSatisfy {
                    $0.range(of: #"^(export\s+)?[A-Z0-9_]+\s*="#, options: .regularExpression) != nil
                }
                if allUpperUnderscore { return .env }
            }

            if nonCommentLines.contains(where: { $0.hasPrefix("[[") && $0.hasSuffix("]]") })
                || nonCommentLines.contains(where: { $0.hasPrefix("[") && $0.hasSuffix("]") && !$0.contains(",") })
                || nonCommentLines.contains(where: { $0.range(of: #"^[A-Za-z0-9_.-]+\s*=\s*"#, options: .regularExpression) != nil }) {
                return .toml
            }

            if let first = nonCommentLines.first,
               (first.contains(",") || first.contains("\t")),
               nonCommentLines.count >= 2,
               !first.contains(":") {
                return .csv
            }
        }

        return .yaml
    }

    static func convert(_ raw: String, from source: DataFormatKind?, to target: DataFormatKind) throws -> (detected: DataFormatKind, output: String) {
        let actualSource = source ?? detectFormat(raw)
        let value = try parse(raw, as: actualSource)
        let output = serialize(value, as: target, pretty: true)
        return (actualSource, output)
    }

    static func parse(_ raw: String, as format: DataFormatKind) throws -> DataValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DataFormatError.message("输入内容为空") }

        switch format {
        case .json:
            return try parseOrderedJson(trimmed)
        case .yaml:
            return try parseYaml(trimmed)
        case .toml:
            return try parseToml(trimmed)
        case .env:
            return parseEnv(trimmed)
        case .csv:
            return parseCsv(trimmed)
        case .markdownTable:
            return try parseMarkdownTable(trimmed)
        }
    }

    // MARK: Ordered JSON Parser

    private static func parseOrderedJson(_ raw: String) throws -> DataValue {
        var directParser = OrderedJsonParser(raw)
        if let direct = try? directParser.parseValue() {
            return direct
        }
        var repairedParser = OrderedJsonParser(JsonEngine.repairRelaxed(raw))
        return try repairedParser.parseValue()
    }

    private struct OrderedJsonParser {
        let scalars: [UnicodeScalar]
        var index: Int = 0

        init(_ raw: String) {
            self.scalars = Array(raw.unicodeScalars)
        }

        mutating func skipWS() {
            while index < scalars.count && CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                index += 1
            }
        }

        mutating func parseValue() throws -> DataValue {
            skipWS()
            guard index < scalars.count else { throw DataFormatError.message("JSON 意外结束") }
            let ch = scalars[index]
            switch ch {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t", "f": return try parseBool()
            case "n": return try parseNull()
            case "-", "0"..."9": return try parseNumber()
            default:
                throw DataFormatError.message("JSON 非法字符: \(Character(ch))")
            }
        }

        mutating func parseObject() throws -> DataValue {
            index += 1 // '{'
            skipWS()
            var entries: [(String, DataValue)] = []
            if index < scalars.count && scalars[index] == "}" {
                index += 1
                return .object(entries)
            }
            while true {
                skipWS()
                guard index < scalars.count && scalars[index] == "\"" else {
                    throw DataFormatError.message("JSON 对象缺少键名")
                }
                let key = try parseString()
                skipWS()
                guard index < scalars.count && scalars[index] == ":" else {
                    throw DataFormatError.message("JSON 键值对缺少冒号 ':'")
                }
                index += 1
                let val = try parseValue()
                if let existingIdx = entries.firstIndex(where: { $0.0 == key }) {
                    entries[existingIdx] = (key, val)
                } else {
                    entries.append((key, val))
                }
                skipWS()
                guard index < scalars.count else { throw DataFormatError.message("JSON 对象未闭合") }
                if scalars[index] == "}" {
                    index += 1
                    return .object(entries)
                }
                guard scalars[index] == "," else {
                    throw DataFormatError.message("JSON 对象缺少逗号或右花括号")
                }
                index += 1
            }
        }

        mutating func parseArray() throws -> DataValue {
            index += 1 // '['
            skipWS()
            var items: [DataValue] = []
            if index < scalars.count && scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try parseValue())
                skipWS()
                guard index < scalars.count else { throw DataFormatError.message("JSON 数组未闭合") }
                if scalars[index] == "]" {
                    index += 1
                    return .array(items)
                }
                guard scalars[index] == "," else {
                    throw DataFormatError.message("JSON 数组缺少逗号或右中括号")
                }
                index += 1
            }
        }

        mutating func parseString() throws -> String {
            let start = index
            index += 1 // opening quote
            while index < scalars.count {
                let s = scalars[index]
                if s == "\\" {
                    index += 2
                    continue
                }
                if s == "\"" {
                    index += 1
                    let slice = String(String.UnicodeScalarView(scalars[start..<index]))
                    if let d = "[\(slice)]".data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: d) as? [String],
                       let str = arr.first {
                        return str
                    }
                    return String(slice.dropFirst().dropLast())
                }
                index += 1
            }
            throw DataFormatError.message("JSON 字符串未闭合")
        }

        mutating func parseBool() throws -> DataValue {
            let rem = String(String.UnicodeScalarView(scalars[index..<min(scalars.count, index + 5)]))
            if rem.hasPrefix("true") {
                index += 4
                return .bool(true)
            }
            if rem.hasPrefix("false") {
                index += 5
                return .bool(false)
            }
            throw DataFormatError.message("JSON 布尔值错误")
        }

        mutating func parseNull() throws -> DataValue {
            let rem = String(String.UnicodeScalarView(scalars[index..<min(scalars.count, index + 4)]))
            if rem == "null" {
                index += 4
                return .null
            }
            throw DataFormatError.message("JSON null 值错误")
        }

        mutating func parseNumber() throws -> DataValue {
            let start = index
            let allowed = CharacterSet(charactersIn: "0123456789+-.eE")
            while index < scalars.count && allowed.contains(scalars[index]) {
                index += 1
            }
            let numStr = String(String.UnicodeScalarView(scalars[start..<index]))
            if !numStr.contains(".") && !numStr.contains("e") && !numStr.contains("E"),
               let i = Int64(numStr) {
                return .int(i)
            }
            if let d = Double(numStr) {
                return .double(d)
            }
            throw DataFormatError.message("JSON 非法数字: \(numStr)")
        }
    }

    // MARK: YAML Parser (Indentation + Flow Collections + Scalars)

    private struct YamlLine {
        let indent: Int
        let content: String
    }

    private static func parseYaml(_ raw: String) throws -> DataValue {
        let rawLines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var lines: [YamlLine] = []
        for l in rawLines {
            let stripped = stripCommentOutsideQuotes(l, commentChar: "#")
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "---" || trimmed == "..." { continue }
            let indent = l.prefix(while: { $0 == " " }).count
            lines.append(YamlLine(indent: indent, content: trimmed))
        }
        guard !lines.isEmpty else { return .null }

        var idx = 0
        func parseBlock(minIndent: Int) throws -> DataValue {
            guard idx < lines.count else { return .null }
            let cur = lines[idx]
            if cur.content == "-" || cur.content.hasPrefix("- ") {
                return try parseSeq(baseIndent: cur.indent)
            }
            if splitYamlKeyValue(cur.content) != nil {
                return try parseMap(baseIndent: cur.indent)
            }
            idx += 1
            return parseScalarOrFlow(cur.content)
        }

        func parseSeq(baseIndent: Int) throws -> DataValue {
            var arr: [DataValue] = []
            while idx < lines.count {
                let line = lines[idx]
                if line.indent < baseIndent { break }
                guard line.indent == baseIndent, (line.content == "-" || line.content.hasPrefix("- ")) else { break }
                let afterDash = line.content == "-" ? "" : String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                idx += 1
                if afterDash.isEmpty {
                    if idx < lines.count && lines[idx].indent > baseIndent {
                        arr.append(try parseBlock(minIndent: lines[idx].indent))
                    } else {
                        arr.append(.null)
                    }
                } else if let kv = splitYamlKeyValue(afterDash) {
                    var entries: [(String, DataValue)] = []
                    if kv.val.isEmpty {
                        if idx < lines.count && lines[idx].indent > baseIndent + 1 {
                            entries.append((kv.key, try parseBlock(minIndent: lines[idx].indent)))
                        } else {
                            entries.append((kv.key, .null))
                        }
                    } else {
                        entries.append((kv.key, parseScalarOrFlow(kv.val)))
                    }
                    // Consume sibling map keys indented deeper than `- `
                    if idx < lines.count && lines[idx].indent > baseIndent {
                        let subIndent = lines[idx].indent
                        if splitYamlKeyValue(lines[idx].content) != nil,
                           case .object(let extra) = try parseMap(baseIndent: subIndent) {
                            entries.append(contentsOf: extra)
                        }
                    }
                    arr.append(.object(entries))
                } else {
                    arr.append(parseScalarOrFlow(afterDash))
                }
            }
            return .array(arr)
        }

        func parseMap(baseIndent: Int) throws -> DataValue {
            var entries: [(String, DataValue)] = []
            while idx < lines.count {
                let line = lines[idx]
                if line.indent < baseIndent { break }
                if line.indent > baseIndent { break }
                guard let kv = splitYamlKeyValue(line.content) else { break }
                idx += 1
                if kv.val.isEmpty {
                    if idx < lines.count && lines[idx].indent > baseIndent {
                        entries.append((kv.key, try parseBlock(minIndent: lines[idx].indent)))
                    } else if idx < lines.count && lines[idx].indent == baseIndent && (lines[idx].content == "-" || lines[idx].content.hasPrefix("- ")) {
                        entries.append((kv.key, try parseSeq(baseIndent: baseIndent)))
                    } else {
                        entries.append((kv.key, .null))
                    }
                } else {
                    entries.append((kv.key, parseScalarOrFlow(kv.val)))
                }
            }
            return .object(entries)
        }

        return try parseBlock(minIndent: lines[0].indent)
    }

    private static func splitYamlKeyValue(_ s: String) -> (key: String, val: String)? {
        var inSingle = false
        var inDouble = false
        let chars = Array(s)
        for i in 0..<chars.count {
            let ch = chars[i]
            if ch == "\\" && inDouble { continue }
            if ch == "'" && !inDouble { inSingle.toggle() }
            else if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == ":" && !inSingle && !inDouble {
                let isEnd = (i + 1 == chars.count) || chars[i + 1] == " " || chars[i + 1] == "\t"
                if isEnd && i > 0 {
                    let rawKey = String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
                    let key = unquoteString(rawKey)
                    let val = i + 1 < chars.count ? String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces) : ""
                    return (key, val)
                }
            }
        }
        return nil
    }

    private static func parseScalarOrFlow(_ raw: String) -> DataValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if (s.hasPrefix("[") && s.hasSuffix("]")) || (s.hasPrefix("{") && s.hasSuffix("}")) {
            if let v = try? parseOrderedJson(s) {
                return v
            }
        }
        return parseScalar(s)
    }

    private static func parseScalar(_ s: String) -> DataValue {
        if s == "null" || s == "~" || s == "Null" || s == "NULL" { return .null }
        if s == "true" || s == "True" || s == "TRUE" { return .bool(true) }
        if s == "false" || s == "False" || s == "FALSE" { return .bool(false) }
        if (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) ||
           (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) {
            return .string(unquoteString(s))
        }
        let noUnderscore = s.replacingOccurrences(of: "_", with: "")
        if let i = Int64(noUnderscore), !s.hasPrefix("0") || s == "0" || s.hasPrefix("-") {
            return .int(i)
        }
        if s.range(of: #"^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
           let d = Double(noUnderscore) {
            return .double(d)
        }
        return .string(s)
    }

    private static func unquoteString(_ s: String) -> String {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            let inner = String(s.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    // MARK: TOML Parser

    private static func parseToml(_ raw: String) throws -> DataValue {
        var root: [(String, DataValue)] = []
        var currentPath: [String] = []
        var currentIsArrayTable = false

        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for rawLine in lines {
            let clean = stripCommentOutsideQuotes(rawLine, commentChar: "#").trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { continue }

            if clean.hasPrefix("[[") && clean.hasSuffix("]]") {
                let inner = String(clean.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                currentPath = splitDottedKey(inner)
                currentIsArrayTable = true
                appendEmptyTableInArray(at: currentPath, into: &root)
                continue
            }

            if clean.hasPrefix("[") && clean.hasSuffix("]") {
                let inner = String(clean.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentPath = splitDottedKey(inner)
                currentIsArrayTable = false
                ensureObjectPath(currentPath, in: &root)
                continue
            }

            if let eq = firstUnquotedCharIndex(clean, target: "=") {
                let lhs = String(clean[..<eq]).trimmingCharacters(in: .whitespaces)
                let rhs = String(clean[clean.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                let keyParts = currentPath + splitDottedKey(lhs)
                let val = parseTomlValue(rhs)
                if currentIsArrayTable && !currentPath.isEmpty {
                    let subParts = splitDottedKey(lhs)
                    setValueInLastArrayTable(arrayPath: currentPath, keyPath: subParts, value: val, in: &root)
                } else {
                    setNestedValue(path: keyParts, value: val, in: &root)
                }
            }
        }
        return .object(root)
    }

    private static func splitDottedKey(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inSingle = false
        var inDouble = false
        for ch in s {
            if ch == "'" && !inDouble { inSingle.toggle(); cur.append(ch) }
            else if ch == "\"" && !inSingle { inDouble.toggle(); cur.append(ch) }
            else if ch == "." && !inSingle && !inDouble {
                let t = unquoteString(cur.trimmingCharacters(in: .whitespaces))
                if !t.isEmpty { parts.append(t) }
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        let t = unquoteString(cur.trimmingCharacters(in: .whitespaces))
        if !t.isEmpty { parts.append(t) }
        return parts
    }

    private static func parseTomlValue(_ raw: String) -> DataValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .array([]) }
            return .array(splitTopLevelArgs(inner).map { parseTomlValue($0) })
        }
        if s.hasPrefix("{") && s.hasSuffix("}") {
            let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .object([]) }
            var obj: [(String, DataValue)] = []
            for part in splitTopLevelArgs(inner) {
                if let eq = firstUnquotedCharIndex(part, target: "=") {
                    let k = unquoteString(String(part[..<eq]).trimmingCharacters(in: .whitespaces))
                    let v = parseTomlValue(String(part[part.index(after: eq)...]))
                    obj.append((k, v))
                }
            }
            return .object(obj)
        }
        return parseScalar(s)
    }

    private static func splitTopLevelArgs(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var depthBracket = 0
        var depthBrace = 0
        var inSingle = false
        var inDouble = false
        var prevBackslash = false
        for ch in s {
            if ch == "\\" && inDouble && !prevBackslash {
                cur.append(ch)
                prevBackslash = true
                continue
            }
            if !prevBackslash {
                if ch == "'" && !inDouble { inSingle.toggle() }
                else if ch == "\"" && !inSingle { inDouble.toggle() }
                else if !inSingle && !inDouble {
                    if ch == "[" { depthBracket += 1 }
                    else if ch == "]" { depthBracket = max(0, depthBracket - 1) }
                    else if ch == "{" { depthBrace += 1 }
                    else if ch == "}" { depthBrace = max(0, depthBrace - 1) }
                    else if ch == "," && depthBracket == 0 && depthBrace == 0 {
                        let t = cur.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { out.append(t) }
                        cur = ""
                        prevBackslash = false
                        continue
                    }
                }
            }
            cur.append(ch)
            prevBackslash = false
        }
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        return out
    }

    private static func setNestedValue(path: [String], value: DataValue, in dict: inout [(String, DataValue)]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            if let idx = dict.firstIndex(where: { $0.0 == head }) { dict[idx] = (head, value) }
            else { dict.append((head, value)) }
            return
        }
        var child: [(String, DataValue)] = []
        if let idx = dict.firstIndex(where: { $0.0 == head }), case .object(let existing) = dict[idx].1 {
            child = existing
            setNestedValue(path: Array(path.dropFirst()), value: value, in: &child)
            dict[idx] = (head, .object(child))
        } else {
            setNestedValue(path: Array(path.dropFirst()), value: value, in: &child)
            dict.append((head, .object(child)))
        }
    }

    private static func ensureObjectPath(_ path: [String], in dict: inout [(String, DataValue)]) {
        guard let head = path.first else { return }
        if let idx = dict.firstIndex(where: { $0.0 == head }) {
            if case .object(var child) = dict[idx].1 {
                ensureObjectPath(Array(path.dropFirst()), in: &child)
                dict[idx] = (head, .object(child))
            }
        } else {
            var child: [(String, DataValue)] = []
            ensureObjectPath(Array(path.dropFirst()), in: &child)
            dict.append((head, .object(child)))
        }
    }

    private static func appendEmptyTableInArray(at path: [String], into dict: inout [(String, DataValue)]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            if let idx = dict.firstIndex(where: { $0.0 == head }), case .array(var arr) = dict[idx].1 {
                arr.append(.object([]))
                dict[idx] = (head, .array(arr))
            } else {
                dict.append((head, .array([.object([])])))
            }
            return
        }
        if let idx = dict.firstIndex(where: { $0.0 == head }), case .object(var child) = dict[idx].1 {
            appendEmptyTableInArray(at: Array(path.dropFirst()), into: &child)
            dict[idx] = (head, .object(child))
        } else {
            var child: [(String, DataValue)] = []
            appendEmptyTableInArray(at: Array(path.dropFirst()), into: &child)
            dict.append((head, .object(child)))
        }
    }

    private static func setValueInLastArrayTable(arrayPath: [String], keyPath: [String], value: DataValue, in dict: inout [(String, DataValue)]) {
        guard let head = arrayPath.first else { return }
        guard let idx = dict.firstIndex(where: { $0.0 == head }) else { return }
        if arrayPath.count == 1 {
            if case .array(var arr) = dict[idx].1, var last = arr.last, case .object(var obj) = last {
                setNestedValue(path: keyPath, value: value, in: &obj)
                last = .object(obj)
                arr[arr.count - 1] = last
                dict[idx] = (head, .array(arr))
            }
        } else if case .object(var child) = dict[idx].1 {
            setValueInLastArrayTable(arrayPath: Array(arrayPath.dropFirst()), keyPath: keyPath, value: value, in: &child)
            dict[idx] = (head, .object(child))
        }
    }

    // MARK: .env Parser

    private static func parseEnv(_ raw: String) -> DataValue {
        var entries: [(String, DataValue)] = []
        for rawLine in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var valRaw = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !(valRaw.hasPrefix("\"") || valRaw.hasPrefix("'")) {
                valRaw = stripCommentOutsideQuotes(valRaw, commentChar: "#").trimmingCharacters(in: .whitespaces)
                entries.append((key, parseScalar(valRaw)))
            } else {
                entries.append((key, .string(unquoteString(valRaw))))
            }
        }
        return .object(entries)
    }

    // MARK: CSV Parser

    private static func parseCsv(_ raw: String) -> DataValue {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return .array([]) }
        let delimiter: Character = headerLine.contains("\t") ? "\t" : (headerLine.contains(",") ? "," : ";")
        let headers = parseCsvRow(headerLine, delimiter: delimiter)
        guard lines.count > 1 else {
            return .array([.object(headers.map { ($0, .string("")) })])
        }
        var rows: [DataValue] = []
        for line in lines.dropFirst() {
            let cells = parseCsvRow(line, delimiter: delimiter)
            var rowObj: [(String, DataValue)] = []
            for (idx, h) in headers.enumerated() {
                let rawCell = idx < cells.count ? cells[idx] : ""
                rowObj.append((h, coerceTableCell(rawCell)))
            }
            rows.append(.object(rowObj))
        }
        return .array(rows)
    }

    private static func parseCsvRow(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var cur = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    cur.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
            } else if ch == delimiter && !inQuotes {
                cells.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
            i += 1
        }
        cells.append(cur)
        return cells
    }

    // MARK: Markdown Table Parser

    private static func parseMarkdownTable(_ raw: String) throws -> DataValue {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("|") }
        guard lines.count >= 2 else { throw DataFormatError.message("至少需要表头行和分隔行 (| --- |)") }

        func splitPipeRow(_ line: String) -> [String] {
            var s = line
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let headers = splitPipeRow(lines[0])
        let dataLines = lines.dropFirst().filter {
            $0.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?$"#, options: .regularExpression) == nil
        }
        var rows: [DataValue] = []
        for line in dataLines {
            let cells = splitPipeRow(line)
            var rowObj: [(String, DataValue)] = []
            for (idx, h) in headers.enumerated() {
                let rawCell = idx < cells.count ? cells[idx] : ""
                rowObj.append((h, coerceTableCell(rawCell)))
            }
            rows.append(.object(rowObj))
        }
        return .array(rows)
    }

    private static func coerceTableCell(_ s: String) -> DataValue {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .string("") }
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if t == "null" { return .null }
        if let i = Int64(t), (!t.hasPrefix("0") || t == "0") { return .int(i) }
        if t.contains("."), let d = Double(t) { return .double(d) }
        return .string(t)
    }

    // MARK: Serializers

    static func serialize(_ value: DataValue, as format: DataFormatKind, pretty: Bool = true) -> String {
        switch format {
        case .json: return serializeJson(value, indent: pretty ? 2 : 0, level: 0)
        case .yaml: return serializeYaml(value, indent: 0)
        case .toml: return serializeToml(value)
        case .env: return serializeEnv(value)
        case .csv: return serializeTable(value, markdown: false)
        case .markdownTable: return serializeTable(value, markdown: true)
        }
    }

    private static func jsonString(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]),
           let str = String(data: d, encoding: .utf8) {
            return String(str.dropFirst().dropLast())
        }
        return "\"\(s)\""
    }

    private static func serializeJson(_ v: DataValue, indent: Int, level: Int) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double: return v.scalarString
        case .string(let s): return jsonString(s)
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            if indent == 0 {
                return "[" + arr.map { serializeJson($0, indent: 0, level: 0) }.joined(separator: ",") + "]"
            }
            let pad = String(repeating: " ", count: indent * (level + 1))
            let closePad = String(repeating: " ", count: indent * level)
            let body = arr.map { "\(pad)\(serializeJson($0, indent: indent, level: level + 1))" }.joined(separator: ",\n")
            return "[\n\(body)\n\(closePad)]"
        case .object(let entries):
            if entries.isEmpty { return "{}" }
            if indent == 0 {
                return "{" + entries.map { "\(jsonString($0.0)):\(serializeJson($0.1, indent: 0, level: 0))" }.joined(separator: ",") + "}"
            }
            let pad = String(repeating: " ", count: indent * (level + 1))
            let closePad = String(repeating: " ", count: indent * level)
            let body = entries.map { "\(pad)\(jsonString($0.0)): \(serializeJson($0.1, indent: indent, level: level + 1))" }.joined(separator: ",\n")
            return "{\n\(body)\n\(closePad)}"
        }
    }

    private static func serializeYaml(_ v: DataValue, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double: return v.scalarString
        case .string(let s):
            let needsQuote = s.isEmpty || ["true", "false", "null", "~"].contains(s.lowercased())
                || Int64(s) != nil || Double(s) != nil
                || s.range(of: #"[:#\n\r\t{}\[\],&*!|>'"%@`]|^\s|\s$"#, options: .regularExpression) != nil
            return needsQuote ? jsonString(s) : s
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            return arr.map { item in
                switch item {
                case .object(let entries) where !entries.isEmpty:
                    let sub = serializeYaml(.object(entries), indent: indent + 1)
                    let trimmed = sub.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
                    return "\(pad)- \(trimmed)"
                case .array(let inner) where !inner.isEmpty:
                    let sub = serializeYaml(.array(inner), indent: indent + 1)
                    let trimmed = sub.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
                    return "\(pad)- \(trimmed)"
                default:
                    return "\(pad)- \(serializeYaml(item, indent: indent + 1))"
                }
            }.joined(separator: "\n")
        case .object(let entries):
            if entries.isEmpty { return "{}" }
            return entries.map { k, val in
                let safeKey = k.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil ? k : jsonString(k)
                let isComplex: Bool = {
                    if case .object(let sub) = val { return !sub.isEmpty }
                    if case .array(let arr) = val { return !arr.isEmpty }
                    return false
                }()
                if isComplex {
                    return "\(pad)\(safeKey):\n\(serializeYaml(val, indent: indent + 1))"
                }
                return "\(pad)\(safeKey): \(serializeYaml(val, indent: indent + 1))"
            }.joined(separator: "\n")
        }
    }

    private static func serializeToml(_ v: DataValue) -> String {
        func tomlKey(_ k: String) -> String {
            k.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil ? k : jsonString(k)
        }
        func tomlScalar(_ val: DataValue) -> String {
            switch val {
            case .null: return "\"\""
            case .bool(let b): return b ? "true" : "false"
            case .int(let i): return String(i)
            case .double: return val.scalarString
            case .string(let s): return jsonString(s)
            case .array(let arr): return "[\(arr.map { tomlScalar($0) }.joined(separator: ", "))]"
            case .object(let entries):
                return "{ \(entries.map { "\(tomlKey($0.0)) = \(tomlScalar($0.1))" }.joined(separator: ", ")) }"
            }
        }
        func writeTable(_ entries: [(String, DataValue)], path: [String], out: inout [String]) {
            var scalars: [(String, DataValue)] = []
            var subTables: [(String, [(String, DataValue)])] = []
            var arrayTables: [(String, [[(String, DataValue)]])] = []
            for (k, val) in entries {
                switch val {
                case .object(let sub): subTables.append((k, sub))
                case .array(let arr) where !arr.isEmpty && arr.allSatisfy({ if case .object = $0 { return true }; return false }):
                    let objs = arr.compactMap { item -> [(String, DataValue)]? in
                        if case .object(let o) = item { return o }
                        return nil
                    }
                    arrayTables.append((k, objs))
                default:
                    scalars.append((k, val))
                }
            }
            for (k, val) in scalars {
                out.append("\(tomlKey(k)) = \(tomlScalar(val))")
            }
            for (k, sub) in subTables {
                let p = path + [tomlKey(k)]
                if !out.isEmpty { out.append("") }
                out.append("[\(p.joined(separator: "."))]")
                writeTable(sub, path: p, out: &out)
            }
            for (k, list) in arrayTables {
                let p = path + [tomlKey(k)]
                for item in list {
                    if !out.isEmpty { out.append("") }
                    out.append("[[\(p.joined(separator: "."))]]")
                    writeTable(item, path: p, out: &out)
                }
            }
        }

        var lines: [String] = []
        switch v {
        case .object(let entries):
            writeTable(entries, path: [], out: &lines)
        case .array(let arr):
            writeTable([("items", .array(arr))], path: [], out: &lines)
        default:
            lines.append("value = \(tomlScalar(v))")
        }
        return lines.joined(separator: "\n")
    }

    private static func serializeEnv(_ v: DataValue) -> String {
        var lines: [String] = []
        func normalizeEnvKey(_ k: String) -> String {
            k.replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .uppercased()
        }
        func formatEnvVal(_ s: String) -> String {
            if s.isEmpty || s.contains(" ") || s.contains("#") || s.contains("\n") || s.contains("\"") {
                return jsonString(s)
            }
            return s
        }
        func flatten(_ node: DataValue, prefix: String) {
            switch node {
            case .object(let entries):
                for (k, val) in entries {
                    let keyPart = normalizeEnvKey(k)
                    let full = prefix.isEmpty ? keyPart : "\(prefix)_\(keyPart)"
                    flatten(val, prefix: full)
                }
            case .array(let arr):
                let allScalars = arr.allSatisfy {
                    switch $0 {
                    case .object, .array: return false
                    default: return true
                    }
                }
                if allScalars {
                    lines.append("\(prefix)=\(formatEnvVal(arr.map(\.scalarString).joined(separator: ",")))")
                } else {
                    for (idx, item) in arr.enumerated() {
                        flatten(item, prefix: "\(prefix)_\(idx)")
                    }
                }
            case .null:
                lines.append("\(prefix)=")
            default:
                lines.append("\(prefix)=\(formatEnvVal(node.scalarString))")
            }
        }
        flatten(v, prefix: "")
        return lines.joined(separator: "\n")
    }

    private static func serializeTable(_ v: DataValue, markdown: Bool) -> String {
        var headers: [String] = []
        var rows: [[String]] = []

        switch v {
        case .array(let arr):
            var seenKeys = Set<String>()
            var objectRows: [[(String, DataValue)]] = []
            for item in arr {
                if case .object(let entries) = item {
                    objectRows.append(entries)
                    for (k, _) in entries where seenKeys.insert(k).inserted {
                        headers.append(k)
                    }
                }
            }
            if !objectRows.isEmpty {
                rows = objectRows.map { entries in
                    let map = Dictionary(entries, uniquingKeysWith: { _, last in last })
                    return headers.map { map[$0]?.scalarString ?? "" }
                }
            } else {
                headers = ["index", "value"]
                rows = arr.enumerated().map { ["\($0.offset)", $0.element.scalarString] }
            }
        case .object(let entries):
            headers = ["key", "value"]
            rows = entries.map { [$0.0, $0.1.scalarString] }
        default:
            headers = ["value"]
            rows = [[v.scalarString]]
        }

        if markdown {
            func esc(_ s: String) -> String {
                s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
            }
            let hRow = "| " + headers.map(esc).joined(separator: " | ") + " |"
            let sepRow = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
            let dataRows = rows.map { "| " + $0.map(esc).joined(separator: " | ") + " |" }
            return ([hRow, sepRow] + dataRows).joined(separator: "\n")
        } else {
            func csvCell(_ s: String) -> String {
                if s.contains(",") || s.contains("\"") || s.contains("\n") {
                    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return s
            }
            let hRow = headers.map(csvCell).joined(separator: ",")
            let dataRows = rows.map { $0.map(csvCell).joined(separator: ",") }
            return ([hRow] + dataRows).joined(separator: "\n")
        }
    }

    private static func stripCommentOutsideQuotes(_ line: String, commentChar: Character) -> String {
        var inSingle = false
        var inDouble = false
        var prevBackslash = false
        var out = ""
        for ch in line {
            if !prevBackslash {
                if ch == "'" && !inDouble { inSingle.toggle() }
                else if ch == "\"" && !inSingle { inDouble.toggle() }
                else if ch == commentChar && !inSingle && !inDouble { break }
            }
            out.append(ch)
            prevBackslash = (ch == "\\" && inDouble)
        }
        return out
    }

    private static func firstUnquotedCharIndex(_ s: String, target: Character) -> String.Index? {
        var inSingle = false
        var inDouble = false
        for idx in s.indices {
            let ch = s[idx]
            if ch == "'" && !inDouble { inSingle.toggle() }
            else if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == target && !inSingle && !inDouble { return idx }
        }
        return nil
    }
}

// MARK: - 2. SQL Formatter & Parameter Binder Engine

enum SqlCaseStyle: String, CaseIterable, Sendable {
    case upper = "UPPER"
    case lower = "lower"
    case preserve = "保留原样"
}

struct SqlBindResult: Sendable {
    let extractedSql: String
    let params: [String]
    let renderedSql: String
    let formattedSql: String
    let detectedFormat: String
    let warning: String?
}

enum SqlEngine {
    static let sampleSql = """
    select u.id, u.email, count(o.id) as order_count, sum(o.total_cents) as spent from users u left join orders o on o.user_id = u.id and o.status = 'paid' where u.created_at >= '2026-01-01' and u.tier in ('pro', 'team') group by u.id, u.email having count(o.id) > 0 order by spent desc limit 20;
    """

    static let sampleMyBatisLog = """
    ==>  Preparing: SELECT id, username, status, created_at FROM users WHERE tenant_id = ? AND status IN (?, ?) AND created_at >= ? ORDER BY id DESC LIMIT ?
    ==> Parameters: 10042(Long), active(String), trial(String), 2026-11-01 00:00:00(Timestamp), 25(Integer)
    """

    private enum TokenKind {
        case word(String)
        case stringLiteral(String)
        case comment(String)
        case symbol(String)
    }

    private static let majorClauses: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET",
        "UNION", "INTERSECT", "EXCEPT", "INSERT", "VALUES", "UPDATE", "SET",
        "DELETE", "WITH", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS",
        "JOIN", "ON", "RETURNING",
    ]

    private static let sqlKeywords: Set<String> = [
        "SELECT", "DISTINCT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL",
        "AS", "ON", "USING", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER",
        "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "UNION", "ALL",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER",
        "DROP", "INDEX", "WITH", "RECURSIVE", "CASE", "WHEN", "THEN", "ELSE", "END",
        "EXISTS", "BETWEEN", "LIKE", "ILIKE", "RETURNING", "ON", "CONFLICT", "DO", "NOTHING",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "CAST", "TRUE", "FALSE",
    ]

    private static func tokenize(_ sql: String) -> [TokenKind] {
        var tokens: [TokenKind] = []
        let chars = Array(sql)
        let n = chars.count
        var i = 0
        while i < n {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }

            // Line comment --
            if ch == "-" && i + 1 < n && chars[i + 1] == "-" {
                let start = i
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
                tokens.append(.comment(String(chars[start..<i])))
                continue
            }
            // Block comment /* ... */
            if ch == "/" && i + 1 < n && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(n, i + 2)
                tokens.append(.comment(String(chars[start..<i])))
                continue
            }
            // Quoted string or identifier `'...'`, `"..."`, `` `...` ``
            if ch == "'" || ch == "\"" || ch == "`" {
                let quote = ch
                let start = i
                i += 1
                while i < n {
                    if chars[i] == "\\" && i + 1 < n { i += 2; continue }
                    if chars[i] == quote {
                        if quote == "'" && i + 1 < n && chars[i + 1] == "'" { i += 2; continue }
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(.stringLiteral(String(chars[start..<min(i, n)])))
                continue
            }
            // Multi-char operators
            if i + 1 < n {
                let two = String([ch, chars[i + 1]])
                if ["<>", "!=", "<=", ">=", "::", "||", "->>", "->"].contains(two) {
                    tokens.append(.symbol(two))
                    i += 2
                    continue
                }
            }
            if ch.isLetter || ch == "_" || ch == "$" || ch == ":" || ch == "#" {
                let start = i
                if ch == "#" && i + 1 < n && chars[i + 1] == "{" {
                    i += 2
                    while i < n && chars[i] != "}" { i += 1 }
                    if i < n { i += 1 }
                    tokens.append(.word(String(chars[start..<i])))
                    continue
                }
                i += 1
                while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$") {
                    i += 1
                }
                tokens.append(.word(String(chars[start..<i])))
                continue
            }
            if ch.isNumber {
                let start = i
                while i < n && (chars[i].isNumber || chars[i] == ".") { i += 1 }
                tokens.append(.word(String(chars[start..<i])))
                continue
            }
            tokens.append(.symbol(String(ch)))
            i += 1
        }
        return tokens
    }

    static func minify(_ sql: String) -> String {
        let tokens = tokenize(sql)
        var out = ""
        for tok in tokens {
            switch tok {
            case .comment:
                continue
            case .symbol(let s):
                if [",", ")", ";", "."].contains(s) {
                    out += s
                } else if s == "(" {
                    out += out.isEmpty || out.hasSuffix(" ") || out.hasSuffix("(") ? "(" : " ("
                } else {
                    if !out.isEmpty && !out.hasSuffix(" ") { out += " " }
                    out += s
                }
            case .word(let w):
                if !out.isEmpty && !out.hasSuffix(" ") && !out.hasSuffix("(") && !out.hasSuffix(".") {
                    out += " "
                }
                out += w
            case .stringLiteral(let lit):
                if !out.isEmpty && !out.hasSuffix(" ") && !out.hasSuffix("(") {
                    out += " "
                }
                out += lit
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func format(_ sql: String, keywordCase: SqlCaseStyle = .upper, indentSpaces: Int = 2) -> String {
        let tokens = tokenize(sql)
        guard !tokens.isEmpty else { return "" }

        let unit = String(repeating: " ", count: max(2, indentSpaces))
        var out = ""
        var parenDepth = 0
        var lastUpperWord = ""
        var prevWasSpaceOrNewline = true

        func applyCase(_ w: String) -> String {
            let up = w.uppercased()
            guard sqlKeywords.contains(up) else { return w }
            switch keywordCase {
            case .upper: return up
            case .lower: return w.lowercased()
            case .preserve: return w
            }
        }

        func appendNewline(_ extraIndent: Int = 0) {
            out = out.replacingOccurrences(of: #" +$"#, with: "", options: .regularExpression)
            if !out.isEmpty { out += "\n" }
            out += String(repeating: unit, count: max(0, parenDepth + extraIndent))
            prevWasSpaceOrNewline = true
        }

        var idx = 0
        while idx < tokens.count {
            let tok = tokens[idx]
            switch tok {
            case .comment(let c):
                if !prevWasSpaceOrNewline { out += " " }
                out += c
                appendNewline()
                idx += 1

            case .symbol(let s):
                if s == "(" {
                    if !prevWasSpaceOrNewline && !out.hasSuffix(".") { out += " " }
                    out += "("
                    parenDepth += 1
                    prevWasSpaceOrNewline = false
                } else if s == ")" {
                    parenDepth = max(0, parenDepth - 1)
                    out += ")"
                    prevWasSpaceOrNewline = false
                } else if s == "," {
                    out += ","
                    if parenDepth == 0 {
                        appendNewline(1)
                    } else {
                        out += " "
                        prevWasSpaceOrNewline = true
                    }
                } else if s == ";" {
                    out += ";"
                    if idx + 1 < tokens.count {
                        appendNewline()
                        out += "\n"
                    }
                    prevWasSpaceOrNewline = true
                } else if s == "." || s == "::" {
                    out += s
                    prevWasSpaceOrNewline = false
                } else {
                    if !prevWasSpaceOrNewline { out += " " }
                    out += s
                    out += " "
                    prevWasSpaceOrNewline = true
                }
                idx += 1

            case .stringLiteral(let lit):
                if !prevWasSpaceOrNewline && !out.hasSuffix("(") { out += " " }
                out += lit
                prevWasSpaceOrNewline = false
                idx += 1

            case .word(let rawWord):
                let up = rawWord.uppercased()
                let isJoinModifier = ["LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS"].contains(up)
                let skipBreakForCombined =
                    (up == "JOIN" && ["LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS"].contains(lastUpperWord))
                    || (up == "BY" && (lastUpperWord == "GROUP" || lastUpperWord == "ORDER"))
                    || (up == "ALL" && lastUpperWord == "UNION")
                    || (up == "INTO" && lastUpperWord == "INSERT")
                    || (up == "FROM" && lastUpperWord == "DELETE")

                if !out.isEmpty && !skipBreakForCombined {
                    if majorClauses.contains(up) && (parenDepth == 0 || up == "SELECT") {
                        appendNewline(0)
                    } else if (up == "AND" || up == "OR") && parenDepth == 0 {
                        appendNewline(1)
                    } else if isJoinModifier && parenDepth == 0 {
                        appendNewline(0)
                    } else if !prevWasSpaceOrNewline && !out.hasSuffix("(") && !out.hasSuffix(".") {
                        out += " "
                    }
                } else if !prevWasSpaceOrNewline && !out.hasSuffix("(") && !out.hasSuffix(".") {
                    out += " "
                }

                out += applyCase(rawWord)
                prevWasSpaceOrNewline = false
                lastUpperWord = up
                idx += 1
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func bindParameters(sqlOrLog: String, manualParams: String, formatOutput: Bool = true) -> SqlBindResult {
        var sql = sqlOrLog
        var parsedParams: [String] = []
        var detectedFormat = "手工参数绑定"

        // Try MyBatis log extraction first
        let lines = sqlOrLog.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if let prepLine = lines.first(where: { $0.contains("Preparing:") }) {
            if let range = prepLine.range(of: "Preparing:") {
                sql = String(prepLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            if let paramLine = lines.first(where: { $0.contains("Parameters:") }),
               let range = paramLine.range(of: "Parameters:") {
                let rawParamStr = String(paramLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                parsedParams = parseMyBatisParamLine(rawParamStr)
                detectedFormat = "MyBatis 日志自动提取"
            }
        }

        // Manual override or non-MyBatis params input
        let trimmedManual = manualParams.trimmingCharacters(in: .whitespacesAndNewlines)
        var namedMap: [String: String] = [:]
        if !trimmedManual.isEmpty {
            let (manualList, map, desc) = parseManualParams(trimmedManual)
            if !manualList.isEmpty { parsedParams = manualList }
            namedMap = map
            if detectedFormat == "手工参数绑定" { detectedFormat = desc }
        }

        // Substitute ?, $N, :name, #{name} safely outside quotes & comments
        let chars = Array(sql)
        var out = ""
        var pIndex = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // Preserve string literals
            if ch == "'" || ch == "\"" || ch == "`" {
                let q = ch
                out.append(ch)
                i += 1
                while i < chars.count {
                    out.append(chars[i])
                    if chars[i] == "\\" && i + 1 < chars.count {
                        out.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    if chars[i] == q {
                        if q == "'" && i + 1 < chars.count && chars[i + 1] == "'" {
                            out.append("'")
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }
            // Preserve comments
            if ch == "-" && i + 1 < chars.count && chars[i + 1] == "-" {
                while i < chars.count && chars[i] != "\n" { out.append(chars[i]); i += 1 }
                continue
            }
            if ch == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                out += "/*"
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") {
                    out.append(chars[i]); i += 1
                }
                if i + 1 < chars.count { out += "*/"; i += 2 }
                continue
            }

            if ch == "?" {
                if pIndex < parsedParams.count {
                    out += parsedParams[pIndex]
                    pIndex += 1
                } else {
                    out.append("?")
                }
                i += 1
                continue
            }

            if ch == "$" && i + 1 < chars.count && chars[i + 1].isNumber {
                var j = i + 1
                while j < chars.count && chars[j].isNumber { j += 1 }
                if let pos = Int(String(chars[(i + 1)..<j])), pos >= 1, pos <= parsedParams.count {
                    out += parsedParams[pos - 1]
                } else {
                    out += String(chars[i..<j])
                }
                i = j
                continue
            }

            if ch == "#" && i + 1 < chars.count && chars[i + 1] == "{" {
                var j = i + 2
                while j < chars.count && chars[j] != "}" { j += 1 }
                let key = String(chars[(i + 2)..<j]).components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
                if let lit = namedMap[key] {
                    out += lit
                } else if pIndex < parsedParams.count {
                    out += parsedParams[pIndex]
                    pIndex += 1
                } else {
                    out += String(chars[i...min(j, chars.count - 1)])
                }
                i = min(chars.count, j + 1)
                continue
            }

            if ch == ":" && (i == 0 || chars[i - 1] != ":") && i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1] == "_") {
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                let key = String(chars[(i + 1)..<j])
                if let lit = namedMap[key] {
                    out += lit
                } else {
                    out += ":\(key)"
                }
                i = j
                continue
            }

            out.append(ch)
            i += 1
        }

        let formatted = formatOutput ? format(out) : out
        return SqlBindResult(
            extractedSql: sql,
            params: parsedParams,
            renderedSql: out,
            formattedSql: formatted,
            detectedFormat: detectedFormat,
            warning: parsedParams.isEmpty ? "未检测到绑定参数，请填入参数或粘贴完整 MyBatis 日志" : nil
        )
    }

    private static func sqlLiteral(value: String, typeHint: String?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let hint = typeHint?.lowercased() ?? ""
        if trimmed == "null" || hint == "null" { return "NULL" }
        if ["integer", "int", "long", "short", "byte", "float", "double", "bigdecimal", "number", "numeric"].contains(hint) {
            return trimmed
        }
        if hint == "boolean" || hint == "bool" {
            return trimmed.lowercased() == "true" ? "TRUE" : "FALSE"
        }
        return "'" + trimmed.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func parseMyBatisParamLine(_ raw: String) -> [String] {
        // MyBatis format: `10042(Long), active(String), null, 2026-11-01 00:00:00(Timestamp)`
        var out: [String] = []
        let regex = try? NSRegularExpression(pattern: #"(?:^|,\s*)(?:(null)|(.*?)\(([A-Za-z0-9_.$]+)\))(?=,|$)"#)
        let ns = raw as NSString
        if let regex {
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                for m in matches {
                    if m.range(at: 1).location != NSNotFound {
                        out.append("NULL")
                    } else if m.range(at: 2).location != NSNotFound, m.range(at: 3).location != NSNotFound {
                        let val = ns.substring(with: m.range(at: 2))
                        let type = ns.substring(with: m.range(at: 3))
                        out.append(sqlLiteral(value: val, typeHint: type))
                    }
                }
                return out
            }
        }
        return raw.components(separatedBy: ",").map { item in
            let t = item.trimmingCharacters(in: .whitespaces)
            return sqlLiteral(value: t, typeHint: t == "null" ? "null" : (Int64(t) != nil ? "int" : "string"))
        }
    }

    private static func parseManualParams(_ raw: String) -> ([String], [String: String], String) {
        if raw.hasPrefix("["),
           let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let lits = arr.map { elem -> String in
                if elem is NSNull { return "NULL" }
                if let num = elem as? NSNumber {
                    if CFGetTypeID(num) == CFBooleanGetTypeID() { return num.boolValue ? "TRUE" : "FALSE" }
                    return "\(num)"
                }
                return "'" + "\(elem)".replacingOccurrences(of: "'", with: "''") + "'"
            }
            return (lits, [:], "JSON 数组参数")
        }

        // Key=Value pairs (`tenant_id=10042, status=active` or multi-line)
        let lines = raw.components(separatedBy: CharacterSet(charactersIn: "\n,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.allSatisfy({ $0.contains("=") }) {
            var map: [String: String] = [:]
            var list: [String] = []
            for line in lines {
                if let eq = line.firstIndex(of: "=") {
                    let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                    let v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    let lit = formatScalarToSqlLiteral(v)
                    map[k] = lit
                    list.append(lit)
                }
            }
            return (list, map, "命名参数 (key=value)")
        }

        let list = raw.components(separatedBy: ",").map { formatScalarToSqlLiteral($0.trimmingCharacters(in: .whitespaces)) }
        return (list, [:], "逗号分隔参数列表")
    }

    private static func formatScalarToSqlLiteral(_ token: String) -> String {
        if token.isEmpty || token.caseInsensitiveCompare("null") == .orderedSame { return "NULL" }
        if token.caseInsensitiveCompare("true") == .orderedSame { return "TRUE" }
        if token.caseInsensitiveCompare("false") == .orderedSame { return "FALSE" }
        if token.hasPrefix("'") && token.hasSuffix("'") && token.count >= 2 { return token }
        if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
            let inner = String(token.dropFirst().dropLast())
            return "'" + inner.replacingOccurrences(of: "'", with: "''") + "'"
        }
        if Double(token) != nil { return token }
        return "'" + token.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
