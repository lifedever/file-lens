import SwiftUI
import SwiftData
import AppKit

enum SidebarSelection: Hashable {
    case workspace(UUID)
    case tag(workspaceID: UUID, name: String)
    case uncategorized(workspaceID: UUID)
    case trashed(workspaceID: UUID)
}

private let kIconSize: CGFloat = 16

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
                        // "All files" — pick the workspace itself
                        rowLabel(
                            text: Text("All files"),
                            count: ws.files.filter { $0.isPresent }.count,
                            icon: AnyView(folderIcon(for: ws))
                        )
                        .tag(SidebarSelection.workspace(ws.id))

                        // User rules → tag rows
                        ForEach(ws.rules.sorted(by: { $0.priority < $1.priority })) { rule in
                            rowLabel(
                                text: Text(verbatim: TagDisplay.localizedName(rule.name)),
                                count: filesCount(for: ws, tag: rule.name),
                                icon: AnyView(symbolIcon("tag.fill").foregroundStyle(.tint))
                            )
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
                            Label {
                                Text("New Rule…").foregroundStyle(.secondary)
                            } icon: {
                                symbolIcon("plus").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Visual separator before System rows
                        Color.clear.frame(height: 6)
                            .listRowSeparator(.hidden)

                        // System rows
                        rowLabel(
                            text: Text("Uncategorized"),
                            count: uncategorizedCount(for: ws),
                            icon: AnyView(symbolIcon("questionmark.circle").foregroundStyle(.secondary))
                        )
                        .tag(SidebarSelection.uncategorized(workspaceID: ws.id))

                        rowLabel(
                            text: Text("Trashed"),
                            count: trashedCount(for: ws),
                            icon: AnyView(symbolIcon("trash").foregroundStyle(.secondary))
                        )
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
                    Label {
                        Text("Add Folder…").foregroundStyle(.secondary)
                    } icon: {
                        symbolIcon("plus").foregroundStyle(.secondary)
                    }
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

    // MARK: Row label with custom count badge

    @ViewBuilder
    private func rowLabel(text: Text, count: Int, icon: AnyView) -> some View {
        Label {
            HStack(spacing: 6) {
                text
                Spacer(minLength: 4)
                if count > 0 {
                    CountBadge(count: count)
                }
            }
        } icon: {
            icon
        }
    }

    // MARK: Workspace section header (collapsible folder row)

    @ViewBuilder
    private func workspaceSectionHeader(_ ws: Workspace) -> some View {
        let isCollapsed = collapsed.contains(ws.id)
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            folderIcon(for: ws)
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
        .padding(.vertical, 2)
        .textCase(nil)
    }

    // MARK: Icon builders — uniform 16px

    private func folderIcon(for ws: Workspace) -> some View {
        let img: NSImage = {
            if FileManager.default.fileExists(atPath: ws.folderPath) {
                return NSWorkspace.shared.icon(forFile: ws.folderPath)
            }
            return NSWorkspace.shared.icon(for: .folder)
        }()
        return Image(nsImage: img)
            .resizable()
            .interpolation(.high)
            .frame(width: kIconSize, height: kIconSize)
    }

    private func symbolIcon(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .frame(width: kIconSize, height: kIconSize)
    }

    // MARK: counts

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

// Mail-style rounded pill count badge
private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.secondary.opacity(0.18))
            )
    }
}
