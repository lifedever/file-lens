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

    @State private var collapsed: Set<UUID> = []

    var body: some View {
        List(selection: $selection) {
            Section("Workspaces") {
                ForEach(workspaces) { ws in
                    DisclosureGroup(isExpanded: expansionBinding(for: ws.id)) {
                        // Tag rows
                        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
                            Label {
                                Text(verbatim: TagDisplay.localizedName(rule.name))
                            } icon: {
                                Image(systemName: "tag")
                            }
                            .badge(filesCount(for: ws, tag: rule.name))
                            .opacity(rule.enabled ? 1.0 : 0.5)
                            .tag(SidebarSelection.tag(workspaceID: ws.id, name: rule.name) as SidebarSelection?)
                            .contextMenu {
                                Button("Edit Rule…") { onEditRule(rule) }
                                Button(rule.enabled ? "Disable" : "Enable") {
                                    rule.enabled.toggle()
                                }
                            }
                        }

                        // New Rule button (not selectable)
                        Button {
                            onNewRule()
                        } label: {
                            Label("New Rule…", systemImage: "plus")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        // System rows
                        Label("Uncategorized", systemImage: "questionmark.circle")
                            .badge(uncategorizedCount(for: ws))
                            .tag(SidebarSelection.uncategorized(workspaceID: ws.id) as SidebarSelection?)

                        Label("Trashed", systemImage: "trash")
                            .badge(trashedCount(for: ws))
                            .tag(SidebarSelection.trashed(workspaceID: ws.id) as SidebarSelection?)
                    } label: {
                        let isActive = ws.id == selectedWorkspace?.id
                        Label {
                            Text(ws.name)
                                .fontWeight(isActive ? .semibold : .regular)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: isActive ? "folder.fill" : "folder")
                                .foregroundStyle(.tint)
                        }
                        .badge(ws.files.filter { $0.isPresent }.count)
                    }
                    .tag(SidebarSelection.workspace(ws.id) as SidebarSelection?)
                }

                Button {
                    onAddFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, sel in
            // Selecting any row in a workspace activates that workspace
            // so the file view filters correctly.
            switch sel {
            case .workspace(let id):
                if let ws = workspaces.first(where: { $0.id == id }) {
                    selectedWorkspace = ws
                }
            case .tag(let wsID, _),
                 .uncategorized(let wsID),
                 .trashed(let wsID):
                if let ws = workspaces.first(where: { $0.id == wsID }),
                   ws.id != selectedWorkspace?.id {
                    selectedWorkspace = ws
                }
            default:
                break
            }
        }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { isExpanded in
                if isExpanded { collapsed.remove(id) }
                else          { collapsed.insert(id) }
            }
        )
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
