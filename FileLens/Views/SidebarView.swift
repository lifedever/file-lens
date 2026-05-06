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
                    workspaceHeader(ws)
                    if !collapsed.contains(ws.id) {
                        nestedRows(for: ws)
                    }
                }
                Button {
                    onAddFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, sel in
            // When user clicks a tag/system row in any workspace, make
            // that workspace active so the file view filters correctly.
            switch sel {
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

    // MARK: Workspace header (folder row, with chevron)

    @ViewBuilder
    private func workspaceHeader(_ ws: Workspace) -> some View {
        let isExpanded = !collapsed.contains(ws.id)
        let isActive = ws.id == selectedWorkspace?.id

        HStack(spacing: 4) {
            Button {
                toggleCollapse(ws.id)
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: isActive ? "folder.fill" : "folder")
                .foregroundStyle(.tint)
            Text(ws.name)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(ws.files.filter { $0.isPresent }.count)")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap on the row (anywhere outside the chevron) selects the workspace.
            selectedWorkspace = ws
            selection = nil
        }
        .padding(.vertical, 3)
    }

    // MARK: Nested tag + system rows under a workspace

    @ViewBuilder
    private func nestedRows(for ws: Workspace) -> some View {
        // Tag rows — use .tag() so List renders native selection styling.
        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
            Label {
                HStack {
                    Text(verbatim: TagDisplay.localizedName(rule.name))
                        .lineLimit(1)
                    Spacer()
                    let count = filesCount(for: ws, tag: rule.name)
                    if count > 0 {
                        Text("\(count)")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                }
            } icon: {
                Image(systemName: "tag")
            }
            .padding(.leading, 18)
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
                .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)

        // System rows — also use native .tag() selection
        Label {
            HStack {
                Text("Uncategorized")
                Spacer()
                let count = uncategorizedCount(for: ws)
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
            }
        } icon: {
            Image(systemName: "questionmark.circle")
        }
        .padding(.leading, 18)
        .tag(SidebarSelection.uncategorized(workspaceID: ws.id) as SidebarSelection?)

        Label {
            HStack {
                Text("Trashed")
                Spacer()
                let count = trashedCount(for: ws)
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
            }
        } icon: {
            Image(systemName: "trash")
        }
        .padding(.leading, 18)
        .tag(SidebarSelection.trashed(workspaceID: ws.id) as SidebarSelection?)
    }

    private func toggleCollapse(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) }
        else { collapsed.insert(id) }
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
