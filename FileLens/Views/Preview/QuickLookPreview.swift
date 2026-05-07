import SwiftUI
import AppKit

/// 非图片但 QL 能渲染的类型(movie / pdf / rtf / md / source code)走的预览。
/// 复用 ThumbnailService 的 largeSize 档缓存,跟 inspector 第二次以上看同一
/// 文件时零等待。
struct QuickLookPreview: View {
    let file: FileNode
    let url: URL?

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear.frame(minHeight: 80)
            }
        }
        .task(id: file.id) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let target = ThumbnailService.largeSize

        // 1. 同步查盘(cachedThumbnail 是 nonisolated,不需要 await)
        if let cached = ThumbnailService.shared.cachedThumbnail(
            for: url, size: target) {
            self.image = cached
            return
        }
        // 2. 异步生成
        if let generated = await ThumbnailService.shared.thumbnail(
            for: url, size: target),
           !Task.isCancelled {
            self.image = generated
        }
    }
}
