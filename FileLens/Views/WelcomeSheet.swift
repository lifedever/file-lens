import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted from Settings → "Show Welcome…" so the main window can
    /// re-present the welcome sheet without coupling Settings to it.
    static let showWelcome = Notification.Name("filelens.showWelcome")
}

struct WelcomeSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, 40)
                .padding(.bottom, 28)

            Divider().opacity(0.5)

            features
                .padding(.horizontal, 36)
                .padding(.vertical, 28)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Text("welcome.getStarted")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 32)
        }
        .frame(width: 540, height: 640)
        .background(
            // Soft brand-tinted backdrop so the hero feels "introduced"
            // rather than a flat sheet.
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 1.00, green: 1.00, blue: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: 14) {
            if let img = NSImage(named: "AppIcon") {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
            }
            Text("welcome.title")
                .font(.system(size: 28, weight: .bold))
            Text("welcome.tagline")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(
                icon: "shield.lefthalf.filled",
                tint: .blue,
                title: "welcome.feature.nondestructive.title",
                description: "welcome.feature.nondestructive.desc"
            )
            FeatureRow(
                icon: "tag.fill",
                tint: .orange,
                title: "welcome.feature.rules.title",
                description: "welcome.feature.rules.desc"
            )
            FeatureRow(
                icon: "folder.fill.badge.gearshape",
                tint: .green,
                title: "welcome.feature.workspaces.title",
                description: "welcome.feature.workspaces.desc"
            )
            FeatureRow(
                icon: "command",
                tint: .pink,
                title: "welcome.feature.shortcuts.title",
                description: "welcome.feature.shortcuts.desc"
            )
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
