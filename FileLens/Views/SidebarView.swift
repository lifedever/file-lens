import SwiftUI
import SwiftData
import AppKit

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
    let onDeleteRule: (Rule) -> Void

    @State private var collapsed: Set<UUID> = []
    @State private var ruleToDelete: Rule?

    var body: some View {
        List(selection: $selection) {
            ForEach(workspaces) { ws in
                Section {
                    if !collapsed.contains(ws.id) {
                        // "All files" — selecting the workspace itself
                        Label {
                            Text("All files")
                        } icon: {
                            Image(nsImage: workspaceIcon(for: ws))
                                .resizable().interpolation(.high)
                                .frame(width: 18, height: 18)
                        }
                        .badge(ws.files.filter { $0.isPresent }.count)
                        .tag(SidebarSelection.workspace(ws.id))

                        // User rules → tag rows
                        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
                            Label {
                                Text(verbatim: TagDisplay.localizedName(rule.name))
                            } icon: {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(.tint)
                            }
                            .badge(filesCount(for: ws, tag: rule.name))
                            .opacity(rule.enabled ? 1.0 : 0.5)
                            .tag(SidebarSelection.tag(workspaceID: ws.id, name: rule.name))
                            .contextMenu {
                                Button("Edit Rule…") { onEditRule(rule) }
                                Button(rule.enabled ? "Disable" : "Enable") {
                                    rule.enabled.toggle()
                                }
                                Divider()
                                Button("Delete Rule", role: .destructive) {
                                    ruleToDelete = rule
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

                        // Visual separator before the System rows
                        Color.clear.frame(height: 8)
                            .listRowSeparator(.hidden)

                        // System rows
                        Label {
                            Text("Uncategorized")
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .badge(uncategorizedCount(for: ws))
                        .tag(SidebarSelection.uncategorized(workspaceID: ws.id))

                        Label {
                            Text("Trashed")
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
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
        .confirmationDialog(
            "delete.confirm.title",
            isPresented: Binding(
                get: { ruleToDelete != nil },
                set: { if !$0 { ruleToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: ruleToDelete
        ) { rule in
            Button("Delete Rule", role: .destructive) {
                onDeleteRule(rule)
                ruleToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                ruleToDelete = nil
            }
        } message: { rule in
            Text(verbatim: String(format:
                NSLocalizedString("delete.confirm.message.format",
                    value: "Files keep any other tags. The “%@” rule will be removed from this workspace.",
                    comment: ""),
                TagDisplay.localizedName(rule.name)))
        }
    }

    // MARK: Workspace section header (collapsible folder row)

    @ViewBuilder
    private func workspaceSectionHeader(_ ws: Workspace) -> some View {
        let isCollapsed = collapsed.contains(ws.id)
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Image(nsImage: workspaceIcon(for: ws))
                .resizable().interpolation(.high)
                .frame(width: 20, height: 20)
            Text(ws.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollapsed { collapsed.remove(ws.id) }
            else           { collapsed.insert(ws.id) }
        }
        .padding(.vertical, 3)
        .textCase(nil)  // override List sidebar's automatic uppercasing
    }

    // MARK: Helpers

    private func workspaceIcon(for ws: Workspace) -> NSImage {
        if FileManager.default.fileExists(atPath: ws.folderPath) {
            return NSWorkspace.shared.icon(forFile: ws.folderPath)
        }
        // Fallback: generic folder icon
        return NSWorkspace.shared.icon(for: .folder)
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
