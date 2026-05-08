import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    @Bindable var workspace: Workspace
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    /// 图标大小读自当前 workspace。状态栏滑块通过 ContentView 持有的
    /// gridIconSize binding 写入 workspace.gridIconSize,@Bindable 保证
    /// 这里的 view 自动重 render。
    private var iconSize: Double { workspace.gridIconSize }

    /// 标记一次 drag 手势内是否已经把控制权交给 AppKit(NSDraggingSession)。
    /// SwiftUI DragGesture.onChanged 会持续 fire,守住这个 flag 保证我们只
    /// beginDraggingSession 一次。.onEnded 重置(即便 AppKit 接管后 SwiftUI
    /// gesture 不再 fire,@State reset 也无害)。
    @State private var dragHandedOff: Bool = false

    /// shift-range 选择的锚点 —— 记上一次普通点击 / ⌘ 点击落在哪个文件,
    /// shift+点 时选「锚点 → 当前」之间整段。Finder 网格视图同款行为。
    /// 锚点不在当前 files 列表里(切 workspace 后变量未清)时 shift+点
    /// 自动退化为普通点击。
    @State private var selectionAnchor: UUID?

    /// 时间分桶 + 桶内 dateAdded 倒序的视图模型,缓存在 class 容器里。
    /// @State 只持指针,SwiftUI 重 init View 不会触发 computeGrouped 重跑;
    /// identityKey 命中时 O(1) 返回缓存。老实现把 grouped 直接当 @State 存,
    /// init 时 `_grouped = State(initialValue: computeGrouped(...))` 看似只
    /// 算一次,实际 SwiftUI 每次 body recompute 都会跑 init 这行,结果被
    /// @State 已存值覆盖丢弃 —— 纯 wasted work。
    @State private var groupedCache = GroupedCache()

    init(workspace: Workspace, files: [FileNode], selection: Binding<Set<UUID>>) {
        self.workspace = workspace
        self.files = files
        _selection = selection
    }

    /// adaptive minimum 基于 iconSize + 文字行 + padding。
    /// maximum 给一点宽度浮动让 GridItem 能整齐排列。
    private var columns: [GridItem] {
        let cell = iconSize + 30
        return [GridItem(.adaptive(minimum: cell, maximum: cell + 50), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            // 按 identityKey 命中缓存 → O(1);不命中才跑 computeGrouped
            // (O(n) bucket + 每桶内 dateAdded 倒序)。同 FileTableView 套路。
            let grouped = groupedCache.grouped(files: files, identityKey: identityKey)
            LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped) { slice in
                    Section {
                        ForEach(slice.files) { file in
                            gridItem(for: file)
                        }
                    } header: {
                        sectionHeader(slice.bucket.localizedTitle)
                    }
                }
            }
            .padding(12)
        }
    }

    /// 拆出来减小 body 类型推导负担。
    @ViewBuilder
    private func gridItem(for file: FileNode) -> some View {
        FileGridItem(file: file, isSelected: selection.contains(file.id),
                     iconSize: iconSize)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { FileActions.open(file) }
            )
            .simultaneousGesture(
                // 一个 DragGesture(0) 同时承载「点击」和「拖拽」,通过实际
                // translation 距离区分:< 4pt 走 click 分支(handleTap 中
                // collapse 多选),>= 4pt 走拖拽分支。这样避免 SwiftUI 在
                // TapGesture / DragGesture 之间的仲裁歧义。详见 FileTableView。
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        guard dist >= 4, !dragHandedOff else { return }
                        let urls = filesForDrag(file).compactMap(FileActions.url(for:))
                        guard !urls.isEmpty else { return }
                        dragHandedOff = true
                        DragSession.begin(urls: urls)
                        DispatchQueue.main.async { dragHandedOff = false }
                    }
                    .onEnded { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        if dist < 4 { handleTap(file) }
                        dragHandedOff = false
                    }
            )
            .contextMenu {
                FileContextMenu(
                    files: filesForContextMenu(file: file),
                    modelContext: modelContext
                )
            }
    }

    /// Section 头:文字 + 上下留白。LazyVGrid 默认让 header 跨整行,贴左对齐。
    /// pinnedViews 设了 .sectionHeaders,所以滚动时 header 会粘顶 —— 大量
    /// 文件时随时知道当前所处分组(同 Finder「按时间排列」)。
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.background)   // 粘顶时遮住下面的内容
    }

    fileprivate struct GroupedSlice: Identifiable {
        let bucket: DateBucket
        let files: [FileNode]
        var id: Int { bucket.rawValue }
    }

    /// 廉价稳定 digest,只在数据真正变化时触发重算 grouped。
    /// 跟 FileTableView 同款:不全量 hash file ID(那等于又遍历一次)。
    private var identityKey: String {
        let firstID = files.first?.id.uuidString ?? "_"
        let lastID  = files.last?.id.uuidString ?? "_"
        return "\(files.count)|\(firstID)|\(lastID)"
    }

    /// 按 dateAdded 分桶 + 桶内按 dateAdded 倒序排序。Grid 视图没有用户可
    /// 切换的 sort 维度(不像 Table),所以固定按时间倒序展示。`fileprivate`
    /// 让同 file 的 GroupedCache 调得到。
    fileprivate static func computeGrouped(files: [FileNode]) -> [GroupedSlice] {
        var byBucket: [DateBucket: [FileNode]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f.dateAdded), default: []].append(f)
        }
        return DateBucket.allCases.compactMap { b in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { $0.dateAdded > $1.dateAdded }
            return GroupedSlice(bucket: b, files: sorted)
        }
    }

    /// 选择规则(同 Finder):
    ///   - 普通点击:替换为该单项 + 锚点更新到该项
    ///   - ⌘ 点击:toggle 该项 + 锚点更新到该项
    ///   - ⇧ 点击:从锚点到当前选取整段(锚点不变,以便连续 shift+点扩选)
    ///   - ⇧ 点击但无锚点:退化为普通点击
    private func handleTap(_ file: FileNode) {
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

        // 普通点击:替换为单项(同 Finder)。click vs drag 已经在
        // DragGesture.onEnded 用距离判过,这里走到的一定是没拖动。
        selection = [file.id]
        selectionAnchor = file.id
    }

    /// Right-click on a selected item targets the whole selection; right-click
    /// on a non-selected item targets just that one (matches Finder).
    private func filesForContextMenu(file: FileNode) -> [FileNode] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }

    /// 拖拽时实际带走的文件集合。Finder 习惯:
    ///   - 当前 file 在 selection 中 → 拖整个 selection
    ///   - 不在 → 只拖它一个,且 *不* 改 selection
    private func filesForDrag(_ file: FileNode) -> [FileNode] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }
}

private struct FileGridItem: View {
    let file: FileNode
    let isSelected: Bool
    let iconSize: Double

    var body: some View {
        VStack(spacing: 6) {
            FileThumbnail(file: file, size: iconSize)
            Text(file.name)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: iconSize + 50)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
    }
}

/// FileGridView 的 grouped 缓存。同 FileTableView.LayoutCache 套路:class
/// 引用类型 + @State 持指针,改内部字段不触发 SwiftUI rerender。
private final class GroupedCache {
    private var lastKey: String = ""
    private var lastGrouped: [FileGridView.GroupedSlice] = []

    func grouped(files: [FileNode],
                 identityKey: String) -> [FileGridView.GroupedSlice] {
        if identityKey == lastKey { return lastGrouped }
        lastGrouped = FileGridView.computeGrouped(files: files)
        lastKey = identityKey
        return lastGrouped
    }
}
