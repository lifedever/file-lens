import SwiftUI
import AppKit

/// 文件缩略图视图。两段式渲染:
///   1. init 同步从 FileIconCache 取扩展名图标 → 首帧不空白
///   2. .task 里同步查 ThumbnailService 磁盘缓存,命中即换图(典型滚动场景)
///   3. 缓存未命中且 kind 是 QL 可渲染类型 → 异步触发 QL 生成,完成后换图
///
/// 设计上跟 grid 的滑块尺寸解耦:`size` 只控制 *显示* 大小,缓存固定走
/// `ThumbnailService.smallSize`(128pt @2x)。Table 18pt / Grid 48~160pt
/// 都共用同一份缓存条目,避免 N 档重复生成。
struct FileThumbnail: View {
    let file: FileSnapshot
    let size: CGFloat

    @State private var image: NSImage

    init(file: FileSnapshot, size: CGFloat) {
        self.file = file
        self.size = size
        self._image = State(initialValue: FileIconCache.icon(for: file))
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .task(id: file.id) { await upgrade() }
    }

    @MainActor
    private func upgrade() async {
        // 不支持的类型(audio / archive / other)直接保留扩展名图标
        guard PreviewHost.kind(for: file) != .unsupported,
              !file.isDirectory,
              let url = FileURLResolver.shared.url(for: file)
        else { return }

        let target = ThumbnailService.smallSize

        if let cached = ThumbnailService.shared.cachedThumbnail(
            for: url, size: target) {
            image = cached
            return
        }

        if let generated = await ThumbnailService.shared.thumbnail(
            for: url, size: target),
           !Task.isCancelled {
            image = generated
        }
    }
}
