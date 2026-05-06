import SwiftUI
import SwiftData
import AppKit

/// Shared right-click menu for the file table and grid. All entries operate
/// on the passed-in `files` array, so multi-selection just works.
///
/// Keeping the menu here means there's one place to add or rename actions,
/// and Table/Grid don't drift apart visually.
struct FileContextMenu: View {
    let files: [FileNode]
    let modelContext: ModelContext

    var body: some View {
        if files.isEmpty {
            EmptyView()
        } else {
            // 每条 Button 上挂 .keyboardShortcut,SwiftUI 会把它转成
            // NSMenuItem 的 keyEquivalent —— 菜单右侧就出现快捷键提示,
            // 跟 ⌘K 触发的 NSMenu 视觉一致。
            Button("Open With Default App") { FileActions.open(files) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Reveal in Finder") { FileActions.reveal(files) }
                .keyboardShortcut("r", modifiers: .command)
            Button("Quick Look") {
                let urls = files.compactMap { FileActions.url(for: $0) }
                if !urls.isEmpty { QuickLookCoordinator.shared.show(urls: urls) }
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Copy to…") { FileActions.copyTo(files) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Move to…") { FileActions.moveTo(files, modelContext: modelContext) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Copy Path") { FileActions.copyPath(files) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            // Rename is a single-file action — Finder's batch rename is a much
            // larger feature than v1 needs.
            if files.count == 1 {
                Button("Rename…") { FileActions.rename(files[0], modelContext: modelContext) }
                    .keyboardShortcut(.return, modifiers: [])
            }
            Button("Share…") { FileActions.share(files, from: nil) }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Move to Trash", role: .destructive) {
                FileActions.moveToTrash(files, modelContext: modelContext)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
