import Foundation
import SwiftData

@Model
final class Workspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var folderPath: String
    var bookmarkData: Data
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Rule.workspace)
    var rules: [Rule] = []

    @Relationship(deleteRule: .cascade, inverse: \FileNode.workspace)
    var files: [FileNode] = []

    init(id: UUID = UUID(), name: String, folderPath: String, bookmarkData: Data, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
    }
}
