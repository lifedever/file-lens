import Foundation
import SwiftData

/// One-time migration that rewrites rule names from their English
/// localization keys ("Documents", "Images", …) to the user's localized
/// form ("文档", "图片", …). Anything created after the BuiltInRules
/// localization fix already uses localized names, so this only touches
/// stale data from older installs.
///
/// We migrate FileTag.name in lockstep so tag-count lookups continue to
/// match against the renamed rules.
enum RuleNameMigration {
    private static let migratedKey = "filelens.ruleNamesMigrated.v1"

    /// English keys shipped with `BuiltInRules` historically. Names that
    /// match one of these are considered "untranslated" and get rewritten
    /// to their localized form via NSLocalizedString.
    private static let knownKeys: Set<String> = [
        "Installers", "Images", "Videos", "Audio", "PDF",
        "Documents", "Archives", "Code", "Screenshots",
        "Large files", "New arrivals", "Stale", "Downloading"
    ]

    @MainActor
    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }

        let context = ModelContext(container)
        var changed = false

        if let rules = try? context.fetch(FetchDescriptor<Rule>()) {
            for rule in rules where knownKeys.contains(rule.name) {
                rule.name = NSLocalizedString(rule.name, value: rule.name, comment: "")
                changed = true
            }
        }

        if let tags = try? context.fetch(FetchDescriptor<FileTag>()) {
            for tag in tags where knownKeys.contains(tag.name) {
                tag.name = NSLocalizedString(tag.name, value: tag.name, comment: "")
                changed = true
            }
        }

        if changed { try? context.save() }
        defaults.set(true, forKey: migratedKey)
    }
}

/// Workspace sortOrder 迁移:1.0.2 之前的工作区只有 createdAt,新加的字段
/// 默认值是 0。第一次启动时按 createdAt 升序赋值 100 / 200 / 300…,后续
/// 拖拽行为就有了一个可预测的基底。
@MainActor
enum WorkspaceSortOrderMigration {
    private static let migratedKey = "filelens.workspaceSortOrderMigrated.v1"

    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        let context = ModelContext(container)
        if let workspaces = try? context.fetch(
            FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.createdAt)])
        ), !workspaces.isEmpty,
           workspaces.allSatisfy({ $0.sortOrder == 0 }) {
            for (idx, ws) in workspaces.enumerated() {
                ws.sortOrder = (idx + 1) * 100
            }
            try? context.save()
        }
        defaults.set(true, forKey: migratedKey)
    }
}

/// 1.1.1 把 `iso` 加进了 Archives 内置规则。但老用户数据库里的 Archives
/// 规则 condition.value 仍是旧字符串,iso 文件不会被自动归类。这里启动时
/// 检测一次:对所有 isBuiltIn=true 且 value 不含 "iso" 的 extension/isAnyOf
/// 条件,把 iso 追加进去。只看是否含 "iso",不假设 value 是默认串,避免
/// 用户自己改过的也被覆盖。
@MainActor
enum ArchivesISOMigration {
    private static let migratedKey = "filelens.archivesISOMigrated.v1"

    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        let context = ModelContext(container)
        guard let conditions = try? context.fetch(FetchDescriptor<Condition>()) else {
            defaults.set(true, forKey: migratedKey)
            return
        }
        var changed = false
        for cnd in conditions where cnd.field == "extension" && cnd.op == "isAnyOf" {
            // 只动 isBuiltIn=true 的规则下挂的条件,避免碰用户自定义规则
            guard cnd.rule?.isBuiltIn == true else { continue }
            let exts = cnd.value.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            // 包含常见压缩格式 + 不含 iso → 给它补上
            let archiveExts: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2"]
            guard !Set(exts).intersection(archiveExts).isEmpty,
                  !exts.contains("iso") else { continue }
            cnd.value = cnd.value + ",iso"
            changed = true
        }
        if changed { try? context.save() }
        defaults.set(true, forKey: migratedKey)
    }
}

/// 1.0.2 引入了 per-workspace `recursive` 字段,默认值 `false`。但老用户的
/// workspace 之前一直是全量递归扫描的,新默认值会让他们的"工作区里突然变
/// 少了文件"。这里第一次启动时把所有现有 workspace 标记成 `recursive = true`,
/// 保留旧行为;之后用户可在 workspace 设置里改。
@MainActor
enum WorkspaceRecursiveMigration {
    private static let migratedKey = "filelens.workspaceRecursiveMigrated.v1"

    static func runIfNeeded(container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        let context = ModelContext(container)
        if let workspaces = try? context.fetch(FetchDescriptor<Workspace>()) {
            for ws in workspaces {
                ws.recursive = true
            }
            try? context.save()
        }
        defaults.set(true, forKey: migratedKey)
    }
}
