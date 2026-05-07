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
                    Image(nsImage: FileIconCache.icon(for: f))
                        .resizable().interpolation(.high)
                        .scaledToFit().frame(width: 18, height: 18)
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
            }

            TableColumn("Size", value: \.size) { f in
                // 文件夹没有"大小"概念,显示破折号(同 Finder)
                Text(verbatim: f.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: f.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Date Added", value: \.dateAdded) { f in
                Text(verbatim: Self.dateFormatter.string(from: f.dateAdded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(160)

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
            .width(80)
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
