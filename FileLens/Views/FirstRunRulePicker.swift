import SwiftUI

struct FirstRunRulePicker: View {
    let folderName: String
    let rules: [Rule]
    @State private var enabled: Set<UUID>
    let onConfirm: (Set<UUID>) -> Void
    let onCancel: () -> Void

    init(folderName: String, rules: [Rule],
         onConfirm: @escaping (Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.folderName = folderName
        self.rules = rules
        self._enabled = State(initialValue: Set(rules.map(\.id)))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: String(format: NSLocalizedString("picker.title.format",
                    value: "Set up tags for “%@”", comment: ""), folderName))
                    .font(.title3.bold())
                Text("picker.subtitle",
                     comment: "Subtitle explaining what FileLens will do")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Recommendation banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("picker.recommendation",
                     comment: "Hint that the user can just click Add")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(0.12))
            )

            // Tag list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rules, id: \.id) { r in
                        ruleRow(r)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(minHeight: 320, maxHeight: 380)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            )

            // Footer
            HStack {
                Text(verbatim: String(format: NSLocalizedString("picker.selected.format",
                    value: "%d of %d selected", comment: ""), enabled.count, rules.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm(enabled)
                } label: {
                    Text("picker.confirm",
                         comment: "Primary button: confirm and start tagging")
                        .frame(minWidth: 100)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    @ViewBuilder
    private func ruleRow(_ r: Rule) -> some View {
        let isOn = Binding<Bool>(
            get: { enabled.contains(r.id) },
            set: { v in
                if v { enabled.insert(r.id) } else { enabled.remove(r.id) }
            }
        )
        Toggle(isOn: isOn) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: NSLocalizedString(r.name, value: r.name, comment: ""))
                    .font(.body)
                    .frame(width: 90, alignment: .leading)
                if let descKey = BuiltInRules.descriptionKey(forBuiltInRuleNamed: r.name) {
                    Text(verbatim: NSLocalizedString(descKey, value: "", comment: ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
