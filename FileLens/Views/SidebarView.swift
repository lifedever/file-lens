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
            ForEach(workspaces) { ws in
                Section {
                    if !collapsed.contains(ws.id) {
                        // "All files" row for the workspace
                        Label {
                            Text("All files")
                        } icon: {
                            Image(systemName: "folder")
                                .foregroundStyle(.tint)
                        }
                        .badge(ws.files.filter { $0.isPresent }.count)
                        .tag(SidebarSelection.workspace(ws.id))

                        // Tag rows
                        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
                            Label(TagDisplay.localizedName(rule.name), systemImage: "tag")
                                .badge(filesCount(for: ws, tag: rule.name))
                                .opacity(rule.enabled ? 1.0 : 0.5)
                                .tag(SidebarSelection.tag(workspaceID: ws.id, name: rule.name))
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
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        // System rows
                        Label("Uncategorized", systemImage: "questionmark.circle")
                            .badge(uncategorizedCount(for: ws))
                            .tag(SidebarSelection.uncategorized(workspaceID: ws.id))

                        Label("Trashed", systemImage: "trash")
                            .badge(trashedCount(for: ws))
                            .tag(SidebarSelection.trashed(workspaceID: ws.id))
                    }
                } header: {
                    workspaceSectionHeader(ws)
                }
            }

            Section {
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
            switch sel {
            case .workspace(let id):
                if let ws = workspaces.first(where: { $0.id == id }) { selectedWorkspace = ws }
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

    @ViewBuilder
    private func workspaceSectionHeader(_ ws: Workspace) -> some View {
        let isCollapsed = collapsed.contains(ws.id)
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.caption)
            Text(ws.name)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollapsed { collapsed.remove(ws.id) }
            else           { collapsed.insert(ws.id) }
        }
        .padding(.vertical, 2)
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
