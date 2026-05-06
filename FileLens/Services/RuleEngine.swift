import Foundation

enum RuleEngine {
    /// Returns the set of tag names produced by evaluating the file against every enabled rule.
    /// A rule with zero conditions never matches (intentional: empty rules are typos, not wildcards).
    static func tags(for file: FileNode, rules: [Rule]) -> [String] {
        rules.compactMap { rule -> String? in
            guard rule.enabled, !rule.conditions.isEmpty else { return nil }
            let results = rule.conditions.map { ConditionEvaluator.evaluate(file: file, condition: $0) }
            let matched: Bool
            switch rule.combinator {
            case "all": matched = results.allSatisfy { $0 }
            case "any": matched = results.contains(true)
            default: matched = false
            }
            return matched ? rule.name : nil
        }
    }
}
