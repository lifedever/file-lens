import Foundation
import SwiftData

@Model
final class FileNode {
    @Attribute(.unique) var id: UUID
    var workspace: Workspace?
    var relativePath: String        // relative to workspace folder
    var name: String
    var ext: String                 // lowercase
    var size: Int64
    var dateAdded: Date             // Spotlight kMDItemDateAdded
    var dateModified: Date
    var kind: String                // big-bucket: "image"|"movie"|"audio"|"document"|"archive"|"code"|"text"|"other"
    var lastSeenAt: Date
    var isPresent: Bool
    var rulesEvaluatedAt: Date?
    var fileResourceID: String?     // serialized URLResourceValues.fileResourceIdentifier (for rename tracking)
    /// 该条目是不是文件夹。true 时 ext 为空、size 为 0、kind = "folder"。
    /// 跟 Finder 一样:文件夹也是列表里的一等条目,但内容不被展开成另一个
    /// 视图 —— 双击在 Finder 中打开。默认 false 保持 SwiftData 迁移兼容。
    var isDirectory: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \FileTag.file)
    var tags: [FileTag] = []

    init(
        id: UUID = UUID(),
        relativePath: String,
        name: String,
        ext: String,
        size: Int64,
        dateAdded: Date,
        dateModified: Date,
        kind: String,
        lastSeenAt: Date = .now,
        isPresent: Bool = true,
        rulesEvaluatedAt: Date? = nil,
        fileResourceID: String? = nil,
        isDirectory: Bool = false
    ) {
        self.id = id
        self.relativePath = relativePath
        self.name = name
        self.ext = ext
        self.size = size
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.kind = kind
        self.lastSeenAt = lastSeenAt
        self.isPresent = isPresent
        self.rulesEvaluatedAt = rulesEvaluatedAt
        self.fileResourceID = fileResourceID
        self.isDirectory = isDirectory
    }
}
