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
                    workspaceRow(ws)
                    if ws.id == selectedWorkspace?.id {
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
    }

    @ViewBuilder
    private func workspaceRow(_ ws: Workspace) -> some View {
        let isSelected = ws.id == selectedWorkspace?.id
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .foregroundStyle(.tint)
            Text(ws.name)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Text("\(ws.files.filter { $0.isPresent }.count)")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedWorkspace = ws
            selection = nil
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func nestedRows(for ws: Workspace) -> some View {
        // Tag rows (indented)
        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(rule.enabled ? .secondary : Color.secondary.opacity(0.4))
                Text(verbatim: TagDisplay.localizedName(rule.name))
                Spacer()
                let count = filesCount(for: ws, tag: rule.name)
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .opacity(rule.enabled ? 1.0 : 0.5)
            .onTapGesture {
                selection = .tag(workspaceID: ws.id, name: rule.name)
            }
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isTagSelected(ws: ws, name: rule.name) ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, -4)
            )
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
                .padding(.leading, 16)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)

        // Divider between tags and system rows
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 1)
            .padding(.leading, 28)
            .padding(.vertical, 4)

        // System rows (Uncategorized + Trashed)
        systemRow(label: "Uncategorized", systemImage: "questionmark.circle",
                  count: uncategorizedCount(for: ws),
                  isSelected: isUncategorizedSelected(ws: ws),
                  action: { selection = .uncategorized(workspaceID: ws.id) })
        systemRow(label: "Trashed", systemImage: "trash",
                  count: trashedCount(for: ws),
                  isSelected: isTrashedSelected(ws: ws),
                  action: { selection = .trashed(workspaceID: ws.id) })
    }

    @ViewBuilder
    private func systemRow(label: LocalizedStringKey, systemImage: String,
                           count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(.leading, 16)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .padding(.horizontal, -4)
        )
    }

    private func isTagSelected(ws: Workspace, name: String) -> Bool {
        if case let .tag(wsID, n) = selection { return wsID == ws.id && n == name }
        return false
    }
    private func isUncategorizedSelected(ws: Workspace) -> Bool {
        if case let .uncategorized(wsID) = selection { return wsID == ws.id }
        return false
    }
    private func isTrashedSelected(ws: Workspace) -> Bool {
        if case let .trashed(wsID) = selection { return wsID == ws.id }
        return false
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
