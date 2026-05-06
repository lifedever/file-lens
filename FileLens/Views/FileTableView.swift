import SwiftUI

struct FileTableView: View {
    let files: [FileNode]
    @State private var sortOrder = [KeyPathComparator(\FileNode.dateAdded, order: .reverse)]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Table(files.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { f in
                HStack {
                    Image(systemName: kindIcon(f.kind))
                    Text(f.name)
                }
            }
            TableColumn("Size", value: \.size) { f in
                Text(byteFormatter.string(fromByteCount: f.size))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Date Added", value: \.dateAdded) { f in
                Text(f.dateAdded, style: .date)
                    .foregroundStyle(.secondary)
            }
            .width(120)

            TableColumn("Tags") { (f: FileNode) in
                Text(f.tags.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Kind") { (f: FileNode) in
                Text(f.kind.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(80)
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { selection in
            if let id = selection.first, let f = files.first(where: { $0.id == id }) {
                Button("Reveal in Finder") { FileActions.reveal(f) }
                Button("Open With Default App") { FileActions.open(f) }
                Button("Quick Look") {
                    if let url = FileActions.url(for: f) {
                        QuickLookCoordinator.shared.show(urls: [url])
                    }
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    FileActions.moveToTrash(f, modelContext: modelContext)
                }
            }
        } primaryAction: { selection in
            if let id = selection.first, let f = files.first(where: { $0.id == id }) {
                FileActions.open(f)
            }
        }
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }

    private func kindIcon(_ k: String) -> String {
        switch k {
        case "image": return "photo"
        case "movie": return "film"
        case "audio": return "music.note"
        case "archive": return "archivebox"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "document": return "doc"
        case "text": return "doc.text"
        default: return "doc"
        }
    }
}
