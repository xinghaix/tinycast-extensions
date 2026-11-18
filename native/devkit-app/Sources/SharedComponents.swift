import AppKit
import SwiftUI

struct MonospaceTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var placeholder: String = ""

    private static let maxRenderUTF8Bytes = 128 * 1024

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MonospaceTextEditor
        var isUpdatingProgrammatically = false

        init(_ parent: MonospaceTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically, let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string {
                parent.text = tv.string
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = isEditable
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = displayString(from: text)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.isEditable != isEditable { tv.isEditable = isEditable }
        let desired = displayString(from: text)
        if tv.string != desired {
            context.coordinator.isUpdatingProgrammatically = true
            let selected = tv.selectedRanges
            tv.string = desired
            if isEditable, let first = selected.first?.rangeValue, first.location <= desired.utf16.count {
                tv.setSelectedRange(NSRange(location: min(first.location, desired.utf16.count), length: 0))
            }
            context.coordinator.isUpdatingProgrammatically = false
        }
    }

    private func displayString(from full: String) -> String {
        guard !isEditable, full.utf8.count > Self.maxRenderUTF8Bytes else { return full }
        let prefixBytes = Data(full.utf8.prefix(Self.maxRenderUTF8Bytes))
        let partial = String(decoding: prefixBytes, as: UTF8.self)
        return partial + "\n\n... [内容超过 128 KB，界面仅预览前 128 KB 以保障流畅；点击右上角「复制」仍会复制全部 \(full.utf8.count) 字节]"
    }
}

struct CopyActionButton: View {
    let text: String
    var concealed: Bool = false
    var label: String = "复制"
    var onCopy: ((String) -> Void)?
    @State private var copied = false

    var body: some View {
        Button {
            performCopy()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(copied ? "已复制" : label)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(copied ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(copied ? Color.green : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func performCopy() {
        ClipboardService.copy(text, concealed: concealed)
        onCopy?(text)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            copied = false
        }
    }
}

struct CopyableResultRow: View {
    let title: String
    let value: String
    var badge: String? = nil
    var badgeColor: Color = .blue
    var concealed: Bool = false
    var secondaryButton: (title: String, icon: String, action: () -> Void)? = nil
    @Environment(StudioState.self) private var studio
    @State private var rowCopied = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(badgeColor.opacity(0.14)))
                            .foregroundStyle(badgeColor)
                    }
                    if rowCopied {
                        Text("✓ 已复制")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }

                Text(value)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerCopy()
                    }
                    .help("点击结果文本直接复制，或点击右侧「复制」按钮")
            }

            HStack(spacing: 6) {
                if let sec = secondaryButton {
                    Button(action: sec.action) {
                        HStack(spacing: 3) {
                            Image(systemName: sec.icon)
                                .font(.system(size: 11))
                            Text(sec.title)
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    triggerCopy()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: rowCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(rowCopied ? "已复制" : "复制")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(rowCopied ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(rowCopied ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.055) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(rowCopied ? Color.green.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private func triggerCopy() {
        studio.copy(value, label: "已复制 \(title)", concealed: concealed)
        rowCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            rowCopied = false
        }
    }
}

struct PillButton: View {
    let title: String
    let active: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? color.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active ? color.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
                )
                .foregroundStyle(active ? color : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct StudioToolBarButton: View {
    let title: String
    let icon: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

struct StudioPanel<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct EditorBoxView: View {
    @Binding var text: String
    var isEditable: Bool = true
    var height: CGFloat = 150

    var body: some View {
        MonospaceTextEditor(text: $text, isEditable: isEditable)
            .frame(minHeight: height, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor).opacity(0.65)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }
}
