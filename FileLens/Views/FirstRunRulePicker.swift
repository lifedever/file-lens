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

            List {
                ForEach(rules) { r in
                    Toggle(r.name, isOn: Binding(
                        get: { enabled.contains(r.id) },
                        set: { isOn in
                            if isOn { enabled.insert(r.id) } else { enabled.remove(r.id) }
                        }
                    ))
                }
            }
            .frame(minHeight: 320)

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
