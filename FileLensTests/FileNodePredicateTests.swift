import XCTest
import SwiftData
@testable import FileLens

/// 验证 per-workspace store 上的 FileNode predicate 行为。
/// 用户实测:sidebar 用 `fetchCount` + `$0.isPresent` 返回 2,
/// 但 ContentView 用 `fetch` + 同 predicate 返回 238。这个测试隔离原因。
final class FileNodePredicateTests: XCTestCase {

    private var container: ModelContainer!

    override func setUpWithError() throws {
        // 跟 WorkspaceStoreManager.store 同样的 schema 配置:per-workspace store
        // 只放 FileNode + FileTag,没有 Workspace/Rule。
        let schema = Schema([FileNode.self, FileTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
    }

    @MainActor
    private func insertNodes(present: Int, vanished: Int) throws {
        let ctx = container.mainContext
        let wsID = UUID()
        for i in 0..<present {
            let node = FileNode(
                workspaceID: wsID,
                relativePath: "p\(i).txt", name: "p\(i).txt", ext: "txt",
                size: 0, dateAdded: .now, dateModified: .now, kind: "text",
                isPresent: true
            )
            ctx.insert(node)
        }
        for i in 0..<vanished {
            let node = FileNode(
                workspaceID: wsID,
                relativePath: "v\(i).txt", name: "v\(i).txt", ext: "txt",
                size: 0, dateAdded: .now, dateModified: .now, kind: "text",
                isPresent: false
            )
            ctx.insert(node)
        }
        try ctx.save()
    }

    @MainActor
    func test_fetchCount_with_isPresent_predicate() async throws {
        try insertNodes(present: 238, vanished: 5)
        let ctx = container.mainContext

        let descriptor = FetchDescriptor<FileNode>(
            predicate: #Predicate<FileNode> { $0.isPresent == true }
        )

        let countViaFetchCount = try ctx.fetchCount(descriptor)
        let countViaFetch = (try ctx.fetch(descriptor)).count

        XCTAssertEqual(countViaFetch, 238, "fetch + .count 应该返回所有 isPresent=true 的节点")
        XCTAssertEqual(countViaFetchCount, 238, "fetchCount 应该跟 fetch.count 一致;不一致就是 SwiftData predicate bug")
    }

    /// 也测一下 sidebar 用的 boolean-only predicate 形式 `$0.isPresent`,
    /// 看跟 `$0.isPresent == true` 是否行为一致。
    @MainActor
    func test_fetchCount_with_boolean_only_predicate() async throws {
        try insertNodes(present: 238, vanished: 5)
        let ctx = container.mainContext

        let descriptor = FetchDescriptor<FileNode>(
            predicate: #Predicate<FileNode> { $0.isPresent }
        )

        let count = try ctx.fetchCount(descriptor)
        XCTAssertEqual(count, 238, "boolean-only predicate `$0.isPresent` 应该等价于 `== true`")
    }
}
