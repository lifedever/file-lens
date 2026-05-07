import XCTest
import SwiftData
@testable import FileLens

final class FileIndexerTests: XCTestCase {

    private var tmp: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let schema = Schema([Workspace.self, Rule.self, Condition.self, FileNode.self, FileTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    @MainActor
    private func makeWorkspace() throws -> Workspace {
        let ctx = container.mainContext
        let bookmark = try BookmarkStore.makeBookmark(for: tmp)
        let ws = Workspace(name: "tmp", folderPath: tmp.path, bookmarkData: bookmark)
        ctx.insert(ws)
        return ws
    }

    @MainActor
    func test_scan_creates_FileNode_per_file() async throws {
        try "hello".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try Data([0xFF]).write(to: tmp.appendingPathComponent("b.png"))

        let ws = try makeWorkspace()
        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        try container.mainContext.save()
        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(Set(nodes.map(\.name)), Set(["a.txt", "b.png"]))
    }

    @MainActor
    func test_scan_marks_missing_files_as_not_present() async throws {
        let f = tmp.appendingPathComponent("vanish.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        try FileManager.default.removeItem(at: f)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(nodes.first?.isPresent, false)
    }

    @MainActor
    func test_scan_skips_hidden_files() async throws {
        try "x".write(to: tmp.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        try "y".write(to: tmp.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(nodes.map(\.name), ["visible.txt"])
    }

    @MainActor
    func test_scan_applies_rules() async throws {
        try Data([0xFF]).write(to: tmp.appendingPathComponent("photo.png"))

        let ws = try makeWorkspace()
        for r in BuiltInRules.all() {
            r.workspace = ws
            container.mainContext.insert(r)
        }

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        let tags = nodes.first?.tags.map(\.name) ?? []
        // BuiltInRules 在创建时本地化 name,断言对当前 locale 计算后的形式
        let imagesLocalized = NSLocalizedString("Images", value: "Images", comment: "")
        XCTAssertTrue(tags.contains(imagesLocalized))
    }

    @MainActor
    func test_scan_nonRecursive_skips_subfolders() async throws {
        try "top".write(to: tmp.appendingPathComponent("top.txt"),
                        atomically: true, encoding: .utf8)
        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "deep".write(to: sub.appendingPathComponent("deep.txt"),
                         atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        ws.recursive = false
        ws.includeFolders = false   // 显式只测文件,不混入文件夹条目

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(nodes.map(\.name), ["top.txt"])
    }

    @MainActor
    func test_scan_recursive_unlimited_walks_full_tree() async throws {
        try "top".write(to: tmp.appendingPathComponent("top.txt"),
                        atomically: true, encoding: .utf8)
        let l1 = tmp.appendingPathComponent("l1")
        let l2 = l1.appendingPathComponent("l2")
        let l3 = l2.appendingPathComponent("l3")
        try FileManager.default.createDirectory(at: l3, withIntermediateDirectories: true)
        try "x".write(to: l1.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        try "x".write(to: l2.appendingPathComponent("b.txt"),
                      atomically: true, encoding: .utf8)
        try "x".write(to: l3.appendingPathComponent("c.txt"),
                      atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        ws.recursive = true
        ws.maxDepth = 0   // 无限制
        ws.includeFolders = false

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(Set(nodes.map(\.name)),
                       Set(["top.txt", "a.txt", "b.txt", "c.txt"]))
    }

    @MainActor
    func test_scan_maxDepth_caps_recursion() async throws {
        // 顶层 = depth 1, l1 里的文件 = depth 2, l2 里的文件 = depth 3
        try "top".write(to: tmp.appendingPathComponent("top.txt"),
                        atomically: true, encoding: .utf8)
        let l1 = tmp.appendingPathComponent("l1")
        let l2 = l1.appendingPathComponent("l2")
        try FileManager.default.createDirectory(at: l2, withIntermediateDirectories: true)
        try "x".write(to: l1.appendingPathComponent("a.txt"),
                      atomically: true, encoding: .utf8)
        try "x".write(to: l2.appendingPathComponent("b.txt"),
                      atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        ws.recursive = true
        ws.maxDepth = 2   // 顶层 + 一层子目录
        ws.includeFolders = false

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        // 顶层 top.txt + l1/a.txt 应该有,l2/b.txt(depth 3)被截
        XCTAssertEqual(Set(nodes.map(\.name)), Set(["top.txt", "a.txt"]))
    }

    @MainActor
    func test_scan_extraIgnoreFolders_appends_to_global() async throws {
        try "x".write(to: tmp.appendingPathComponent("keep.txt"),
                      atomically: true, encoding: .utf8)
        let custom = tmp.appendingPathComponent("CustomTrash")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try "x".write(to: custom.appendingPathComponent("dont-index.txt"),
                      atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        ws.recursive = true
        ws.extraIgnoreFolders = "CustomTrash"
        ws.includeFolders = false

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(nodes.map(\.name), ["keep.txt"])
    }

    @MainActor
    func test_scan_includeFolders_indexes_directories_too() async throws {
        try "x".write(to: tmp.appendingPathComponent("file.txt"),
                      atomically: true, encoding: .utf8)
        let sub = tmp.appendingPathComponent("MyFolder")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let ws = try makeWorkspace()
        ws.recursive = false
        ws.includeFolders = true

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(Set(nodes.map(\.name)), Set(["file.txt", "MyFolder"]))

        let folder = nodes.first { $0.isDirectory }
        XCTAssertNotNil(folder)
        XCTAssertEqual(folder?.kind, "folder")
        XCTAssertEqual(folder?.size, 0)
        XCTAssertEqual(folder?.ext, "")
    }

    @MainActor
    func test_scan_includeFolders_off_skips_directory_entries() async throws {
        try "x".write(to: tmp.appendingPathComponent("file.txt"),
                      atomically: true, encoding: .utf8)
        let sub = tmp.appendingPathComponent("MyFolder")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        // 关掉 includeFolders 但保留 recursive,验证子目录里的文件仍能被收
        try "deep".write(to: sub.appendingPathComponent("deep.txt"),
                         atomically: true, encoding: .utf8)

        let ws = try makeWorkspace()
        ws.recursive = true
        ws.includeFolders = false

        let indexer = FileIndexer(container: container)
        try await indexer.scan(workspace: ws)

        let nodes = try container.mainContext.fetch(FetchDescriptor<FileNode>())
        XCTAssertEqual(Set(nodes.map(\.name)), Set(["file.txt", "deep.txt"]))
        XCTAssertTrue(nodes.allSatisfy { !$0.isDirectory })
    }
}
