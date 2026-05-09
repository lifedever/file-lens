import Foundation
import SwiftData

/// Workspace 生命周期管理。新架构(per-workspace SQLite)下:
/// - scan 走 catalog 元数据 + per-workspace store FileNode/FileTag
/// - 删除 workspace 直接 `rm` 那个 SQLite 文件,毫秒级
/// - 扫描串行,FIFO 队列,切走/切回不打断
@MainActor
final class WorkspaceCoordinator {
    private let storeManager: WorkspaceStoreManager
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?

    private var scanTask: Task<Void, Never>?
    private var scanningWorkspaceID: UUID?
    private var scanQueue: [QueueEntry] = []

    private struct QueueEntry {
        let uuid: UUID
        let forceRescan: Bool
        let silent: Bool
    }

    /// 本次 app 会话已 scan 过的 workspace。重启后置空。
    private var activatedWorkspaceIDs: Set<UUID> = []

    init(storeManager: WorkspaceStoreManager) {
        self.storeManager = storeManager
    }

    func activate(workspace: Workspace, forceRescan: Bool = false) async {
        stopWatcher()

        let wsUUID = workspace.id

        // FileActions / FileThumbnail / Inspector 用全局注册表查 file URL
        // (跨 store 后 FileNode 不再持有 workspace 关系)。
        if let (folder, _) = try? BookmarkStore.resolve(bookmark: workspace.bookmarkData) {
            FileURLResolver.shared.register(workspaceID: wsUUID, folderURL: folder)
        }

        let needsScan = forceRescan || !activatedWorkspaceIDs.contains(wsUUID)

        if needsScan {
            // 跨重启复用持久化数据。store 已有数据(fileCount > 0)走 silent
            // scan —— UI 立刻 ready 显示老数据,后台对账完(增删 FileNode)
            // 再实时刷。FSEvents watcher 在 app 跑着时实时同步,silent scan
            // 补 app 没跑期间漏掉的变化。
            //
            // 关键前提:view 层已完全 snapshot 化(FileSnapshot,无 @Model
            // 引用),mainContext 上 FileNode 属性变化不再触发 view rerender
            // 风暴;sidebar 也改读 ws.fileCount 缓存(scan 末尾才写),scan
            // 期间不会高频 fetchCount。silent scan 中间不 save,只末尾一次
            // (FileIndexer 内部已实现),把 SwiftData 通知压到一次。
            //
            // 空库(首次添加)或 forceRescan(右键重索引)走 silent=false,
            // 显示进度页正常 scan。
            let hasExistingData = workspace.fileCount > 0
            let silent = hasExistingData && !forceRescan
            enqueueScan(uuid: wsUUID, forceRescan: forceRescan, silent: silent)
            ensureScanRunning()
        }

        guard workspace.watchEnabled else { return }
        startWatcher(for: workspace)
    }

    func reindex(workspace: Workspace) async {
        enqueueScan(uuid: workspace.id, forceRescan: true, silent: false)
        ensureScanRunning()
    }

    /// 删除 workspace —— 三步:mark pending(立即 UI 消失) → cancel scan → 删
    /// 文件 + 删 catalog 行(毫秒级)。
    func removeWorkspace(_ workspace: Workspace) async {
        let wsUUID = workspace.id
        scanQueue.removeAll { $0.uuid == wsUUID }
        activatedWorkspaceIDs.remove(wsUUID)
        FileURLResolver.shared.unregister(workspaceID: wsUUID)

        // 1. 标记 pendingDeletion + save。UI 当帧消失。
        workspace.isPendingDeletion = true
        try? storeManager.catalog.mainContext.save()

        // 2. 取消正在跑的 scan、停 watcher
        if scanningWorkspaceID == wsUUID {
            scanTask?.cancel()
            if let scanTask { _ = await scanTask.value }
        }
        stopWatcher()

        // 3. 直接 rm per-workspace SQLite 文件。不管几万几十万 FileNode,
        //    毫秒级。
        storeManager.deleteStore(for: wsUUID)

        // 4. 删 catalog 行(workspace + cascade rules + conditions)。catalog
        //    是小表,删一行不会卡。
        let ctx = storeManager.catalog.mainContext
        ctx.delete(workspace)
        try? ctx.save()
    }

    func deactivate() async {
        stopWatcher()
    }

    // MARK: - Private

    private func enqueueScan(uuid: UUID, forceRescan: Bool, silent: Bool) {
        if scanningWorkspaceID == uuid, !forceRescan { return }
        if let existingIdx = scanQueue.firstIndex(where: { $0.uuid == uuid }) {
            if forceRescan {
                scanQueue[existingIdx] = QueueEntry(
                    uuid: uuid, forceRescan: true,
                    silent: scanQueue[existingIdx].silent && silent
                )
            }
            return
        }
        scanQueue.append(QueueEntry(uuid: uuid, forceRescan: forceRescan, silent: silent))
    }

    private func ensureScanRunning() {
        guard scanTask == nil else { return }
        guard let entry = scanQueue.first else { return }
        scanQueue.removeFirst()

        scanningWorkspaceID = entry.uuid
        let uuid = entry.uuid
        let silent = entry.silent
        let manager = storeManager

        scanTask = Task { @MainActor [weak self] in
            let indexer = FileIndexer(storeManager: manager)
            do {
                try await indexer.scan(workspaceID: uuid, silent: silent)
                self?.activatedWorkspaceIDs.insert(uuid)
            } catch is CancellationError {
                // 用户切走 / 删除 → 正常 cancel
            } catch {
                print("Scan failed: \(error)")
            }
            self?.scanTask = nil
            self?.scanningWorkspaceID = nil
            self?.ensureScanRunning()
        }
    }

    private func startWatcher(for workspace: Workspace) {
        let (folderURL, _) = (try? BookmarkStore.resolve(bookmark: workspace.bookmarkData))
            ?? (URL(fileURLWithPath: "/"), false)
        let w = FolderWatcher()
        watcher = w
        let uuid = workspace.id
        watchTask = Task { [weak self] in
            for await _ in w.start(url: folderURL) {
                guard let self else { break }
                self.enqueueScan(uuid: uuid, forceRescan: true, silent: true)
                self.ensureScanRunning()
            }
        }
    }

    private func stopWatcher() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }
}
