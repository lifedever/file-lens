import SwiftUI

// MARK: - Focused-value plumbing

private struct AddFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct NewRuleActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct CheckUpdateActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct ActiveWorkspaceNameKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    var addFolderAction: (() -> Void)? {
        get { self[AddFolderActionKey.self] }
        set { self[AddFolderActionKey.self] = newValue }
    }
    var newRuleAction: (() -> Void)? {
        get { self[NewRuleActionKey.self] }
        set { self[NewRuleActionKey.self] = newValue }
    }
    var checkUpdateAction: (() -> Void)? {
        get { self[CheckUpdateActionKey.self] }
        set { self[CheckUpdateActionKey.self] = newValue }
    }
    /// Name of the workspace currently shown in the active window. nil means
    /// no workspace is selected — workspace-scoped commands (e.g. New Rule)
    /// should disable.
    var activeWorkspaceName: String? {
        get { self[ActiveWorkspaceNameKey.self] }
        set { self[ActiveWorkspaceNameKey.self] = newValue }
    }
}

// MARK: - Menu commands

struct FileLensCommands: Commands {
    @FocusedValue(\.addFolderAction) private var addFolder
    @FocusedValue(\.newRuleAction) private var newRule
    @FocusedValue(\.checkUpdateAction) private var checkUpdate
    @FocusedValue(\.activeWorkspaceName) private var workspaceName
    /// Mirrored in SidebarView so the two stay in sync — UserDefaults is
    /// the single source of truth.
    @AppStorage("filelens.showEmptyRules") private var showEmptyRules: Bool = true

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                addFolder?()
            } label: {
                Text("Add Folder…")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(addFolder == nil)

            // New Rule's label includes the workspace it'll be created in,
            // so users can see at a glance where ⌘N will land. Disabled
            // when no workspace is active, since rules can't exist
            // detached from a workspace.
            Button {
                newRule?()
            } label: {
                if let name = workspaceName {
                    Text(verbatim: String(format:
                        NSLocalizedString("menu.newRuleIn.format",
                            value: "New Rule in “%@”…",
                            comment: ""), name))
                } else {
                    Text("New Rule…")
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newRule == nil || workspaceName == nil)
        }

        CommandGroup(after: .appInfo) {
            Button {
                UpdateService.checkAndPrompt()
            } label: {
                Text("Check for Updates…")
            }
        }

        // 在 View 菜单 sidebar 项之后插一个 "Show Empty Rules" 开关。
        // 必须包在 Section 里 —— 否则它会跟系统的 "Enter Full Screen"
        // (后者带 image 在 leading 列)挤在同一 NSMenu state-column 段
        // 里,checkmark 列宽和 image 列宽不一致,文本起始位置就对不齐。
        // Section 等价于强制插一个 NSMenuItem.separator,让我们的开关
        // 单独成段,自己的 state-column 自己算对齐,跟系统项互不干扰。
        CommandGroup(after: .sidebar) {
            Section {
                Toggle(isOn: $showEmptyRules) {
                    Text("Show Empty Rules")
                }
            }
        }
    }
}
