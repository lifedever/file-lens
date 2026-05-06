import SwiftUI

struct EmptyStateView: View {
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.tint)

                Text("empty.title", comment: "Empty state main title")
                    .font(.title.bold())

                Text("empty.lead", comment: "Lead paragraph: what FileLens does")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 28) {
                    feature(icon: "tag.fill",
                            title: "empty.feat1.title",
                            body:  "empty.feat1.body")
                    feature(icon: "lock.shield.fill",
                            title: "empty.feat2.title",
                            body:  "empty.feat2.body")
                    feature(icon: "bolt.fill",
                            title: "empty.feat3.title",
                            body:  "empty.feat3.body")
                }
                .padding(.top, 8)

                Button(action: onAddFolder) {
                    Label("empty.cta", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .padding(.top, 8)

                Text("empty.hint", comment: "Subtle hint: ⌘O + recommendation")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func feature(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(height: 28)
            Text(title)
                .font(.callout.bold())
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 160)
    }
}
