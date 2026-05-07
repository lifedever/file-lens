import Foundation
import SwiftData
import AppKit

/// JSON 序列化 + 反序列化「工作区 + 规则」配置,用于换 Mac 时迁移或备份。
/// 故意不导出 bookmarkData(security-scoped,跨机器无效)和 files / tags
/// (这些是索引产物,导入后 FSEvents 会自动重建);只导出用户配置本身。
enum ConfigIO {
    private static let schemaVersion = 1

    // MARK: - DTO

    struct ConfigFile: Codable {
        var version: Int
        var exportedAt: Date
        var workspaces: [WorkspaceDTO]
    }

    struct WorkspaceDTO: Codable {
        var name: String
        var folderPath: String
        var sortOrder: Int
        var rules: [RuleDTO]
    }

    struct RuleDTO: Codable {
        var name: String
        var color: String
        var enabled: Bool
        var priority: Int
        var combinator: String
        var isBuiltIn: Bool
        var conditions: [ConditionDTO]
    }

    struct ConditionDTO: Codable {
        var field: String
        var op: String
        var value: String
    }

    // MARK: - Export

    @MainActor
    static func exportConfig(container: ModelContainer) throws -> Data {
        let context = ModelContext(container)
        let workspaces = try context.fetch(
            FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder),
                                                SortDescriptor(\.createdAt)])
        )
        let dto = ConfigFile(
            version: schemaVersion,
            exportedAt: .now,
            workspaces: workspaces.map { ws in
                WorkspaceDTO(
                    name: ws.name,
                    folderPath: ws.folderPath,
                    sortOrder: ws.sortOrder,
                    rules: ws.rules
                        .sorted(by: { $0.priority < $1.priority })
                        .map { rule in
                            RuleDTO(
                                name: rule.name,
                                color: rule.color,
                                enabled: rule.enabled,
                                priority: rule.priority,
                                combinator: rule.combinator,
                                isBuiltIn: rule.isBuiltIn,
                                conditions: rule.conditions.map {
                                    ConditionDTO(field: $0.field, op: $0.op, value: $0.value)
                                }
                            )
                        }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(dto)
    }

    /// 用 NSSavePanel 让用户选保存位置,默认文件名带日期。
    /// 返回写入的 URL;如果用户取消,返回 nil。
    @MainActor
    @discardableResult
    static func exportConfigToFile(container: ModelContainer) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("config.export.title",
                                        value: "Export FileLens Configuration",
                                        comment: "")
        panel.allowedContentTypes = [.json]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        panel.nameFieldStringValue = "filelens-config-\(formatter.string(from: .now)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try exportConfig(container: container)
        try data.write(to: url)
        return url
    }

    // MARK: - Import

    /// 从 NSOpenPanel 选取 JSON,返回解析结果。调用方负责对返回的 ConfigFile
    /// 调用 applyImport(_:container:) 完成实际写入。两步分离方便 UI 在写入前
    /// 先做预览或确认。
    @MainActor
    static func importConfigFromFile() throws -> ConfigFile? {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("config.import.title",
                                        value: "Import FileLens Configuration",
                                        comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfigFile.self, from: data)
    }

    /// 把解码出的配置写入 ModelContext。重名工作区(folderPath 一致)直接跳过 ——
    /// 不覆盖,避免误删用户当前已建好的规则;用户应该先手动移除目标工作区再导入。
    /// 返回新建工作区数(0 = 全部已存在或失败)。
    @MainActor
    @discardableResult
    static func applyImport(_ config: ConfigFile, container: ModelContainer) throws -> Int {
        guard config.version <= schemaVersion else {
            throw NSError(domain: "FileLens.ConfigIO", code: 1, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "config.import.unsupportedVersion",
                    value: "This config file is from a newer FileLens. Please update the app first.",
                    comment: "")
            ])
        }

        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<Workspace>())) ?? []
        let existingPaths = Set(existing.map(\.folderPath))

        var imported = 0
        for wsDTO in config.workspaces where !existingPaths.contains(wsDTO.folderPath) {
            // 尝试为已知路径创建 bookmark。如果路径不再存在就跳过这个 workspace ——
            // 用户跨机迁移时该让他重新拖拽文件夹再选。
            let url = URL(fileURLWithPath: wsDTO.folderPath)
            guard FileManager.default.fileExists(atPath: url.path),
                  let bookmark = try? BookmarkStore.makeBookmark(for: url) else { continue }

            let ws = Workspace(
                name: wsDTO.name,
                folderPath: wsDTO.folderPath,
                bookmarkData: bookmark,
                sortOrder: wsDTO.sortOrder
            )
            context.insert(ws)
            for ruleDTO in wsDTO.rules {
                let rule = Rule(
                    name: ruleDTO.name,
                    color: ruleDTO.color,
                    enabled: ruleDTO.enabled,
                    priority: ruleDTO.priority,
                    combinator: ruleDTO.combinator,
                    isBuiltIn: ruleDTO.isBuiltIn
                )
                rule.workspace = ws
                for condDTO in ruleDTO.conditions {
                    rule.conditions.append(
                        Condition(field: condDTO.field, op: condDTO.op, value: condDTO.value)
                    )
                }
                context.insert(rule)
            }
            imported += 1
        }
        try context.save()
        return imported
    }
}
