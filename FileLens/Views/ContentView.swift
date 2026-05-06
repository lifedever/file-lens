import SwiftUI
import SwiftData

enum ViewMode: Int { case grid = 1, list = 2, gallery = 4 }

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
    @State private var viewMode: ViewMode = .list
    /// Multi-selection of file IDs. We store IDs (not FileNode) so the set
    /// stays valid across SwiftData refresh cycles.
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var showInspector: Bool = false
    @State private var pendingWorkspace: PendingWorkspace?
    @State private var editingRule: Rule?
    /// A freshly-created Rule that hasn't been inserted into the ModelContext yet.
    /// Set by `newRule()` and committed on Save inside the sheet. Lets us drop
    /// the draft on Cancel without leaving an orphan.
    @State private var pendingNewRule: Rule?
    @State private var welcomeOpen: Bool = false
    /// Tracks whether the sidebar is shown. We keep the state local so we
    /// can collapse it automatically when there are no workspaces (the
    /// sidebar would just be empty space + the support footer otherwise).
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @AppStorage("filelens.onboardingCompleted") private var onboardingCompleted: Bool = false
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = false
    @State private var searchText: String = ""
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

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
                }
            )
            .frame(minWidth: 220)
        } detail: {
            if workspaces.isEmpty {
                EmptyStateView(onAddFolder: addFolder)
            } else if let ws = selectedWorkspace {
                let files = filesForCurrentSelection(workspace: ws)
                let selectedFiles = files.filter { selectedFileIDs.contains($0.id) }
                VStack(spacing: 0) {
                    Group {
                        switch viewMode {
                        case .grid:    FileGridView(files: files, selection: $selectedFileIDs)
                        case .list:    FileTableView(files: files, selection: $selectedFileIDs)
                        case .gallery: GalleryView(files: files)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    HStack {
                        if selectedFiles.count > 1 {
                            Text("\(selectedFiles.count) of \(files.count) selected")
                            Text("·")
                            Text(byteFormatter.string(fromByteCount: selectedFiles.reduce(0) { $0 + $1.size }))
                        } else {
                            Text("\(files.count) items")
                            Text("·")
                            Text(byteFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .searchable(text: $searchText, placement: .toolbar)
                .inspector(isPresented: $showInspector) {
                    InspectorView(file: selectedFiles.first)
                        .inspectorColumnWidth(min: 220, ideal: 280, max: 400)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Picker("View", selection: $viewMode) {
                            Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                            Image(systemName: "list.bullet").tag(ViewMode.list)
                            Image(systemName: "rectangle.grid.1x2").tag(ViewMode.gallery)
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
            } else {
                // Empty hero — there are workspaces, just nothing picked.
                // ContentUnavailableView gives us the native centered look
                // with the right hierarchy: icon, title, supporting text.
                ContentUnavailableView {
                    Label("empty.workspace.title", systemImage: "sidebar.left")
                } description: {
                    Text("empty.workspace.subtitle")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle(windowTitle)
        .sheet(item: $pendingWorkspace) { pending in
            FirstRunRulePicker(
                folderName: pending.url.lastPathComponent,
                rules: pending.rules,
                onConfirm: { enabledIDs in
                    commitWorkspace(pending: pending, enabledRuleIDs: enabledIDs)
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
        .task {
            // First-launch onboarding. The flag persists across launches so
            // returning users don't see the sheet again unless they invoke
            // it from Settings.
            if !onboardingCompleted {
                welcomeOpen = true
            }
            // Collapse the sidebar when there are no workspaces — empty
            // sidebar plus the empty hero in detail looked twice as empty.
            if workspaces.isEmpty {
                columnVisibility = .detailOnly
            }
        }
        .onChange(of: workspaces.isEmpty) { _, isEmpty in
            // First workspace added: restore the standard split view. If
            // every workspace is removed, hide the sidebar again.
            columnVisibility = isEmpty ? .detailOnly : .all
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcome)) { _ in
            welcomeOpen = true
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                isNewRule: pendingNewRule?.id == rule.id,
                onSave: {
                    if let pending = pendingNewRule, pending.id == rule.id,
                       let ws = selectedWorkspace {
                        // Commit the draft rule into the context now.
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
                },
                onCancel: {
                    // Drop the draft entirely; nothing was inserted.
                    pendingNewRule = nil
                    editingRule = nil
                },
                onDelete: {
                    if pendingNewRule?.id != rule.id {
                        modelContext.delete(rule)
                        try? modelContext.save()
                        reapplyRulesIfNeeded()
                    }
                    pendingNewRule = nil
                    editingRule = nil
                }
            )
        }
        .background(
            Group {
                Button("Grid")    { viewMode = .grid    }.keyboardShortcut("1", modifiers: .command).hidden()
                Button("List")    { viewMode = .list    }.keyboardShortcut("2", modifiers: .command).hidden()
                Button("Gallery") { viewMode = .gallery }.keyboardShortcut("4", modifiers: .command).hidden()
                Button("Quick Look") { quickLookSelected() }
                    .keyboardShortcut(.space, modifiers: [])
                    .hidden()
                Button("Open") { FileActions.open(currentSelection) }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                Button("Open (alt)") { FileActions.open(currentSelection) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                Button("Reveal in Finder") { FileActions.reveal(currentSelection) }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                Button("Move to Trash") {
                    FileActions.moveToTrash(currentSelection, modelContext: modelContext)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(currentSelection.isEmpty)
                .hidden()
                Button("Copy Path") { FileActions.copyPath(currentSelection) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                Button("Copy to…") { FileActions.copyTo(currentSelection) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                Button("Move to…") {
                    FileActions.moveTo(currentSelection, modelContext: modelContext)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(currentSelection.isEmpty)
                .hidden()
                Button("Share…") { FileActions.share(currentSelection, from: nil) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(currentSelection.isEmpty)
                    .hidden()
                // Plain Return = rename, single-file only (matches Finder).
                // SwiftUI's keyboardShortcut respects first-responder focus,
                // so text fields like the search bar still consume Return
                // before it reaches this button.
                Button("Rename…") {
                    if let f = currentSelection.first {
                        FileActions.rename(f, modelContext: modelContext)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(currentSelection.count != 1)
                .hidden()
                Button("Show Actions") {
                    ActionMenu.popUp(for: currentSelection, modelContext: modelContext)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(currentSelection.isEmpty)
                .hidden()
            }
        )
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
        // Publish actions to the macOS menu bar (File → Add Folder…, New Rule…)
        .focusedValue(\.addFolderAction, addFolder)
        .focusedValue(\.newRuleAction, newRule)
        .focusedValue(\.activeWorkspaceName, selectedWorkspace?.name)
    }

    private func filesForCurrentSelection(workspace ws: Workspace) -> [FileNode] {
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

        let filtered = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        return filtered.sorted { $0.dateAdded > $1.dateAdded }
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

    private func commitWorkspace(pending: PendingWorkspace, enabledRuleIDs: Set<UUID>) {
        do {
            let bookmark = try BookmarkStore.makeBookmark(for: pending.url)
            let ws = Workspace(name: pending.url.lastPathComponent,
                               folderPath: pending.url.path,
                               bookmarkData: bookmark)
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

    private func newRule() {
        guard let ws = selectedWorkspace else { return }
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

    /// Window title reflects the current workspace + sidebar selection,
    /// e.g. "Downloads — 安装包" or "Downloads — 无标签". Defaults to "FileLens"
    /// when nothing has been picked yet.
    private var windowTitle: String {
        guard let ws = selectedWorkspace else { return "FileLens" }
        switch selection {
        case .tag(_, let name):
            return "\(ws.name) — \(TagDisplay.localizedName(name))"
        case .uncategorized:
            return "\(ws.name) — \(NSLocalizedString("Unfiled", value: "Unfiled", comment: ""))"
        case .workspace, .none:
            return ws.name
        }
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }
}
