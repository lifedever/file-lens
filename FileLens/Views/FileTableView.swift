import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// 文件列表视图(list 模式)。底层 `NSViewRepresentable` 包 `NSTableView`,
/// 不走 SwiftUI 的 `Table` —— 后者在大数据集下会因为 `usesAutomaticRowHeights`
/// + 每行 NSHostingView 给 NSWindow 注册 KVO 形成 O(n²) 主线程开销,11k+
/// 行 selection 切换会卡死秒级。我们关掉 auto row heights、固定 22pt、让
/// NSTableView 自己 lazy 只 mount visible row,11k 数据集 cell 实例数恒定 ~30。
///
/// 数据始终是 `[FileSnapshot]`(sendable struct),不持有 SwiftData @Model
/// 引用 → cell 渲染不触发 ObservationRegistrar 的 KeyPath 注册 / cancel
/// 风暴(snapshot 化前的真凶)。点击 / 拖拽 / 右键等操作通过 `resolveNodes`
/// 反查回 FileNode 调 FileActions —— 仅在用户操作那一刻发生。
struct FileTableView: View {
    @Bindable var workspace: Workspace
    let files: [FileSnapshot]
    /// `[file.id : tag display names]` —— Tags 列用,跟 cell 渲染解耦,
    /// 上层一次性 fetch 所有 FileTag 后建 map 传进来。
    let tagsByFileID: [UUID: [String]]
    @Binding var selection: Set<UUID>
    let resolveNodes: ([FileSnapshot]) -> [FileNode]
    @Environment(\.modelContext) private var modelContext

    /// 列布局(顺序 / 宽度 / 显隐 / 排序)。从 workspace.tableColumnCustomizationJSON
    /// 反序列化(失败回默认),用户交互后写回。
    @State private var layoutState: FileTableLayoutState

    init(workspace: Workspace,
         files: [FileSnapshot],
         tagsByFileID: [UUID: [String]],
         selection: Binding<Set<UUID>>,
         resolveNodes: @escaping ([FileSnapshot]) -> [FileNode]) {
        self.workspace = workspace
        self.files = files
        self.tagsByFileID = tagsByFileID
        _selection = selection
        self.resolveNodes = resolveNodes
        _layoutState = State(initialValue: FileTableLayoutState.decode(workspace.tableColumnCustomizationJSON))
    }

    private var rows: [FileTableRow] {
        let sorted = FileTableSorter.sort(files,
                                          by: layoutState.sortKey,
                                          ascending: layoutState.sortAscending)
        return FileTableRowBuilder.makeRows(sortedFiles: sorted, sortKey: layoutState.sortKey)
    }

    var body: some View {
        NativeFileTable(
            rows: rows,
            tagsByFileID: tagsByFileID,
            layoutState: layoutState,
            selection: $selection,
            onLayoutChange: { newState in
                layoutState = newState
                workspace.tableColumnCustomizationJSON = newState.encode()
            },
            onDoubleClick: { snap in
                FileActions.open(resolveNodes([snap]))
            },
            onContextRequested: { snaps in
                resolveNodes(snaps)
            },
            modelContext: modelContext
        )
    }
}

// MARK: - Row model + grouping

/// 拍平后的表格行。`.dateAdded` / `.dateModified` 排序时按 DateBucket 在
/// 文件之间插入 `.header`(今天 / 本周 / 长期未动 等),给视觉分组,跟 Finder
/// 「按日期排列」一致。其他排序维度(name/size/kind)只产生 `.item` —— 跟
/// 分组无关时不强加 header 噪音。
enum FileTableRow: Equatable {
    case header(String)
    case item(FileSnapshot)

    var isHeader: Bool {
        if case .header = self { return true }
        return false
    }

    var item: FileSnapshot? {
        if case .item(let f) = self { return f }
        return nil
    }
}

private enum FileTableRowBuilder {
    static func makeRows(sortedFiles: [FileSnapshot], sortKey: FileSortKey) -> [FileTableRow] {
        let bucketKey: KeyPath<FileSnapshot, Date>?
        switch sortKey {
        case .dateAdded:    bucketKey = \.dateAdded
        case .dateModified: bucketKey = \.dateModified
        default:            bucketKey = nil
        }
        guard let bucketKey else {
            return sortedFiles.map { .item($0) }
        }
        var rows: [FileTableRow] = []
        rows.reserveCapacity(sortedFiles.count + DateBucket.allCases.count)
        var lastBucket: DateBucket?
        for f in sortedFiles {
            let bucket = DateBucket.bucket(for: f[keyPath: bucketKey])
            if bucket != lastBucket {
                rows.append(.header(bucket.localizedTitle))
                lastBucket = bucket
            }
            rows.append(.item(f))
        }
        return rows
    }
}

// MARK: - Sort

enum FileSortKey: String, Codable, CaseIterable {
    case name, size, dateAdded, dateModified, kind
}

private enum FileTableSorter {
    static func sort(_ files: [FileSnapshot], by key: FileSortKey, ascending: Bool) -> [FileSnapshot] {
        let cmp: (FileSnapshot, FileSnapshot) -> Bool
        switch key {
        case .name:         cmp = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:         cmp = { $0.size < $1.size }
        case .dateAdded:    cmp = { $0.dateAdded < $1.dateAdded }
        case .dateModified: cmp = { $0.dateModified < $1.dateModified }
        case .kind:         cmp = { $0.kind < $1.kind }
        }
        return files.sorted { ascending ? cmp($0, $1) : cmp($1, $0) }
    }
}

// MARK: - Layout state (sort + columns)

struct FileTableLayoutState: Codable, Equatable {
    var sortKey: FileSortKey
    var sortAscending: Bool
    /// 用户排序后的列顺序 + visibility + width。包含的 id 必须是
    /// `FileTableColumns.allColumnIDs` 子集;新版本加列时自动 append 默认值。
    var columns: [ColumnState]

    struct ColumnState: Codable, Equatable {
        var id: String
        var visible: Bool
        var width: CGFloat
    }

    static let `default` = FileTableLayoutState(
        sortKey: .dateAdded,
        sortAscending: false,
        columns: FileTableColumns.allSpecs.map {
            ColumnState(id: $0.id, visible: $0.defaultVisible, width: $0.defaultWidth)
        }
    )

    func encode() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    static func decode(_ raw: String) -> FileTableLayoutState {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(FileTableLayoutState.self, from: data)
        else { return .default }
        // 跟当前已知列对齐:删掉已不存在的列 id,补上 decoded 里没有的新列
        // (新版本加列向前兼容)。
        let knownIDs = Set(FileTableColumns.allColumnIDs)
        var aligned = decoded.columns.filter { knownIDs.contains($0.id) }
        let presentIDs = Set(aligned.map(\.id))
        for spec in FileTableColumns.allSpecs where !presentIDs.contains(spec.id) {
            aligned.append(.init(id: spec.id, visible: spec.defaultVisible, width: spec.defaultWidth))
        }
        return FileTableLayoutState(sortKey: decoded.sortKey,
                                    sortAscending: decoded.sortAscending,
                                    columns: aligned)
    }
}

// MARK: - Column specs

enum FileTableColumns {
    struct Spec {
        let id: String
        let titleKey: String
        let titleFallback: String
        let sortKey: FileSortKey?      // nil = 不可排序(Tags)
        let defaultWidth: CGFloat
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let defaultVisible: Bool
        let lockedVisible: Bool        // name 列不能隐藏
    }

    static let allSpecs: [Spec] = [
        .init(id: "name",         titleKey: "Name",          titleFallback: "Name",
              sortKey: .name,         defaultWidth: 320, minWidth: 160, maxWidth: 800,
              defaultVisible: true,  lockedVisible: true),
        .init(id: "size",         titleKey: "Size",          titleFallback: "Size",
              sortKey: .size,         defaultWidth: 80,  minWidth: 60,  maxWidth: 160,
              defaultVisible: true,  lockedVisible: false),
        .init(id: "dateAdded",    titleKey: "Date Added",    titleFallback: "Date Added",
              sortKey: .dateAdded,    defaultWidth: 160, minWidth: 120, maxWidth: 220,
              defaultVisible: true,  lockedVisible: false),
        .init(id: "dateModified", titleKey: "Date Modified", titleFallback: "Date Modified",
              sortKey: .dateModified, defaultWidth: 160, minWidth: 120, maxWidth: 220,
              defaultVisible: false, lockedVisible: false),
        .init(id: "tags",         titleKey: "Tags",          titleFallback: "Tags",
              sortKey: nil,           defaultWidth: 200, minWidth: 80,  maxWidth: 400,
              defaultVisible: true,  lockedVisible: false),
        .init(id: "kind",         titleKey: "Kind",          titleFallback: "Kind",
              sortKey: .kind,         defaultWidth: 80,  minWidth: 60,  maxWidth: 160,
              defaultVisible: false, lockedVisible: false),
    ]

    static let allColumnIDs: [String] = allSpecs.map(\.id)

    static func spec(id: String) -> Spec? { allSpecs.first { $0.id == id } }
}

// MARK: - Native table

private struct NativeFileTable: NSViewRepresentable {
    let rows: [FileTableRow]
    let tagsByFileID: [UUID: [String]]
    let layoutState: FileTableLayoutState
    @Binding var selection: Set<UUID>
    let onLayoutChange: (FileTableLayoutState) -> Void
    let onDoubleClick: (FileSnapshot) -> Void
    let onContextRequested: ([FileSnapshot]) -> [FileNode]
    let modelContext: ModelContext

    static let rowHeight: CGFloat = 22
    /// Date bucket 分组标题行的高度,对齐 FileGridView sectionHeader 的视觉:
    /// vertical padding 6 + 13pt 字 ≈ 28pt。
    static let headerRowHeight: CGFloat = 28

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = FileNSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        let header = FileTableHeaderView()
        header.onMenuRequested = { [weak coordinator = context.coordinator] in
            coordinator?.makeColumnsMenu()
        }
        tableView.headerView = header
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        // 关键:关掉 automatic row heights —— SwiftUI Table 这个开关默认开,
        // 强制 NSTableView 在 endUpdates 阶段 measure 所有 inserted row 的高度,
        // 每次 measure 创建临时 NSHostingView,11k 行 = N² KVO 注册风暴。
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = Self.rowHeight
        // Group row(date bucket section header)滚动时粘顶,跟 Grid 视图
        // 的 LazyVGrid pinnedViews 一致。配合 isGroupRow delegate 启用。
        tableView.floatsGroupRows = true
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.menu = NSMenu()
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .link, .generic], forLocal: false)

        // 应用初始 layout(列顺序 / visible / width / sort)。
        context.coordinator.installColumns(on: tableView)
        scrollView.documentView = tableView
        context.coordinator.install(scrollView: scrollView, tableView: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyLayoutIfNeeded()
        context.coordinator.applyRows(rows)
        context.coordinator.applySelection(selection)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeFileTable
        private weak var scrollView: NSScrollView?
        private weak var tableView: FileNSTableView?
        private var lastRows: [FileTableRow] = []
        /// 仅 `.item` 行的 file id → row index 映射,selection 同步用。
        private var itemRowIndexByID: [UUID: Int] = [:]
        private var lastAppliedLayout: FileTableLayoutState?
        /// 阻止 column move / resize 通知触发的 onLayoutChange 反向重建 table —— 我们
        /// 自己应用 layout 时把这个 flag 拉高,期间忽略 didMoveColumn / didResizeColumn。
        private var applyingLayout = false

        init(parent: NativeFileTable) {
            self.parent = parent
        }

        fileprivate func install(scrollView: NSScrollView, tableView: FileNSTableView) {
            self.scrollView = scrollView
            self.tableView = tableView
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleColumnDidMove(_:)),
                name: NSTableView.columnDidMoveNotification, object: tableView
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleColumnDidResize(_:)),
                name: NSTableView.columnDidResizeNotification, object: tableView
            )
        }

        func teardown() {
            NotificationCenter.default.removeObserver(self)
            tableView?.delegate = nil
            tableView?.dataSource = nil
        }

        // MARK: 初始化列

        fileprivate func installColumns(on tableView: NSTableView) {
            applyingLayout = true
            defer { applyingLayout = false }
            // 按 layoutState.columns 顺序加 column;hidden 列也加(NSTableView 通过
            // isHidden 控制可见性,column 顺序仍要保留以便用户从 header 菜单切回)。
            for state in parent.layoutState.columns {
                guard let spec = FileTableColumns.spec(id: state.id) else { continue }
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
                column.title = NSLocalizedString(spec.titleKey, value: spec.titleFallback, comment: "")
                column.width = state.width
                column.minWidth = spec.minWidth
                column.maxWidth = spec.maxWidth
                column.resizingMask = .userResizingMask
                column.isHidden = !state.visible
                if let sortKey = spec.sortKey {
                    // sortDescriptorPrototype.key 用 sortKey rawValue,delegate
                    // 拿到时反查回 FileSortKey。
                    column.sortDescriptorPrototype = NSSortDescriptor(
                        key: sortKey.rawValue, ascending: true
                    )
                }
                tableView.addTableColumn(column)
            }
            // 应用 sort indicator
            applySortIndicator(on: tableView)
            lastAppliedLayout = parent.layoutState
        }

        private func applySortIndicator(on tableView: NSTableView) {
            tableView.sortDescriptors = [
                NSSortDescriptor(key: parent.layoutState.sortKey.rawValue,
                                 ascending: parent.layoutState.sortAscending)
            ]
        }

        // MARK: Layout 同步(外部修改 layoutState 时反映到 NSTableView)

        fileprivate func applyLayoutIfNeeded() {
            guard let tableView else { return }
            guard lastAppliedLayout != parent.layoutState else { return }
            let prev = lastAppliedLayout
            lastAppliedLayout = parent.layoutState

            applyingLayout = true
            defer { applyingLayout = false }

            // 仅 visibility 或 width 变化时,locate column by id 并 patch。
            // 顺序变化(用户拖)和 sort 变化在自己的事件回调里已经写到 layout 了,
            // 这里只补外部状态注入(比如其他视图同步,通常不会发生)。
            for state in parent.layoutState.columns {
                guard let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(state.id))
                else { continue }
                if column.isHidden != !state.visible { column.isHidden = !state.visible }
                if abs(column.width - state.width) > 0.5 { column.width = state.width }
            }

            if prev?.sortKey != parent.layoutState.sortKey
                || prev?.sortAscending != parent.layoutState.sortAscending {
                applySortIndicator(on: tableView)
            }
        }

        // MARK: 数据应用

        func applyRows(_ rows: [FileTableRow]) {
            // 只比较 row 序列(item id 顺序 + header 标题 + header 位置)。
            // header 标题相同 + items 相同 → 不 reload。
            guard rows != lastRows else { return }
            lastRows = rows
            rebuildItemIndex()
            tableView?.reloadData()
        }

        private func rebuildItemIndex() {
            var map: [UUID: Int] = [:]
            map.reserveCapacity(lastRows.count)
            for (idx, row) in lastRows.enumerated() {
                if case .item(let snap) = row { map[snap.id] = idx }
            }
            itemRowIndexByID = map
        }

        func applySelection(_ selectionIDs: Set<UUID>) {
            guard let tableView else { return }
            let rows = IndexSet(selectionIDs.compactMap { itemRowIndexByID[$0] })
            guard tableView.selectedRowIndexes != rows else { return }
            tableView.selectRowIndexes(rows, byExtendingSelection: false)
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            lastRows.count
        }

        // MARK: NSTableViewDelegate (cell)

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < lastRows.count else { return nil }

            // Group row 路径:NSTableView 在 isGroupRow == true 时给 viewFor
            // 传 column == nil,要求一个跨整行的 view(用作 sticky pinned header)。
            if tableColumn == nil {
                guard case .header(let title) = lastRows[row] else { return nil }
                let identifier = NSUserInterfaceItemIdentifier("FileLensGroupRow")
                let view: FileTableGroupRowView
                if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? FileTableGroupRowView {
                    view = reused
                } else {
                    view = FileTableGroupRowView()
                    view.identifier = identifier
                }
                view.populate(title: title)
                return view
            }

            guard let column = tableColumn else { return nil }
            let columnID = column.identifier.rawValue

            switch lastRows[row] {
            case .header:
                // 普通列在 group row 上不渲染 cell —— group row 路径(column == nil)
                // 已经接管整行渲染。返回空 view 避免 NSTableView 拿到 nil 报错。
                return NSView(frame: .zero)

            case .item(let snap):
                let identifier = NSUserInterfaceItemIdentifier("FileLensCell.\(columnID)")
                let cell: FileTableCell
                if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? FileTableCell {
                    cell = reused
                } else {
                    cell = FileTableCell()
                    cell.identifier = identifier
                }
                cell.populate(
                    columnID: columnID,
                    snapshot: snap,
                    tagNames: parent.tagsByFileID[snap.id] ?? [],
                    contextProvider: { [weak self] in
                        guard let self else { return [] }
                        let selection = self.parent.selection
                        let snaps: [FileSnapshot]
                        if selection.contains(snap.id) {
                            snaps = self.lastRows.compactMap { $0.item }.filter { selection.contains($0.id) }
                        } else {
                            snaps = [snap]
                        }
                        return self.parent.onContextRequested(snaps)
                    },
                    modelContext: parent.modelContext
                )
                return cell
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < lastRows.count else { return NativeFileTable.rowHeight }
            return lastRows[row].isHeader ? NativeFileTable.headerRowHeight : NativeFileTable.rowHeight
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row < lastRows.count else { return false }
            return !lastRows[row].isHeader
        }

        /// 标记 date bucket header 为 group row,配合 `floatsGroupRows = true`
        /// 实现滚动 sticky pinned。NSTableView 会在 viewFor 时给 column = nil,
        /// 从我们这边拿一个跨整行的 NSView 作为 floating header。
        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard row < lastRows.count else { return false }
            return lastRows[row].isHeader
        }

        /// inset style 下 NSTableRowView 默认给 group row 画底边 separator,
        /// 我们 cell 用 NSVisualEffectView 占满整行盖住中段,但 row 左右两端的
        /// inset margin 区域 separator 仍然露出来(用户看到的那两小段下划线)。
        /// 给 group row 用自定义 NSTableRowView 把 drawSeparator 整段砍掉。
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < lastRows.count, lastRows[row].isHeader else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileLensGroupRowContainer")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? FileTableGroupRow {
                return reused
            }
            let view = FileTableGroupRow()
            view.identifier = identifier
            return view
        }

        // MARK: Selection

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            let selectedRows = tableView.selectedRowIndexes
            let newSelection = Set(selectedRows.compactMap { idx -> UUID? in
                guard idx < lastRows.count else { return nil }
                if case .item(let snap) = lastRows[idx] { return snap.id }
                return nil
            })
            if newSelection != parent.selection {
                parent.selection = newSelection
            }
        }

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView,
                  tableView.clickedRow >= 0,
                  tableView.clickedRow < lastRows.count,
                  case .item(let snap) = lastRows[tableView.clickedRow]
            else { return }
            parent.onDoubleClick(snap)
        }

        // MARK: Sort

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let sd = tableView.sortDescriptors.first,
                  let raw = sd.key,
                  let key = FileSortKey(rawValue: raw)
            else { return }
            var state = parent.layoutState
            state.sortKey = key
            state.sortAscending = sd.ascending
            persistLayout(state)
        }

        // MARK: Column reorder / resize

        @objc private func handleColumnDidMove(_ note: Notification) {
            guard !applyingLayout, let tableView else { return }
            // tableView.tableColumns 顺序已经反映了用户拖拽后的状态。
            let order = tableView.tableColumns.map(\.identifier.rawValue)
            var byID = Dictionary(uniqueKeysWithValues: parent.layoutState.columns.map { ($0.id, $0) })
            var rebuilt: [FileTableLayoutState.ColumnState] = []
            for id in order {
                if let s = byID.removeValue(forKey: id) { rebuilt.append(s) }
            }
            // 把已知但当前 NSTableView 没列出的(理论不会有)塞回末尾,防丢失。
            rebuilt.append(contentsOf: byID.values)
            var state = parent.layoutState
            state.columns = rebuilt
            persistLayout(state)
        }

        @objc private func handleColumnDidResize(_ note: Notification) {
            guard !applyingLayout, let tableView else { return }
            var state = parent.layoutState
            for (idx, colState) in state.columns.enumerated() {
                guard let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(colState.id))
                else { continue }
                state.columns[idx].width = column.width
            }
            persistLayout(state)
        }

        // MARK: Column visibility (右键 header 菜单)

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            // 单击列头排序由 sortDescriptorsDidChange 处理,这里 no-op。
        }

        fileprivate func makeColumnsMenu() -> NSMenu {
            let menu = NSMenu()
            for spec in FileTableColumns.allSpecs {
                let item = NSMenuItem(
                    title: NSLocalizedString(spec.titleKey, value: spec.titleFallback, comment: ""),
                    action: #selector(toggleColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = spec.id
                let isVisible = parent.layoutState.columns.first { $0.id == spec.id }?.visible ?? spec.defaultVisible
                item.state = isVisible ? .on : .off
                if spec.lockedVisible { item.isEnabled = false }
                menu.addItem(item)
            }
            return menu
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            var state = parent.layoutState
            guard let idx = state.columns.firstIndex(where: { $0.id == id }) else { return }
            state.columns[idx].visible.toggle()
            persistLayout(state)
        }

        private func persistLayout(_ state: FileTableLayoutState) {
            parent.onLayoutChange(state)
        }

        // MARK: 拖拽 source

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < lastRows.count, case .item(let snap) = lastRows[row] else { return nil }
            return FileURLResolver.shared.url(for: snap) as NSURL?
        }
    }
}

// MARK: - NSTableView 子类

/// 扩展点:右键命中行时单选该行(Finder 一致行为)。Header 区域的右键菜单
/// 由 `FileTableHeaderView` 提供。
private final class FileNSTableView: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return super.menu(for: event) }
        if !self.selectedRowIndexes.contains(row) {
            self.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

/// Table header 右键 → 列显隐菜单。每次弹出由 closure 重建,根据当前
/// layoutState 动态生成 + 勾选。
private final class FileTableHeaderView: NSTableHeaderView {
    var onMenuRequested: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenuRequested?() ?? super.menu(for: event)
    }
}

// MARK: - Cell

/// NSTableCellView 子类,根据 columnID 渲染不同字段。
/// NSHostingView 渲染 SwiftUI content —— NSTableView lazy 复用,11k 行也只
/// 有可见 ~30 个 NSHostingView 实例。
private final class FileTableCell: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    func populate(columnID: String, snapshot: FileSnapshot,
                  tagNames: [String],
                  contextProvider: @escaping () -> [FileNode],
                  modelContext: ModelContext) {
        // .contextMenu 挂在最外层 —— 整行所有列右键都能弹，跟 Finder 一致。
        // 不能只挂在 name 列 cell 上,否则右键 size / date / tags / kind 列只
        // 命中 NSTableView 的空 menu,什么都不弹。
        let inner = Self.makeContent(
            columnID: columnID, snapshot: snapshot, tagNames: tagNames
        )
        let content = AnyView(
            inner.contextMenu {
                FileContextMenu(files: contextProvider(), modelContext: modelContext)
            }
        )
        if let host = hostingView {
            host.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingView = host
        }
    }

    private static func makeContent(columnID: String, snapshot: FileSnapshot,
                                    tagNames: [String]) -> AnyView {
        switch columnID {
        case "name":
            return AnyView(
                HStack(spacing: 6) {
                    FileThumbnail(file: snapshot, size: 16)
                    Text(snapshot.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            )
        case "size":
            return AnyView(
                Text(snapshot.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: snapshot.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case "dateAdded":
            return AnyView(
                Text(Self.dateFormatter.string(from: snapshot.dateAdded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case "dateModified":
            return AnyView(
                Text(Self.dateFormatter.string(from: snapshot.dateModified))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case "tags":
            let display = tagNames.map(TagDisplay.localizedName).joined(separator: ", ")
            return AnyView(
                Text(display)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case "kind":
            return AnyView(
                Text(KindDisplay.localizedName(snapshot.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        default:
            return AnyView(EmptyView())
        }
    }

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

/// 自定义 NSTableRowView for group rows —— 关掉默认 separator(底边横线),
/// 也让背景透明让 NSVisualEffectView 控制视觉。
private final class FileTableGroupRow: NSTableRowView {
    override func drawSeparator(in dirtyRect: NSRect) {
        // intentionally empty:跟 Grid 视图 sectionHeader 一致,无底边线。
    }
    override func drawBackground(in dirtyRect: NSRect) {
        // 让 cell 内的 NSVisualEffectView 画背景,row level 不画。
    }
}

/// Date bucket group row 的整行 view —— NSTableView 在 isGroupRow == true 时
/// 给 viewFor 传 column = nil,要求一个跨整行的 view 作为 group header / sticky
/// floating pin。
///
/// 样式跟 FileGridView 的 sectionHeader 对齐:
///   - system size 13 weight semibold + .secondaryLabel(同 SwiftUI .secondary)
///   - leading 12pt(对齐 cell content 起点)
///   - 视觉 vibrancy `.headerView` material —— sticky 时半透明,跟系统 List
///     的 group header 风格一致(Mail / Notes / Reminders 都是这个 material)
private final class FileTableGroupRowView: NSView {
    private let label: NSTextField
    private let visualEffect: NSVisualEffectView

    override init(frame frameRect: NSRect) {
        let visual = NSVisualEffectView()
        visual.material = .headerView
        visual.blendingMode = .withinWindow
        visual.state = .followsWindowActiveState
        visual.translatesAutoresizingMaskIntoConstraints = false
        self.visualEffect = visual

        let tf = NSTextField(labelWithString: "")
        tf.font = .systemFont(ofSize: 13, weight: .semibold)
        tf.textColor = .secondaryLabelColor
        tf.translatesAutoresizingMaskIntoConstraints = false
        self.label = tf

        super.init(frame: frameRect)
        addSubview(visual)
        addSubview(tf)
        NSLayoutConstraint.activate([
            visual.leadingAnchor.constraint(equalTo: leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: trailingAnchor),
            visual.topAnchor.constraint(equalTo: topAnchor),
            visual.bottomAnchor.constraint(equalTo: bottomAnchor),
            tf.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func populate(title: String) {
        label.stringValue = title
    }
}
