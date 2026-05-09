import XCTest
@testable import FileLens

final class RuleEngineTests: XCTestCase {

    private func makeFile(name: String, ext: String, size: Int64 = 1_000_000,
                         kind: String = "other") -> FileNode {
        FileNode(workspaceID: UUID(),
                 relativePath: name, name: name, ext: ext, size: size,
                 dateAdded: .now, dateModified: .now, kind: kind)
    }

    private func makeRule(name: String, combinator: String = "any", _ conditions: [Condition]) -> Rule {
        let r = Rule(name: name, color: "#000000", combinator: combinator)
        for c in conditions { r.conditions.append(c) }
        return r
    }

    func test_no_rules_returns_empty() {
        let tags = RuleEngine.tags(for: makeFile(name: "x.dmg", ext: "dmg"), rules: [])
        XCTAssertEqual(tags, [])
    }

    func test_single_rule_match_returns_one_tag() {
        let rule = makeRule(name: "Installers", [
            Condition(field: "extension", op: "isAnyOf", value: "dmg,pkg")
        ])
        let tags = RuleEngine.tags(for: makeFile(name: "x.dmg", ext: "dmg"), rules: [rule])
        XCTAssertEqual(tags, ["Installers"])
    }

    func test_multiple_rules_match_returns_multiple_tags() {
        let r1 = makeRule(name: "PDF", [Condition(field: "extension", op: "is", value: "pdf")])
        let r2 = makeRule(name: "Invoices", [Condition(field: "name", op: "contains", value: "invoice")])
        let tags = RuleEngine.tags(
            for: makeFile(name: "Q1-invoice.pdf", ext: "pdf"),
            rules: [r1, r2]
        )
        XCTAssertEqual(Set(tags), Set(["PDF", "Invoices"]))
    }

    func test_disabled_rule_does_not_match() {
        let r = makeRule(name: "PDF", [Condition(field: "extension", op: "is", value: "pdf")])
        r.enabled = false
        let tags = RuleEngine.tags(for: makeFile(name: "x.pdf", ext: "pdf"), rules: [r])
        XCTAssertEqual(tags, [])
    }

    func test_combinator_all_requires_every_condition() {
        let rule = makeRule(name: "BigInvoicePDF", combinator: "all", [
            Condition(field: "extension", op: "is", value: "pdf"),
            Condition(field: "name", op: "contains", value: "invoice"),
            Condition(field: "size", op: ">", value: "1MB")
        ])
        let small = makeFile(name: "invoice.pdf", ext: "pdf", size: 500)
        XCTAssertEqual(RuleEngine.tags(for: small, rules: [rule]), [])

        let big = makeFile(name: "invoice.pdf", ext: "pdf", size: 2_000_000)
        XCTAssertEqual(RuleEngine.tags(for: big, rules: [rule]), ["BigInvoicePDF"])
    }

    func test_combinator_any_matches_with_one_condition() {
        let rule = makeRule(name: "ImageOrPDF", combinator: "any", [
            Condition(field: "extension", op: "is", value: "pdf"),
            Condition(field: "kind", op: "is", value: "image"),
        ])
        XCTAssertEqual(RuleEngine.tags(for: makeFile(name: "x.pdf", ext: "pdf"), rules: [rule]), ["ImageOrPDF"])
        XCTAssertEqual(RuleEngine.tags(for: makeFile(name: "x.png", ext: "png", kind: "image"), rules: [rule]), ["ImageOrPDF"])
        XCTAssertEqual(RuleEngine.tags(for: makeFile(name: "x.zip", ext: "zip"), rules: [rule]), [])
    }

    func test_rule_with_no_conditions_does_not_match() {
        let rule = makeRule(name: "Empty", [])
        XCTAssertEqual(RuleEngine.tags(for: makeFile(name: "x.dmg", ext: "dmg"), rules: [rule]), [])
    }
}
