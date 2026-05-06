import SwiftUI

// MARK: - Focused-value plumbing
//
// SwiftUI commands (the macOS menu bar) can't directly call into a specific
// View's state. The textbook pattern: the View publishes "actions" via
// `.focusedValue(\.key, closure)`, and Commands reads them with
// `@FocusedValue(\.key)`. When the focused window's view tree provides the
// closure, the menu item is enabled and routes to it.

private struct AddFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct NewRuleActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
private struct CheckUpdateActionKey: FocusedValueKey {
    typealias Value = () -> Void
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
}

// MARK: - Menu commands

struct FileLensCommands: Commands {
    @FocusedValue(\.addFolderAction) private var addFolder
    @FocusedValue(\.newRuleAction) private var newRule
    @FocusedValue(\.checkUpdateAction) private var checkUpdate

    var body: some Commands {
        // File menu — append to the system "New" group so our items sit
        // alongside macOS's standard new-window items.
        CommandGroup(after: .newItem) {
            Button {
                addFolder?()
            } label: {
                Text("Add Folder…")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(addFolder == nil)

            Button {
                newRule?()
            } label: {
                Text("New Rule…")
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newRule == nil)
        }

        // App menu — "Check for Updates…" near About.
        CommandGroup(after: .appInfo) {
            Button {
                checkUpdate?()
            } label: {
                Text("Check for Updates…")
            }
            .disabled(checkUpdate == nil)
        }
    }
}
