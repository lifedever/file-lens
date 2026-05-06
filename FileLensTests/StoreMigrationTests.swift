import XCTest
@testable import FileLens

final class StoreMigrationTests: XCTestCase {
    func test_resolveStoreURL_returnsBundleIDSubdirectory() throws {
        let url = try StoreMigration.resolveStoreURL(
            bundleID: "com.example.TestApp",
            appSupportRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        XCTAssertTrue(url.path.contains("/com.example.TestApp/"))
        XCTAssertEqual(url.lastPathComponent, "default.store")
    }

    func test_resolveStoreURL_createsParentDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = try StoreMigration.resolveStoreURL(bundleID: "com.example.TestApp", appSupportRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
}
