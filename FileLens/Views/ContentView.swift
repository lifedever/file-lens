import SwiftUI
import SwiftData

enum ViewMode: Int { case grid = 1, list = 2, gallery = 4 }

struct ContentView: View {
    @State private var selectedWorkspace: Workspace?
    @State private var selection: SidebarSelection?
    @State private var coordinator: WorkspaceCoordinator?
    @State private var viewMode: ViewMode = .grid
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                selectedWorkspace: $selectedWorkspace,
                onAddFolder: addFolder
            )
            .frame(minWidth: 220)
        } detail: {
            if workspaces.isEmpty {
                EmptyStateView(onAddFolder: addFolder)
            } else if let ws = selectedWorkspace {
                let files = filesForCurrentSelection(workspace: ws)
                Group {
                    switch viewMode {
                    case .grid:    FileGridView(files: files)
                    case .list:    FileTableView(files: files)
                    case .gallery: FileGridView(files: files)  // Task 19 swaps this to GalleryView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Picker("View", selection: $viewMode) {
                            Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                            Image(systemName: "list.bullet").tag(ViewMode.list)
                            Image(systemName: "rectangle.grid.1x2").tag(ViewMode.gallery)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            } else {
                Text("Select a workspace from the sidebar")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
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
        let present = ws.files.filter { $0.isPresent }
        switch selection {
        case .tag(_, let name):
            return present.filter { $0.tags.contains(where: { $0.name == name }) }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .uncategorized:
            return present.filter { $0.tags.isEmpty }
                .sorted { $0.dateAdded > $1.dateAdded }
        case .trashed:
            return ws.files.filter { !$0.isPresent }
                .sorted { $0.dateAdded > $1.dateAdded }
        default:
            return present.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try BookmarkStore.makeBookmark(for: url)
            let ws = Workspace(name: url.lastPathComponent, folderPath: url.path, bookmarkData: bookmark)
            modelContext.insert(ws)
            for rule in BuiltInRules.all() {
                rule.workspace = ws
                modelContext.insert(rule)
            }
            try modelContext.save()
            selectedWorkspace = ws
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
