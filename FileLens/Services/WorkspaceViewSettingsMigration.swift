import Foundation
import SwiftData

/// 一次性把全局 @AppStorage 里的视图相关设置(viewMode / gridIconSize /
/// FileTable.columnCustomizationJSON)迁移到 per-workspace 字段。让老用户
/// 升级后所有现有 workspace 保持原状,独立性从这一刻起开始累积。
///
/// 老的 UserDefaults key 故意 *不* 删除 —— 万一用户回滚旧 build 还能读到。
@MainActor
enum WorkspaceViewSettingsMigration {
    private static let migratedKey = "filelens.viewMigration.v1.done"

    /// `defaults` 参数留出 testing 注入点。生产路径调用方传 `.standard`。
    static func runIfNeeded(context: ModelContext,
                            defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migratedKey) else { return }

        let globalViewModeRaw = defaults.object(forKey: "filelens.viewMode") as? Int ?? 2
        let rawIconSize = defaults.object(forKey: "filelens.gridIconSize") as? Double ?? 80
        let globalGridIconSize = min(160, max(48, rawIconSize))
        let globalColumnJSON = defaults.string(forKey: "FileTable.columnCustomizationJSON") ?? ""

        if let workspaces = try? context.fetch(FetchDescriptor<Workspace>()) {
            for ws in workspaces {
                ws.viewModeRaw = globalViewModeRaw
                ws.gridIconSize = globalGridIconSize
                ws.tableColumnCustomizationJSON = globalColumnJSON
            }
            try? context.save()
        }
        defaults.set(true, forKey: migratedKey)
    }
}
