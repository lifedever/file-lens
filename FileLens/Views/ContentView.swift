import SwiftUI
import SwiftData
import AppKit

enum ViewMode: Int { case grid = 1, list = 2 }

/// Bundle for the first-run rule picker sheet. Lets us use .sheet(item:),
/// which guarantees the closure receives the actual data and avoids the
/// timing bug we hit with multiple independent @State + .sheet(isPresented:).
struct PendingWorkspace: Identifiable {
    let id = UUID()
    let url: URL
    let rules: [Rule]
}

struct ContentView: View {
    @State private var selectedWorkspace: Workspace?
    @State private var selection: SidebarSelection?
    @State private var coordinator: WorkspaceCoordinator?
    /// Multi-selection of file IDs. We store IDs (not FileNode) so the set
    /// stays valid across SwiftData refresh cycles.
    @State private var selectedFileIDs: Set<UUID> = []
    /// Inspector 展开状态持久化 —— 习惯一直开着的用户不用每次 ⌘I。
    @AppStorage("filelens.showInspector") private var showInspector: Bool = false
    @State private var pendingWorkspace: PendingWorkspace?
    @State private var editingRule: Rule?
    /// A freshly-created Rule that hasn't been inserted into the ModelContext yet.
    /// Set by `newRule()` and committed on Save inside the sheet. Lets us drop
    /// the draft on Cancel without leaving an orphan.
    @State private var pendingNewRule: Rule?
    @State private var welcomeOpen: Bool = false
    @AppStorage("filelens.onboardingCompleted") private var onboardingCompleted: Bool = false
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = false
    @State private var searchText: String = ""
    /// `searchText` 的防抖镜像。`.searchable` 直接绑定 `searchText`,但
    /// 过滤(filesForCurrentSelection)只读 `debouncedSearchText`。每次按键 cancel
    /// 上一个等待 task,250ms 内没有新输入才把值落到 debounced —— 大目录
    /// (10k+ 文件)每键都全表 filter+sort 的卡顿就此消失。
    /// 250ms 是 VSCode / Spotlight 同款数量级,体感「即时」但能拢住快速连击。
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    /// `filesForCurrentSelection` 的廉价 memo。class 引用类型,@State 只持有
    /// 指针,改 result/key 不触发 SwiftUI 重 render —— 这正是 memo 想要的。
    /// 同 selection / search / file-count 重复 body recompute(inspector toggle、
    /// hover、focus 切换等)直接命中缓存,跳过 filter+sort 链路。
    @State private var filesMemo = FilesMemo()
    /// 首次启动(没添加任何文件夹)时把 sidebar 隐藏 —— 空状态本身已经有
    /// 选择文件夹的 CTA,左侧空白栏看起来很奇怪。注意这是 *单向* 切换:
    /// 一旦用户加了第一个 workspace 就转 .all,之后用户手动隐藏/显示都
    /// 自己掌控。**不要** 双向 .onChange(workspaces.isEmpty) 自动来回切,
    /// 那会跟 NSSplitView 的状态机打架,出现"sidebar 撑全宽"的诡异 bug。
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// columnVisibility 的 AppStorage 镜像。NavigationSplitViewVisibility 不是
    /// RawRepresentable,所以用 String 背书 + 双向 sync(task 启动时 decode,
    /// onChange 时 encode)。
    @AppStorage("filelens.columnVisibility") private var columnVisibilityRaw: String = "automatic"
    /// 当前正在编辑设置的 workspace。打开 WorkspaceSettingsView sheet。
    @State private var editingWorkspace: Workspace?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.workspaceStoreManager) private var storeManager
    /// 跟 SidebarView 的 @Query 同样过滤掉 pending deletion —— 否则用户删
    /// 大 workspace 后,workspaces.isEmpty / count 还把它算进去,空状态 UI
    /// 不会出现 / 计数错。
    @Query(filter: #Predicate<Workspace> { !$0.isPendingDeletion })
    private var workspaces: [Workspace]

    /// 视图模式 binding,绑到当前选中 workspace。selectedWorkspace == nil
    /// 时(空状态)getter 返回 .list 兜底,setter no-op —— 此时 toolbar 本来
    /// 也不会出现,这是双保险。
    private var viewMode: Binding<ViewMode> {
        Binding(
            get: { selectedWorkspace.flatMap { ViewMode(rawValue: $0.viewModeRaw) } ?? .list },
            set: { newValue in selectedWorkspace?.viewModeRaw = newValue.rawValue }
        )
    }

    private var gridIconSize: Binding<Double> {
        Binding(
            get: { selectedWorkspace?.gridIconSize ?? 80 },
            set: { newValue in selectedWorkspace?.gridIconSize = newValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: $selection,
                selectedWorkspace: $selectedWorkspace,
                onEditRule: { editingRule = $0 },
                onDeleteRule: { rule in
                    modelContext.delete(rule)
                    try? modelContext.save()
                    reapplyRulesIfNeeded()
                },
                onNewRule: { ws in
                    // 让点击 ⊕ 那一行的 workspace 立即被选中,这样 reapply
                    // 等后续操作的目标和 RuleEditor 保存路径都对得上。
                    selectedWorkspace = ws
                    selection = .workspace(ws.id)
                    newRule(for: ws)
                },
                onEditWorkspace: { ws in
                    editingWorkspace = ws
                },
                onReindex: { ws in
                    // "正在重新索引" 用 info 等级表"进行中",reindex 完成后再
                    // 弹一条 success "完成"。同步 Task 里串起来,避免完成 toast
                    // 早于异步 reindex 结束。
                    ToastCenter.shared.info(
                        NSLocalizedString("workspace.reindex.toast.start",
                            value: "Reindexing folder…", comment: "")
                    )
                    Task {
                        await coordinator?.reindex(workspace: ws)
                        ToastCenter.shared.success(
                            NSLocalizedString("workspace.reindex.toast.done",
                                value: "Reindex complete", comment: "")
                        )
                    }
                },
                onRemoveWorkspace: { ws in
                    Task {
                        await coordinator?.removeWorkspace(ws)
                    }
                }
            )
            // 用 NavigationSplitView 自带的列宽 clamp,而不是 .frame —— 后者
            // 在持久化的 split state 异常时(比如旧版本把 sidebar 撑成全宽
            // 后存盘了)救不回来,只有 navigationSplitViewColumnWidth 会强制
            // 把宽度夹回合理范围,让用户不需要重装就能恢复布局。
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 600, ideal: 900)
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(windowTitle)
        .sheet(item: $pendingWorkspace) { pending in
            FirstRunRulePicker(
                folderName: pending.url.lastPathComponent,
                rules: pending.rules,
                onConfirm: { enabledIDs, recursive in
                    commitWorkspace(pending: pending,
                                    enabledRuleIDs: enabledIDs,
                                    recursive: recursive)
                },
                onCancel: {
                    pendingWorkspace = nil
                }
            )
        }
        .sheet(isPresented: $welcomeOpen) {
            WelcomeSheet(onDismiss: {
                onboardingCompleted = true
                welcomeOpen = false
            })
        }
        .sheet(item: $editingWorkspace) { ws in
            WorkspaceSettingsView(workspace: ws) { saved in
                // 保存后:重启 watcher(可能 watchEnabled 变了)+ 强制重新扫描
                // (递归 / 深度 / 排除项变了都需要 rescan,绕开 activate 的
                // session 缓存)。activate 自带 deactivate,顺带处理 watcher
                // 状态切换。
                Task { await coordinator?.activate(workspace: saved, forceRescan: true) }
            }
        }
        .task {
            // First-launch onboarding. The flag persists across launches so
            // returning users don't see the sheet again unless they invoke
            // it from Settings.
            if !onboardingCompleted {
                welcomeOpen = true
            }
            // 先从 AppStorage 恢复用户上次的 sidebar 状态。
            columnVisibility = decodeColumnVisibility(columnVisibilityRaw)
            // 启动时如果还没添加文件夹(且之前也没有显式选择),sidebar 默认
            // 隐藏。只在 *初始* 这一次决策,之后由用户/onChange-add 接管。
            if workspaces.isEmpty {
                columnVisibility = .detailOnly
            }
        }
        // 单向:从空 → 非空(用户刚加完第一个 workspace),把 sidebar 拉出来。
        // 反方向(用户删光所有 workspace)不动 —— 让用户保留手动状态,而且
        // 也避免触发与 NSSplitView 的双向状态机冲突。
        .onChange(of: workspaces.isEmpty) { wasEmpty, isEmpty in
            if wasEmpty && !isEmpty && columnVisibility == .detailOnly {
                columnVisibility = .all
            }
        }
        // 把用户对 sidebar 的所有切换写回 AppStorage,下次启动恢复。
        .onChange(of: columnVisibility) { _, new in
            columnVisibilityRaw = encodeColumnVisibility(new)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in
            welcomeOpen = true
        }
        .sheet(item: $editingRule) { rule in
            ruleEditorSheet(rule: rule)
        }
        .background(hiddenShortcuts)
        .task {
            if coordinator == nil, let manager = storeManager {
                coordinator = WorkspaceCoordinator(storeManager: manager)
            }
        }
        .onChange(of: selectedWorkspace) { _, ws in
            Task {
                if let ws { await coordinator?.activate(workspace: ws) }
                else      { await coordinator?.deactivate() }
            }
        }
        .onChange(of: selectedFileIDs) { _, ids in
            if autoExpandInspector, !ids.isEmpty {
                showInspector = true
            }
        }
        // 搜索防抖。clear(空串)走即时通道 —— 用户点 X 不希望看到列表 250ms
        // 后才弹回完整;有内容时才进入 debounce 等待。
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                return
            }
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled {
                    debouncedSearchText = newValue
                }
            }
        }
        // Publish actions to the macOS menu bar (File → Add Folder…, New Rule…)
        .focusedValue(\.addFolderAction, addFolder)
        .focusedValue(\.newRuleAction, { newRule() })
        .focusedValue(\.activeWorkspaceName, selectedWorkspace?.name)
    }

    private func filesForCurrentSelection(workspace ws: Workspace) -> [FileSnapshot] {
        // 多 key cache:同 workspace 里 workspace ↔ 各 tag 来回切第二次起 O(1)。
        // workspace.fileCount 变化(scan 完成写回)整个 cache 清空。
        if let cached = filesMemo.get(workspace: ws,
                                      selection: selection,
                                      search: debouncedSearchText) {
            return cached
        }

        // 走 per-workspace store 取 FileNode。同一个 store 里的所有 FileNode
        // 都是这一个 workspace 的(物理隔离),所以不需要 workspace.id predicate。
        guard let manager = storeManager,
              let storeCtx = try? manager.store(for: ws.id).mainContext else {
            return []
        }

        // 过滤下推到 SQL。老实现先 fetch 全表 → in-memory `.tags` 遍历过滤,
        // 11k+ 节点每个都触发 SwiftData lazy fault 单条 SQL roundtrip,主线
        // 程卡到秒级。SidebarView.filesCount 已经是这套写法,这里对齐。
        // sortBy 顺手交给 SQL 排,渲染层桶内再 sort 不会重复扫全表。
        let sortByDateAddedDesc = [SortDescriptor(\FileNode.dateAdded, order: .reverse)]
        let base: [FileNode]
        switch selection {
        case .tag(_, let name):
            // 用 ruleID 而非 rule.name —— name 是 @Bindable 实时字段,编辑器
            // 输入时会跟 FileTag.name 短暂错位,误命中空集。规则被删后
            // selection 暂停留 → 空列表,sidebar 下一帧那条 tag 自然消失。
            guard let ruleID = ws.rules.first(where: { $0.name == name })?.id else {
                base = []
                break
            }
            let descriptor = FetchDescriptor<FileNode>(
                predicate: #Predicate<FileNode> { f in
                    f.isPresent && f.tags.contains { $0.ruleID == ruleID }
                },
                sortBy: sortByDateAddedDesc
            )
            base = (try? storeCtx.fetch(descriptor)) ?? []
        case .uncategorized:
            let descriptor = FetchDescriptor<FileNode>(
                predicate: #Predicate<FileNode> { f in
                    f.isPresent && f.tags.isEmpty
                },
                sortBy: sortByDateAddedDesc
            )
            base = (try? storeCtx.fetch(descriptor)) ?? []
        default:
            let descriptor = FetchDescriptor<FileNode>(
                predicate: #Predicate<FileNode> { $0.isPresent },
                sortBy: sortByDateAddedDesc
            )
            base = (try? storeCtx.fetch(descriptor)) ?? []
        }

        // 搜索字段(name)是 attribute 不是 relationship,内存遍历不触发
        // fault;SwiftData #Predicate 也不支持 localizedCaseInsensitiveContains,
        // 这一步留在内存里。
        let filtered: [FileNode] = debouncedSearchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(debouncedSearchText) }

        // 转 sendable struct snapshot —— cell 渲染时不持有 @Model 引用,跳过
        // SwiftUI ObservationRegistrar 的 KeyPath 注册 / cancel 风暴。
        let result: [FileSnapshot] = filtered.map { FileSnapshot($0) }

        filesMemo.set(workspace: ws,
                      selection: selection,
                      search: debouncedSearchText,
                      files: result)
        return result
    }

    /// 把 FileSnapshot 列表反查回 FileNode managed objects。点击 / 拖拽 /
    /// 右键菜单等操作入口用 —— 操作流程需要 FileNode (modelContext 写改)。
    /// 仅在用户操作那一刻执行,不在持续 render 路径,observation 开销可接受。
    private func resolveFileNodes(_ snapshots: [FileSnapshot]) -> [FileNode] {
        guard !snapshots.isEmpty,
              let ws = selectedWorkspace,
              let manager = storeManager,
              let storeCtx = try? manager.store(for: ws.id).mainContext
        else { return [] }
        let ids = Set(snapshots.map(\.id))
        let descriptor = FetchDescriptor<FileNode>(
            predicate: #Predicate<FileNode> { ids.contains($0.id) }
        )
        let nodes = (try? storeCtx.fetch(descriptor)) ?? []
        // 保持 snapshot 顺序
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return snapshots.compactMap { byID[$0.id] }
    }

    private func resolveFileNode(_ snapshot: FileSnapshot) -> FileNode? {
        resolveFileNodes([snapshot]).first
    }

    /// `[fileID : [tag display names]]` map,Tags 列渲染用。FilesMemo lazy
    /// 缓存,fileCount 变化(scan 完成)整 bucket 清空 → 下次重建。
    /// 第一次 build:fetch 全 workspace 含 rule tag 的 FileNode + 解 tags
    /// 关系,主线程 ~100ms 量级一次。后续 SwiftUI body recompute 命中 cache。
    private func tagsMapForWorkspace(_ ws: Workspace) -> [UUID: [String]] {
        guard let manager = storeManager,
              let storeCtx = try? manager.store(for: ws.id).mainContext
        else { return [:] }
        return filesMemo.tagsByFileID(workspace: ws) {
            let descriptor = FetchDescriptor<FileNode>(
                predicate: #Predicate<FileNode> { f in
                    f.isPresent && !f.tags.isEmpty
                }
            )
            let nodes = (try? storeCtx.fetch(descriptor)) ?? []
            var byFile: [UUID: [String]] = [:]
            byFile.reserveCapacity(nodes.count)
            for node in nodes {
                let names = node.tags.compactMap { tag -> String? in
                    tag.source == "rule" ? tag.name : nil
                }
                if !names.isEmpty {
                    byFile[node.id] = names
                }
            }
            return byFile
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Add Folder", value: "Add Folder", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingWorkspace = PendingWorkspace(url: url, rules: BuiltInRules.all())
    }

    private func commitWorkspace(pending: PendingWorkspace,
                                 enabledRuleIDs: Set<UUID>,
                                 recursive: Bool) {
        do {
            let bookmark = try BookmarkStore.makeBookmark(for: pending.url)
            // 新工作区放到现有列表之后,留 100 余量给后续拖拽插入
            let nextSort = (workspaces.map(\.sortOrder).max() ?? 0) + 100
            let ws = Workspace(name: pending.url.lastPathComponent,
                               folderPath: pending.url.path,
                               bookmarkData: bookmark,
                               sortOrder: nextSort,
                               recursive: recursive)
            modelContext.insert(ws)
            for rule in pending.rules where enabledRuleIDs.contains(rule.id) {
                rule.workspace = ws
                modelContext.insert(rule)
            }
            try modelContext.save()
            selectedWorkspace = ws
        } catch {
            NSAlert(error: error).runModal()
        }
        pendingWorkspace = nil
    }

    private func newRule(for ws: Workspace? = nil) {
        guard let ws = ws ?? selectedWorkspace else { return }
        // Build a draft Rule but don't insert into the ModelContext yet —
        // RuleEditorView's Save handler does the insert. Cancel just drops
        // the draft so we don't leave orphans behind.
        let draft = Rule(
            name: NSLocalizedString("Untitled", value: "Untitled", comment: ""),
            color: "#3B82F6",
            enabled: true,
            priority: (ws.rules.map(\.priority).max() ?? 0) + 10,
            combinator: "any",
            isBuiltIn: false
        )
        draft.conditions.append(Condition(field: "extension", op: "is", value: ""))
        pendingNewRule = draft
        editingRule = draft
    }

    private func reapplyRulesIfNeeded() {
        guard let ws = selectedWorkspace, let manager = storeManager else { return }
        let wsID = ws.id
        Task { @MainActor in
            let indexer = FileIndexer(storeManager: manager)
            try? await indexer.applyRules(workspaceID: wsID)
            filesMemo.invalidate()
        }
    }

    /// 把状态栏拆成单独的 @ViewBuilder,避免 body 太大导致 Swift 类型推导
    /// 在合理时间内算不完(报 "the compiler is unable to type-check this
    /// expression in reasonable time")。
    /// 把 detail column 拆出去 —— body 主体太大时 Swift 推导会超时。
    @ViewBuilder
    private var detailColumn: some View {
        if workspaces.isEmpty {
            EmptyStateView(onAddFolder: addFolder)
        } else if let ws = selectedWorkspace {
            workspaceDetail(ws)
        } else {
            ContentUnavailableView {
                Label("empty.workspace.title", systemImage: "sidebar.left")
            } description: {
                Text("empty.workspace.subtitle")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func workspaceDetail(_ ws: Workspace) -> some View {
        if ws.isIndexing {
            // 关键 gate:scanning 期间根本不读 ws.files,也不 mount Table/Grid。
            // 这一段时间背景 actor 会跑完 enumerate + insert + applyRules + save,
            // ws.files 总数从 0 飙到上万。如果 UI 这边在跑 filter/sort/render,
            // 每次 save 通知都会触发 11k 行 NSTableView reentrant reload —— UI 卡死。
            // 切到 ready 之后才一次性渲染最终数据。
            indexingProgressView(ws)
        } else {
            readyDetail(ws)
        }
    }

    @ViewBuilder
    private func indexingProgressView(_ ws: Workspace) -> some View {
        let done = ws.indexProgressDone
        let total = ws.indexProgressTotal
        VStack(spacing: 12) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : nil) {
                Text(verbatim: NSLocalizedString("indexing.title",
                    value: "Indexing folder…", comment: ""))
                    .font(.headline)
            } currentValueLabel: {
                if total > 0 {
                    Text(verbatim: "\(done) / \(total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: "\(done)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 360)
            Text(verbatim: NSLocalizedString("indexing.subtitle",
                value: "Files will appear once indexing completes.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func readyDetail(_ ws: Workspace) -> some View {
        let files = filesForCurrentSelection(workspace: ws)
        let selectedSnapshots = files.filter { selectedFileIDs.contains($0.id) }
        // Inspector 需要 FileNode 读 tags 关系。但只 resolve selected(通常 1-3 个),
        // 不影响 cell 渲染主路径。
        let selectedFiles = resolveFileNodes(selectedSnapshots)
        let workspaceRules = ws.rules
        let inspectorSnapshot: InspectorSnapshot? = selectedFiles.first.map { f in
            InspectorSnapshot(file: f, rules: workspaceRules)
        }
        // Tags 列用的 fileID → tag 名字 map。FilesMemo 内 lazy 缓存,fileCount
        // 变化(scan 完成写回)清空。第一次构造跑 ~100ms 主线程,之后命中 0ms。
        let tagsByFileID = tagsMapForWorkspace(ws)
        // 不用 SwiftUI 的 .inspector(isPresented:) —— 它底层是 NSSplitViewController,
        // pane slide 动画跟内容首帧渲染会撞,表现就是用户看到的"半 → 卡 → 半"
        // (slide 到一半 SwiftUI 同步渲染 inspector 内容、阻塞 main、动画卡住,
        // 然后再继续)。手动 HStack + .transition 由 SwiftUI 自己驱动,内容
        // 渲染和位移共享一个动画时钟,不会两边互相阻塞。
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                fileBody(files: files, tagsByFileID: tagsByFileID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar(files: files, selectedFiles: selectedSnapshots)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showInspector {
                HStack(spacing: 0) {
                    Divider()
                    InspectorView(snapshot: inspectorSnapshot,
                                  selectedFiles: selectedFiles)
                        .frame(width: inspectorWidth)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.22), value: showInspector)
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar { detailToolbar }
        // ⌘F 把焦点抢到工具栏搜索框。`.searchFocused` 是 macOS 15 才有,
        // 这里走 AppKit responder chain:在 keyWindow 的 toolbar 里找 NSSearchField
        // 然后 makeFirstResponder。隐藏 Button 的 keyboardShortcut 用来注册热键,
        // 放 .background 里对布局零影响。
        .background(
            Button("Find") { focusToolbarSearchField() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    /// Persisted inspector pane width. 280 是 macOS Mail / Notes 等系统应用
    /// inspector 的默认宽度,既能放下文件名 + 标签流又不挤压主区。
    private var inspectorWidth: CGFloat { 280 }

    @ViewBuilder
    private func fileBody(files: [FileSnapshot], tagsByFileID: [UUID: [String]]) -> some View {
        if let ws = selectedWorkspace {
            // 两种视图始终都在 view tree 里,toggle grid/list 只切 opacity ——
            // 避免 SwiftUI _ConditionalContent 切分支带来的 teardown→空帧→重建
            // (~50ms)。workspace 切换时仍用 .id(ws.id) 让两个子视图都重 init,
            // @State(列定制 / 缓存)跟着重置。
            //
            // 只有当前可见的视图收 files,隐藏的永远收 [] —— selection 切换
            // 时只让一个 NSTableView / Grid 扛 reload,主线程不会被双倍工作吃死。
            // view mode toggle(cmd-1 / cmd-2)时另一边第一次 mount 会卡一下
            // (从 [] 到 N 行 layout),但这是低频操作,远比每次 selection
            // 切换都两个视图同时 reload 划算。
            let mode = viewMode.wrappedValue
            let gridFiles  = mode == .grid ? files : []
            let tableFiles = mode == .list ? files : []
            ZStack {
                FileGridView(workspace: ws,
                             files: gridFiles,
                             selection: $selectedFileIDs,
                             resolveNodes: resolveFileNodes)
                    .id(ws.id)
                    .opacity(mode == .grid ? 1 : 0)
                    .allowsHitTesting(mode == .grid)
                FileTableView(workspace: ws,
                              files: tableFiles,
                              tagsByFileID: tagsByFileID,
                              selection: $selectedFileIDs,
                              resolveNodes: resolveFileNodes)
                    .id(ws.id)
                    .opacity(mode == .list ? 1 : 0)
                    .allowsHitTesting(mode == .list)
            }
        } else {
            // 没选中 workspace 时不渲染数据视图;父级会显示 EmptyStateView。
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            Spacer()
            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: showInspector ? "info.circle.fill" : "info.circle")
            }
            .keyboardShortcut("i", modifiers: .command)
            .help("Show Info  ⌘I")
        }
    }

    /// 抽出 sheet content 减小 body 类型推导负担。
    @ViewBuilder
    private func ruleEditorSheet(rule: Rule) -> some View {
        RuleEditorView(
            rule: rule,
            isNewRule: pendingNewRule?.id == rule.id,
            onSave:   { draft in saveRule(rule, draft: draft) },
            onCancel: { cancelRule() },
            onDelete: { deleteRule(rule) }
        )
    }

    /// 把编辑器回传的草稿 patch 回 SwiftData 模型。
    /// - 字段(name / color / enabled / combinator):直接赋值
    /// - conditions:按 id 协调
    ///   * 草稿有 / 模型没 → 新建 Condition + insert
    ///   * 模型有 / 草稿没 → modelContext.delete (不再作为 cascade 孤儿留着)
    ///   * 两边都有 → 更新 field/op/value(只在内容变了的时候赋值,避免无谓 dirty)
    /// 新规则路径(pendingNewRule)在 patch 完之后才把 rule + conditions 一起 insert。
    private func saveRule(_ rule: Rule, draft: RuleEditorView.Draft) {
        rule.name = draft.name
        rule.color = draft.color
        rule.enabled = draft.enabled
        rule.combinator = draft.combinator

        let isPending = pendingNewRule?.id == rule.id

        // Conditions 协调
        let draftIDs = Set(draft.conditions.map(\.id))
        let existing = Dictionary(uniqueKeysWithValues: rule.conditions.map { ($0.id, $0) })

        // 删除草稿里不再有的旧 condition。pending 路径下整条 rule 还没入库,
        // 这些 Condition 对象也就还在内存里,从 rule.conditions 里拿掉就行;
        // 已入库的走 modelContext.delete。
        for (id, cond) in existing where !draftIDs.contains(id) {
            if !isPending {
                modelContext.delete(cond)
            }
            rule.conditions.removeAll { $0.id == id }
        }

        // 更新或插入
        for d in draft.conditions {
            if let cond = existing[d.id] {
                if cond.field != d.field { cond.field = d.field }
                if cond.op != d.op       { cond.op = d.op }
                if cond.value != d.value { cond.value = d.value }
            } else {
                let cond = Condition(id: d.id, field: d.field, op: d.op, value: d.value)
                cond.rule = rule
                rule.conditions.append(cond)
            }
        }

        if isPending, let ws = selectedWorkspace {
            rule.workspace = ws
            modelContext.insert(rule)
            for cond in rule.conditions { modelContext.insert(cond) }
            pendingNewRule = nil
        }
        try? modelContext.save()
        editingRule = nil
        reapplyRulesIfNeeded()
        ToastCenter.shared.success(
            NSLocalizedString("Rule saved", value: "Rule saved", comment: "")
        )
    }

    private func cancelRule() {
        pendingNewRule = nil
        editingRule = nil
    }

    private func deleteRule(_ rule: Rule) {
        if pendingNewRule?.id != rule.id {
            modelContext.delete(rule)
            try? modelContext.save()
            reapplyRulesIfNeeded()
        }
        pendingNewRule = nil
        editingRule = nil
    }

    /// 全部 hidden 快捷键 button。SwiftUI ViewBuilder 在一个 closure 里
    /// 最多容纳 10 个 view,所以拆成 viewModeKeys + selectionKeys 两组。
    @ViewBuilder
    private var hiddenShortcuts: some View {
        Group {
            viewModeKeys
            selectionKeys
        }
    }

    @ViewBuilder
    private var viewModeKeys: some View {
        Group {
            Button("Grid") { viewMode.wrappedValue = .grid }.keyboardShortcut("1", modifiers: .command).hidden()
            Button("List") { viewMode.wrappedValue = .list }.keyboardShortcut("2", modifiers: .command).hidden()
            Button("Quick Look") { quickLookSelected() }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
            // ⌘A — Finder 全选语义:作用于当前过滤后的可见文件列表
            // (sidebar 选择 + 搜索都已过滤过)。搜索框聚焦时 SwiftUI 让
            // TextField 先消费,跟 Finder 一致 —— 这里无需特殊判断。
            Button("Select All") { selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(selectedWorkspace == nil)
                .hidden()
        }
    }

    @ViewBuilder
    private var selectionKeys: some View {
        // .disabled 必须只读 @State `selectedFileIDs`(Set<UUID>),不能调
        // currentSelection —— 后者每次都跑 filesForCurrentSelection,
        // hidden button × body 高频 recompute(indexing 期间 FileIndexer 每
        // 200 个文件 save 一次,每次都 @Bindable 通知整个 ContentView body
        // 重 build)= 数百次 ffcs/sec,顺带触发 SidebarView 的 fetchCount
        // 风暴(每秒 300+ SQL),主线程被 SQL 阻塞 → UI 卡死。
        // action closure 里的 currentSelection 是惰性的,点击时才跑一次,OK。
        //
        // 拆成两个 Group:SwiftUI ViewBuilder 单个 closure 上限 10 个 view,
        // 加了 ⌘C / ⌘D 后总数 12,溢出 ⇒ 编译报错。两个 Group 各自计数。
        let isEmpty = selectedFileIDs.isEmpty
        let isSingle = selectedFileIDs.count == 1
        Group {
            Button("Open") { FileActions.open(currentSelection) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(isEmpty).hidden()
            Button("Open (alt)") { FileActions.open(currentSelection) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(isEmpty).hidden()
            Button("Reveal in Finder") { FileActions.reveal(currentSelection) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isEmpty).hidden()
            Button("Move to Trash") {
                FileActions.moveToTrash(currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(isEmpty).hidden()
            // Finder ⌘C 语义:把 fileURL 放 NSPasteboard,之后在 Finder
            // 任意位置 ⌘V 能粘出真文件(不是路径文本,那是 ⌥⌘C)。
            Button("Copy") { FileActions.copyFiles(currentSelection) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(isEmpty).hidden()
            Button("Duplicate") { FileActions.duplicate(currentSelection) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(isEmpty).hidden()
            Button("Copy Path") { FileActions.copyPath(currentSelection) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(isEmpty).hidden()
            Button("Copy to…") { FileActions.copyTo(currentSelection) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(isEmpty).hidden()
            Button("Move to…") {
                FileActions.moveTo(currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(isEmpty).hidden()
            Button("Share…") { FileActions.share(currentSelection, from: nil) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(isEmpty).hidden()
        }
        Group {
            // Plain Return = rename(单文件,Finder 约定)。SwiftUI 的
            // keyboardShortcut 尊重 first-responder,搜索框等会先消费。
            Button("Rename…") {
                if let f = currentSelection.first {
                    FileActions.rename(f, modelContext: modelContext)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!isSingle).hidden()
            Button("Show Actions") {
                ActionMenu.popUp(for: currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(isEmpty).hidden()
        }
    }

    /// ⌘A 实现:把当前 workspace + sidebar + 搜索过滤后的全部文件 ID 灌进
    /// selectedFileIDs。点击时才跑 filesForCurrentSelection,有 filesMemo
    /// 二级缓存,O(1) 命中。
    @MainActor
    private func selectAllVisible() {
        guard let ws = selectedWorkspace else { return }
        let visible = filesForCurrentSelection(workspace: ws)
        selectedFileIDs = Set(visible.map(\.id))
    }

    @ViewBuilder
    private func statusBar(files: [FileSnapshot], selectedFiles: [FileSnapshot]) -> some View {
        let bytes: Int64 = (selectedFiles.count > 1 ? selectedFiles : files)
            .reduce(0) { $0 + $1.size }
        let label: String = {
            if selectedFiles.count > 1 {
                return String(format:
                    NSLocalizedString("status.selected.format",
                        value: "%lld of %lld selected", comment: ""),
                    selectedFiles.count, files.count)
            }
            return String(format:
                NSLocalizedString("status.items.format",
                    value: "%lld items", comment: ""), files.count)
        }()
        HStack(spacing: 6) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "·")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(byteFormatter.string(fromByteCount: bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            // Grid 视图右下角的图标大小滑块。Finder 同款交互。
            // 只在 grid 视图显示 —— list 视图行高一致,无需调节。
            if viewMode.wrappedValue == .grid {
                gridIconSizeSlider
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func encodeColumnVisibility(_ v: NavigationSplitViewVisibility) -> String {
        switch v {
        case .all:          return "all"
        case .doubleColumn: return "doubleColumn"
        case .detailOnly:   return "detailOnly"
        default:            return "automatic"
        }
    }

    private func decodeColumnVisibility(_ s: String) -> NavigationSplitViewVisibility {
        switch s {
        case "all":          return .all
        case "doubleColumn": return .doubleColumn
        case "detailOnly":   return .detailOnly
        default:             return .automatic
        }
    }

    /// 状态栏右下的图标大小调节器:左小右大两个图标 + 滑块,跟 Finder 一致。
    private var gridIconSizeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Slider(value: gridIconSize, in: 48...160)
                .frame(width: 100)
                .controlSize(.mini)
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// 用户当前选中的文件 (FileNode managed objects),给 hidden 快捷键 button
    /// 的 action closure 用。点击瞬间才计算 —— body recompute 时不调用,
    /// 不进 SwiftData observation 主路径。
    private var currentSelection: [FileNode] {
        guard let ws = selectedWorkspace else { return [] }
        let snapshots = filesForCurrentSelection(workspace: ws)
            .filter { selectedFileIDs.contains($0.id) }
        return resolveFileNodes(snapshots)
    }

    private func quickLookSelected() {
        let urls = currentSelection.compactMap { FileActions.url(for: $0) }
        guard !urls.isEmpty else { return }
        QuickLookCoordinator.shared.show(urls: urls)
    }

    /// macOS 14 fallback for `searchFocused` (which is macOS 15+):在 keyWindow 的
    /// toolbar 里挖出 SwiftUI `.searchable` 注入的 NSSearchField,然后
    /// makeFirstResponder。SwiftUI 把 search field 包成 NSSearchToolbarItem
    /// (有则直接用其 .searchField),没找到时再退回深度优先 subview 扫描兜底。
    private func focusToolbarSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let toolbar = window.toolbar else { return }
        for item in toolbar.items {
            if let searchItem = item as? NSSearchToolbarItem {
                window.makeFirstResponder(searchItem.searchField)
                return
            }
            if let view = item.view, let field = Self.findSearchField(in: view) {
                window.makeFirstResponder(field)
                return
            }
        }
    }

    private static func findSearchField(in root: NSView) -> NSSearchField? {
        if let sf = root as? NSSearchField { return sf }
        for sub in root.subviews {
            if let found = findSearchField(in: sub) { return found }
        }
        return nil
    }

    /// Window title reflects the current workspace + sidebar selection,
    /// e.g. "Downloads — 安装包" or "Downloads — 无标签". Defaults to "FileLens"
    /// when nothing has been picked yet.
    private var windowTitle: String {
        guard let ws = selectedWorkspace else { return "FileLens" }
        let displayed = ws.effectiveName
        switch selection {
        case .tag(_, let name):
            return "\(displayed) — \(TagDisplay.localizedName(name))"
        case .uncategorized:
            return "\(displayed) — \(NSLocalizedString("Unfiled", value: "Unfiled", comment: ""))"
        case .workspace, .none:
            return displayed
        }
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }
}

/// `filesForCurrentSelection` 的 memo 容器。class 引用类型,@State 只持有
/// 指针 —— 改内部字段不触发 SwiftUI 重 render(只有 @State 指针变了才会),
/// 适合做不影响视图的纯缓存。
///
/// 按 workspace 分桶,每个 workspace 内是 multi-key cache(workspace selection
/// + 各 tag selection)。版本戳是该 workspace 的 fileCount,scan 完成写回时
/// 仅清空那一个 workspace 的桶,跨 workspace 切回不重 fetch。
///
/// SwiftData FileNode 是 live managed object,silent scan 期间属性原地变,
/// cache 持有的引用始终是最新值;只有 isPresent 反转(vanished)的 stale 行
/// 会留在 cache 里 —— 等 fileCount 更新时一并清掉。
private final class FilesMemo {
    private struct Bucket {
        var versionKey: String
        var entries: [String: [FileSnapshot]]
        /// `[fileID : tag display names]`,Tags 列用。第一次访问按需 lazy
        /// 填充;fileCount 变化(scan 完成写回)Bucket 重建时一并清空。
        var tagsByFileID: [UUID: [String]]?
    }
    private var byWorkspace: [UUID: Bucket] = [:]

    func get(workspace ws: Workspace, selection: SidebarSelection?, search: String) -> [FileSnapshot]? {
        let v = Self.versionKey(ws: ws)
        guard let bucket = byWorkspace[ws.id], bucket.versionKey == v else {
            byWorkspace[ws.id] = Bucket(versionKey: v, entries: [:], tagsByFileID: nil)
            return nil
        }
        let k = Self.selectionKey(selection: selection, search: search)
        return bucket.entries[k]
    }

    func set(workspace ws: Workspace, selection: SidebarSelection?, search: String, files: [FileSnapshot]) {
        let v = Self.versionKey(ws: ws)
        var bucket = byWorkspace[ws.id] ?? Bucket(versionKey: v, entries: [:], tagsByFileID: nil)
        if bucket.versionKey != v {
            bucket = Bucket(versionKey: v, entries: [:], tagsByFileID: nil)
        }
        let k = Self.selectionKey(selection: selection, search: search)
        bucket.entries[k] = files
        byWorkspace[ws.id] = bucket
    }

    /// 取 [fileID : [tag names]] map。第一次缺失时由 caller 提供 builder
    /// (一次性 fetch FileTag),之后 cache 命中。fileCount 变化整 bucket 清空。
    func tagsByFileID(workspace ws: Workspace, build: () -> [UUID: [String]]) -> [UUID: [String]] {
        let v = Self.versionKey(ws: ws)
        var bucket = byWorkspace[ws.id] ?? Bucket(versionKey: v, entries: [:], tagsByFileID: nil)
        if bucket.versionKey != v {
            bucket = Bucket(versionKey: v, entries: [:], tagsByFileID: nil)
        }
        if let cached = bucket.tagsByFileID { return cached }
        let built = build()
        bucket.tagsByFileID = built
        byWorkspace[ws.id] = bucket
        return built
    }

    private static func versionKey(ws: Workspace) -> String {
        // 单看 fileCount 在"新增 N + vanished N = 净 0"场景下不变,cache
        // 永久 stale(Chrome .crdownload → 重命名 走的就是这个 path)。
        // 联合 scanGeneration(每次完整 scan +1)确保任何一次 scan 完成都
        // 让 cache 失效一次。
        "\(ws.fileCount)|\(ws.scanGeneration)"
    }

    private static func selectionKey(selection: SidebarSelection?, search: String) -> String {
        let sel: String
        switch selection {
        case .none:                       sel = "_"
        case .workspace(let id):          sel = "ws:\(id)"
        case .tag(_, let name):           sel = "t:\(name)"
        case .uncategorized(let id):      sel = "u:\(id)"
        }
        return "\(sel)|\(search)"
    }

    func invalidate() {
        byWorkspace.removeAll(keepingCapacity: false)
    }
}
