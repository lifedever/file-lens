import SwiftUI
import AppKit

/// 图片类文件的 inspector 预览。直接 NSImage(contentsOf:) 读全分辨率,
/// 比走 QL 还快(QL 内部对 image 类型也是直接解码 + 压缩到目标 size)。
///
/// 加载策略:
///   - 首帧不阻塞:body 出现时 image 还是 nil,显示空 placeholder
///   - .task 异步把全分辨率 NSImage 解到内存(bgQ),再切回主线程赋值
///   - 单选场景,大图也最多一份在内存里;切到下一张时 .task(id:) 自动 cancel
struct ImagePreview: View {
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
                // 占位:别让 ZStack 高度塌成 0,给 inspector 一个最小可见高度
                Color.clear.frame(minHeight: 80)
            }
        }
        .task(id: file.id) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let loaded = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        if !Task.isCancelled {
            await MainActor.run { self.image = loaded }
        }
    }
}
