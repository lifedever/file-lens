import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case workspace(UUID)
    case tag(workspaceID: UUID, name: String)
    case uncategorized(workspaceID: UUID)
    case trashed(workspaceID: UUID)
}

struct SidebarView: View {
    @Query(sort: \Workspace.createdAt) private var workspaces: [Workspace]
    @Binding var selection: SidebarSelection?
    @Binding var selectedWorkspace: Workspace?
    let onAddFolder: () -> Void
    let onNewRule: () -> Void
    let onEditRule: (Rule) -> Void

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
                    ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
                        Label {
                            Text(verbatim: NSLocalizedString(rule.name, value: rule.name, comment: ""))
                        } icon: {
                            Image(systemName: "tag")
                        }
                            .badge(filesCount(for: ws, tag: rule.name))
                            .tag(SidebarSelection.tag(workspaceID: ws.id, name: rule.name) as SidebarSelection?)
                            .opacity(rule.enabled ? 1.0 : 0.5)
                            .contextMenu {
                                Button("Edit Rule…") { onEditRule(rule) }
                                Button(rule.enabled ? "Disable" : "Enable") {
                                    rule.enabled.toggle()
                                }
                            }
                    }
                    Button {
                        onNewRule()
                    } label: {
                        Label("New Rule…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
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
