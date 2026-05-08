import SwiftUI
import SwiftData

/// 单个 workspace 的配置面板。从 sidebar 右键 → 文件夹设置 唤起。
///
/// 视觉模仿 macOS System Settings:顶部 icon-above-label 的 tab toolbar
/// (通用 / 范围 / 排除),下方是当前 tab 的 Form 内容,底部一行 Cancel / Save。
/// **没用 SwiftUI `TabView`** —— 它在 sheet 里 fall back 到紧凑文字标签,
/// 跟 Settings scene 那种大图标 toolbar 长得不一样;且 TabView 会强制按
/// 第一帧最高的 tab 撑高,空白区难以收敛。换成自定义 tab bar + switch
/// 之后 sheet 高度直接跟当前 tab 内容走,看起来干净。
struct WorkspaceSettingsView: View {
    @Bindable var workspace: Workspace
    /// 关闭时回调,通常是父页拿来重扫的钩子。
    let onSaved: (Workspace) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case general, scope, exclude }
    @State private var tab: Tab = .general

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
            tabBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            tabButton(.general,
                      label: "workspace.settings.tab.general",
                      icon: "gear")
            tabButton(.scope,
                      label: "workspace.settings.tab.scope",
                      icon: "square.3.layers.3d")
            tabButton(.exclude,
                      label: "workspace.settings.tab.exclude",
                      icon: "minus.circle")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func tabButton(_ value: Tab,
                           label: LocalizedStringKey,
                           icon: String) -> some View {
        let active = tab == value
        Button {
            tab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
            }
            .frame(width: 80)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: generalTab
        case .scope:   scopeTab
        case .exclude: excludeTab
        }
    }

    /// 通用:显示名 / 路径 / 监听变化。
    private var generalTab: some View {
        Form {
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
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 范围:递归 / 深度 / 是否包含文件夹。
    private var scopeTab: some View {
        Form {
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
            } footer: {
                Text(scopeFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 排除:此 workspace 专属忽略文件夹列表。
    private var excludeTab: some View {
        Form {
            Section {
                TextEditor(text: $extraIgnoreFolders)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 200)
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 一行 "label + 控件" 的 row。等价于 LabeledContent 但不会因为 Form
    /// 对 LabeledContent 做特殊布局而把 trailing 控件压窄(Stepper 之类的
    /// 复合控件被压会被截成竖排)。
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
