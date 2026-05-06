import SwiftUI

struct FileTableView: View {
    let files: [FileNode]
    @State private var sortOrder = [KeyPathComparator(\FileNode.dateAdded, order: .reverse)]

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
