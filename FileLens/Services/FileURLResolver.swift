import Foundation

/// FileNode 现在不再持有 `workspace: Workspace?` 关系(per-workspace SQLite
/// 之间没法跨 store 引用)。但 `FileActions.url(for:)` 是 static 函数,需要
/// 一种办法把 `workspaceID -> 文件夹 URL` 映射出来。
///
/// 解决方案:全局只读注册表。`WorkspaceCoordinator` 在 activate 时注册,
/// removeWorkspace 时反注册。FileActions / FileThumbnail / Inspector 等通过
/// 共享单例查 URL。
@MainActor
final class FileURLResolver {
    static let shared = FileURLResolver()

    private var folders: [UUID: URL] = [:]

    private init() {}

    func register(workspaceID: UUID, folderURL: URL) {
        folders[workspaceID] = folderURL
    }

    func unregister(workspaceID: UUID) {
        folders.removeValue(forKey: workspaceID)
    }

    func url(for file: FileNode) -> URL? {
        guard let folder = folders[file.workspaceID] else { return nil }
        return folder.appendingPathComponent(file.relativePath)
    }

    func url(for snap: FileSnapshot) -> URL? {
        guard let folder = folders[snap.workspaceID] else { return nil }
        return folder.appendingPathComponent(snap.relativePath)
    }

    func folderURL(for workspaceID: UUID) -> URL? {
        folders[workspaceID]
    }
}
