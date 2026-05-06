import SwiftUI
import AppKit

struct EmptyStateView: View {
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                appIcon

                VStack(spacing: 10) {
                    Text("empty.title", comment: "Empty state main title")
                        .font(.system(size: 28, weight: .bold))
                    Text("empty.lead", comment: "Lead paragraph: what FileLens does")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                HStack(alignment: .top, spacing: 14) {
                    featureCard(icon: "tag.fill", tint: .orange,
                                title: "empty.feat1.title",
                                body:  "empty.feat1.body")
                    featureCard(icon: "lock.shield.fill", tint: .blue,
                                title: "empty.feat2.title",
                                body:  "empty.feat2.body")
                    featureCard(icon: "bolt.fill", tint: .green,
                                title: "empty.feat3.title",
                                body:  "empty.feat3.body")
                }
                .padding(.top, 12)

                Button(action: onAddFolder) {
                    Label("empty.cta", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .pointingHandCursor()
                .padding(.top, 12)

                Text("empty.hint", comment: "Subtle hint: ⌘O + recommendation")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// App-icon hero. Falls back to an SF Symbol if the asset can't load
    /// (shouldn't happen in production, but keeps SwiftUI previews working).
    private var appIcon: some View {
        Group {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 124, height: 124)
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    /// Tinted icon badge + title + body, sized so the row of three reads
    /// as one unit. Fixed height keeps cards visually aligned even when
    /// translations have different line counts.
    @ViewBuilder
    private func featureCard(icon: String, tint: Color,
                             title: LocalizedStringKey,
                             body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.14))
                )
            Text(title).font(.callout.bold())
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 200, alignment: .leading)
        // .frame(maxHeight: .infinity) 会让卡片把外层 VStack 的垂直空间
        // 全部吃掉，标题/图标会被挤出窗口。直接让卡片按内容大小渲染即可。
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 0.5)
        )
    }
}
