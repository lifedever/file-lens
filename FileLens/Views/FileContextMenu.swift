import SwiftUI
import SwiftData

/// Shared right-click menu for the file table and grid. All entries operate
/// on the passed-in `files` array, so multi-selection just works.
///
/// 实际 action 列表 + 派发逻辑在 `FileActionRegistry`,Inspector 也用同一份。
/// 这里只负责把 registry 渲染成 NSMenu(SwiftUI Button 加 keyboardShortcut
/// 自动转 NSMenuItem keyEquivalent)。
struct FileContextMenu: View {
    let files: [FileNode]
    let modelContext: ModelContext

    var body: some View {
        if files.isEmpty {
            EmptyView()
        } else {
            ForEach(Array(FileActionGroup.allCases.enumerated()), id: \.offset) { idx, group in
                ForEach(group.kinds) { kind in
                    if kind.isAvailable(for: files) {
                        Button(role: kind.role) {
                            kind.perform(files, modelContext: modelContext)
                        } label: {
                            Text(kind.titleKey)
                        }
                        .modifier(FileActionShortcut(kind: kind))
                    }
                }
                if idx < FileActionGroup.allCases.count - 1 {
                    Divider()
                }
            }
        }
    }
}

/// 给每个 action 挂上键盘快捷键。SwiftUI Button 上的 `.keyboardShortcut`
/// 在 NSMenuItem 上自动渲染成 keyEquivalent,菜单右侧就出现"⌘O"等提示。
private struct FileActionShortcut: ViewModifier {
    let kind: FileActionKind

    func body(content: Content) -> some View {
        switch kind {
        case .open:        content.keyboardShortcut("o", modifiers: .command)
        case .reveal:      content.keyboardShortcut("r", modifiers: .command)
        case .quickLook:   content.keyboardShortcut(.space, modifiers: [])
        case .copyFiles:   content.keyboardShortcut("c", modifiers: .command)
        case .duplicate:   content.keyboardShortcut("d", modifiers: .command)
        case .copyTo:      content.keyboardShortcut("c", modifiers: [.command, .shift])
        case .moveTo:      content.keyboardShortcut("m", modifiers: [.command, .shift])
        case .copyPath:    content.keyboardShortcut("c", modifiers: [.command, .option])
        case .rename:      content.keyboardShortcut(.return, modifiers: [])
        case .share:       content.keyboardShortcut("s", modifiers: [.command, .shift])
        case .moveToTrash: content.keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
