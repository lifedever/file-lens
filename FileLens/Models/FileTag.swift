import Foundation
import SwiftData

@Model
final class FileTag {
    @Attribute(.unique) var id: UUID
    var file: FileNode?
    var name: String        // tag name (= rule.name when rule-sourced, or user-typed)
    var source: String      // "rule" | "manual"
    var ruleID: UUID?       // populated when source == "rule"

    init(id: UUID = UUID(), name: String, source: String, ruleID: UUID? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.ruleID = ruleID
    }
}
