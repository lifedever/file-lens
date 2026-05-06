import Foundation
import SwiftData

@Model
final class Condition {
    @Attribute(.unique) var id: UUID
    var rule: Rule?
    var field: String   // "extension" | "name" | "size" | "dateAdded" | "kind"
    var op: String      // "is" | "isAnyOf" | "isNot" | "contains" | "matches"
                        // | "startsWith" | "endsWith" | ">" | "<" | "between"
                        // | "inLastDays" | "notInLastDays" | "before" | "after"
    var value: String   // serialized; parsed by ConditionEvaluator per field

    init(id: UUID = UUID(), field: String, op: String, value: String) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }
}
