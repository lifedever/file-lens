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

            // 直接 VStack(不套 ScrollView):内容多就让弹窗自然变高,少就缩短。
            // ScrollView 加 idealHeight 是上一版的折中,但永远撑出固定空白,
            // 没真正"自适应"。条件极多(>20)时就让它顶到屏幕极限,普通使用
            // 场景下一两条就一两条的高度。
            VStack(alignment: .leading, spacing: 22) {
                metadataSection
                conditionsSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()
            footer
        }
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
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
            Picker("", selection: fieldBinding) {
                Text("Extension").tag("extension")
                Text("Name").tag("name")
                Text("Size").tag("size")
                Text("Date Added").tag("dateAdded")
                Text("Kind").tag("kind")
            }
            .labelsHidden()
            .frame(width: 110)

            Picker("", selection: opBinding) {
                ForEach(opsFor(condition.field), id: \.0) { (key, label) in
                    Text(verbatim: NSLocalizedString(label, value: label, comment: ""))
                        .tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            valueControl
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// 切 field 时把 value 清空 —— 旧值在新 field 下基本都没意义(比如
    /// "100MB" 切到 dateAdded 解析不动),让用户从空开始填比留脏数据靠谱。
    /// op 也跟着重置成新 field 的第一个合法 op。
    private var fieldBinding: Binding<String> {
        Binding(
            get: { condition.field },
            set: { newField in
                guard newField != condition.field else { return }
                condition.field = newField
                condition.op = opsFor(newField).first?.0 ?? "is"
                condition.value = ""
            }
        )
    }

    /// 切 op 时,如果 value 格式跟新 op 不兼容(比如 size "100MB" 切到 between
    /// 需要逗号对),清空让用户重新填;同 field 内格式兼容时保留 value。
    private var opBinding: Binding<String> {
        Binding(
            get: { condition.op },
            set: { newOp in
                guard newOp != condition.op else { return }
                if !valueCompatible(field: condition.field,
                                    fromOp: condition.op, toOp: newOp,
                                    value: condition.value) {
                    condition.value = ""
                }
                condition.op = newOp
            }
        )
    }

    private func valueCompatible(field: String, fromOp: String, toOp: String, value: String) -> Bool {
        if value.isEmpty { return true }
        switch field {
        case "size":
            // 单值 ↔ between 格式不同(后者要逗号),互切就清空
            if (fromOp == "between") != (toOp == "between") { return false }
            return true
        case "dateAdded":
            // 数字 days ↔ ISO8601 互不兼容
            let bothDays = ["inLastDays", "notInLastDays"].contains(fromOp) &&
                           ["inLastDays", "notInLastDays"].contains(toOp)
            let bothDates = ["before", "after"].contains(fromOp) &&
                            ["before", "after"].contains(toOp)
            return bothDays || bothDates
        default:
            return true
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

    // MARK: - Value control dispatcher

    @ViewBuilder
    private var valueControl: some View {
        switch condition.field {
        case "extension": extensionField
        case "name":      nameField
        case "size":      sizeField
        case "dateAdded": dateField
        case "kind":      kindValuePicker
        default:
            TextField("value", text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: extension

    private var extensionField: some View {
        let placeholder: LocalizedStringKey = condition.op == "isAnyOf"
            ? "rule.condition.ext.placeholder.list"   // "png, jpg, heic"
            : "rule.condition.ext.placeholder.single" // "png"
        return TextField("", text: $condition.value, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
    }

    // MARK: name

    private var nameField: some View {
        let placeholder: LocalizedStringKey = {
            switch condition.op {
            case "contains":   return "rule.condition.name.placeholder.contains"
            case "startsWith": return "rule.condition.name.placeholder.startsWith"
            case "endsWith":   return "rule.condition.name.placeholder.endsWith"
            case "matches":    return "rule.condition.name.placeholder.regex"
            default:           return "rule.condition.name.placeholder.contains"
            }
        }()
        return TextField("", text: $condition.value, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .font(condition.op == "matches" ? .body.monospaced() : .body)
    }

    // MARK: size

    private var sizeField: some View {
        Group {
            if condition.op == "between" {
                HStack(spacing: 4) {
                    sizeUnitPair(part: 0)
                    Text("rule.condition.size.between.separator")
                        .foregroundStyle(.secondary)
                    sizeUnitPair(part: 1)
                }
            } else {
                sizeUnitPair(part: 0)
            }
        }
    }

    /// "100MB" / 单值,或者 "100MB,500MB" 的某一部分(part 0 / 1)。
    /// 把 condition.value 拆成 (number, unit),给两个独立控件;改一个就重组回去。
    @ViewBuilder
    private func sizeUnitPair(part: Int) -> some View {
        let parts = sizeParts()
        let initial = (part < parts.count) ? parts[part] : ("", "MB")
        let numberBinding = Binding<String>(
            get: { initial.0 },
            set: { setSizePart(part: part, number: $0, unit: initial.1) }
        )
        let unitBinding = Binding<String>(
            get: { initial.1 },
            set: { setSizePart(part: part, number: initial.0, unit: $0) }
        )
        HStack(spacing: 3) {
            TextField("", text: numberBinding, prompt: Text(verbatim: "0"))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 70)
            Picker("", selection: unitBinding) {
                ForEach(["B", "KB", "MB", "GB"], id: \.self) { u in
                    Text(verbatim: u).tag(u)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
    }

    private func sizeParts() -> [(String, String)] {
        let raw = condition.value
        let chunks: [String]
        if condition.op == "between" {
            chunks = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        } else {
            chunks = [raw]
        }
        return chunks.map(splitNumberUnit)
    }

    private func splitNumberUnit(_ s: String) -> (String, String) {
        let trimmed = s.trimmingCharacters(in: .whitespaces).uppercased()
        for u in ["GB", "MB", "KB", "B"] where trimmed.hasSuffix(u) {
            let num = trimmed.dropLast(u.count).trimmingCharacters(in: .whitespaces)
            return (num, u)
        }
        // 没单位:当成纯字节(默认 unit 用 MB,因为新建条件时空值要给个合理默认)
        return (trimmed, "MB")
    }

    private func setSizePart(part: Int, number: String, unit: String) {
        var ps = sizeParts()
        while ps.count <= part {
            ps.append(("", "MB"))
        }
        ps[part] = (number, unit)
        if condition.op == "between" {
            let combined = ps.prefix(2).map { joinNumberUnit($0.0, $0.1) }.joined(separator: ",")
            condition.value = combined
        } else {
            condition.value = joinNumberUnit(ps[0].0, ps[0].1)
        }
    }

    private func joinNumberUnit(_ n: String, _ u: String) -> String {
        let trimmed = n.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        return "\(trimmed)\(u)"
    }

    // MARK: dateAdded

    @ViewBuilder
    private var dateField: some View {
        switch condition.op {
        case "inLastDays", "notInLastDays":
            let daysBinding = Binding<Int>(
                get: { Int(condition.value) ?? 0 },
                set: { newValue in
                    let clamped = max(0, min(newValue, 36500))
                    condition.value = clamped == 0 ? "" : String(clamped)
                }
            )
            let textBinding = Binding<String>(
                get: { condition.value },
                set: { txt in
                    // 保留 String 输入(让用户任意输入数字),Stepper 操作时
                    // 会经过 daysBinding 自动 clamp。
                    condition.value = txt.filter { $0.isNumber }
                }
            )
            HStack(spacing: 6) {
                TextField("", text: textBinding, prompt: Text(verbatim: "30"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 70)
                Stepper("", value: daysBinding, in: 0...36500)
                    .labelsHidden()
                    .controlSize(.small)
                Text("rule.condition.date.daysSuffix")
                    .foregroundStyle(.secondary)
            }
        case "before", "after":
            let dateBinding = Binding<Date>(
                get: {
                    Self.dateParser.date(from: condition.value) ?? Date()
                },
                set: { d in
                    condition.value = Self.dateParser.string(from: d)
                }
            )
            DatePicker("", selection: dateBinding, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
        default:
            TextField("value", text: $condition.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// ConditionEvaluator 用 ISO8601DateFormatter 解析,这里用同一个 formatter
    /// 序列化 Date,保证写出去的字符串能被运行时正确读回。
    private static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    /// 种类(kind)字段是 8 个枚举值的封闭集合,UI 用 Picker 比 TextField 友好。
    /// `is any of` 时支持多选 —— 用逗号分隔的字符串存。这里给单选 Picker;
    /// `is any of` 用 Menu 加 toggle 实现多选(每个 bucket 一个 checkmark)。
    private var kindValuePicker: some View {
        Group {
            if condition.op == "isAnyOf" {
                kindMultiSelect
            } else {
                Picker("", selection: $condition.value) {
                    Text(verbatim: "—").tag("")
                    ForEach(Self.kindOptions, id: \.0) { (key, _) in
                        Text(verbatim: KindDisplay.localizedName(key)).tag(key)
                    }
                }
                .labelsHidden()
            }
        }
    }

    /// is any of:每个 bucket 一个开关。文本里存逗号分隔的 key 列表。
    private var kindMultiSelect: some View {
        let selected = Set(condition.value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let validKeys = Set(Self.kindOptions.map { $0.0 })
        let summary: String = selected.isEmpty
            ? NSLocalizedString("rule.condition.kind.empty", value: "Choose kinds…", comment: "")
            : selected
                .filter { validKeys.contains($0) }
                .map { KindDisplay.localizedName($0) }
                .sorted()
                .joined(separator: ", ")
        return Menu(summary) {
            ForEach(Self.kindOptions, id: \.0) { (key, _) in
                Button {
                    var s = selected
                    if s.contains(key) { s.remove(key) } else { s.insert(key) }
                    condition.value = s.sorted().joined(separator: ",")
                } label: {
                    HStack {
                        if selected.contains(key) {
                            Image(systemName: "checkmark")
                        }
                        Text(verbatim: KindDisplay.localizedName(key))
                    }
                }
            }
        }
    }

    /// FileNode.kind 可能取的全部 bucket 值。第二项是 fallback 英文名,
    /// 实际显示走 KindDisplay.localizedName(走 kind.<key> 本地化键)。
    private static let kindOptions: [(String, String)] = [
        ("image",    "Image"),
        ("movie",    "Movie"),
        ("audio",    "Audio"),
        ("document", "Document"),
        ("archive",  "Archive"),
        ("code",     "Code"),
        ("text",     "Text"),
        ("folder",   "Folder"),
        ("other",    "Other"),
    ]
}
