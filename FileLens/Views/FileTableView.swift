import SwiftUI
import AppKit

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
                Menu("Add Tag") {
                    let existing = workspaceTags(for: f)
                    ForEach(existing, id: \.self) { tag in
                        Button(tag) { addTag(tag, to: f) }
                    }
                    if !existing.isEmpty { Divider() }
                    Button("New Tag…") { promptNewTag(for: f) }
                }
                if f.tags.contains(where: { $0.source == "manual" }) {
                    Menu("Remove Tag") {
                        ForEach(f.tags.filter { $0.source == "manual" }) { tag in
                            Button(tag.name) { removeManualTag(tag) }
                        }
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

    // MARK: - Manual tag helpers

    private func workspaceTags(for file: FileNode) -> [String] {
        guard let ws = file.workspace else { return [] }
        var s = Set<String>()
        for f in ws.files where f.isPresent {
            for t in f.tags { s.insert(t.name) }
        }
        return s.sorted()
    }

    private func addTag(_ name: String, to file: FileNode) {
        let tag = FileTag(name: name, source: "manual", ruleID: nil)
        tag.file = file
        modelContext.insert(tag)
        file.tags.append(tag)
        try? modelContext.save()
    }

    private func removeManualTag(_ tag: FileTag) {
        modelContext.delete(tag)
        try? modelContext.save()
    }

    private func promptNewTag(for file: FileNode) {
        let alert = NSAlert()
        alert.messageText = "New tag for \(file.name)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { addTag(name, to: file) }
        }
    }
}
