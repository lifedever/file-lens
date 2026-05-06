import SwiftUI

struct RuleEditorView: View {
    @Bindable var rule: Rule
    let isNewRule: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    private var titleKey: LocalizedStringKey {
        if isNewRule          { return "New rule" }
        if rule.isBuiltIn     { return "Edit built-in rule" }
        return "Edit rule"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(titleKey)
                .font(.title3.bold())
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Divider()

            // Form-style fields
            VStack(alignment: .leading, spacing: 14) {
                LabeledRow(label: "Name") {
                    if rule.isBuiltIn {
                        // Built-in rule names are i18n keys; don't let users mutate
                        // them or the localization mapping breaks.
                        Text(verbatim: TagDisplay.localizedName(rule.name))
                            .foregroundStyle(.primary)
                        Spacer()
                    } else {
                        TextField("Rule name", text: $rule.name)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                LabeledRow(label: "Match") {
                    Picker("", selection: $rule.combinator) {
                        Text("All conditions").tag("all")
                        Text("Any condition").tag("any")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                    Toggle("Enabled", isOn: $rule.enabled)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            // Conditions section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Conditions").font(.headline)
                    Spacer()
                    Button {
                        rule.conditions.append(Condition(field: "extension", op: "is", value: ""))
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(rule.conditions) { cnd in
                    ConditionRow(condition: cnd, onRemove: {
                        if let i = rule.conditions.firstIndex(where: { $0.id == cnd.id }) {
                            rule.conditions.remove(at: i)
                        }
                    })
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Spacer(minLength: 0)
            Divider()

            // Footer
            HStack {
                Button("Delete", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(isNewRule)  // nothing to delete for a draft

                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNewRule ? "Add Rule" : "Save") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 460)
        .confirmationDialog(
            "delete.confirm.title",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("delete.confirm.message")
        }
    }
}

private struct LabeledRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
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
            .labelsHidden()
            .frame(width: 110)

            Picker("", selection: $condition.op) {
                ForEach(opsFor(condition.field), id: \.0) { (key, label) in
                    Text(verbatim: NSLocalizedString(label, value: label, comment: ""))
                        .tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            TextField("value", text: $condition.value)
                .textFieldStyle(.roundedBorder)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
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
