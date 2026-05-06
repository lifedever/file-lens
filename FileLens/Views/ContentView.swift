import SwiftUI
import SwiftData

enum ViewMode: Int { case grid = 1, list = 2, gallery = 4 }

struct ContentView: View {
    @State private var selectedWorkspace: Workspace?
    @State private var selection: SidebarSelection?
    @State private var coordinator: WorkspaceCoordinator?
    @State private var viewMode: ViewMode = .grid
    @State private var selectedFile: FileNode?
    @State private var showInspector: Bool = false
    @State private var pendingWorkspaceURL: URL?
    @State private var pendingRules: [Rule] = []
    @State private var showFirstRunPicker: Bool = false
    @State private var editingRule: Rule?
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
                onEditRule: { editingRule = $0 }
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
                        case .list:    FileTableView(files: files)
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
                            Image(systemName: "sidebar.right")
                        }
                        .keyboardShortcut("i", modifiers: .command)
                    }
                }
            } else {
                Text("Select a workspace from the sidebar")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showFirstRunPicker) {
            FirstRunRulePicker(
                rules: pendingRules,
                onConfirm: commitWorkspace,
                onCancel: {
                    pendingWorkspaceURL = nil
                    pendingRules = []
                    showFirstRunPicker = false
                }
            )
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(
                rule: rule,
                onSave: {
                    try? modelContext.save()
                    editingRule = nil
                    if let ws = selectedWorkspace {
                        Task {
                            let indexer = FileIndexer(container: modelContext.container)
                            try? indexer.applyRules(workspace: ws)
                            try? modelContext.save()
                        }
                    }
                },
                onCancel: { editingRule = nil },
                onDelete: rule.isBuiltIn ? nil : {
                    modelContext.delete(rule)
                    try? modelContext.save()
                    editingRule = nil
                }
            )
        }
        .background(
            Group {
                Button("Grid")    { viewMode = .grid    }.keyboardShortcut("1", modifiers: .command).hidden()
                Button("List")    { viewMode = .list    }.keyboardShortcut("2", modifiers: .command).hidden()
                Button("Gallery") { viewMode = .gallery }.keyboardShortcut("4", modifiers: .command).hidden()
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
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingWorkspaceURL = url
        pendingRules = BuiltInRules.all()
        showFirstRunPicker = true
    }

    private func commitWorkspace(enabledRuleIDs: Set<UUID>) {
        guard let url = pendingWorkspaceURL else { return }
        do {
            let bookmark = try BookmarkStore.makeBookmark(for: url)
            let ws = Workspace(name: url.lastPathComponent, folderPath: url.path, bookmarkData: bookmark)
            modelContext.insert(ws)
            for rule in pendingRules where enabledRuleIDs.contains(rule.id) {
                rule.workspace = ws
                modelContext.insert(rule)
            }
            try modelContext.save()
            selectedWorkspace = ws
        } catch {
            NSAlert(error: error).runModal()
        }
        pendingWorkspaceURL = nil
        pendingRules = []
        showFirstRunPicker = false
    }

    private func newRule() {
        guard let ws = selectedWorkspace else { return }
        let rule = Rule(name: "Untitled", color: "#3B82F6", enabled: true,
                        priority: (ws.rules.map(\.priority).max() ?? 0) + 10,
                        combinator: "any", isBuiltIn: false)
        rule.conditions.append(Condition(field: "extension", op: "is", value: ""))
        rule.workspace = ws
        modelContext.insert(rule)
        editingRule = rule
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }
}
