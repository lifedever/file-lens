import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case workspace(UUID)        // not selectable directly — header/marker
    case tag(workspaceID: UUID, name: String)
    case uncategorized(workspaceID: UUID)
    case trashed(workspaceID: UUID)
}

struct SidebarView: View {
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @Binding var selection: SidebarSelection?
    @Binding var selectedWorkspace: Workspace?
    let onAddFolder: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Workspaces") {
                ForEach(workspaces) { ws in
                    Button(action: { selectedWorkspace = ws }) {
                        HStack {
                            Image(systemName: "folder")
                            Text(ws.name)
                            Spacer()
                            Text("\(ws.files.filter { $0.isPresent }.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                Button {
                    onAddFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .buttonStyle(.plain)
            }

            if let ws = selectedWorkspace {
                Section("Tags") {
                    ForEach(tags(for: ws), id: \.self) { tag in
                        let count = filesCount(for: ws, tag: tag)
                        Label("\(tag)", systemImage: "tag")
                            .badge(count)
                            .tag(SidebarSelection.tag(workspaceID: ws.id, name: tag) as SidebarSelection?)
                    }
                }
                Section("System") {
                    Label("Uncategorized", systemImage: "questionmark.circle")
                        .badge(uncategorizedCount(for: ws))
                        .tag(SidebarSelection.uncategorized(workspaceID: ws.id) as SidebarSelection?)
                    Label("Trashed", systemImage: "trash")
                        .badge(trashedCount(for: ws))
                        .tag(SidebarSelection.trashed(workspaceID: ws.id) as SidebarSelection?)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func tags(for ws: Workspace) -> [String] {
        var names = Set<String>()
        for f in ws.files where f.isPresent {
            for t in f.tags { names.insert(t.name) }
        }
        return names.sorted()
    }

    private func filesCount(for ws: Workspace, tag: String) -> Int {
        ws.files.filter { f in f.isPresent && f.tags.contains(where: { $0.name == tag }) }.count
    }

    private func uncategorizedCount(for ws: Workspace) -> Int {
        ws.files.filter { $0.isPresent && $0.tags.isEmpty }.count
    }

    private func trashedCount(for ws: Workspace) -> Int {
        ws.files.filter { !$0.isPresent }.count
    }
}
