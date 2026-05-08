import XCTest
import SwiftData
@testable import FileLens

@MainActor
final class WorkspaceViewSettingsMigrationTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private let suiteName = "WorkspaceViewSettingsMigrationTests"

    override func setUpWithError() throws {
        let schema = Schema([Workspace.self, Rule.self, Condition.self, FileNode.self, FileTag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)

        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        defaults = nil
        super.tearDown()
    }

    private func makeWorkspace(_ name: String) -> Workspace {
        Workspace(
            name: name,
            folderPath: "/tmp/\(name)",
            bookmarkData: Data()
        )
    }

    func test_runIfNeeded_stampsGlobalValuesOntoExistingWorkspaces() throws {
        let context = ModelContext(container)
        let a = makeWorkspace("A"); let b = makeWorkspace("B")
        context.insert(a); context.insert(b)
        try context.save()

        defaults.set(1, forKey: "filelens.viewMode")          // grid
        defaults.set(120.0, forKey: "filelens.gridIconSize")
        defaults.set(#"{"columns":[]}"#, forKey: "FileTable.columnCustomizationJSON")

        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(a.viewModeRaw, 1)
        XCTAssertEqual(a.gridIconSize, 120.0)
        XCTAssertEqual(a.tableColumnCustomizationJSON, #"{"columns":[]}"#)
        XCTAssertEqual(b.viewModeRaw, 1)
        XCTAssertEqual(b.gridIconSize, 120.0)
        XCTAssertEqual(b.tableColumnCustomizationJSON, #"{"columns":[]}"#)
        XCTAssertTrue(defaults.bool(forKey: "filelens.viewMigration.v1.done"))
    }

    func test_runIfNeeded_usesDefaultsWhenGlobalsAbsent() throws {
        let context = ModelContext(container)
        let a = makeWorkspace("A")
        context.insert(a)
        try context.save()

        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)

        XCTAssertEqual(a.viewModeRaw, 2)        // list
        XCTAssertEqual(a.gridIconSize, 80.0)
        XCTAssertEqual(a.tableColumnCustomizationJSON, "")
    }

    func test_runIfNeeded_clampsOutOfRangeIconSize() throws {
        let context = ModelContext(container)
        let a = makeWorkspace("A")
        context.insert(a)
        try context.save()

        defaults.set(999.0, forKey: "filelens.gridIconSize")
        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(a.gridIconSize, 160.0)

        // Reset migration flag and re-run with too-small value
        defaults.set(false, forKey: "filelens.viewMigration.v1.done")
        defaults.set(10.0, forKey: "filelens.gridIconSize")
        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(a.gridIconSize, 48.0)
    }

    func test_runIfNeeded_isIdempotent() throws {
        let context = ModelContext(container)
        let a = makeWorkspace("A")
        context.insert(a)
        try context.save()

        defaults.set(1, forKey: "filelens.viewMode")
        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(a.viewModeRaw, 1)

        // User has since switched A to list manually
        a.viewModeRaw = 2
        try context.save()

        // Running migration again must NOT overwrite the manual change
        defaults.set(1, forKey: "filelens.viewMode")  // global still grid, should be ignored
        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(a.viewModeRaw, 2, "Second run must not re-stamp globals")
    }

    func test_runIfNeeded_handlesEmptyWorkspaceList() throws {
        let context = ModelContext(container)
        WorkspaceViewSettingsMigration.runIfNeeded(context: context, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "filelens.viewMigration.v1.done"))
    }
}
