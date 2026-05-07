import SwiftUI
import SwiftData

/// 单个文件 action 的元数据 + 派发逻辑。
/// 同一个 action 在右键菜单 / Inspector 操作面板 / 快捷键三处共用,改一处即三
/// 处生效;实际执行始终走 `FileActions` 那一层,避免重复实现。
enum FileActionKind: String, CaseIterable, Identifiable {
    // primary
    case open
    case reveal
    case quickLook
    // transfer
    case copyTo
    case moveTo
    case copyPath
    case rename
    case share
    // destructive
    case moveToTrash

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .open:        return "Open With Default App"
        case .reveal:      return "Reveal in Finder"
        case .quickLook:   return "Quick Look"
        case .copyTo:      return "Copy to…"
        case .moveTo:      return "Move to…"
        case .copyPath:    return "Copy Path"
        case .rename:      return "Rename…"
        case .share:       return "Share…"
        case .moveToTrash: return "Move to Trash"
        }
    }

    /// SF Symbol。Inspector 操作面板拿来画图标,右键菜单暂不画(NSMenuItem
    /// 的 image 处理跟 SwiftUI 不一致,留空让 macOS 自己处理)。
    var systemImage: String {
        switch self {
        case .open:        return "arrow.up.right.square"
        case .reveal:      return "folder"
        case .quickLook:   return "eye"
        case .copyTo:      return "doc.on.doc"
        case .moveTo:      return "arrow.right.doc.on.clipboard"
        case .copyPath:    return "doc.on.clipboard"
        case .rename:      return "pencil"
        case .share:       return "square.and.arrow.up"
        case .moveToTrash: return "trash"
        }
    }

    var role: ButtonRole? {
        self == .moveToTrash ? .destructive : nil
    }

    /// 快捷键提示文本(显示在 Inspector 操作按钮的右侧)。跟
    /// FileContextMenu 的 FileActionShortcut modifier 保持一一对应 ——
    /// 改快捷键时两处都要改。
    ///
    /// 视觉上模仿 macOS 右键菜单:符号间留半空格,Space 走 NSLocalizedString
    /// 让中文系统渲染成"空格键"。
    var shortcutHint: String? {
        switch self {
        case .open:        return "⌘ O"
        case .reveal:      return "⌘ R"
        case .quickLook:   return NSLocalizedString("shortcut.space",
                                value: "Space", comment: "")
        case .copyTo:      return "⇧ ⌘ C"
        case .moveTo:      return "⇧ ⌘ M"
        case .copyPath:    return "⌥ ⌘ C"
        case .rename:      return "↩"
        case .share:       return "⇧ ⌘ S"
        case .moveToTrash: return "⌘ ⌫"
        }
    }

    /// 该 action 是否对当前选择有效(比如 rename 只支持单选)。
    func isAvailable(for files: [FileNode]) -> Bool {
        guard !files.isEmpty else { return false }
        switch self {
        case .rename: return files.count == 1
        default:      return true
        }
    }

    /// 实际执行 —— 全部委托给 FileActions / QuickLookCoordinator,确保跟
    /// 右键菜单的行为保持一致。
    @MainActor
    func perform(_ files: [FileNode], modelContext: ModelContext) {
        switch self {
        case .open:
            FileActions.open(files)
        case .reveal:
            FileActions.reveal(files)
        case .quickLook:
            let urls = files.compactMap { FileActions.url(for: $0) }
            if !urls.isEmpty { QuickLookCoordinator.shared.show(urls: urls) }
        case .copyTo:
            FileActions.copyTo(files)
        case .moveTo:
            FileActions.moveTo(files, modelContext: modelContext)
        case .copyPath:
            FileActions.copyPath(files)
        case .rename:
            if let f = files.first { FileActions.rename(f, modelContext: modelContext) }
        case .share:
            FileActions.share(files, from: nil)
        case .moveToTrash:
            FileActions.moveToTrash(files, modelContext: modelContext)
        }
    }
}

/// 把 actions 按显示语义分成三组:
/// 1. **primary**:打开 / 在 Finder 显示 / Quick Look —— 高频
/// 2. **transfer**:复制 / 移动 / 复制路径 / 重命名 / 共享 —— 中频
/// 3. **destructive**:移到废纸篓 —— 红色,单独成组
///
/// 右键菜单和 Inspector 都按这三组渲染,中间塞 Divider 视觉分隔。
enum FileActionGroup: CaseIterable {
    case primary, transfer, destructive

    var kinds: [FileActionKind] {
        switch self {
        case .primary:     return [.open, .reveal, .quickLook]
        case .transfer:    return [.copyTo, .moveTo, .copyPath, .rename, .share]
        case .destructive: return [.moveToTrash]
        }
    }
}
