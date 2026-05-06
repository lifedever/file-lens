import Foundation
import SwiftData

@Model
final class Rule {
    @Attribute(.unique) var id: UUID
    var workspace: Workspace?
    var name: String
    var color: String          // hex like "#FF8800" or system color name
    var enabled: Bool
    var priority: Int
    var combinator: String     // "all" | "any"
    var isBuiltIn: Bool

    @Relationship(deleteRule: .cascade, inverse: \Condition.rule)
    var conditions: [Condition] = []

    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        enabled: Bool = true,
        priority: Int = 0,
        combinator: String = "any",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.enabled = enabled
        self.priority = priority
        self.combinator = combinator
        self.isBuiltIn = isBuiltIn
    }
}
