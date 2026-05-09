import Foundation
import SwiftData

/// FileNode 的纯值快照,用于 SwiftUI 大列表渲染。@Model 类直接交给
/// SwiftUI Table cell 时,每行渲染都触发 ObservationRegistrar 给该 cell 的
/// KeyPath 注册 / cancel observations,11k+ 行 × 多个 KeyPath = 主线程
/// 被 KeyPath hash 风暴吃死(sample 抓到的栈底全是 AnyKeyPath.hash)。
/// 改用 sendable struct,cell 直接读 struct 字段不触发任何 observation,
/// Table 切换大数据集不再卡。
///
/// 操作(open/reveal/move/etc)还需要 FileNode managed object → 通过 id
/// 反查 modelContext.fetch(byID:);只在点击瞬间一次,不在持续 render 路径。
struct FileSnapshot: Sendable, Hashable, Identifiable {
    let id: UUID
    let workspaceID: UUID
    let relativePath: String
    let name: String
    let ext: String
    let size: Int64
    let dateAdded: Date
    let dateModified: Date
    let kind: String
    let isDirectory: Bool

    init(_ f: FileNode) {
        self.id = f.id
        self.workspaceID = f.workspaceID
        self.relativePath = f.relativePath
        self.name = f.name
        self.ext = f.ext
        self.size = f.size
        self.dateAdded = f.dateAdded
        self.dateModified = f.dateModified
        self.kind = f.kind
        self.isDirectory = f.isDirectory
    }
}

@Model
final class FileNode {
    @Attribute(.unique) var id: UUID
    /// FileNode 现在保存在 **per-workspace 独立 SQLite**(`workspaces/<uuid>.sqlite`),
    /// 跟 catalog 里的 Workspace 不在同一个 store —— 跨 store 关系 SwiftData
    /// 不支持,所以这里**只存 workspace UUID**(冗余字段,主要用于校验和未来
    /// 跨 store 查询)。同一个 store 里的所有 FileNode 都属于这一个 workspace。
    var workspaceID: UUID
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
        workspaceID: UUID,
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
        self.workspaceID = workspaceID
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
