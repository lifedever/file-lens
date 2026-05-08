import SwiftUI
import AppKit

struct FileTableView: View {
    @Bindable var workspace: Workspace
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    @State private var sortOrder: [KeyPathComparator<FileNode>]

    /// 列顺序 / 显隐自定义。Table 自带的右键 header 菜单 + 拖拽 reorder 全靠它。
    /// 持久化:JSON encode 后塞到 workspace.tableColumnCustomizationJSON,
    /// 每个 workspace 独立。
    @State private var columnCustomization: TableColumnCustomization<FileNode>
    /// 上一次满足"至少 3 列可见"的合法 customization 快照。当用户在 header
    /// 菜单里把第 3 列也勾掉时,onChange 会回滚到这个值,UI 上表现就是那一栏
    /// 勾不掉(也不报错,一致性很 macOS-like)。
    @State private var lastValidCustomization: TableColumnCustomization<FileNode>

    /// 排好序、按当前 sort 决定要不要分桶的视图。
    /// - 主排序 = `dateAdded` / `dateModified` → `.grouped`,section 头按对应
    ///   日期分桶("今天 / 昨天 / 本周")
    /// - 主排序 = name / size / kind 等非时间字段 → `.flat`,单段平铺
    ///
    /// 缓存在 class 容器里,@State 只持指针 —— 每次 SwiftUI 重 init View
    /// (body recompute)不会触发 computeLayout 重跑;真正变化只在 identityKey
    /// 变了的时候才重算。老实现把 layout 直接当 @State 存,init 时同步算
    /// 一次喂 initialValue,但 SwiftUI 重 init 时这次计算会被 @State 已存值
    /// 覆盖丢弃 —— 纯 wasted work,大列表点击延迟主要来自这里。
    @State private var layoutCache = LayoutCache()

    /// 一次拖拽手势内只 beginDraggingSession 一次的守门 flag。
    @State private var dragHandedOff: Bool = false

    /// shift-range 锚点(同 grid)。
    @State private var selectionAnchor: UUID?

    init(workspace: Workspace, files: [FileNode], selection: Binding<Set<UUID>>) {
        self.workspace = workspace
        self.files = files
        _selection = selection
        let initialSort: [KeyPathComparator<FileNode>] = [
            KeyPathComparator(\FileNode.dateAdded, order: .reverse)
        ]
        _sortOrder = State(initialValue: initialSort)
        // 从 workspace.tableColumnCustomizationJSON 还原上次 column 顺序 / 显隐。
        // 每个 workspace 独立 —— 切换 workspace 时 SwiftUI 通过 .id(workspace.id)
        // 在 ContentView 调用处强制重新 init 这个 view,@State 也跟着重置。
        let initialCustomization = Self.decodeCustomization(workspace.tableColumnCustomizationJSON)
        _columnCustomization = State(initialValue: initialCustomization)
        _lastValidCustomization = State(initialValue: initialCustomization)
    }

    var body: some View {
        Table(
            of: FileNode.self,
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 6) {
                    FileThumbnail(file: f, size: 18)
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
                // SwiftUI gesture 在 Table cell 里会跟 NSTableView 抢 mouseDown,
                // 单击不再触发 NSTableView 自带的选中。所以我们自己挂一个
                // TapGesture 同步 selection 状态(支持 ⌘ toggle / ⇧ range)。
                // 然后 DragGesture 处理拖拽,二者通过 .simultaneousGesture 并行。
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { FileActions.open(f) }
                )
                .simultaneousGesture(
                    // 用 minimumDistance: 0 一手抓「点击」和「拖拽」两件事 ——
                    // 通过 translation 实际距离区分。这样不依赖 SwiftUI 自己
                    // 在 TapGesture / DragGesture 之间仲裁,「微动后松手」也能
                    // 干净落到 click 分支,不会卡在「拖不起来又 collapse 不了」
                    // 的中间态。
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dist = hypot(value.translation.width, value.translation.height)
                            guard dist >= 4, !dragHandedOff else { return }
                            let urls = filesForDrag(f).compactMap(FileActions.url(for:))
                            guard !urls.isEmpty else { return }
                            dragHandedOff = true
                            DragSession.begin(urls: urls)
                            // AppKit 接管后 SwiftUI 不再 fire,下个 runloop tick
                            // 重置 flag。详见原 onChanged 注释。
                            DispatchQueue.main.async { dragHandedOff = false }
                        }
                        .onEnded { value in
                            let dist = hypot(value.translation.width, value.translation.height)
                            // 没真拖动(< 4pt)才走点击逻辑,否则不动 selection,
                            // 让 AppKit drag session 自己收尾。
                            if dist < 4 { handleClick(f) }
                            dragHandedOff = false
                        }
                )
            }
            .customizationID("name")
            // Name 列不允许隐藏 / 重排,作为锚定列(隐了用户就找不到文件了)。
            .disabledCustomizationBehavior([.reorder, .visibility])

            TableColumn("Size", value: \.size) { f in
                // 文件夹没有"大小"概念,显示破折号(同 Finder)
                Text(verbatim: f.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: f.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // .width(min:ideal:) 让用户能拖列分隔符调整宽度;固定 .width(N)
            // 会让 SwiftUI Table 把列锁死,分隔符不响应拖拽。
            .width(min: 60, ideal: 80)
            .customizationID("size")

            TableColumn("Date Added", value: \.dateAdded) { f in
                Text(verbatim: Self.dateFormatter.string(from: f.dateAdded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 160)
            .customizationID("dateAdded")

            TableColumn("Date Modified", value: \.dateModified) { f in
                Text(verbatim: Self.dateFormatter.string(from: f.dateModified))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 160)
            .customizationID("dateModified")

            TableColumn("Tags") { (f: FileNode) in
                Text(f.tags.map { TagDisplay.localizedName($0.name) }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .customizationID("tags")

            TableColumn("Kind", value: \.kind) { (f: FileNode) in
                Text(KindDisplay.localizedName(f.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("kind")
        } rows: {
            // 按 identityKey 命中缓存 → O(1) 返回上次 layout;不命中才跑
            // computeLayout(O(n) bucket + sort)。inspector toggle、hover 等
            // 不影响数据的 body recompute 全部走 fast path,只剩 NSTableView
            // 自己 reload 那点开销。
            let layout = layoutCache.layout(
                files: files,
                sortOrder: sortOrder,
                identityKey: identityKey
            )
            switch layout {
            case .grouped(let slices):
                ForEach(slices) { slice in
                    Section(slice.bucket.localizedTitle) {
                        ForEach(slice.files) { f in
                            TableRow(f)
                        }
                    }
                }
            case .flat(let files):
                ForEach(files) { f in
                    TableRow(f)
                }
            }
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let targets = filesForContextMenu(ids: ids)
            FileContextMenu(files: targets, modelContext: modelContext)
        } primaryAction: { ids in
            FileActions.open(filesForContextMenu(ids: ids))
        }
        // 用户在 header 右键勾选/拖动 reorder 后,把新的 customization 持久化。
        // 同时强制至少 3 列可见 —— 用户在菜单里把第 3 列也勾掉时,把状态回滚
        // 到 lastValidCustomization,这次 onChange 还会再 fire 一次 (newValue =
        // last valid),但那次合法,会安静地 no-op。
        .onChange(of: columnCustomization) { _, newValue in
            if Self.visibleColumnCount(newValue) < 3 {
                columnCustomization = lastValidCustomization
                return
            }
            lastValidCustomization = newValue
            workspace.tableColumnCustomizationJSON = Self.encodeCustomization(newValue)
        }
    }

    /// Name 列锚定永远算 1。其余列查 customization 里的 visibility:
    /// `.hidden` 不算;`.visible` / `.automatic` 都算可见。
    private static let optionalColumnIDs = ["size", "dateAdded", "dateModified", "tags", "kind"]
    private static func visibleColumnCount(_ c: TableColumnCustomization<FileNode>) -> Int {
        var count = 1   // name 锚定
        for id in optionalColumnIDs where c[visibility: id] != .hidden {
            count += 1
        }
        return count
    }

    fileprivate struct GroupedSlice: Identifiable {
        let bucket: DateBucket
        let files: [FileNode]
        var id: Int { bucket.rawValue }
    }

    /// 表格的两种渲染形态。grouped 时按日期分桶(section 标题 = "今天 / 本周"
    /// 之类);flat 时单段平铺,跟当前非日期排序对得上。
    /// fileprivate 是为了让同 file 内的 LayoutCache class 拿得到。
    fileprivate enum Layout {
        case grouped([GroupedSlice])
        case flat([FileNode])
    }

    /// Cheap stable digest of the inputs that affect grouping/sort.
    /// Don't compute a hash over all file IDs — that defeats the purpose;
    /// the parent already feeds us the actual array identity through `files`.
    private var identityKey: String {
        let firstID = files.first?.id.uuidString ?? "_"
        let lastID  = files.last?.id.uuidString ?? "_"
        let sortKey = sortOrder.map { "\($0.keyPath.hashValue):\($0.order == .forward ? "f" : "r")" }
            .joined(separator: ",")
        return "\(files.count)|\(firstID)|\(lastID)|\(sortKey)"
    }

    /// 决定当前 sort 下的渲染形态。`static` + `fileprivate` 是为了让 LayoutCache
    /// 能跨类型调到。规则:
    ///   - 主排序 = `dateAdded` → 按 dateAdded 分桶
    ///   - 主排序 = `dateModified` → 按 dateModified 分桶
    ///   - 其他(name / size / kind 等) → 不分桶,平铺
    /// 这样 section 标题永远跟当前排序的"维度"对齐,不会出现"今天"组里
    /// 排着 3 周前修改的文件这种困惑。
    fileprivate static func computeLayout(
        files: [FileNode],
        sortOrder: [KeyPathComparator<FileNode>]
    ) -> Layout {
        let primary = sortOrder.first?.keyPath
        let bucketKey: KeyPath<FileNode, Date>?
        if primary == \FileNode.dateModified {
            bucketKey = \.dateModified
        } else if primary == \FileNode.dateAdded {
            bucketKey = \.dateAdded
        } else {
            bucketKey = nil
        }

        guard let bucketKey else {
            return .flat(files.sorted(using: sortOrder))
        }

        var byBucket: [DateBucket: [FileNode]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f[keyPath: bucketKey]), default: []].append(f)
        }
        let slices = DateBucket.allCases.compactMap { b -> GroupedSlice? in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            return GroupedSlice(bucket: b, files: arr.sorted(using: sortOrder))
        }
        return .grouped(slices)
    }

    /// Right-click on an unselected row should target *that* row, even if
    /// other rows are selected — Finder behavior. Right-click on a selected
    /// row should target the whole selection.
    private func filesForContextMenu(ids: Set<FileNode.ID>) -> [FileNode] {
        files.filter { ids.contains($0.id) }
    }

    /// 拖拽时实际带走的文件集合(同 grid):被拖项在 selection 中 → 拖整组;
    /// 不在 → 只拖它一个,不动 selection。
    private func filesForDrag(_ file: FileNode) -> [FileNode] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }

    /// 模拟 NSTableView 的单击选中行为(因为 SwiftUI cell 上的 gesture 把
    /// mouseDown 拦截了)。同 grid 选择规则:
    ///   - 普通点击:替换为该单项 + 锚点更新
    ///   - ⌘ 点击:toggle + 锚点更新
    ///   - ⇧ 点击(有锚点):锚点到当前整段
    ///   - ⇧ 点击(无锚点):退化为普通点击
    private func handleClick(_ file: FileNode) {
        let mods = NSEvent.modifierFlags
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)

        if shift,
           let anchor = selectionAnchor,
           let from = files.firstIndex(where: { $0.id == anchor }),
           let to = files.firstIndex(where: { $0.id == file.id }) {
            let lo = min(from, to)
            let hi = max(from, to)
            selection = Set(files[lo...hi].map(\.id))
            return
        }

        if cmd {
            if selection.contains(file.id) { selection.remove(file.id) }
            else { selection.insert(file.id) }
            selectionAnchor = file.id
            return
        }

        // 普通点击:替换为单项(同 Finder)。点击在已选中项也 collapse,
        // 因为 DragGesture 已经在 onEnded 之前用距离判定区分过 click vs drag,
        // 这里走到的一定是「点击 + 没拖动」。
        selection = [file.id]
        selectionAnchor = file.id
    }

    /// JSON-encode `TableColumnCustomization` 用于 workspace.tableColumnCustomizationJSON 持久化。
    /// 失败返回空串,下一次启动用默认布局。
    private static func encodeCustomization(_ value: TableColumnCustomization<FileNode>) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    /// 反向 decode;空串 / 旧数据损坏时给一个新的默认 customization。
    private static func decodeCustomization(_ raw: String) -> TableColumnCustomization<FileNode> {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(TableColumnCustomization<FileNode>.self, from: data)
        else { return TableColumnCustomization<FileNode>() }
        return decoded
    }

    /// Per-cell formatters as `static let` —— 之前是 computed property,
    /// 每个 row 渲染都 new 一个 ByteCountFormatter(它有 NumberFormatter +
    /// locale 解析的内部成本)。300+ 行 × inspector 动画多帧 = 肉眼卡。
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// FileTableView 的 layout 缓存。class 引用类型,@State 只持指针 —— 改内
/// 部字段不触发 SwiftUI rerender,纯 memo。identityKey 命中时 O(1) 返回缓
/// 存,不命中才跑 computeLayout。
private final class LayoutCache {
    private var lastKey: String = ""
    private var lastLayout: FileTableView.Layout = .flat([])

    func layout(files: [FileNode],
                sortOrder: [KeyPathComparator<FileNode>],
                identityKey: String) -> FileTableView.Layout {
        if identityKey == lastKey { return lastLayout }
        lastLayout = FileTableView.computeLayout(files: files, sortOrder: sortOrder)
        lastKey = identityKey
        return lastLayout
    }
}
