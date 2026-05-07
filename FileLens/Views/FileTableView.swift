import SwiftUI
import AppKit

struct FileTableView: View {
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    @State private var sortOrder: [KeyPathComparator<FileNode>]

    /// Grouped + sorted view of `files`. Cached in @State so that triggering
    /// SwiftUI body recompute (e.g. inspector toggle reshapes the parent view
    /// tree) doesn't re-run the full bucket+sort pass on every frame of the
    /// inspector slide animation. Recomputed on the actual data dependencies:
    /// files identity (count + first/last id) and sortOrder.
    @State private var grouped: [GroupedSlice]

    /// 一次拖拽手势内只 beginDraggingSession 一次的守门 flag。
    @State private var dragHandedOff: Bool = false

    /// shift-range 锚点(同 grid)。
    @State private var selectionAnchor: UUID?

    init(files: [FileNode], selection: Binding<Set<UUID>>) {
        self.files = files
        _selection = selection
        let initialSort: [KeyPathComparator<FileNode>] = [
            KeyPathComparator(\FileNode.dateAdded, order: .reverse)
        ]
        _sortOrder = State(initialValue: initialSort)
        // 同步计算初始 grouped,避免首帧表格空白(否则 task(id:) 异步填值
        // 会闪一下)。后续 sort/files 变化通过 onChange 增量更新。
        _grouped = State(initialValue: Self.computeGrouped(files: files, sortOrder: initialSort))
    }

    var body: some View {
        Table(of: FileNode.self, selection: $selection, sortOrder: $sortOrder) {
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

            TableColumn("Size", value: \.size) { f in
                // 文件夹没有"大小"概念,显示破折号(同 Finder)
                Text(verbatim: f.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: f.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // .width(min:ideal:) 让用户能拖列分隔符调整宽度;固定 .width(N)
            // 会让 SwiftUI Table 把列锁死,分隔符不响应拖拽。
            .width(min: 60, ideal: 80)

            TableColumn("Date Added", value: \.dateAdded) { f in
                Text(verbatim: Self.dateFormatter.string(from: f.dateAdded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 160)

            TableColumn("Tags") { (f: FileNode) in
                Text(f.tags.map { TagDisplay.localizedName($0.name) }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            TableColumn("Kind", value: \.kind) { (f: FileNode) in
                Text(KindDisplay.localizedName(f.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(grouped) { slice in
                Section(slice.bucket.localizedTitle) {
                    ForEach(slice.files) { f in
                        TableRow(f)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let targets = filesForContextMenu(ids: ids)
            FileContextMenu(files: targets, modelContext: modelContext)
        } primaryAction: { ids in
            FileActions.open(filesForContextMenu(ids: ids))
        }
        // 用 onChange 把分桶/排序限定在数据真正变化时跑;identityKey 是
        // 廉价的稳定 key(count + 首尾 id),足以 detect 列表替换与排序切换。
        // 老实现把 grouped 写成 computed property 时,inspector 展开会让
        // ContentView 重算 body,顺带把这段也跑一遍 —— 列表大时就是肉眼卡。
        // 初始值已在 init 同步计算,这里只处理后续变化。
        .onChange(of: identityKey) { _, _ in
            grouped = Self.computeGrouped(files: files, sortOrder: sortOrder)
        }
    }

    private struct GroupedSlice: Identifiable {
        let bucket: DateBucket
        let files: [FileNode]
        var id: Int { bucket.rawValue }
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

    /// `static` 版本能在 init 阶段被调用(那时 self 还没构造完)。
    private static func computeGrouped(
        files: [FileNode],
        sortOrder: [KeyPathComparator<FileNode>]
    ) -> [GroupedSlice] {
        var byBucket: [DateBucket: [FileNode]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f.dateAdded), default: []].append(f)
        }
        return DateBucket.allCases.compactMap { b in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            return GroupedSlice(bucket: b, files: arr.sorted(using: sortOrder))
        }
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
