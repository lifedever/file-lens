import AppKit
import SwiftData

/// "Cmd+K" entry point for showing the same context menu the user gets from
/// right-clicking the row. We build an NSMenu programmatically (closures
/// wrapped in a tiny target object) and pop it up at the cursor — so it
/// behaves and looks exactly like the right-click menu.
enum ActionMenu {
    @MainActor
    static func popUp(for files: [FileNode], modelContext: ModelContext) {
        guard !files.isEmpty else { return }
        let menu = buildMenu(for: files, modelContext: modelContext)

        // popUpContextMenu(_:with:for:) reads the event's window location to
        // position the menu, but a ⌘K key event reports (0,0) — that's why
        // the menu kept landing in the top-left. popUp(positioning:at:in:)
        // takes an explicit point, so we hand it the cursor's location
        // converted into the content view's coordinate space.
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let mouseInScreen = NSEvent.mouseLocation
        let mouseInWindow = window.convertPoint(fromScreen: mouseInScreen)
        let mouseInView   = view.convert(mouseInWindow, from: nil)
        menu.popUp(positioning: nil, at: mouseInView, in: view)
    }

    // MARK: - Building

    @MainActor
    private static func buildMenu(for files: [FileNode], modelContext: ModelContext) -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item("Open With Default App", key: "o") {
            FileActions.open(files)
        })
        menu.addItem(item("Reveal in Finder", key: "r") {
            FileActions.reveal(files)
        })
        menu.addItem(item("Quick Look", key: " ") {
            let urls = files.compactMap { FileActions.url(for: $0) }
            if !urls.isEmpty { QuickLookCoordinator.shared.show(urls: urls) }
        })

        menu.addItem(.separator())

        menu.addItem(item("Copy to…",
                          key: "c",
                          modifiers: [.command, .shift]) { FileActions.copyTo(files) })
        menu.addItem(item("Move to…",
                          key: "m",
                          modifiers: [.command, .shift]) { FileActions.moveTo(files, modelContext: modelContext) })
        menu.addItem(item("Copy Path",
                          key: "c",
                          modifiers: [.command, .option]) { FileActions.copyPath(files) })
        if files.count == 1 {
            // Return alone (no modifier) matches Finder's rename convention.
            menu.addItem(item("Rename…",
                              key: "\r",
                              modifiers: []) {
                FileActions.rename(files[0], modelContext: modelContext)
            })
        }
        menu.addItem(item("Share…",
                          key: "s",
                          modifiers: [.command, .shift]) { FileActions.share(files, from: nil) })

        menu.addItem(.separator())

        let trash = item("Move to Trash",
                         key: String(Character(UnicodeScalar(NSDeleteCharacter)!)),
                         modifiers: .command) {
            FileActions.moveToTrash(files, modelContext: modelContext)
        }
        menu.addItem(trash)

        return menu
    }

    @MainActor
    private static func item(
        _ key: String,
        key keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let title = NSLocalizedString(key, value: key, comment: "")
        let target = ClosureTarget(action)
        let mi = NSMenuItem(title: title,
                            action: #selector(ClosureTarget.run),
                            keyEquivalent: keyEquivalent)
        mi.target = target
        mi.keyEquivalentModifierMask = modifiers
        // representedObject keeps the closure target alive while the menu
        // is shown — NSMenuItem only holds target weakly.
        mi.representedObject = target
        return mi
    }

}

private final class ClosureTarget: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor @objc func run() { action() }
}
