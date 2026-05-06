import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedWorkspace: Workspace?
    @State private var coordinator: WorkspaceCoordinator?
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [Workspace]

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedWorkspace: $selectedWorkspace, onAddFolder: addFolder)
                .frame(minWidth: 220)
        } detail: {
            if workspaces.isEmpty {
                EmptyStateView(onAddFolder: addFolder)
            } else if let ws = selectedWorkspace {
                Text("Workspace: \(ws.name) — \(ws.files.filter { $0.isPresent }.count) files")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a workspace from the sidebar")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
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
