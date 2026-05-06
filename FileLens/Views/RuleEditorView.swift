import SwiftUI

struct RuleEditorView: View {
    @Bindable var rule: Rule
    let isNewRule: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    private var titleKey: LocalizedStringKey {
        isNewRule ? "New rule" : "Edit rule"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    metadataSection
                    conditionsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 520)
        .confirmationDialog(
            "delete.confirm.title",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("delete.confirm.message")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: rule.color))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            Text(titleKey)
                .font(.title3.bold())
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledRow(label: "Name") {
                // Built-in rules are now stored with their localized name at
                // creation time, so all rules — built-in or user-made — are
                // freely editable here.
                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledRow(label: "Color") {
                ColorPaletteRow(selected: $rule.color)
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
    }

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Conditions").font(.headline)
                Spacer()
                Button {
                    rule.conditions.append(Condition(field: "extension", op: "is", value: ""))
                } label: {
                    Label("Add Condition", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 8) {
                ForEach(rule.conditions) { cnd in
                    ConditionRow(condition: cnd, onRemove: {
                        if let i = rule.conditions.firstIndex(where: { $0.id == cnd.id }) {
                            rule.conditions.remove(at: i)
                        }
                    })
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private var footer: some View {
        HStack {
            Button("Delete", role: .destructive) {
                confirmingDelete = true
            }
            .disabled(isNewRule)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(isNewRule ? "Add Rule" : "Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Color row

private struct ColorPaletteRow: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RuleColorPresets.all, id: \.self) { hex in
                ColorSwatch(
                    color: Color(hexString: hex),
                    isSelected: hex.lowercased() == selected.lowercased()
                )
                .onTapGesture { selected = hex }
            }
            Spacer()
        }
    }
}

private struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .padding(2)
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Helpers

private struct LabeledRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        // .center keeps the label vertically centered with non-text content
        // (e.g. the color swatch row). .firstTextBaseline silently falls back
        // to the view's bottom edge for views without text, which pushed the
        // swatches' optical centers off the label's center.
        HStack(alignment: .center, spacing: 12) {
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
