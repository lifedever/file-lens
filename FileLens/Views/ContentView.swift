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
    @Query private var workspaces: [Workspace]

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
            if coordinator == nil {
                coordinator = WorkspaceCoordinator(container: modelContext.container)
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

    private func filesForCurrentSelection(workspace ws: Workspace) -> [FileNode] {
        // 廉价 memo key:同 (workspace, selection, search, file count) 直接命中
        // 缓存,跳过整条过滤链。SwiftData 增删文件会改 file count 触发重算。
        // tag 改动不在 key 里 —— reapplyRulesIfNeeded 末尾会调用 invalidate
        // 让重打 tag 后下次能强制重算。
        let key = filesMemo.key(workspace: ws,
                                selection: selection,
                                search: debouncedSearchText)
        if filesMemo.lastKey == key {
            return filesMemo.lastResult
        }

        let base: [FileNode]
        let present = ws.files.filter { $0.isPresent }
        switch selection {
        case .tag(_, let name):
            base = present.filter { $0.tags.contains(where: { $0.name == name }) }
        case .uncategorized:
            base = present.filter { $0.tags.isEmpty }
        default:
            base = present
        }

        let result = debouncedSearchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(debouncedSearchText) }

        // 注意:不再做外层 sort —— FileTableView/FileGridView 内部都按当前
        // sortOrder 重新分桶+排序,外层 sort 永远被覆盖,白做一次 O(n log n)。

        filesMemo.lastKey = key
        filesMemo.lastResult = result
        return result
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
        guard let ws = selectedWorkspace else { return }
        Task {
            let indexer = FileIndexer(container: modelContext.container)
            try? indexer.applyRules(workspace: ws)
            try? modelContext.save()
            // tag 重打过,memo 里基于 file count + selection name 算的 key
            // 没变化,但内容已经变了 —— 强制 invalidate 让下次 filter 重跑。
            await MainActor.run { filesMemo.invalidate() }
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
        let files = filesForCurrentSelection(workspace: ws)
        let selectedFiles = files.filter { selectedFileIDs.contains($0.id) }
        // SwiftData lazy fault(f.tags) + icon 同步 IO 都在父 body 收完,让
        // InspectorView 拿纯值。一直构建(不 gate showInspector)是为了 slide-out
        // 期间 inspector 还显示着旧数据,而不是闪成 "No selection"。
        // 把 workspace.rules 一起塞进 snapshot,Inspector 用来给标签匹配颜色
        // (跟 sidebar 那边的圆点颜色对齐)。读 ws.rules 在 main body 里同步
        // 走完,不会触发动画期间的 fault。
        let workspaceRules = ws.rules
        let inspectorSnapshot: InspectorSnapshot? = selectedFiles.first.map { f in
            InspectorSnapshot(file: f, rules: workspaceRules)
        }
        // 不用 SwiftUI 的 .inspector(isPresented:) —— 它底层是 NSSplitViewController,
        // pane slide 动画跟内容首帧渲染会撞,表现就是用户看到的"半 → 卡 → 半"
        // (slide 到一半 SwiftUI 同步渲染 inspector 内容、阻塞 main、动画卡住,
        // 然后再继续)。手动 HStack + .transition 由 SwiftUI 自己驱动,内容
        // 渲染和位移共享一个动画时钟,不会两边互相阻塞。
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                fileBody(files: files)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar(files: files, selectedFiles: selectedFiles)
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
    private func fileBody(files: [FileNode]) -> some View {
        if let ws = selectedWorkspace {
            switch viewMode.wrappedValue {
            case .grid:
                FileGridView(workspace: ws, files: files, selection: $selectedFileIDs)
                    .id(ws.id)
            case .list:
                FileTableView(workspace: ws, files: files, selection: $selectedFileIDs)
                    .id(ws.id)
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
        }
    }

    @ViewBuilder
    private var selectionKeys: some View {
        Group {
            Button("Open") { FileActions.open(currentSelection) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(currentSelection.isEmpty).hidden()
            Button("Open (alt)") { FileActions.open(currentSelection) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(currentSelection.isEmpty).hidden()
            Button("Reveal in Finder") { FileActions.reveal(currentSelection) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(currentSelection.isEmpty).hidden()
            Button("Move to Trash") {
                FileActions.moveToTrash(currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(currentSelection.isEmpty).hidden()
            Button("Copy Path") { FileActions.copyPath(currentSelection) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(currentSelection.isEmpty).hidden()
            Button("Copy to…") { FileActions.copyTo(currentSelection) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(currentSelection.isEmpty).hidden()
            Button("Move to…") {
                FileActions.moveTo(currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(currentSelection.isEmpty).hidden()
            Button("Share…") { FileActions.share(currentSelection, from: nil) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(currentSelection.isEmpty).hidden()
            // Plain Return = rename(单文件,Finder 约定)。SwiftUI 的
            // keyboardShortcut 尊重 first-responder,搜索框等会先消费。
            Button("Rename…") {
                if let f = currentSelection.first {
                    FileActions.rename(f, modelContext: modelContext)
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(currentSelection.count != 1).hidden()
            Button("Show Actions") {
                ActionMenu.popUp(for: currentSelection, modelContext: modelContext)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(currentSelection.isEmpty).hidden()
        }
    }

    @ViewBuilder
    private func statusBar(files: [FileNode], selectedFiles: [FileNode]) -> some View {
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

    /// Files matching the current multi-selection, in the same order they
    /// appear on screen.
    private var currentSelection: [FileNode] {
        guard let ws = selectedWorkspace else { return [] }
        return filesForCurrentSelection(workspace: ws)
            .filter { selectedFileIDs.contains($0.id) }
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
/// 指针 —— 改 lastKey/lastResult 不触发 SwiftUI 重 render(只有 @State 指
/// 针变了才会),适合做不影响视图的纯缓存。
private final class FilesMemo {
    var lastKey: String = ""
    var lastResult: [FileNode] = []

    /// 廉价 stable digest:workspace.id + 当前 selection + 搜索词 + 文件总数。
    /// tag 改动会经 reapplyRulesIfNeeded 显式 invalidate,不在这里算。
    func key(workspace ws: Workspace,
             selection: SidebarSelection?,
             search: String) -> String {
        let sel: String
        switch selection {
        case .none:                       sel = "_"
        case .workspace(let id):          sel = "ws:\(id)"
        case .tag(_, let name):           sel = "t:\(name)"
        case .uncategorized(let id):      sel = "u:\(id)"
        }
        return "\(ws.id)|\(sel)|\(search)|\(ws.files.count)"
    }

    func invalidate() {
        lastKey = ""
        lastResult = []
    }
}
