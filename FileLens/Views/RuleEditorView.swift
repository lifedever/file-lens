import SwiftUI

struct RuleEditorView: View {
    @Bindable var rule: Rule
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?  // nil for built-ins

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rule.isBuiltIn ? "Edit built-in rule" : (onDelete == nil ? "New rule" : "Edit rule"))
                .font(.title3.bold())

            HStack {
                Text("Name")
                TextField("Rule name", text: $rule.name)
            }

            HStack {
                Text("Match")
                Picker("", selection: $rule.combinator) {
                    Text("All conditions").tag("all")
                    Text("Any condition").tag("any")
                }
                .frame(width: 180)
                Spacer()
                Toggle("Enabled", isOn: $rule.enabled)
            }

            Divider()

            Text("Conditions").font(.headline)

            ForEach(rule.conditions) { cnd in
                ConditionRow(condition: cnd, onRemove: {
                    if let i = rule.conditions.firstIndex(where: { $0.id == cnd.id }) {
                        rule.conditions.remove(at: i)
                    }
                })
            }

            Button {
                rule.conditions.append(Condition(field: "extension", op: "is", value: ""))
            } label: {
                Label("Add Condition", systemImage: "plus.circle")
            }

            Spacer()

            HStack {
                if let onDelete, !rule.isBuiltIn {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}

private struct ConditionRow: View {
    @Bindable var condition: Condition
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $condition.field) {
                Text("Extension").tag("extension")
                Text("Name").tag("name")
                Text("Size").tag("size")
                Text("Date Added").tag("dateAdded")
                Text("Kind").tag("kind")
            }
            .frame(width: 110)

            Picker("", selection: $condition.op) {
                ForEach(opsFor(condition.field), id: \.0) { (key, label) in
                    Text(label).tag(key)
                }
            }
            .frame(width: 130)

            TextField("value", text: $condition.value)

            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
        }
    }

    private func opsFor(_ field: String) -> [(String, String)] {
        switch field {
        case "extension": return [("is","is"),("isAnyOf","is any of"),("isNot","is not")]
        case "name":      return [("contains","contains"),("matches","matches regex"),
                                  ("startsWith","starts with"),("endsWith","ends with")]
        case "size":      return [(">","greater than"),("<","less than"),("between","between")]
        case "dateAdded": return [("inLastDays","in the last N days"),("notInLastDays","not in the last N days"),
                                  ("before","before"),("after","after")]
        case "kind":      return [("is","is"),("isAnyOf","is any of")]
        default: return [("is","is")]
        }
    }
}
