import Foundation
import SwiftData

/// 启动时清理两类残留:
///
/// 1. **stuck scanning 状态**:scan 中途 app 强杀,`indexStateRaw=1` 持久化下来,
///    重启后 UI 一打开就显示假进度条。重置回 0。
/// 2. **未完成的 deletion**:用户上次点删除但 rm + save 没跑完就关了 app,
///    catalog 里还有 `isPendingDeletion=true` 的 Workspace 行 + workspaces/
///    目录下还有那个 SQLite 文件。把它们真删了。
@MainActor
enum WorkspaceStateRecovery {
    static func runIfNeeded(storeManager: WorkspaceStoreManager) {
        let ctx = storeManager.catalog.mainContext

        // 1. 同步:重置卡 scanning 的 workspace
        do {
            let stuckDescriptor = FetchDescriptor<Workspace>(
                predicate: #Predicate<Workspace> { $0.indexStateRaw == 1 }
            )
            let stuck = try ctx.fetch(stuckDescriptor)
            if !stuck.isEmpty {
                for ws in stuck {
                    ws.indexStateRaw = 0
                    ws.indexProgressDone = 0
                    ws.indexProgressTotal = 0
                }
                try ctx.save()
                print("WorkspaceStateRecovery: reset \(stuck.count) stuck workspace state(s)")
            }
        } catch {
            print("WorkspaceStateRecovery: stuck-state reset failed: \(error)")
        }

        // 2. 同步(快,因为 rm 文件 + 删 catalog 行毫秒级):清理未完成的删除
        do {
            let pendingDescriptor = FetchDescriptor<Workspace>(
                predicate: #Predicate<Workspace> { $0.isPendingDeletion }
            )
            let pending = try ctx.fetch(pendingDescriptor)
            guard !pending.isEmpty else { return }
            for ws in pending {
                storeManager.deleteStore(for: ws.id)
                ctx.delete(ws)
            }
            try ctx.save()
            print("WorkspaceStateRecovery: finished deleting \(pending.count) pending workspace(s)")
        } catch {
            print("WorkspaceStateRecovery: pending-deletion cleanup failed: \(error)")
        }
    }
}
