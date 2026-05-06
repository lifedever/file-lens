import SwiftUI

struct FirstRunRulePicker: View {
    let rules: [Rule]
    @State private var enabled: Set<UUID>
    let onConfirm: (Set<UUID>) -> Void
    let onCancel: () -> Void

    init(rules: [Rule], onConfirm: @escaping (Set<UUID>) -> Void, onCancel: @escaping () -> Void) {
        self.rules = rules
        self._enabled = State(initialValue: Set(rules.map(\.id)))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose default tags").font(.title3.bold())
            Text("FileLens groups files by these rules. You can turn any of them off later.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rules, id: \.id) { r in
                        Toggle(isOn: Binding(
                            get: { enabled.contains(r.id) },
                            set: { isOn in
                                if isOn { enabled.insert(r.id) } else { enabled.remove(r.id) }
                            }
                        )) {
                            Text(verbatim: NSLocalizedString(r.name, value: r.name, comment: ""))
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { onConfirm(enabled) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
