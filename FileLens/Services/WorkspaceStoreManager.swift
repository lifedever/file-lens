import Foundation
import SwiftData
import SwiftUI

/// 把 SwiftData 数据切成两层:
///
/// 1. **catalog**(单一 SQLite):`Workspace` + `Rule` + `Condition`。
///    几条到几百条记录,加载快、操作快。UI sidebar 的 `@Query<Workspace>`
///    走这一层。
///
/// 2. **per-workspace store**(每个 workspace 一个 SQLite):
///    `FileNode` + `FileTag`。同一个 workspace 的几万到几十万文件互不
///    干扰别的 workspace。删除 workspace = `rm` 这个文件,**毫秒级**,
///    不管文件多少。
///
/// 文件路径:
/// ```
/// Application Support/<bundleID>/
///   catalog.sqlite
///   workspaces/
///     {workspace-uuid}.sqlite
/// ```
@MainActor
final class WorkspaceStoreManager {
    let catalog: ModelContainer
    let baseDir: URL
    let storesDir: URL
    private var stores: [UUID: ModelContainer] = [:]

    init() throws {
        // 测试 host 启动:用 in-memory 全套,不碰磁盘
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let schema = Schema([Workspace.self, Rule.self, Condition.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            self.catalog = try ModelContainer(for: schema, configurations: config)
            self.baseDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileLens-test-\(UUID().uuidString)")
            self.storesDir = baseDir.appendingPathComponent("workspaces")
            try FileManager.default.createDirectory(at: storesDir, withIntermediateDirectories: true)
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.FileLens"
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        self.baseDir = appSupport.appendingPathComponent(bundleID)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // catalog
        let catalogURL = baseDir.appendingPathComponent("catalog.sqlite")
        let catalogSchema = Schema([Workspace.self, Rule.self, Condition.self])
        let catalogConfig = ModelConfiguration(schema: catalogSchema, url: catalogURL)
        self.catalog = try ModelContainer(for: catalogSchema, configurations: catalogConfig)

        self.storesDir = baseDir.appendingPathComponent("workspaces")
        try FileManager.default.createDirectory(at: storesDir, withIntermediateDirectories: true)
    }

    /// 拿到 workspace 自己的 store。第一次调用懒加载创建。
    func store(for workspaceID: UUID) throws -> ModelContainer {
        if let existing = stores[workspaceID] { return existing }
        let url = storesDir.appendingPathComponent("\(workspaceID.uuidString).sqlite")
        let schema = Schema([FileNode.self, FileTag.self])
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: config)
        stores[workspaceID] = container
        return container
    }

    /// 真正的"删除":卸载内存 container + `rm` 三个 SQLite 文件(主 + WAL + SHM)。
    /// 毫秒级,跟文件数无关。
    func deleteStore(for workspaceID: UUID) {
        stores.removeValue(forKey: workspaceID)
        let base = storesDir.appendingPathComponent("\(workspaceID.uuidString).sqlite")
        try? FileManager.default.removeItem(at: base)
        // SQLite WAL/SHM sidecar 文件命名是 `<base>-wal` 和 `<base>-shm`(注意是 `-`)
        let wal = base.deletingLastPathComponent()
            .appendingPathComponent(base.lastPathComponent + "-wal")
        let shm = base.deletingLastPathComponent()
            .appendingPathComponent(base.lastPathComponent + "-shm")
        try? FileManager.default.removeItem(at: wal)
        try? FileManager.default.removeItem(at: shm)
    }
}

private struct WorkspaceStoreManagerKey: EnvironmentKey {
    @MainActor
    static let defaultValue: WorkspaceStoreManager? = nil
}

extension EnvironmentValues {
    var workspaceStoreManager: WorkspaceStoreManager? {
        get { self[WorkspaceStoreManagerKey.self] }
        set { self[WorkspaceStoreManagerKey.self] = newValue }
    }
}
