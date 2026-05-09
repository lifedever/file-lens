import XCTest
@testable import FileLens

final class ConditionEvaluatorTests: XCTestCase {

    private func makeFile(name: String = "test.dmg", ext: String = "dmg", size: Int64 = 1_000_000,
                         dateAdded: Date = .now, kind: String = "other") -> FileNode {
        FileNode(workspaceID: UUID(),
                 relativePath: name, name: name, ext: ext, size: size,
                 dateAdded: dateAdded, dateModified: dateAdded, kind: kind)
    }

    // extension
    func test_extension_is_match() {
        let cond = Condition(field: "extension", op: "is", value: "dmg")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(), condition: cond))
    }
    func test_extension_isAnyOf_match() {
        let cond = Condition(field: "extension", op: "isAnyOf", value: "pkg,dmg,exe")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(), condition: cond))
    }
    func test_extension_isAnyOf_no_match() {
        let cond = Condition(field: "extension", op: "isAnyOf", value: "pdf,zip")
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(), condition: cond))
    }
    func test_extension_case_insensitive() {
        let cond = Condition(field: "extension", op: "is", value: "DMG")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(ext: "dmg"), condition: cond))
    }

    // name
    func test_name_contains() {
        let cond = Condition(field: "name", op: "contains", value: "invoice")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(name: "Q1-invoice-2026.pdf"), condition: cond))
    }
    func test_name_matches_regex() {
        let cond = Condition(field: "name", op: "matches", value: "^(截屏|Screenshot|CleanShot)")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(name: "Screenshot 2026-05-06.png"), condition: cond))
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(name: "截屏2026-05-06.png"), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(name: "report.pdf"), condition: cond))
    }

    // size
    func test_size_greater_than() {
        let cond = Condition(field: "size", op: ">", value: "500MB")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(size: 600_000_000), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(size: 400_000_000), condition: cond))
    }
    func test_size_between() {
        let cond = Condition(field: "size", op: "between", value: "100MB,1GB")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(size: 500_000_000), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(size: 50_000_000), condition: cond))
    }

    // dateAdded
    func test_dateAdded_inLastDays() {
        let cond = Condition(field: "dateAdded", op: "inLastDays", value: "7")
        XCTAssertTrue(ConditionEvaluator.evaluate(
            file: makeFile(dateAdded: Date(timeIntervalSinceNow: -3 * 86400)), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(
            file: makeFile(dateAdded: Date(timeIntervalSinceNow: -10 * 86400)), condition: cond))
    }
    func test_dateAdded_notInLastDays() {
        let cond = Condition(field: "dateAdded", op: "notInLastDays", value: "30")
        XCTAssertTrue(ConditionEvaluator.evaluate(
            file: makeFile(dateAdded: Date(timeIntervalSinceNow: -45 * 86400)), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(
            file: makeFile(dateAdded: Date(timeIntervalSinceNow: -10 * 86400)), condition: cond))
    }

    // kind
    func test_kind_is() {
        let cond = Condition(field: "kind", op: "is", value: "image")
        XCTAssertTrue(ConditionEvaluator.evaluate(file: makeFile(kind: "image"), condition: cond))
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(kind: "movie"), condition: cond))
    }

    // unknown field: never matches
    func test_unknown_field_does_not_match() {
        let cond = Condition(field: "bogus", op: "is", value: "anything")
        XCTAssertFalse(ConditionEvaluator.evaluate(file: makeFile(), condition: cond))
    }
}
