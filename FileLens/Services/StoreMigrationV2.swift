import Foundation
import SwiftData

/// 一次性迁移:把老版本(<= 1.1.0 某个临界点)的 SwiftData 数据从单一
/// `default.store` 搬到新架构 `catalog.sqlite` + `workspaces/<uuid>.sqlite`。
///
/// **背景**:某次重构把 store 拆成两层(见 `WorkspaceStoreManager`),但没
/// 写迁移代码。结果老用户升级后启动 app 看到的是 0 个 workspace,以为数据
/// 丢了 —— 其实数据还完好躺在 default.store 里,只是新版本完全不读它。
///
/// **本迁移做的事**:
/// 1. 检测 `<bundleID>/default.store` 存在
/// 2. 用当前 Schema 打开它(SwiftData lightweight migration 处理 schema 差异)
/// 3. fetch [Workspace] (带 rules + conditions)
/// 4. 按 UUID 去重,catalog 里已有的同 UUID workspace 跳过
/// 5. 逐个 deep copy 到 catalog(workspace + 所有 rule + 所有 condition)
/// 6. 把 default.store / -wal / -shm 改名为 .legacy 防止重入,也作 safety backup
///
/// **不迁移**:`FileNode` / `FileTag` —— 它们要进 per-workspace store
/// `workspaces/<uuid>.sqlite`,跨 store 关系复杂。Workspace 迁过去后
/// FileIndexer 会按 folderPath + 现有 rule 自动重扫一遍,几秒就能恢复全部
/// 文件索引和分类。用户感知到的损失:之前手动的"打开 / 滚动位置"之类
/// 短期状态。所有 rule 分类、文件夹结构、显示名、排除规则、bookmark
/// 权限——全部保留。
///
/// **失败策略**:任何一步失败都不抛 —— 让 app 用空 catalog 启动,用户可以
/// 手动添加 workspace(原 default.store 依然 intact 保留为 .legacy,数据没
/// 丢,只是这次没自动恢复)。在静态初始化里 throw 会让 app 启动就崩溃,
/// 不可接受。
@MainActor
enum StoreMigrationV2 {
    private static let migratedKey = "filelens.storeMigrationV2.completed"

    static func runIfNeeded(baseDir: URL, catalog: ModelContainer) {
        let defaults = UserDefaults.standard
        // 双重 guard:UserDefaults 标志 + .legacy 文件存在 —— 两个都判,
        // 防止 defaults 被清(测试 / 用户重置)时重复跑。
        if defaults.bool(forKey: migratedKey) { return }

        let oldStoreURL = baseDir.appendingPathComponent("default.store")
        let legacyMarker = baseDir.appendingPathComponent("default.store.legacy")

        guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
            // 没 default.store —— 全新用户或者已经迁过的老用户(被 rename 了)。
            // 标记完成,下次启动直接 return。
            defaults.set(true, forKey: migratedKey)
            return
        }

        if FileManager.default.fileExists(atPath: legacyMarker.path) {
            // .legacy 已存在但 .store 也还在 —— 罕见(可能上次 rename 中途失败)。
            // 不要覆盖 .legacy(那是 safety backup),也不要再迁(可能造成重复)。
            // 标记完成,人工排查。
            NSLog("StoreMigrationV2: both default.store and .legacy exist, skipping")
            defaults.set(true, forKey: migratedKey)
            return
        }

        // 用当前 Schema 打开老 store。SwiftData 会做 lightweight migration ——
        // 老 store 的 ZWORKSPACE 少几列(filecount/viewmode/...),都是 additive
        // 加上默认值。ZRULE/ZCONDITION schema 一致。老 store 里还有 ZFILENODE/
        // ZFILETAG 表但新 Schema 没声明这些 Model —— SwiftData/Core Data 对
        // "数据库里有 schema 不知道的表" 是无视的,不会失败。
        let schema = Schema([Workspace.self, Rule.self, Condition.self])
        let legacyConfig = ModelConfiguration(schema: schema, url: oldStoreURL)

        let legacyContainer: ModelContainer
        do {
            legacyContainer = try ModelContainer(for: schema, configurations: legacyConfig)
        } catch {
            NSLog("StoreMigrationV2: failed to open legacy store: %@", error.localizedDescription)
            // 打不开就别动 —— 老文件保留原样,标记完成防重试。
            defaults.set(true, forKey: migratedKey)
            return
        }

        let legacyContext = ModelContext(legacyContainer)
        let catalogContext = ModelContext(catalog)

        let oldWorkspaces: [Workspace]
        do {
            oldWorkspaces = try legacyContext.fetch(FetchDescriptor<Workspace>())
        } catch {
            NSLog("StoreMigrationV2: failed to fetch legacy workspaces: %@", error.localizedDescription)
            defaults.set(true, forKey: migratedKey)
            return
        }

        guard !oldWorkspaces.isEmpty else {
            // 老 store 是空的(可能用户从未建过 workspace)—— rename 防重入。
            renameLegacyFiles(at: oldStoreURL)
            defaults.set(true, forKey: migratedKey)
            return
        }

        let existingIDs: Set<UUID> = Set(
            ((try? catalogContext.fetch(FetchDescriptor<Workspace>())) ?? []).map(\.id)
        )

        var migrated = 0
        for oldWS in oldWorkspaces where !existingIDs.contains(oldWS.id) {
            let newWS = Workspace(
                id: oldWS.id,
                name: oldWS.name,
                folderPath: oldWS.folderPath,
                bookmarkData: oldWS.bookmarkData,
                createdAt: oldWS.createdAt,
                sortOrder: oldWS.sortOrder,
                recursive: oldWS.recursive,
                maxDepth: oldWS.maxDepth,
                displayName: oldWS.displayName,
                extraIgnoreFolders: oldWS.extraIgnoreFolders,
                watchEnabled: oldWS.watchEnabled,
                includeFolders: oldWS.includeFolders,
                viewModeRaw: oldWS.viewModeRaw,
                gridIconSize: oldWS.gridIconSize,
                tableColumnCustomizationJSON: oldWS.tableColumnCustomizationJSON
            )
            catalogContext.insert(newWS)

            for oldRule in oldWS.rules {
                let newRule = Rule(
                    id: oldRule.id,
                    name: oldRule.name,
                    color: oldRule.color,
                    enabled: oldRule.enabled,
                    priority: oldRule.priority,
                    combinator: oldRule.combinator,
                    isBuiltIn: oldRule.isBuiltIn
                )
                newRule.workspace = newWS
                catalogContext.insert(newRule)

                for oldCond in oldRule.conditions {
                    let newCond = Condition(
                        id: oldCond.id,
                        field: oldCond.field,
                        op: oldCond.op,
                        value: oldCond.value
                    )
                    newCond.rule = newRule
                    catalogContext.insert(newCond)
                }
            }
            migrated += 1
        }

        do {
            try catalogContext.save()
        } catch {
            // 写 catalog 失败 —— 不要 rename 老文件,留个后路下次再试。
            // (但也不要 set migrated key,避免永久跳过。)
            NSLog("StoreMigrationV2: catalog save failed: %@", error.localizedDescription)
            return
        }

        // 成功 —— rename 老文件防重入,作为 safety backup 永久保留。
        renameLegacyFiles(at: oldStoreURL)
        defaults.set(true, forKey: migratedKey)
        NSLog("StoreMigrationV2: migrated %lld workspaces", Int64(migrated))
    }

    /// 把 `default.store` + WAL + SHM 三件套 rename 成 `.legacy` 后缀。
    /// 顺序:wal → shm → 主文件最后(同 StoreMigration 注释里的 crash-safe
    /// 顺序——主文件存在 = 库就绪,最后动)。
    private static func renameLegacyFiles(at storeURL: URL) {
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent  // "default.store"
        let pairs: [(String, String)] = [
            ("\(base)-wal", "\(base).legacy-wal"),
            ("\(base)-shm", "\(base).legacy-shm"),
            (base, "\(base).legacy"),
        ]
        for (from, to) in pairs {
            let src = dir.appendingPathComponent(from)
            let dst = dir.appendingPathComponent(to)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            if FileManager.default.fileExists(atPath: dst.path) {
                // 不覆盖既有 .legacy —— 那是更老的安全备份。给当前的加时间戳。
                let ts = Int(Date().timeIntervalSince1970)
                let alt = dir.appendingPathComponent("\(to).\(ts)")
                try? FileManager.default.moveItem(at: src, to: alt)
            } else {
                try? FileManager.default.moveItem(at: src, to: dst)
            }
        }
    }
}
