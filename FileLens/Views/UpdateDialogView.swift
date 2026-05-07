import SwiftUI
import AppKit

// MARK: - Markdown 渲染(纯 SwiftUI,不走 WKWebView)

/// 简易 markdown 视图。按行解析:#/##/### 标题、`-` 列表、```围栏代码块、
/// 引用块、空行 = 段落分隔;行内交给 AttributedString 处理粗体 / 行内 code /
/// 链接。
///
/// 走 WKWebView 在 macOS 26 上有奇怪的空白渲染问题(WKWebView 内容明明
/// 在但屏幕一片空白),换成 SwiftUI 原生 Text + VStack 拼装,稳。
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 块结构

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(level: Int, text: String)   // level = 缩进级别
        case paragraph(text: String)
        case code(text: String)
        case quote(text: String)
        case rule                                // ---
        case spacer
    }

    private func parseBlocks(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let lines = md.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块
            if trimmed.hasPrefix("```") {
                var buf: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    buf.append(lines[i])
                    i += 1
                }
                blocks.append(.code(text: buf.joined(separator: "\n")))
                i += 1
                continue
            }
            // 标题
            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            }
            // 横线
            else if trimmed == "---" || trimmed == "***" {
                blocks.append(.rule)
            }
            // 引用
            else if trimmed.hasPrefix("> ") {
                blocks.append(.quote(text: String(trimmed.dropFirst(2))))
            }
            // 列表项(支持缩进:-/  -/    - 算 0/1/2 级)
            else if let bulletText = bulletContent(of: line) {
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                blocks.append(.bullet(level: leadingSpaces / 2, text: bulletText))
            }
            // 空行
            else if trimmed.isEmpty {
                if case .spacer? = blocks.last {
                    // 多个空行不重复加 spacer
                } else {
                    blocks.append(.spacer)
                }
            }
            // 普通段落
            else {
                blocks.append(.paragraph(text: trimmed))
            }
            i += 1
        }
        return blocks
    }

    private func bulletContent(of line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        if trimmed.hasPrefix("- ") {
            return String(trimmed.dropFirst(2))
        }
        if trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }
        return nil
    }

    // MARK: 块渲染

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 8 : 4)
                .padding(.bottom, 2)

        case .bullet(let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                    .foregroundStyle(.secondary)
                Text(inline(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(level) * 16)

        case .paragraph(let text):
            Text(inline(text))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .code(let text):
            Text(verbatim: text)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))

        case .quote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(inline(text))
                    .padding(.leading, 8)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .rule:
            Divider()
                .padding(.vertical, 4)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        case 3: return .body.bold()
        default: return .body.bold()
        }
    }

    /// 行内格式化(粗体 / 行内 code / 链接 / emoji),AttributedString 自带
    /// markdown 解析。失败回退纯文本。
    private func inline(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(text)
    }
}

// MARK: - Update dialog

struct UpdateDialogView: View {
    @ObservedObject var controller: UpdateController
    let onClose: () -> Void

    var body: some View {
        Group {
            if controller.isDownloading || controller.downloadComplete {
                downloadView
            } else {
                availableView
            }
        }
    }

    // MARK: Available

    private var availableView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("update.available.title")
                        .font(.title3.bold())
                    Text(verbatim: String(format: NSLocalizedString(
                        "update.available.subtitle.format",
                        value: "Version %@ is available — you’re on %@",
                        comment: ""), controller.latestTag, controller.currentVersion))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if !controller.releaseNotes.isEmpty {
                MarkdownView(markdown: controller.releaseNotes)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 20)
            }

            Divider().padding(.top, 16)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    controller.startDownload()
                } label: {
                    Text("update.install")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 460)
    }

    // MARK: Downloading / Ready

    private var downloadView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(controller.downloadComplete
                         ? "update.ready.title"
                         : "update.downloading.title")
                        .font(.headline)
                    ProgressView(value: controller.downloadProgress)
                        .progressViewStyle(.linear)
                    if !controller.downloadComplete && controller.totalBytes > 0 {
                        Text(verbatim:
                            "\(formatBytes(controller.downloadedBytes)) / \(formatBytes(controller.totalBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                if controller.downloadComplete {
                    Button {
                        onClose()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            controller.installAndRestart()
                        }
                    } label: {
                        Text("update.installAndRestart")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        controller.cancelDownload()
                        onClose()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 200)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - Window presenter

@MainActor
enum UpdateDialogPresenter {
    static func present(_ info: UpdateInfo, currentVersion: String) {
        UpdateController.shared.prepare(info: info, currentVersion: currentVersion)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("update.available.title",
            value: "Update Available", comment: "")
        window.center()
        window.isReleasedWhenClosed = false

        let dialog = UpdateDialogView(
            controller: UpdateController.shared,
            onClose: { [weak window] in
                window?.close()
                NSApp.stopModal()
            }
        )
        let hosting = NSHostingView(rootView: dialog)
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        NSApp.runModal(for: window)
    }
}
