import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    let files: [FileNode]
    @Binding var selectedFile: FileNode?
    @Environment(\.modelContext) private var modelContext

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(files) { file in
                    FileGridItem(file: file, isSelected: file.id == selectedFile?.id)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { FileActions.open(file) }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded { selectedFile = file }
                        )
                        .onDrag {
                            let url = FileActions.url(for: file).map { $0 as NSURL } ?? NSURL()
                            return NSItemProvider(object: url)
                        }
                        .contextMenu {
                            fileContextMenu(file)
                        }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ file: FileNode) -> some View {
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
                Button(TagDisplay.localizedName(tag)) { addTag(tag, to: file) }
            }
            if !existing.isEmpty { Divider() }
            Button("New Tag…") { promptNewTag(for: file) }
        }
        if file.tags.contains(where: { $0.source == "manual" }) {
            Menu("Remove Tag") {
                ForEach(file.tags.filter { $0.source == "manual" }) { tag in
                    Button(TagDisplay.localizedName(tag.name)) { removeManualTag(tag) }
                }
            }
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            FileActions.moveToTrash(file, modelContext: modelContext)
        }
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

private struct FileGridItem: View {
    let file: FileNode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: systemIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 80, height: 80)
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
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
    }

    private var systemIcon: NSImage {
        if let url = FileActions.url(for: file) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}
