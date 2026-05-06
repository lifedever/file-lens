import XCTest
@testable import FileLens

final class BookmarkStoreTests: XCTestCase {

    func test_create_and_resolve_roundtrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let bookmark = try BookmarkStore.makeBookmark(for: tmp)
        let (resolved, isStale) = try BookmarkStore.resolve(bookmark: bookmark)

        XCTAssertEqual(resolved.standardizedFileURL.path, tmp.standardizedFileURL.path)
        XCTAssertFalse(isStale)
    }

    func test_resolve_after_rename_succeeds_marks_stale_or_resolves() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let originalDir = parent.appendingPathComponent("original")
        try FileManager.default.createDirectory(at: originalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let bookmark = try BookmarkStore.makeBookmark(for: originalDir)

        let renamedDir = parent.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: originalDir, to: renamedDir)

        let (resolved, _) = try BookmarkStore.resolve(bookmark: bookmark)
        XCTAssertEqual(resolved.standardizedFileURL.path, renamedDir.standardizedFileURL.path)
    }
}
