import XCTest
@testable import FileLens

/// Smoke test to ensure the test target compiles and runs at all.
/// Real tests come in subsequent tasks; this guarantees the harness is wired up.
final class SmokeTest: XCTestCase {
    func test_app_module_imports() {
        XCTAssertTrue(true)
    }
}
