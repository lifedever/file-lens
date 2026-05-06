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
        XCTAssertTrue(tags.contains("Images"))
    }
}
