import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    @Bindable var workspace: Workspace
    let files: [FileSnapshot]
    @Binding var selection: Set<UUID>
    let resolveNodes: ([FileSnapshot]) -> [FileNode]
    @Environment(\.modelContext) private var modelContext

    private var iconSize: Double { workspace.gridIconSize }

    @State private var dragHandedOff: Bool = false
    @State private var selectionAnchor: UUID?
    @State private var groupedCache = GroupedCache()

    init(workspace: Workspace,
         files: [FileSnapshot],
         selection: Binding<Set<UUID>>,
         resolveNodes: @escaping ([FileSnapshot]) -> [FileNode]) {
        self.workspace = workspace
        self.files = files
        _selection = selection
        self.resolveNodes = resolveNodes
    }

    private var columns: [GridItem] {
        let cell = iconSize + 30
        return [GridItem(.adaptive(minimum: cell, maximum: cell + 50), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            let grouped = groupedCache.grouped(files: files, identityKey: identityKey)
            LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped) { slice in
                    Section {
                        ForEach(slice.files) { snap in
                            gridItem(for: snap)
                        }
                    } header: {
                        sectionHeader(slice.bucket.localizedTitle)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func gridItem(for snap: FileSnapshot) -> some View {
        FileGridItem(file: snap, isSelected: selection.contains(snap.id),
                     iconSize: iconSize)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    FileActions.open(resolveNodes([snap]))
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        guard dist >= 4, !dragHandedOff else { return }
                        let dragSnaps = filesForDrag(snap)
                        let urls = dragSnaps.compactMap { FileURLResolver.shared.url(for: $0) }
                        guard !urls.isEmpty else { return }
                        dragHandedOff = true
                        DragSession.begin(urls: urls)
                        DispatchQueue.main.async { dragHandedOff = false }
                    }
                    .onEnded { value in
                        let dist = hypot(value.translation.width, value.translation.height)
                        if dist < 4 { handleTap(snap) }
                        dragHandedOff = false
                    }
            )
            .contextMenu {
                FileContextMenu(
                    files: resolveNodes(filesForContextMenu(snap: snap)),
                    modelContext: modelContext
                )
            }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.background)
    }

    fileprivate struct GroupedSlice: Identifiable {
        let bucket: DateBucket
        let files: [FileSnapshot]
        var id: Int { bucket.rawValue }
    }

    private var identityKey: String {
        let firstID = files.first?.id.uuidString ?? "_"
        let lastID  = files.last?.id.uuidString ?? "_"
        return "\(files.count)|\(firstID)|\(lastID)"
    }

    fileprivate static func computeGrouped(files: [FileSnapshot]) -> [GroupedSlice] {
        var byBucket: [DateBucket: [FileSnapshot]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f.dateAdded), default: []].append(f)
        }
        return DateBucket.allCases.compactMap { b in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            let sorted = arr.sorted { $0.dateAdded > $1.dateAdded }
            return GroupedSlice(bucket: b, files: sorted)
        }
    }

    private func handleTap(_ snap: FileSnapshot) {
        let mods = NSEvent.modifierFlags
        let cmd = mods.contains(.command)
        let shift = mods.contains(.shift)

        if shift,
           let anchor = selectionAnchor,
           let from = files.firstIndex(where: { $0.id == anchor }),
           let to = files.firstIndex(where: { $0.id == snap.id }) {
            let lo = min(from, to)
            let hi = max(from, to)
            selection = Set(files[lo...hi].map(\.id))
            return
        }

        if cmd {
            if selection.contains(snap.id) { selection.remove(snap.id) }
            else { selection.insert(snap.id) }
            selectionAnchor = snap.id
            return
        }

        selection = [snap.id]
        selectionAnchor = snap.id
    }

    private func filesForContextMenu(snap: FileSnapshot) -> [FileSnapshot] {
        if selection.contains(snap.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [snap]
    }

    private func filesForDrag(_ snap: FileSnapshot) -> [FileSnapshot] {
        if selection.contains(snap.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [snap]
    }
}

private struct FileGridItem: View {
    let file: FileSnapshot
    let isSelected: Bool
    let iconSize: Double

    var body: some View {
        VStack(spacing: 6) {
            FileThumbnail(file: file, size: iconSize)
            Text(file.name)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: iconSize + 50)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
    }
}

private final class GroupedCache {
    private var lastKey: String = ""
    private var lastGrouped: [FileGridView.GroupedSlice] = []

    func grouped(files: [FileSnapshot],
                 identityKey: String) -> [FileGridView.GroupedSlice] {
        if identityKey == lastKey { return lastGrouped }
        lastGrouped = FileGridView.computeGrouped(files: files)
        lastKey = identityKey
        return lastGrouped
    }
}
