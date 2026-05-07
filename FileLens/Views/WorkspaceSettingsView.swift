import SwiftUI
import SwiftData

/// 单个 workspace 的配置面板。从 sidebar 右键 → 文件夹设置 唤起。
///
/// 关闭时如果改了任何字段,会触发一次 rescan(走当前的协调器),让递归 /
/// 深度 / 排除列表的变更立刻生效。
struct WorkspaceSettingsView: View {
    @Bindable var workspace: Workspace
    /// 关闭时回调,通常是父页拿来重扫的钩子。
    let onSaved: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 把递归这一栏抽成本地 state,避免 toggle 跟 maxDepth 字段实时绑定时
    /// 频繁触发 SwiftData 写入,关窗时再统一回写。
    @State private var initialSnapshot: Snapshot
    @State private var displayName: String
    @State private var recursive: Bool
    @State private var maxDepthText: String
    @State private var includeFolders: Bool
    @State private var extraIgnoreFolders: String
    @State private var watchEnabled: Bool

    init(workspace: Workspace, onSaved: @escaping (Workspace) -> Void) {
        self.workspace = workspace
        self.onSaved = onSaved
        let snap = Snapshot(workspace)
        _initialSnapshot = State(initialValue: snap)
        _displayName = State(initialValue: snap.displayName)
        _recursive = State(initialValue: snap.recursive)
        _maxDepthText = State(initialValue: snap.maxDepth == 0 ? "" : String(snap.maxDepth))
        _includeFolders = State(initialValue: snap.includeFolders)
        _extraIgnoreFolders = State(initialValue: snap.extraIgnoreFolders)
        _watchEnabled = State(initialValue: snap.watchEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                // 显示名 + 路径(只读)。不用 LabeledContent —— 它在 Form.grouped
                // 里会把 trailing 控件区压窄,带 Stepper 之类的复合控件就被
                // 挤成竖排。手动 HStack 完全可控。TextField 用 prompt 而不是
                // title,否则 Form 会把 title 字符串当成第二个 label 渲染。
                Section {
                    labeledRow("workspace.settings.displayName") {
                        TextField("",
                                  text: $displayName,
                                  prompt: Text(verbatim: workspace.name))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                    }
                    labeledRow("workspace.settings.path") {
                        Text(verbatim: workspace.folderPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                // 递归 + 深度 + 是否包含文件夹
                Section {
                    Toggle("workspace.settings.recursive", isOn: $recursive)
                    if recursive {
                        labeledRow("workspace.settings.maxDepth") {
                            HStack(spacing: 6) {
                                TextField("",
                                          text: $maxDepthText,
                                          prompt: Text("workspace.settings.maxDepth.placeholder"))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(width: 80)
                                Stepper("", value: depthBinding, in: 0...20)
                                    .labelsHidden()
                                    .controlSize(.small)
                            }
                        }
                    }
                    Toggle("workspace.settings.includeFolders", isOn: $includeFolders)
                } header: {
                    Text("workspace.settings.section.scope")
                } footer: {
                    Text(scopeFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 该 workspace 专属排除项
                Section {
                    TextEditor(text: $extraIgnoreFolders)
                        .font(.callout.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 64, maxHeight: 100)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                } header: {
                    Text("workspace.settings.extraIgnore.label")
                        .textCase(nil)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                } footer: {
                    Text("workspace.settings.extraIgnore.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 监听
                Section {
                    Toggle("workspace.settings.watchEnabled", isOn: $watchEnabled)
                } footer: {
                    Text("workspace.settings.watchEnabled.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            // 内容很短(尤其 recursive 关掉时),用 scrollDisabled + fixedSize
            // 让 sheet 高度自适应,免得空 padding 顶出多余的滚动条。
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header / Footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("workspace.settings.title")
                    .font(.headline)
                Text(verbatim: workspace.effectiveName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// 一行 "label + 控件" 的 row。等价于 LabeledContent 但不会因为 Form
    /// 对 LabeledContent 做特殊布局而把 trailing 控件压窄(Stepper 之类的
    /// 复合控件被压会被截成竖排)。我们手动 HStack,完全可控。
    @ViewBuilder
    private func labeledRow<Trailing: View>(
        _ key: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(key)
            Spacer()
            trailing()
        }
    }

    private var scopeFooter: String {
        if !recursive {
            return NSLocalizedString("workspace.settings.scope.nonrecursive.hint",
                value: "Only top-level files in the folder are indexed.",
                comment: "")
        }
        if maxDepth == 0 {
            return NSLocalizedString("workspace.settings.scope.unlimited.hint",
                value: "All subfolders, no depth limit.",
                comment: "")
        }
        return String(format: NSLocalizedString("workspace.settings.scope.limited.hint.format",
            value: "Subfolders up to %lld level(s) deep.",
            comment: ""), Int64(maxDepth))
    }

    // MARK: - State helpers

    /// maxDepthText 是字符串(给 TextField 用),Stepper 要 Int —— 用一个
    /// 计算属性绑定双向同步。空串视为 0(无限制)。
    private var depthBinding: Binding<Int> {
        Binding(
            get: { maxDepth },
            set: { newValue in
                let clamped = max(0, min(newValue, 20))
                maxDepthText = clamped == 0 ? "" : String(clamped)
            }
        )
    }

    private var maxDepth: Int {
        Int(maxDepthText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// 关窗时把所有字段写回 workspace,如果有变更触发回调让外层 rescan。
    private func save() {
        let newDepth = max(0, min(maxDepth, 20))
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespaces)

        workspace.displayName = trimmedDisplay
        workspace.recursive = recursive
        workspace.maxDepth = newDepth
        workspace.includeFolders = includeFolders
        workspace.extraIgnoreFolders = extraIgnoreFolders
        workspace.watchEnabled = watchEnabled

        // 只有"会影响 scan 结果或 watcher 状态"的字段变了才触发回调。
        // displayName 改了不需要 rescan(只是显示)。
        let needsRescan =
            recursive != initialSnapshot.recursive ||
            newDepth != initialSnapshot.maxDepth ||
            includeFolders != initialSnapshot.includeFolders ||
            extraIgnoreFolders != initialSnapshot.extraIgnoreFolders ||
            watchEnabled != initialSnapshot.watchEnabled

        if needsRescan {
            onSaved(workspace)
        }
    }

    private struct Snapshot {
        let displayName: String
        let recursive: Bool
        let maxDepth: Int
        let includeFolders: Bool
        let extraIgnoreFolders: String
        let watchEnabled: Bool

        init(_ ws: Workspace) {
            displayName = ws.displayName
            recursive = ws.recursive
            maxDepth = ws.maxDepth
            includeFolders = ws.includeFolders
            extraIgnoreFolders = ws.extraIgnoreFolders
            watchEnabled = ws.watchEnabled
        }
    }
}
