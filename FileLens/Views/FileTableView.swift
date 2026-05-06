import SwiftUI
import AppKit

struct FileTableView: View {
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    @State private var sortOrder: [KeyPathComparator<FileNode>] = [
        KeyPathComparator(\FileNode.dateAdded, order: .reverse)
    ]

    private var grouped: [(bucket: DateBucket, files: [FileNode])] {
        var byBucket: [DateBucket: [FileNode]] = [:]
        for f in files {
            byBucket[DateBucket.bucket(for: f.dateAdded), default: []].append(f)
        }
        return DateBucket.allCases.compactMap { b in
            guard let arr = byBucket[b], !arr.isEmpty else { return nil }
            return (b, arr.sorted(using: sortOrder))
        }
    }

    var body: some View {
        Table(of: FileNode.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { f in
                HStack(spacing: 6) {
                    Image(nsImage: icon(for: f))
                        .resizable().interpolation(.high)
                        .scaledToFit().frame(width: 18, height: 18)
                    Text(f.name).lineLimit(1).truncationMode(.middle)
                }
            }

            TableColumn("Size", value: \.size) { f in
                Text(byteFormatter.string(fromByteCount: f.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Date Added", value: \.dateAdded) { f in
                Text(f.dateAdded, format: .dateTime
                    .year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(160)

            TableColumn("Tags") { (f: FileNode) in
                Text(f.tags.map { TagDisplay.localizedName($0.name) }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            TableColumn("Kind", value: \.kind) { (f: FileNode) in
                Text(KindDisplay.localizedName(f.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(80)
        } rows: {
            ForEach(grouped, id: \.bucket) { group in
                Section(group.bucket.localizedTitle) {
                    ForEach(group.files) { f in
                        TableRow(f)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let targets = filesForContextMenu(ids: ids)
            FileContextMenu(files: targets, modelContext: modelContext)
        } primaryAction: { ids in
            FileActions.open(filesForContextMenu(ids: ids))
        }
    }

    /// Right-click on an unselected row should target *that* row, even if
    /// other rows are selected — Finder behavior. Right-click on a selected
    /// row should target the whole selection.
    private func filesForContextMenu(ids: Set<FileNode.ID>) -> [FileNode] {
        files.filter { ids.contains($0.id) }
    }

    private func icon(for f: FileNode) -> NSImage {
        if let url = FileActions.url(for: f) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }
}
