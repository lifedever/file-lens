import XCTest
import SwiftData
@testable import FileLens

final class ConfigIOTests: XCTestCase {

    // 用 in-memory 容器避免污染真实数据库,每个 case 都拿到干净状态。
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workspace.self, Rule.self, Condition.self,
                             FileNode.self, FileTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    @MainActor
    private func seed(_ container: ModelContainer) throws {
        let ctx = ModelContext(container)
        let bookmark = Data()  // 测试中用空 bookmark,导出/导入流程不读它
        let ws = Workspace(name: "Downloads", folderPath: "/tmp/downloads",
                           bookmarkData: bookmark, sortOrder: 100)
        ctx.insert(ws)

        let rule = Rule(name: "Images", color: "#10B981", enabled: true,
                        priority: 10, combinator: "any", isBuiltIn: true)
        rule.workspace = ws
        rule.conditions.append(Condition(field: "kind", op: "is", value: "image"))
        ctx.insert(rule)

        try ctx.save()
    }

    // MARK: - Export

    @MainActor
    func test_export_serializes_workspace_and_rules() throws {
        let container = try makeContainer()
        try seed(container)

        let data = try ConfigIO.exportConfig(container: container)
        let decoded = try JSONDecoder.iso8601().decode(ConfigIO.ConfigFile.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.workspaces.count, 1)
        let ws = try XCTUnwrap(decoded.workspaces.first)
        XCTAssertEqual(ws.name, "Downloads")
        XCTAssertEqual(ws.folderPath, "/tmp/downloads")
        XCTAssertEqual(ws.sortOrder, 100)
        XCTAssertEqual(ws.rules.count, 1)
        let rule = try XCTUnwrap(ws.rules.first)
        XCTAssertEqual(rule.name, "Images")
        XCTAssertEqual(rule.color, "#10B981")
        XCTAssertEqual(rule.priority, 10)
        XCTAssertEqual(rule.conditions.first?.field, "kind")
        XCTAssertEqual(rule.conditions.first?.op, "is")
        XCTAssertEqual(rule.conditions.first?.value, "image")
    }

    // MARK: - Import

    @MainActor
    func test_import_creates_workspace_when_path_exists() throws {
        // 用临时目录确保 folderPath 真的存在 + bookmark 能创建出来
        let tmp = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let container = try makeContainer()
        let cfg = ConfigIO.ConfigFile(
            version: 1, exportedAt: .now,
            workspaces: [
                ConfigIO.WorkspaceDTO(
                    name: tmp.lastPathComponent,
                    folderPath: tmp.path,
                    sortOrder: 100,
                    rules: [
                        ConfigIO.RuleDTO(
                            name: "Images", color: "#10B981",
                            enabled: true, priority: 10,
                            combinator: "any", isBuiltIn: true,
                            conditions: [
                                ConfigIO.ConditionDTO(field: "kind", op: "is", value: "image")
                            ]
                        )
                    ]
                )
            ]
        )

        let count = try ConfigIO.applyImport(cfg, container: container)
        XCTAssertEqual(count, 1)

        let ctx = ModelContext(container)
        let workspaces = try ctx.fetch(FetchDescriptor<Workspace>())
        XCTAssertEqual(workspaces.count, 1)
        let ws = try XCTUnwrap(workspaces.first)
        XCTAssertEqual(ws.folderPath, tmp.path)
        XCTAssertEqual(ws.rules.count, 1)
        XCTAssertEqual(ws.rules.first?.conditions.first?.value, "image")
    }

    @MainActor
    func test_import_skips_workspace_when_path_missing() throws {
        let container = try makeContainer()
        let cfg = ConfigIO.ConfigFile(
            version: 1, exportedAt: .now,
            workspaces: [
                ConfigIO.WorkspaceDTO(
                    name: "GhostFolder",
                    folderPath: "/this/path/should/never/exist/\(UUID().uuidString)",
                    sortOrder: 100,
                    rules: []
                )
            ]
        )
        let count = try ConfigIO.applyImport(cfg, container: container)
        XCTAssertEqual(count, 0,
                       "missing folderPath should skip,不应该污染数据库")

        let ctx = ModelContext(container)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Workspace>()).count, 0)
    }

    @MainActor
    func test_import_skips_workspace_when_path_already_exists() throws {
        let tmp = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let container = try makeContainer()
        // 先放一个同 folderPath 的工作区进去
        let ctx = ModelContext(container)
        let bookmark = (try? BookmarkStore.makeBookmark(for: tmp)) ?? Data()
        let pre = Workspace(name: "Old", folderPath: tmp.path,
                            bookmarkData: bookmark, sortOrder: 50)
        ctx.insert(pre)
        try ctx.save()

        let cfg = ConfigIO.ConfigFile(
            version: 1, exportedAt: .now,
            workspaces: [
                ConfigIO.WorkspaceDTO(
                    name: "New", folderPath: tmp.path, sortOrder: 200, rules: []
                )
            ]
        )
        let count = try ConfigIO.applyImport(cfg, container: container)
        XCTAssertEqual(count, 0, "重复 folderPath 不应覆盖已有工作区")

        let workspaces = try ctx.fetch(FetchDescriptor<Workspace>())
        XCTAssertEqual(workspaces.count, 1)
        XCTAssertEqual(workspaces.first?.name, "Old", "原有工作区应保留")
    }

    @MainActor
    func test_import_rejects_unsupported_version() throws {
        let container = try makeContainer()
        let cfg = ConfigIO.ConfigFile(
            version: 999, exportedAt: .now, workspaces: []
        )
        XCTAssertThrowsError(try ConfigIO.applyImport(cfg, container: container))
    }

    // MARK: - Round-trip

    @MainActor
    func test_export_then_import_round_trips_data() throws {
        let tmp = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 来源容器:用临时路径以保证 import 端 folderPath 存在
        let source = try makeContainer()
        let srcCtx = ModelContext(source)
        let bookmark = (try? BookmarkStore.makeBookmark(for: tmp)) ?? Data()
        let ws = Workspace(name: tmp.lastPathComponent, folderPath: tmp.path,
                           bookmarkData: bookmark, sortOrder: 100)
        srcCtx.insert(ws)
        let rule = Rule(name: "Code", color: "#059669", enabled: true,
                        priority: 70, combinator: "any", isBuiltIn: true)
        rule.workspace = ws
        rule.conditions.append(Condition(field: "extension", op: "isAnyOf", value: "swift,rs"))
        srcCtx.insert(rule)
        try srcCtx.save()

        let exported = try ConfigIO.exportConfig(container: source)
        let cfg = try JSONDecoder.iso8601().decode(ConfigIO.ConfigFile.self, from: exported)

        let dest = try makeContainer()
        let imported = try ConfigIO.applyImport(cfg, container: dest)
        XCTAssertEqual(imported, 1)

        let destCtx = ModelContext(dest)
        let workspaces = try destCtx.fetch(FetchDescriptor<Workspace>())
        XCTAssertEqual(workspaces.count, 1)
        let dws = try XCTUnwrap(workspaces.first)
        XCTAssertEqual(dws.name, tmp.lastPathComponent)
        XCTAssertEqual(dws.sortOrder, 100)
        XCTAssertEqual(dws.rules.count, 1)
        XCTAssertEqual(dws.rules.first?.color, "#059669")
        XCTAssertEqual(dws.rules.first?.conditions.first?.value, "swift,rs")
    }

    // MARK: - helpers

    private func makeTempFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filelens-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
