import AppKit
import Foundation
import SwiftUI

enum ToolGroup: String, CaseIterable, Sendable {
    case smart = "智能与快捷"
    case core = "核心开发者工具"
    case utility = "实用效率工具"
}

enum ToolID: String, CaseIterable, Identifiable, Sendable {
    case smart
    case uuid
    case timestamp
    case hash
    case codec
    case json
    case color
    case password
    case text
    case qr
    case cron
    case network

    var id: String { rawValue }

    var group: ToolGroup {
        switch self {
        case .smart: return .smart
        case .uuid, .timestamp, .hash, .codec, .json, .color: return .core
        case .password, .text, .qr, .cron, .network: return .utility
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
        case .password: return "密码与密钥"
        case .text: return "文本格式化"
        case .qr: return "二维码生成"
        case .cron: return "Cron 解析"
        case .network: return "IP & 端口"
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
        case .password: return ["password", "pw", "secret", "token", "passphrase", "pin", "密码", "密钥"]
        case .text: return ["text", "case", "camel", "pascal", "snake", "kebab", "constant", "slug", "sort", "dedupe", "文本", "大小写", "去重"]
        case .qr: return ["qr", "qrcode", "svg", "png", "wifi", "二维码"]
        case .cron: return ["cron", "crontab", "schedule", "定时", "表达式"]
        case .network: return ["ip", "port", "lsof", "tcp", "listen", "kill", "network", "端口", "网络"]
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
    var textInput: String = ""
    var jsonInput: String = ""
    var codecInput: String = "Hello Tinycast!"
    var qrInput: String = "https://github.com/abue-ammar/tinycast"
    var cronInput: String = "*/15 9-18 * * 1-5"
    var timestampInput: String = ""
    var hashInput: String = "Hello Tinycast!"
    var uuidSeedInput: String = ""
    var colorInput: String = "#3B82F6"

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
            textInput = sel
            smartInput = sel
            hashInput = sel
            codecInput = sel
            if (sel.hasPrefix("{") || sel.hasPrefix("[")) && JsonEngine.analyze(sel).valid {
                jsonInput = sel
            }
            if ColorEngine.parse(sel) != nil {
                colorInput = sel.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if !clip.isEmpty {
            smartInput = clip
            if resolvedTool == .text { textInput = clip }
            if resolvedTool == .json {
                let trimmedClip = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonInput.isEmpty || trimmedClip.hasPrefix("{") || trimmedClip.hasPrefix("[") {
                    jsonInput = clip
                }
            }
            if resolvedTool == .codec { codecInput = clip }
            if resolvedTool == .hash { hashInput = clip }
            if resolvedTool == .qr { qrInput = clip }
            if resolvedTool == .cron, (clip.hasPrefix("@") || clip.split(whereSeparator: \.isWhitespace).count == 5) {
                cronInput = clip
            }
            if resolvedTool == .timestamp, TimestampEngine.parse(clip) != nil {
                timestampInput = clip
            }
            if resolvedTool == .uuid, UUIDEngine.shared.inspect(clip) != nil {
                uuidSeedInput = clip
            }
            if resolvedTool == .color, ColorEngine.parse(clip) != nil {
                colorInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
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
