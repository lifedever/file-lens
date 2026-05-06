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
    @State private var selectedFile: FileNode?
    @State private var showInspector: Bool = false
    @State private var pendingWorkspace: PendingWorkspace?
    @State private var editingRule: Rule?
    /// A freshly-created Rule that hasn't been inserted into the ModelContext yet.
    /// Set by `newRule()` and committed on Save inside the sheet. Lets us drop
    /// the draft on Cancel without leaving an orphan.
    @State private var pendingNewRule: Rule?
    @AppStorage("filelens.autoExpandInspector") private var autoExpandInspector: Bool = false
    @State private var searchText: String = ""
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                selectedWorkspace: $selectedWorkspace,
                onAddFolder: addFolder,
                onNewRule: newRule,
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
                VStack(spacing: 0) {
                    Group {
                        switch viewMode {
                        case .grid:    FileGridView(files: files, selectedFile: $selectedFile)
                        case .list:    FileTableView(files: files, selectedFile: $selectedFile)
                        case .gallery: GalleryView(files: files)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    HStack {
                        Text("\(files.count) items")
                        Text("·")
                        Text(byteFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .searchable(text: $searchText, placement: .toolbar)
                .inspector(isPresented: $showInspector) {
                    InspectorView(file: selectedFile)
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
                Text("Select a workspace from the sidebar")
                    .foregroundStyle(.secondary)
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
                Button("Open") {
                    if let f = selectedFile { FileActions.open(f) }
                }
                .keyboardShortcut(.return, modifiers: .command)
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
        .onChange(of: selectedFile) { _, newFile in
            // Respect the user's setting; off by default. Selecting a file
            // doesn't pop the inspector unless the user opted in.
            if autoExpandInspector, newFile != nil {
                showInspector = true
            }
        }
    }

    private func filesForCurrentSelection(workspace ws: Workspace) -> [FileNode] {
        let base: [FileNode]
        let present = ws.files.filter { $0.isPresent }
        switch selection {
        case .tag(_, let name):
            base = present.filter { $0.tags.contains(where: { $0.name == name }) }
        case .uncategorized:
            base = present.filter { $0.tags.isEmpty }
        case .trashed:
            base = ws.files.filter { !$0.isPresent }
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

    private func quickLookSelected() {
        guard let f = selectedFile, let url = FileActions.url(for: f) else { return }
        QuickLookCoordinator.shared.show(urls: [url])
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
            return "\(ws.name) — \(NSLocalizedString("Uncategorized", value: "Uncategorized", comment: ""))"
        case .trashed:
            return "\(ws.name) — \(NSLocalizedString("Trashed", value: "Trashed", comment: ""))"
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
