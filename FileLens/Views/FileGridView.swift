import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    @Bindable var workspace: Workspace
    let files: [FileSnapshot]
    @Binding var selection: Set<UUID>
    let resolveNodes: ([FileSnapshot]) -> [FileNode]
    @Environment(\.modelContext) private var modelContext

    private var iconSize: Double { workspace.gridIconSize }

    @State private var dragHandedOff: Bool = false
    @State private var selectionAnchor: UUID?
    @State private var groupedCache = GroupedCache()
    // 方向键导航的"光标"位置。区别于 selection —— 用户 shift+arrow 扩
    // 选时,cursor 在移动,anchor 不动,selection 是这两者的区间。
    @State private var cursor: UUID?
    @FocusState private var keyboardFocused: Bool

    init(workspace: Workspace,
         files: [FileSnapshot],
         selection: Binding<Set<UUID>>,
         resolveNodes: @escaping ([FileSnapshot]) -> [FileNode]) {
        self.workspace = workspace
        self.files = files
        _selection = selection
        self.resolveNodes = resolveNodes
    }

    private var columns: [GridItem] {
        let cell = iconSize + 30
        return [GridItem(.adaptive(minimum: cell, maximum: cell + 50), spacing: 12)]
    }

    var body: some View {
        // ScrollViewReader 包一层是为了方向键导航 scroll-to-cursor。
        // .focusable + .onKeyPress 是 macOS 14+ 的 API,我们的 deployment
        // target 是 14.0,刚好够用。
        ScrollViewReader { proxy in
            ScrollView {
                let grouped = groupedCache.grouped(files: files, identityKey: identityKey)
                LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(grouped) { slice in
                        Section {
                            ForEach(slice.files) { snap in
                                gridItem(for: snap)
                            }
                        } header: {
                            sectionHeader(slice.bucket.localizedTitle)
                        }
                    }
                }
                .padding(12)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($keyboardFocused)
            // 视图出现 / files 列表非空时,主动把 keyboard focus 抢过来,
            // 否则用户得先点一下 grid 才能用方向键。selectedFileIDs 不在
            // 这里 reset —— 上层 ContentView 切 workspace 时 .id() 重 init,
            // selection 是 @Binding 由父级管。
            .onAppear { if !files.isEmpty { keyboardFocused = true } }
            .onChange(of: files.count) { _, newCount in
                if newCount > 0, !keyboardFocused { keyboardFocused = true }
            }
            .onKeyPress(phases: .down) { press in
                handleArrowKey(press, proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func gridItem(for snap: FileSnapshot) -> some View {
        FileGridItem(file: snap, isSelected: selection.contains(snap.id),
                     iconSize: iconSize)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    FileActions.open(resolveNodes([snap]))
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        guard dist >= 4, !dragHandedOff else { return }
                        let dragSnaps = filesForDrag(snap)
                        let urls = dragSnaps.compactMap { FileURLResolver.shared.url(for: $0) }
                        guard !urls.isEmpty else { return }
                        dragHandedOff = true
                        DragSession.begin(urls: urls)
                        DispatchQueue.main.async { dragHandedOff = false }
                    }
                    .onEnded { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        if dist < 4 { handleTap(snap) }
                        dragHandedOff = false
                    }
            )
            .contextMenu {
                FileContextMenu(
                    files: resolveNodes(filesForContextMenu(snap: snap)),
                    modelContext: modelContext
                )
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.background)
    }

    fileprivate struct GroupedSlice: Identifiable {
        let bucket: DateBucket
        let files: [FileSnapshot]
        var id: Int { bucket.rawValue }
    }

    private var identityKey: String {
        let firstID = files.first?.id.uuidString ?? "_"
        let lastID  = files.last?.id.uuidString ?? "_"
        return "\(files.count)|\(firstID)|\(lastID)"
    }

    fileprivate static func computeGrouped(files: [FileSnapshot]) -> [GroupedSlice] {
        var byBucket: [DateBucket: [FileSnapshot]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f.dateAdded), default: []].append(f)
        }
        return DateBucket.allCases.compactMap { b in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { $0.dateAdded > $1.dateAdded }
            return GroupedSlice(bucket: b, files: sorted)
        }
    }

    private func handleTap(_ snap: FileSnapshot) {
        let mods = NSEvent.modifierFlags
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)
        // 点击时也把 keyboard focus 抢过来,确保下一次方向键能用。
        keyboardFocused = true

        if shift,
           let anchor = selectionAnchor,
           let from = files.firstIndex(where: { $0.id == anchor }),
           let to = files.firstIndex(where: { $0.id == snap.id }) {
            let lo = min(from, to)
            let hi = max(from, to)
            selection = Set(files[lo...hi].map(\.id))
            cursor = snap.id
            return
        }

        if cmd {
            if selection.contains(snap.id) { selection.remove(snap.id) }
            else { selection.insert(snap.id) }
            selectionAnchor = snap.id
            cursor = snap.id
            return
        }

        selection = [snap.id]
        selectionAnchor = snap.id
        cursor = snap.id
    }

    private func filesForContextMenu(snap: FileSnapshot) -> [FileSnapshot] {
        if selection.contains(snap.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [snap]
    }

    private func filesForDrag(_ snap: FileSnapshot) -> [FileSnapshot] {
        if selection.contains(snap.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [snap]
    }

    // MARK: - Arrow-key navigation

    /// 线性方向键导航(方案 A):
    /// - ← / ↑ = files 数组 prev,→ / ↓ = next
    /// - Shift+arrow 从 anchor 起扩选,跟 Finder 一致
    /// - 真二维偏移(列宽 × 行偏移)在 .adaptive 列宽 + grouped section 下
    ///   太脆,线性走视觉阅读顺序,grouped 跨桶时跳到下一桶刚好合理
    private func handleArrowKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !files.isEmpty else { return .ignored }
        let step: Int
        switch press.key {
        case .upArrow, .leftArrow:    step = -1
        case .downArrow, .rightArrow: step = 1
        default: return .ignored
        }
        let extend = press.modifiers.contains(.shift)

        // 当前 cursor 位置:优先用 @State cursor,fallback selectionAnchor,
        // 再 fallback selection 任意一个,最后 -1(起步从头/末)。
        let currentIdx: Int = {
            if let c = cursor, let i = files.firstIndex(where: { $0.id == c }) { return i }
            if let a = selectionAnchor, let i = files.firstIndex(where: { $0.id == a }) { return i }
            if let any = selection.first, let i = files.firstIndex(where: { $0.id == any }) { return i }
            return step > 0 ? -1 : files.count
        }()
        let nextIdx = max(0, min(files.count - 1, currentIdx + step))
        let nextID = files[nextIdx].id

        if extend {
            // shift+arrow:anchor 不动,selection 是 anchor↔cursor 区间
            let anchorID = selectionAnchor ?? cursor ?? nextID
            if selectionAnchor == nil { selectionAnchor = anchorID }
            if let a = files.firstIndex(where: { $0.id == anchorID }) {
                let lo = min(a, nextIdx)
                let hi = max(a, nextIdx)
                selection = Set(files[lo...hi].map(\.id))
            } else {
                selection = [nextID]
            }
        } else {
            // 普通 arrow:单选,anchor 跟着走
            selection = [nextID]
            selectionAnchor = nextID
        }
        cursor = nextID
        // scrollTo 用 ForEach 自动注入的 id(FileSnapshot.id = UUID),anchor
        // .center 让光标项停在可视区中央,符合 Finder 体感。
        withAnimation(.linear(duration: 0.08)) {
            proxy.scrollTo(nextID, anchor: .center)
        }
        return .handled
    }
}

private struct FileGridItem: View {
    let file: FileSnapshot
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

private final class GroupedCache {
    private var lastKey: String = ""
    private var lastGrouped: [FileGridView.GroupedSlice] = []

    func grouped(files: [FileSnapshot],
                 identityKey: String) -> [FileGridView.GroupedSlice] {
        if identityKey == lastKey { return lastGrouped }
        lastGrouped = FileGridView.computeGrouped(files: files)
        lastKey = identityKey
        return lastGrouped
    }
}
