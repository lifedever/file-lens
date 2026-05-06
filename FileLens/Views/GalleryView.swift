import SwiftUI
import AppKit
import QuickLookThumbnailing

struct GalleryView: View {
    let files: [FileNode]
    @State private var selectedID: UUID?
    @State private var bigImage: NSImage?

    private var selected: FileNode? {
        files.first(where: { $0.id == selectedID }) ?? files.first
    }

    var body: some View {
        VSplitView {
            ZStack {
                if let img = bigImage {
                    Image(nsImage: img).resizable().scaledToFit().padding(20)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 80))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(files) { file in
                        FileGridItemThumb(file: file, isSelected: file.id == (selectedID ?? selected?.id))
                            .onTapGesture { selectedID = file.id }
                    }
                }
                .padding(8)
            }
            .frame(height: 120)
        }
        .task(id: selected?.id) {
            await loadBigPreview()
        }
    }

    private func loadBigPreview() async {
        bigImage = nil
        guard let f = selected,
              let ws = f.workspace,
              let (folder, _) = try? BookmarkStore.resolve(bookmark: ws.bookmarkData) else { return }
        let url = folder.appendingPathComponent(f.relativePath)
        let img = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 1024, height: 1024))
        await MainActor.run { bigImage = img }
    }
}

private struct FileGridItemThumb: View {
    let file: FileNode
    let isSelected: Bool
    @State private var img: NSImage?

    var body: some View {
        Group {
            if let img { Image(nsImage: img).resizable().scaledToFit() }
            else { Image(systemName: "doc").font(.system(size: 30)).foregroundStyle(.secondary) }
        }
        .frame(width: 80, height: 80)
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .task(id: file.id) {
            guard img == nil,
                  let ws = file.workspace,
                  let (folder, _) = try? BookmarkStore.resolve(bookmark: ws.bookmarkData) else { return }
            let url = folder.appendingPathComponent(file.relativePath)
            let i = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 160, height: 160))
            await MainActor.run { img = i }
        }
    }
}
