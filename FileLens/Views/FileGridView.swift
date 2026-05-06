import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(files) { file in
                    FileGridItem(file: file, isSelected: selection.contains(file.id))
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { FileActions.open(file) }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded { handleTap(file) }
                        )
                        .onDrag {
                            let url = FileActions.url(for: file).map { $0 as NSURL } ?? NSURL()
                            return NSItemProvider(object: url)
                        }
                        .contextMenu {
                            FileContextMenu(
                                files: filesForContextMenu(file: file),
                                modelContext: modelContext
                            )
                        }
                }
            }
            .padding(12)
        }
    }

    /// Cmd-click toggles, plain click replaces selection. Shift-range selection
    /// would need an anchor — skipped for v1, matches Finder gallery view.
    private func handleTap(_ file: FileNode) {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld {
            if selection.contains(file.id) { selection.remove(file.id) }
            else { selection.insert(file.id) }
        } else {
            selection = [file.id]
        }
    }

    /// Right-click on a selected item targets the whole selection; right-click
    /// on a non-selected item targets just that one (matches Finder).
    private func filesForContextMenu(file: FileNode) -> [FileNode] {
        if selection.contains(file.id) {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
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
