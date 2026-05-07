import SwiftUI
import SwiftData
import AppKit

enum SidebarSelection: Hashable {
    case workspace(UUID)
    case tag(workspaceID: UUID, name: String)
    case uncategorized(workspaceID: UUID)
}

private let kIconSize: CGFloat = 16

struct SidebarView: View {
    @Query(sort: [SortDescriptor(\Workspace.sortOrder),
                  SortDescriptor(\Workspace.createdAt)])
    private var workspaces: [Workspace]
    @Binding var selection: SidebarSelection?
    @Binding var selectedWorkspace: Workspace?
    let onEditRule: (Rule) -> Void
    let onDeleteRule: (Rule) -> Void
    /// 工作区行 hover 时点 ⊕ 调用 —— 给那一行的 workspace 新建规则,
    /// 不依赖当前 selectedWorkspace,这样 hover 加号点击立刻精准生效。
    let onNewRule: (Workspace) -> Void
    /// 右键 → "文件夹设置…" 调用,父页拿来打开 WorkspaceSettingsView sheet。
    let onEditWorkspace: (Workspace) -> Void
    /// 右键 → "立即重索引" 调用,父页让 coordinator 跑一次 reindex。
    let onReindex: (Workspace) -> Void
    @Environment(\.modelContext) private var modelContext

    @State private var collapsed: Set<UUID> = []
    @State private var ruleToDelete: Rule?
    @State private var workspaceToDelete: Workspace?
    /// 当前被鼠标 hover 的工作区行。一次只允许一个,所以用 UUID? 而不是 Set。
    @State private var hoveredWorkspaceID: UUID?
    /// User-visible count of items in the system Trash. Refreshed every
    /// `kTrashCountRefreshInterval` seconds — cheap directory listing,
    /// nothing recursive, hidden files skipped.
    @State private var trashCount: Int = 0
    private static let kTrashCountRefreshInterval: TimeInterval = 15
    /// Persisted via UserDefaults so the toggle in the View menu stays
    /// consistent across launches and windows.
    @AppStorage("filelens.showEmptyRules") private var showEmptyRules: Bool = true

    private static let sponsorURL = URL(string: "https://www.lifedever.com")!

    var body: some View {
        VStack(spacing: 0) {
            sidebarList
            Divider()
            supportFooter
        }
        .task {
            // Refresh the Trash count on appear, then every interval. Cheap
            // (single non-recursive directory listing with hidden files
            // skipped) — the loop ends when this view leaves the hierarchy.
            while !Task.isCancelled {
                await refreshTrashCount()
                try? await Task.sleep(for: .seconds(Self.kTrashCountRefreshInterval))
            }
        }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            ForEach(workspaces) { ws in
                DisclosureGroup(isExpanded: expansionBinding(for: ws.id)) {
                    // Children render indented automatically by DisclosureGroup.

                    // Tag rows — small colored dot (rule.color) gives each tag a
                    // visual identity and aligns the leading edge with system rows.
                    // Drag-reorder rewrites priorities so order persists.
                    ForEach(visibleRules(in: ws)) { rule in
                        tagRow(
                            text: TagDisplay.localizedName(rule.name),
                            count: filesCount(for: ws, tag: rule.name),
                            color: Color(hexString: rule.color)
                        )
                        .opacity(rule.enabled ? 1.0 : 0.5)
                        .tag(SidebarSelection.tag(workspaceID: ws.id, name: rule.name))
                        .contextMenu {
                            Button("Edit Rule…") { onEditRule(rule) }
                            Button(rule.enabled ? "Disable" : "Enable") {
                                rule.enabled.toggle()
                            }
                            Divider()
                            Button("Delete Rule", role: .destructive) {
                                ruleToDelete = rule
                            }
                        }
                    }
                    .onMove { source, destination in
                        reorderRules(in: ws, fromOffsets: source, toOffset: destination)
                    }
                } label: {
                    workspaceRow(ws)
                        // contextMenu 挂在 label 上,只对 workspace 行生效;若挂在
                        // DisclosureGroup 外侧会泄漏到所有子规则的右键菜单。
                        .contextMenu {
                            Button("workspace.contextmenu.settings") {
                                onEditWorkspace(ws)
                            }
                            Button("workspace.contextmenu.reindex") {
                                onReindex(ws)
                            }
                            Divider()
                            Button("workspace.remove…", role: .destructive) {
                                workspaceToDelete = ws
                            }
                        }
                }
                .tag(SidebarSelection.workspace(ws.id))
            }
            .onMove { source, destination in
                reorderWorkspaces(fromOffsets: source, toOffset: destination)
            }

            // Pinned global rows. They sit at the bottom of the list,
            // independent of any single workspace's expansion state.
            // - Unfiled is scoped to the currently-selected workspace; with
            //   no selection or with zero unfiled files it doesn't add value,
            //   so we hide it entirely.
            // - Trash is a system action and shows unconditionally.
            Section {
                if let ws = selectedWorkspace, uncategorizedCount(for: ws) > 0 {
                    rowLabel(
                        text: NSLocalizedString("Unfiled", value: "Unfiled", comment: ""),
                        count: uncategorizedCount(for: ws),
                        icon: AnyView(symbolIcon("questionmark.circle").foregroundStyle(.secondary))
                    )
                    .tag(SidebarSelection.uncategorized(workspaceID: ws.id))
                }

                HStack(spacing: 6) {
                    iconSlot { symbolIcon("trash").foregroundStyle(.secondary) }
                    Text(NSLocalizedString("Trash", value: "Trash", comment: ""))
                    Spacer(minLength: 4)
                    if trashCount > 0 {
                        CountBadge(count: trashCount)
                    }
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .selectionDisabled()
                .onTapGesture { openSystemTrash() }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, sel in
            switch sel {
            case .workspace(let id):
                if let ws = workspaces.first(where: { $0.id == id }) { selectedWorkspace = ws }
            case .tag(let wsID, _),
                 .uncategorized(let wsID):
                if let ws = workspaces.first(where: { $0.id == wsID }),
                   ws.id != selectedWorkspace?.id {
                    selectedWorkspace = ws
                }
            default:
                break
            }
        }
        .confirmationDialog(
            "workspace.remove.confirm.title",
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: workspaceToDelete
        ) { ws in
            Button("workspace.remove", role: .destructive) {
                removeWorkspace(ws)
                workspaceToDelete = nil
            }
            Button("Cancel", role: .cancel) { workspaceToDelete = nil }
        } message: { ws in
            Text(verbatim: String(format:
                NSLocalizedString("workspace.remove.confirm.message.format",
                    value: "Stop watching “%@”? Files on disk are untouched; only this folder is removed from FileLens.",
                    comment: ""), ws.name))
        }
        .confirmationDialog(
            "delete.confirm.title",
            isPresented: Binding(
                get: { ruleToDelete != nil },
                set: { if !$0 { ruleToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: ruleToDelete
        ) { rule in
            Button("Delete Rule", role: .destructive) {
                onDeleteRule(rule)
                ruleToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                ruleToDelete = nil
            }
        } message: { rule in
            Text(verbatim: String(format:
                NSLocalizedString("delete.confirm.message.format",
                    value: "Files keep any other tags. The “%@” rule will be removed from this workspace.",
                    comment: ""),
                TagDisplay.localizedName(rule.name)))
        }
    }

    // MARK: Support footer

    private var supportFooter: some View {
        Button {
            NSWorkspace.shared.open(Self.sponsorURL)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text("Support FileLens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())  // entire row, not just the text/icon
        }
        .buttonStyle(.plain)
        .help("Support FileLens")
        .pointingHandCursor()
    }

    // MARK: Helpers

    private func visibleRules(in ws: Workspace) -> [Rule] {
        let sorted = ws.rules.sorted(by: { $0.priority < $1.priority })
        if showEmptyRules { return sorted }
        return sorted.filter { filesCount(for: ws, tag: $0.name) > 0 }
    }

    private func openSystemTrash() {
        if let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(trash)
        }
    }

    /// Counts user-visible items in the system Trash (no recursion, hidden
    /// files like .DS_Store skipped). Cheap enough to call every 15s.
    private func refreshTrashCount() async {
        let count = await Task.detached(priority: .utility) { () -> Int in
            guard let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first,
                  let contents = try? FileManager.default.contentsOfDirectory(
                    at: trash,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
            else { return 0 }
            return contents.count
        }.value
        await MainActor.run { trashCount = count }
    }

    // MARK: Reorder

    private func reorderWorkspaces(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ordered = workspaces
        ordered.move(fromOffsets: source, toOffset: destination)
        // 步长 100 给手动插入留余量,跟 sortOrder doc 保持一致
        for (idx, ws) in ordered.enumerated() {
            ws.sortOrder = (idx + 1) * 100
        }
        try? modelContext.save()
    }

    private func removeWorkspace(_ ws: Workspace) {
        if selectedWorkspace?.id == ws.id { selectedWorkspace = nil }
        modelContext.delete(ws)
        try? modelContext.save()
    }

    private func reorderRules(in ws: Workspace, fromOffsets source: IndexSet, toOffset destination: Int) {
        // ForEach 渲染的是 visibleRules(in:)（可能被 Show Empty Rules 过滤过）
        // 所以 source / destination 是 *可见列表* 的索引。之前直接对完整
        // ws.rules.sorted 做 move，索引就对不上了 —— 这就是用户看到的
        // "顺序变了但没按拖拽保存" 的根因。
        var visible = visibleRules(in: ws)
        visible.move(fromOffsets: source, toOffset: destination)

        // 隐藏的规则（不在 visible 里的）按原有 priority 顺序保留在末尾，
        // 不会因为这次拖拽被打乱相对位置。
        let visibleIDs = Set(visible.map(\.id))
        let hidden = ws.rules
            .filter { !visibleIDs.contains($0.id) }
            .sorted(by: { $0.priority < $1.priority })

        // 步长 10 重新编号，给后续插入留余量，避免每次拖拽都要 re-renumber。
        for (idx, rule) in (visible + hidden).enumerated() {
            rule.priority = (idx + 1) * 10
        }
        try? modelContext.save()
    }

    // MARK: Row builders

    /// Workspace 行:hover 时右侧的 count badge 切换成 ⊕ 按钮(像相册 App 的
    /// 「固定」栏)。两种视觉同时挂在 ZStack 里、用 opacity 切换可见性 ——
    /// 用 if/else 让 view 树突变会引发 _NSDetectedLayoutRecursion(hover
    /// 触发重建,重建又重新触发 hover)。
    @ViewBuilder
    private func workspaceRow(_ ws: Workspace) -> some View {
        let count = ws.files.filter { $0.isPresent }.count
        let isHovered = hoveredWorkspaceID == ws.id

        HStack(spacing: 6) {
            iconSlot { folderIcon(for: ws) }
            Text(verbatim: ws.effectiveName)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)   // 名字优先吃宽度,badge 不够位置时挤掉自己
            // 递归状态的小角标 —— 让用户一眼看到 workspace 的扫描范围。
            // 不递归时不画(默认值,无需视觉噪音);开启时显示带颜色的小箭头
            // (无穷大或带数字的深度),点上去能去到设置里改。
            if ws.recursive {
                recursiveBadge(for: ws)
            }
            Spacer(minLength: 4)
            ZStack(alignment: .trailing) {
                CountBadge(count: count)
                    .opacity((count > 0 && !isHovered) ? 1 : 0)
                Button {
                    onNewRule(ws)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("New Rule…")
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            // 只在状态确实改变时写,避免无谓的 state churn。
            if hovering {
                if hoveredWorkspaceID != ws.id { hoveredWorkspaceID = ws.id }
            } else if hoveredWorkspaceID == ws.id {
                hoveredWorkspaceID = nil
            }
        }
    }

    /// 递归状态的小角标。无限制 → 无穷符号;有 maxDepth → 显示数字。
    /// 鼠标悬停提示扫描范围,点击 → 文件夹设置面板。
    @ViewBuilder
    private func recursiveBadge(for ws: Workspace) -> some View {
        let label: String = ws.maxDepth == 0 ? "∞" : "\(ws.maxDepth)"
        let helpText: String = ws.maxDepth == 0
            ? NSLocalizedString("workspace.badge.recursive.unlimited",
                value: "Recursive · all subfolders",
                comment: "")
            : String(format:
                NSLocalizedString("workspace.badge.recursive.limited.format",
                    value: "Recursive · up to %lld levels",
                    comment: ""),
                Int64(ws.maxDepth))
        Button {
            onEditWorkspace(ws)
        } label: {
            HStack(spacing: 1) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(verbatim: label)
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    /// All sidebar rows share this layout: a fixed kIconSize leading slot,
    /// 6pt gap, then the text, then a trailing badge. Using an explicit HStack
    /// (rather than SwiftUI's `Label`) is the only way to guarantee identical
    /// icon-to-text spacing across NSImage / SF Symbol / Circle icons —
    /// `Label` adjusts spacing based on the icon's intrinsic size, which is
    /// what was making the dot rows look slightly off-grid.
    @ViewBuilder
    private func rowLabel(
        text: String,
        count: Int,
        icon: AnyView,
        bold: Bool = false,
        showBadgeAlways: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            iconSlot { icon }
            if bold {
                Text(verbatim: text).fontWeight(.semibold)
            } else {
                Text(verbatim: text)
            }
            Spacer(minLength: 4)
            if count > 0 || showBadgeAlways {
                CountBadge(count: count)
            }
        }
    }

    @ViewBuilder
    private func tagRow(text: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            iconSlot {
                Circle()
                    .fill(color)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: 10, height: 10)
            }
            Text(verbatim: text)
            Spacer(minLength: 4)
            if count > 0 {
                CountBadge(count: count)
            }
        }
    }

    /// Pads any icon to the canonical kIconSize box and centers it. This is
    /// the alignment anchor for every sidebar row.
    @ViewBuilder
    private func iconSlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: kIconSize, height: kIconSize)
    }

    // MARK: Icons

    /// Icons are sized by their containing iconSlot — no internal frame so
    /// they don't double-pad and end up smaller than their slot.
    private func folderIcon(for ws: Workspace) -> some View {
        let img: NSImage = {
            if FileManager.default.fileExists(atPath: ws.folderPath) {
                return NSWorkspace.shared.icon(forFile: ws.folderPath)
            }
            return NSWorkspace.shared.icon(for: .folder)
        }()
        return Image(nsImage: img)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    private func symbolIcon(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
    }

    // MARK: Expansion binding

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { isExpanded in
                if isExpanded { collapsed.remove(id) }
                else          { collapsed.insert(id) }
            }
        )
    }

    // MARK: counts

    private func filesCount(for ws: Workspace, tag: String) -> Int {
        ws.files.filter { f in f.isPresent && f.tags.contains(where: { $0.name == tag }) }.count
    }

    private func uncategorizedCount(for ws: Workspace) -> Int {
        ws.files.filter { $0.isPresent && $0.tags.isEmpty }.count
    }
}

// Mail-style rounded pill count badge — kept light so it doesn't compete with
// the row label or the system selection highlight.
private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}
