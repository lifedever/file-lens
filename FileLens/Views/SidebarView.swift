import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    let onAddFolder: () -> Void

    var body: some View {
        List(selection: $selectedWorkspace) {
            Section("Workspaces") {
                ForEach(workspaces) { ws in
                    Label(ws.name, systemImage: "folder")
                        .tag(ws as Workspace?)
                }
                Button {
                    onAddFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
