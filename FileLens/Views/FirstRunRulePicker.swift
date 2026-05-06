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

    private var allSelected: Bool { enabled.count == rules.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: String(format: NSLocalizedString("picker.title.format",
                    value: "Set up rules for “%@”", comment: ""), folderName))
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

            // Native inset List for the standard macOS rounded-list look —
            // subtle hover, native separators, no hand-drawn dividers.
            // Select-all moved to the footer alongside the count so the
            // list reads cleanly from top to bottom.
            List {
                ForEach(rules, id: \.id) { r in
                    ruleRow(r)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 340, maxHeight: 400)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6),
                            lineWidth: 0.5)
            )

            // Footer: count + select-all on the left, action buttons on
            // the right.
            HStack(spacing: 12) {
                Text(verbatim: String(format: NSLocalizedString("picker.selected.format",
                    value: "%d of %d selected", comment: ""), enabled.count, rules.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    enabled = allSelected ? [] : Set(rules.map(\.id))
                } label: {
                    Text(allSelected ? "picker.deselectAll" : "picker.selectAll")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .pointingHandCursor()
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm(enabled)
                } label: {
                    Text("picker.confirm",
                         comment: "Primary button: confirm and start applying rules")
                        .frame(minWidth: 100)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    @ViewBuilder
    private func ruleRow(_ r: Rule) -> some View {
        let isOn = Binding<Bool>(
            get: { enabled.contains(r.id) },
            set: { v in
                if v { enabled.insert(r.id) } else { enabled.remove(r.id) }
            }
        )
        let descKey = BuiltInRules.descriptionKey(forBuiltInRuleNamed: r.name)
        let desc = descKey.flatMap { key -> String? in
            let s = NSLocalizedString(key, value: "", comment: "")
            return s.isEmpty ? nil : s
        }

        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: NSLocalizedString(r.name, value: r.name, comment: ""))
                    .font(.body)
                if let desc {
                    Text(verbatim: desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
    }
}
