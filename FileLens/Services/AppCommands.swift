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

        // Drops a "Show Empty Rules" toggle into the View menu, alongside
        // the system-provided "Show/Hide Sidebar" item.
        CommandGroup(after: .sidebar) {
            Toggle(isOn: $showEmptyRules) {
                Text("Show Empty Rules")
            }
        }
    }
}
