import Foundation
import SwiftData

@Model
final class Workspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var folderPath: String
    var bookmarkData: Data
    var createdAt: Date
    /// User-controlled sidebar order. 0 means "未初始化" — 一次性迁移会按
    /// createdAt 升序给老数据填入 100 / 200 / 300…，新建 workspace 也走
    /// 同样的步长，保证拖拽时有充足空间不需要每次重排。
    var sortOrder: Int = 0

    // MARK: - Per-workspace 设置(全部带默认值,SwiftData 迁移友好)

    /// 是否递归扫描子目录。**新建 workspace 默认 false** —— 大多数用户加
    /// Downloads/Desktop 这种浅目录,递归会把杂碎子项都拉进列表。开发者加
    /// 代码目录时再到设置里开。
    /// 老用户的迁移由 `WorkspaceRecursiveMigration` 一次性把所有现有 workspace
    /// 设成 true(保留旧行为,不惊吓老用户)。
    var recursive: Bool = false

    /// 递归时的最大深度。`0` 表示无限制(只在 recursive == true 时生效)。
    /// 1 表示只看顶层,2 表示顶层 + 一层子目录,以此类推。
    var maxDepth: Int = 0

    /// 显示名,覆盖 name(name 默认是文件夹名)。空串表示用 name。
    /// 比如用户加了 `~/Code/projects` 想叫"工作项目"。
    var displayName: String = ""

    /// 该 workspace 专属的排除目录/文件名,用 ", " 或换行分隔。
    /// 在全局排除列表(设置 → 偏好 → 排除规则)的基础上 *叠加*。
    /// 项目类文件夹经常有特殊垃圾目录(比如某个项目的 `output/`),不需要
    /// 污染全局列表。
    var extraIgnoreFolders: String = ""

    /// FSEvents 监听开关。默认 true。关掉后只能手动刷新 —— 适合网络盘 /
    /// 远程挂载 / 巨大目录(事件量爆炸)。
    var watchEnabled: Bool = true

    /// 是否在文件列表里把文件夹也当作一等条目显示(双击在 Finder 打开)。
    /// 默认 true,跟 Finder 一致。某些场景(只关心文件流)用户可以关掉。
    var includeFolders: Bool = true

    /// 视图模式持久化:每个 workspace 独立。1 = grid, 2 = list。
    /// 用 Int 不用 RawRepresentable enum,SwiftData 对 enum 演化支持不稳。
    /// 与 `ViewMode` 在 ContentView.swift 的 rawValue 对齐。
    var viewModeRaw: Int = 2

    /// Grid 视图的图标大小,范围 48-160。每个 workspace 独立。
    var gridIconSize: Double = 80

    /// FileTable 列自定义(顺序/宽度/可见性)的 JSON 串。空串 = SwiftUI 默认列布局。
    /// 每个 workspace 独立。
    var tableColumnCustomizationJSON: String = ""

    // MARK: - 索引状态(决定 UI 该 render 数据还是 render 进度)
    //
    // 0 = ready (默认,迁移友好 —— 老用户数据全是 ready)
    // 1 = scanning (背景 actor 正在跑首扫,UI 显示进度,不 mount Table/Grid)
    //
    // 关键:scanning 时 UI 不读 files relationship。让背景把 11k+ 个节点都
    // 索引完、tags 也打完,再一次性切到 ready,UI 这边只渲染一次。否则进度
    // 中途 ws.files 反复变化会触发 NSTableView reentrant reload,UI 卡死。
    var indexStateRaw: Int = 0
    /// 当前批次扫到的总数(累加,从 0 开始)。
    var indexProgressDone: Int = 0
    /// 当前批次预估总量。0 表示未知(enumerator 不预先 count,只在跑完后才有总数)。
    /// UI 显示用 `progressDone` + (有 total 时显示分数)。
    var indexProgressTotal: Int = 0

    /// 待删除标记。用户点"移除"时立刻 set true 并 save —— 这一下是单字段写入,
    /// 几乎瞬时,sidebar 当帧从列表过滤掉。后台 `rm` 文件 + 删 catalog 行。
    /// 关键:这个 flag **跨重启持久化**,如果 app 在 rm 跑完前关掉,下次启动
    /// `WorkspaceStateRecovery` 接着删掉,不会"删了的 workspace 重启后又出现"。
    var isPendingDeletion: Bool = false

    /// 缓存的当前文件总数(present)。SidebarView 需要 badge 数,但 FileNode
    /// 现在是在**独立 SQLite 文件**里(`workspaces/<uuid>.sqlite`),
    /// catalog 这边查不到 —— scan 完成时由 FileIndexer 显式回写到这个字段。
    /// 没扫过 / 还在扫:0。
    var fileCount: Int = 0

    /// 每个规则匹配的文件数,JSON 编码的 `[UUID-string: Int]`。
    /// SidebarView 拿这个出来给规则子行显示 badge。FileIndexer 在 scan 末尾
    /// 一次性算好回写。空字符串 = 没数据(没扫过)。
    var ruleCountsJSON: String = ""

    /// 没匹配任何 rule 的文件数(未归档)。
    var uncategorizedCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Rule.workspace)
    var rules: [Rule] = []
    // 注意:**不再**有 `@Relationship var files: [FileNode]` ——
    // FileNode 已经搬到 per-workspace 独立 SQLite,跨 store 关系 SwiftData
    // 不支持。删除走 `WorkspaceStoreManager.deleteStore` 直接 rm 文件,毫秒级。

    init(id: UUID = UUID(), name: String, folderPath: String, bookmarkData: Data,
         createdAt: Date = .now, sortOrder: Int = 0,
         recursive: Bool = false, maxDepth: Int = 0,
         displayName: String = "", extraIgnoreFolders: String = "",
         watchEnabled: Bool = true, includeFolders: Bool = true,
         viewModeRaw: Int = 2, gridIconSize: Double = 80,
         tableColumnCustomizationJSON: String = "") {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.recursive = recursive
        self.maxDepth = maxDepth
        self.displayName = displayName
        self.extraIgnoreFolders = extraIgnoreFolders
        self.watchEnabled = watchEnabled
        self.includeFolders = includeFolders
        self.viewModeRaw = viewModeRaw
        self.gridIconSize = gridIconSize
        self.tableColumnCustomizationJSON = tableColumnCustomizationJSON
    }

    /// User-visible name. displayName 非空就用它,否则回 name。
    var effectiveName: String {
        displayName.isEmpty ? name : displayName
    }

    var isIndexing: Bool { indexStateRaw == 1 }
}
