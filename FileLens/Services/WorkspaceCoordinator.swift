import Foundation
import SwiftData

/// Manages per-workspace lifecycle: initial scan + live FSEvents subscription.
/// Owned by ContentView; restarts when the selected workspace changes.
@MainActor
final class WorkspaceCoordinator {
    private let container: ModelContainer
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?
    /// 本次 app 会话中已扫描过的 workspace。第二次切回来时直接跳过全量
    /// scan,只重接 watcher —— 切换文件夹的可感知延迟从 ~1s 降到 ~10ms。
    /// trade-off:在被切走期间外部修改不会被自动同步(FSEvents 那时没在
    /// 听该目录),用户得右键 Reindex 显式触发刷新。设置变更/手动 Reindex
    /// 都走 forceRescan=true 路径,绕开缓存。
    private var activatedWorkspaceIDs: Set<UUID> = []

    init(container: ModelContainer) {
        self.container = container
    }

    func activate(workspace: Workspace, forceRescan: Bool = false) async {
        await deactivate()

        let indexer = FileIndexer(container: container)
        let needsScan = forceRescan || !activatedWorkspaceIDs.contains(workspace.id)
        if needsScan {
            do {
                try await indexer.scan(workspace: workspace)
                activatedWorkspaceIDs.insert(workspace.id)
            } catch {
                print("Initial scan failed: \(error)")
                return
            }
        }

        // workspace.watchEnabled = false 时(网络盘 / 巨大目录的兜底),
        // 不挂 FSEvents 监听,只在用户手动刷新时再扫一次。
        guard workspace.watchEnabled else { return }

        let (folderURL, _) = (try? BookmarkStore.resolve(bookmark: workspace.bookmarkData)) ?? (URL(fileURLWithPath: "/"), false)
        let w = FolderWatcher()
        watcher = w
        watchTask = Task { [weak self] in
            for await _ in w.start(url: folderURL) {
                guard let self else { break }
                _ = self
                do {
                    try await indexer.scan(workspace: workspace)
                } catch {
                    print("Re-scan failed: \(error)")
                }
            }
        }
    }

    /// 手动触发一次 rescan(右键 → 立即重索引)。
    func reindex(workspace: Workspace) async {
        let indexer = FileIndexer(container: container)
        do {
            try await indexer.scan(workspace: workspace)
            activatedWorkspaceIDs.insert(workspace.id)
        } catch {
            print("Manual reindex failed: \(error)")
        }
    }

    func deactivate() async {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }
}
