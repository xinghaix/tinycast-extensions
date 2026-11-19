import AppKit
import Foundation
import SwiftUI

enum ToolGroup: String, CaseIterable, Sendable {
    case smart = "智能与快捷"
    case core = "核心开发者工具"
    case data = "数据与安全"
    case media = "视觉与效率"
}

enum ToolID: String, CaseIterable, Identifiable, Sendable {
    case smart
    case uuid
    case timestamp
    case hash
    case codec
    case json
    case color
    case regex
    case diff
    case url
    case radix
    case cidr
    case dataFormat = "data"
    case sql
    case cert
    case ocr
    case image
    case currency
    case password
    case text
    case qr
    case cron
    case network

    var id: String { rawValue }

    var group: ToolGroup {
        switch self {
        case .smart:
            return .smart
        case .uuid, .timestamp, .hash, .codec, .json, .color, .regex, .diff, .url, .radix, .cidr:
            return .core
        case .dataFormat, .sql, .cert:
            return .data
        case .ocr, .image, .currency, .password, .text, .qr, .cron, .network:
            return .media
        }
    }

    var title: String {
        switch self {
        case .smart: return "智能识别"
        case .uuid: return "UUID & ID"
        case .timestamp: return "时间戳转换"
        case .hash: return "Hash & 校验"
        case .codec: return "编解码 & AES"
        case .json: return "JSON 工具"
        case .color: return "色值 & 取色"
        case .regex: return "Regex 正则"
        case .diff: return "文本/JSON Diff"
        case .url: return "URL & cURL"
        case .radix: return "进制 & 位运算"
        case .cidr: return "CIDR 子网"
        case .dataFormat: return "格式互转"
        case .sql: return "SQL & 日志"
        case .cert: return "TLS 证书/SSH"
        case .ocr: return "离线 OCR 识字"
        case .image: return "图片转换/EXIF"
        case .currency: return "汇率换算"
        case .password: return "密码与密钥"
        case .text: return "文本格式化"
        case .qr: return "二维码生成"
        case .cron: return "Cron 解析"
        case .network: return "IP/端口/Hosts"
        }
    }

    var sfSymbol: String {
        switch self {
        case .smart: return "sparkles"
        case .uuid: return "touchid"
        case .timestamp: return "clock"
        case .hash: return "lock.shield"
        case .codec: return "chevron.left.forwardslash.chevron.right"
        case .json: return "curlybraces"
        case .color: return "paintpalette"
        case .regex: return "text.magnifyingglass"
        case .diff: return "arrow.left.arrow.right.square"
        case .url: return "link"
        case .radix: return "number.square"
        case .cidr: return "point.3.connected.trianglepath.dotted"
        case .dataFormat: return "tablecells"
        case .sql: return "cylinder.split.1x2"
        case .cert: return "checkmark.seal"
        case .ocr: return "text.viewfinder"
        case .image: return "photo.on.rectangle.angled"
        case .currency: return "banknote"
        case .password: return "key"
        case .text: return "doc.plaintext"
        case .qr: return "qrcode"
        case .cron: return "calendar.badge.clock"
        case .network: return "network"
        }
    }

    var accentColor: Color {
        switch self {
        case .smart: return .purple
        case .uuid: return .indigo
        case .timestamp: return .orange
        case .hash: return .green
        case .codec: return .purple
        case .json: return .cyan
        case .color: return .pink
        case .regex: return .orange
        case .diff: return .blue
        case .url: return .cyan
        case .radix: return .mint
        case .cidr: return .teal
        case .dataFormat: return .indigo
        case .sql: return .blue
        case .cert: return .green
        case .ocr: return .purple
        case .image: return .pink
        case .currency: return .green
        case .password: return .pink
        case .text: return .blue
        case .qr: return .primary
        case .cron: return .orange
        case .network: return .teal
        }
    }

    var keywords: [String] {
        switch self {
        case .smart: return ["smart", "clipboard", "auto", "剪贴板", "智能", "工作台", "workbench"]
        case .uuid: return ["uuid", "guid", "v1", "v3", "v4", "v5", "v6", "v7", "v8", "ulid", "nanoid", "ksuid", "objectid", "nil", "max"]
        case .timestamp: return ["timestamp", "unix", "epoch", "date", "time", "timezone", "iso", "utc", "时间戳", "时区", "日期"]
        case .hash: return ["hash", "md5", "sha1", "sha224", "sha256", "sha384", "sha512", "sha3", "keccak", "blake2", "sm3", "ripemd", "hmac", "crc32", "adler", "fnv", "murmur", "校验", "文件"]
        case .codec: return ["encode", "decode", "base64", "base32", "base58", "hex", "url", "html", "unicode", "jwt", "gzip", "deflate", "aes", "gcm", "cbc", "rot13", "morse", "radix", "编码", "解码", "加解密"]
        case .json: return ["json", "format", "minify", "yaml", "typescript", "pretty", "repair", "query", "格式化"]
        case .color: return ["color", "hex", "rgb", "rgba", "hsl", "hsv", "hsb", "oklch", "oklab", "lab", "lch", "hwb", "cmyk", "wcag", "contrast", "eyedropper", "palette", "tailwind", "色值", "颜色", "取色", "吸管", "对比度", "调色板"]
        case .regex: return ["regex", "regexp", "match", "capture", "replace", "pattern", "正则", "匹配", "替换", "捕获"]
        case .diff: return ["diff", "compare", "patch", "merge", "json", "contrast", "对比", "差异", "语义"]
        case .url: return ["url", "uri", "query", "params", "curl", "fetch", "python", "httpie", "golang", "链接", "参数", "请求"]
        case .radix: return ["radix", "binary", "hex", "octal", "decimal", "bit", "bitwise", "chmod", "endian", "bytes", "进制", "位运算", "权限", "字节"]
        case .cidr: return ["cidr", "subnet", "ip", "ipv4", "ipv6", "netmask", "broadcast", "子网", "掩码", "网段"]
        case .dataFormat: return ["data", "yaml", "toml", "env", "csv", "markdown", "table", "json", "convert", "表格", "互转", "配置"]
        case .sql: return ["sql", "format", "minify", "mybatis", "gorm", "prisma", "orm", "bind", "params", "日志", "参数", "数据库"]
        case .cert: return ["cert", "tls", "ssl", "x509", "pem", "ssh", "pubkey", "san", "fingerprint", "randomart", "证书", "公钥", "指纹"]
        case .ocr: return ["ocr", "vision", "scan", "barcode", "qrcode", "text", "screenshot", "识字", "扫码", "截屏"]
        case .image: return ["image", "png", "jpeg", "heic", "webp", "tiff", "gif", "exif", "gps", "resize", "datauri", "图片", "转换", "压缩", "脱敏"]
        case .currency: return ["currency", "fx", "exchange", "rate", "money", "usd", "cny", "rmb", "hkd", "jpy", "eur", "gbp", "twd", "krw", "btc", "xau", "汇率", "货币", "换算", "美元", "人民币", "日元", "港币", "欧元", "黄金"]
        case .password: return ["password", "pw", "secret", "token", "passphrase", "pin", "密码", "密钥"]
        case .text: return ["text", "case", "camel", "pascal", "snake", "kebab", "constant", "slug", "sort", "dedupe", "文本", "大小写", "去重"]
        case .qr: return ["qr", "qrcode", "svg", "png", "wifi", "二维码"]
        case .cron: return ["cron", "crontab", "schedule", "定时", "表达式"]
        case .network: return ["ip", "port", "lsof", "tcp", "listen", "kill", "network", "hosts", "dns", "端口", "网络"]
        }
    }
}

enum ClipboardService {
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @MainActor
    static func copy(_ text: String, concealed: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if concealed {
            pb.declareTypes([.string, concealedType], owner: nil)
            pb.setString(text, forType: .string)
            pb.setData(Data(), forType: concealedType)
        } else {
            pb.setString(text, forType: .string)
        }
    }

    @MainActor
    static func readString() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }
}

enum CodecSubTab: String, CaseIterable, Sendable {
    case bidirectional = "双向工作台"
    case matrix = "全算法速览"
    case jwt = "JWT 解析与验签"
    case aes = "AES-256 加解密"
}

enum UrlSubTab: String, CaseIterable, Sendable {
    case urlParser = "URL 解析与构造"
    case curlConverter = "cURL 转换代码"
}

@MainActor
@Observable
final class StudioState {
    var activeTool: ToolID = .smart
    var sidebarSearch: String = ""
    var isPinnedOnTop: Bool = false
    var toastText: String? = nil
    var toastIsError: Bool = false
    private var toastToken: Int = 0

    // Shared handoff / routing hints
    var smartInput: String = ""
    var hashFilterHint: String = ""
    var codecTabHint: CodecSubTab = .bidirectional
    var urlTabHint: UrlSubTab = .urlParser
    var textInput: String = ""
    var jsonInput: String = ""
    var codecInput: String = "Hello Tinycast!"
    var qrInput: String = "https://github.com/abue-ammar/tinycast"
    var cronInput: String = "*/15 9-18 * * 1-5"
    var timestampInput: String = ""
    var hashInput: String = "Hello Tinycast!"
    var uuidSeedInput: String = ""
    var colorInput: String = "#3B82F6"

    var regexPattern: String = RegexEngine.presets[0].pattern
    var regexInput: String = RegexEngine.presets[0].sample
    var diffLeft: String = DiffEngine.sampleLeft
    var diffRight: String = DiffEngine.sampleRight
    var urlInput: String = UrlCurlEngine.sampleUrl
    var curlInput: String = UrlCurlEngine.sampleCurl
    var radixInput: String = "0xDEADBEEF"
    var cidrInput: String = "10.0.12.34/22"
    var dataFormatInput: String = DataFormatEngine.sampleJson
    var sqlInput: String = SqlEngine.sampleSql
    var certInput: String = CertEngine.sampleSshKey
    var currencyBaseCode: String = "USD"
    var currencyTargetCode: String = "CNY"
    var currencyAmountInput: String = "100"

    var onPinChange: ((Bool) -> Void)?
    var onFocusSearch: (() -> Void)?

    func showToast(_ message: String, isError: Bool = false) {
        toastToken &+= 1
        let captured = toastToken
        toastText = message
        toastIsError = isError
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            if self.toastToken == captured {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.toastText = nil
                }
            }
        }
    }

    func copy(_ text: String, label: String = "已复制到剪贴板", concealed: Bool = false) {
        ClipboardService.copy(text, concealed: concealed)
        showToast(concealed ? "✓ \(label) (隐私保护)" : "✓ \(label)")
    }

    func applyLaunch(toolRaw: String?, handoffSelected: String?, clipboardText: String?) {
        let resolvedTool = toolRaw.flatMap(ToolID.init(rawValue:)) ?? .smart
        activeTool = resolvedTool
        let clip = clipboardText ?? ""

        if let sel = handoffSelected, !sel.isEmpty {
            let trimmedSel = sel.trimmingCharacters(in: .whitespacesAndNewlines)
            textInput = sel
            smartInput = sel
            hashInput = sel
            codecInput = sel
            regexInput = sel
            dataFormatInput = sel
            if resolvedTool == .diff { diffLeft = sel }
            if (trimmedSel.hasPrefix("{") || trimmedSel.hasPrefix("[")) && JsonEngine.analyze(sel).valid {
                jsonInput = sel
            }
            if ColorEngine.parse(sel) != nil {
                colorInput = trimmedSel
            }
            if trimmedSel.lowercased().hasPrefix("curl ") {
                curlInput = sel
                urlTabHint = .curlConverter
            } else if UrlCurlEngine.parseUrl(trimmedSel) != nil && (trimmedSel.contains("://") || trimmedSel.contains("=")) {
                urlInput = trimmedSel
            }
            if RadixBitwiseEngine.parse(trimmedSel) != nil {
                radixInput = trimmedSel
            }
            if CidrEngine.parseIpv4Cidr(trimmedSel) != nil || (trimmedSel.contains(":") && CidrEngine.parseIpv6Cidr(trimmedSel) != nil) {
                cidrInput = trimmedSel
            }
            if trimmedSel.contains("Preparing:") || trimmedSel.lowercased().hasPrefix("select ") || trimmedSel.lowercased().hasPrefix("with ") {
                sqlInput = sel
            }
            if CertEngine.parseSshPublicKey(trimmedSel) != nil || !CertEngine.extractPemCertificates(trimmedSel).isEmpty {
                certInput = sel
            }
            if let cur = CurrencyEngine.parseCurrencyQuery(trimmedSel) {
                currencyBaseCode = cur.code
                currencyTargetCode = (cur.code == "CNY" ? "USD" : "CNY")
                currencyAmountInput = CurrencyEngine.formatCopyPlain(cur.amount, code: cur.code)
            }
        } else if !clip.isEmpty {
            let trimmedClip = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            smartInput = clip
            if resolvedTool == .text { textInput = clip }
            if resolvedTool == .json {
                if jsonInput.isEmpty || trimmedClip.hasPrefix("{") || trimmedClip.hasPrefix("[") {
                    jsonInput = clip
                }
            }
            if resolvedTool == .codec { codecInput = clip }
            if resolvedTool == .hash { hashInput = clip }
            if resolvedTool == .qr { qrInput = clip }
            if resolvedTool == .cron, (trimmedClip.hasPrefix("@") || trimmedClip.split(whereSeparator: \.isWhitespace).count == 5) {
                cronInput = clip
            }
            if resolvedTool == .timestamp, TimestampEngine.parse(clip) != nil {
                timestampInput = clip
            }
            if resolvedTool == .uuid, UUIDEngine.shared.inspect(clip) != nil {
                uuidSeedInput = clip
            }
            if resolvedTool == .color, ColorEngine.parse(clip) != nil {
                colorInput = trimmedClip
            }
            if resolvedTool == .regex { regexInput = clip }
            if resolvedTool == .diff { diffLeft = clip }
            if resolvedTool == .url {
                if trimmedClip.lowercased().hasPrefix("curl ") {
                    curlInput = clip
                    urlTabHint = .curlConverter
                } else if trimmedClip.contains("://") || trimmedClip.contains("=") {
                    urlInput = trimmedClip
                    urlTabHint = .urlParser
                }
            }
            if resolvedTool == .radix, RadixBitwiseEngine.parse(trimmedClip) != nil {
                radixInput = trimmedClip
            }
            if resolvedTool == .cidr, (CidrEngine.parseIpv4Cidr(trimmedClip) != nil || (trimmedClip.contains(":") && CidrEngine.parseIpv6Cidr(trimmedClip) != nil)) {
                cidrInput = trimmedClip
            }
            if resolvedTool == .dataFormat { dataFormatInput = clip }
            if resolvedTool == .sql { sqlInput = clip }
            if resolvedTool == .cert, (CertEngine.parseSshPublicKey(trimmedClip) != nil || !CertEngine.extractPemCertificates(trimmedClip).isEmpty || trimmedClip.contains("-----BEGIN")) {
                certInput = clip
            }
            if resolvedTool == .currency, let cur = CurrencyEngine.parseCurrencyQuery(trimmedClip) {
                currencyBaseCode = cur.code
                currencyTargetCode = (cur.code == "CNY" ? "USD" : "CNY")
                currencyAmountInput = CurrencyEngine.formatCopyPlain(cur.amount, code: cur.code)
            }
        }
    }

    func jump(to tool: ToolID, searchTerm: String = "") {
        activeTool = tool
        let q = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tool == .hash && !q.isEmpty && !["hash", "校验", "文件"].contains(q) {
            hashFilterHint = q
        }
        if tool == .codec {
            if q.contains("jwt") { codecTabHint = .jwt }
            else if q.contains("aes") || q.contains("gcm") || q.contains("cbc") { codecTabHint = .aes }
            else { codecTabHint = .bidirectional }
        }
        if tool == .url {
            if q.contains("curl") || q.contains("fetch") || q.contains("httpie") {
                urlTabHint = .curlConverter
            } else if q == "url" {
                urlTabHint = .urlParser
            }
        }
    }

    func filteredTools() -> [ToolID] {
        let q = sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ToolID.allCases }
        return ToolID.allCases.filter { tool in
            tool.title.lowercased().contains(q)
                || tool.rawValue.contains(q)
                || tool.keywords.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }
}
