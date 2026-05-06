import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    let files: [FileNode]
    @Binding var selectedFile: FileNode?
    @State private var thumbs: [UUID: NSImage] = [:]
    @Environment(\.modelContext) private var modelContext

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(files) { file in
                    FileGridItem(file: file, image: thumbs[file.id], isSelected: file.id == selectedFile?.id)
                        .task(id: file.id) {
                            await loadThumb(for: file)
                        }
                        .onTapGesture(count: 2) { FileActions.open(file) }
                        .onTapGesture(count: 1) { selectedFile = file }
                        .onDrag {
                            let url = FileActions.url(for: file).map { $0 as NSURL } ?? NSURL()
                            return NSItemProvider(object: url)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { FileActions.reveal(file) }
                            Button("Open With Default App") { FileActions.open(file) }
                            Button("Quick Look") {
                                if let url = FileActions.url(for: file) {
                                    QuickLookCoordinator.shared.show(urls: [url])
                                }
                            }
                            .keyboardShortcut(" ", modifiers: [])
                            Divider()
                            Menu("Add Tag") {
                                let existing = workspaceTags(for: file)
                                ForEach(existing, id: \.self) { tag in
                                    Button(tag) { addTag(tag, to: file) }
                                }
                                if !existing.isEmpty { Divider() }
                                Button("New Tag…") { promptNewTag(for: file) }
                            }
                            if file.tags.contains(where: { $0.source == "manual" }) {
                                Menu("Remove Tag") {
                                    ForEach(file.tags.filter { $0.source == "manual" }) { tag in
                                        Button(tag.name) { removeManualTag(tag) }
                                    }
                                }
                            }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                FileActions.moveToTrash(file, modelContext: modelContext)
                            }
                        }
                }
            }
            .padding(12)
        }
    }

    private func loadThumb(for file: FileNode) async {
        guard thumbs[file.id] == nil,
              let ws = file.workspace,
              let (folder, _) = try? BookmarkStore.resolve(bookmark: ws.bookmarkData) else { return }
        let url = folder.appendingPathComponent(file.relativePath)
        if let img = await ThumbnailService.shared.thumbnail(for: url) {
            await MainActor.run { thumbs[file.id] = img }
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

private struct FileGridItem: View {
    let file: FileNode
    let image: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: kindIcon(file.kind)).font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            Text(file.name)
                .lineLimit(2)
                .truncationMode(.middle)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 130)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
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
