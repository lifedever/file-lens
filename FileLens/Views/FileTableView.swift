import SwiftUI
import AppKit

struct FileTableView: View {
    let files: [FileNode]
    @Binding var selectedFile: FileNode?
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

    private var selectionBinding: Binding<FileNode.ID?> {
        Binding(
            get: { selectedFile?.id },
            set: { id in
                selectedFile = files.first { $0.id == id }
            }
        )
    }

    var body: some View {
        Table(of: FileNode.self, selection: selectionBinding, sortOrder: $sortOrder) {
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
                        Button(TagDisplay.localizedName(tag)) { addTag(tag, to: f) }
                    }
                    if !existing.isEmpty { Divider() }
                    Button("New Tag…") { promptNewTag(for: f) }
                }
                if f.tags.contains(where: { $0.source == "manual" }) {
                    Menu("Remove Tag") {
                        ForEach(f.tags.filter { $0.source == "manual" }) { tag in
                            Button(TagDisplay.localizedName(tag.name)) { removeManualTag(tag) }
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

    private func icon(for f: FileNode) -> NSImage {
        if let url = FileActions.url(for: f) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }

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
        alert.messageText = String(format: NSLocalizedString("dialog.newTag.format",
            value: "New tag for %@", comment: ""), file.name)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: NSLocalizedString("Add", value: "Add", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", value: "Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { addTag(name, to: file) }
        }
    }
}
