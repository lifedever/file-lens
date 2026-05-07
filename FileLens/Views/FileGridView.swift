import SwiftUI
import SwiftData
import AppKit

struct FileGridView: View {
    let files: [FileNode]
    @Binding var selection: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    /// 由状态栏右下的滑块驱动,跨视图实例持久化(AppStorage)。
    /// 48~160 是合理的图标尺寸区间:48 ≈ Finder "图标小"档,160 ≈ "巨大"档。
    @AppStorage("filelens.gridIconSize") private var iconSize: Double = 80

    /// adaptive minimum 基于 iconSize + 文字行 + padding。
    /// maximum 给一点宽度浮动让 GridItem 能整齐排列。
    private var columns: [GridItem] {
        let cell = iconSize + 30
        return [GridItem(.adaptive(minimum: cell, maximum: cell + 50), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(files) { file in
                    FileGridItem(file: file, isSelected: selection.contains(file.id),
                                 iconSize: iconSize)
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
    let iconSize: Double

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: systemIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
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

    private var systemIcon: NSImage {
        // 走扩展名缓存,避免每个 grid item 都同步命中 Launch Services
        FileIconCache.icon(for: file)
    }
}
