import AppKit

/// SwiftUI 的 .draggable 一次只产 1 个 NSItemProvider,无法满足「多选拖出去」。
/// 这里直接绕到 AppKit 层 —— `NSView.beginDraggingSession(with:event:source:)`
/// 接受 N 个 NSDraggingItem,Finder/Photos 等 receiver 拿到的就是 N 份,跟
/// 从 Finder 拖出来一致。
///
/// 用法:在 SwiftUI grid item 的 .simultaneousGesture(DragGesture) onChanged
/// 里调用 DragSession.begin(urls:) 启动一次。同一拖拽手势期间只会启动一次
/// (内部由调用方守护,这里只负责干净启动)。
enum DragSession {
    /// 启动一次多文件 drag。失败(没拿到 key window / event / 空 urls)就静默
    /// 跳过 —— 用户视角是「没拖动」,不会崩。
    static func begin(urls: [URL]) {
        guard !urls.isEmpty,
              let event = NSApp.currentEvent,
              let window = NSApp.keyWindow,
              let view = window.contentView
        else { return }

        // 把鼠标当前位置(window 坐标)转成 contentView 坐标,作为 drag image
        // 中心。如果不传具体 frame,setDraggingFrame 会用 (0, 0),AppKit 的
        // (0, 0) 是 contentView 左下角 —— 视觉上 drag 图标从屏幕左下飞出来。
        let imageSize = NSSize(width: 64, height: 64)
        let mouseInView = view.convert(event.locationInWindow, from: nil)
        let originAtCursor = NSRect(
            x: mouseInView.x - imageSize.width / 2,
            y: mouseInView.y - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // 多选时 N 个 item 都从光标位置出发,系统拖拽过程会自动堆叠 +
            // 显示数量角标(跟 Finder 一致)。
            //
            // 优先用 ThumbnailService 缓存的真实缩略图(grid/table 已经在
            // 滚动渲染时填好缓存)。命中不到才退回扩展名兜底图标 —— 拖一
            // 没怎么浏览过的文件夹时会发生,可以接受。
            let preview: NSImage = {
                if let cached = ThumbnailService.shared.cachedThumbnail(
                    for: url, size: ThumbnailService.smallSize) {
                    cached.size = imageSize
                    return cached
                }
                let fallback = NSWorkspace.shared.icon(forFile: url.path)
                fallback.size = imageSize
                return fallback
            }()
            item.setDraggingFrame(originAtCursor, contents: preview)
            return item
        }

        let source = Source.shared
        view.beginDraggingSession(with: items, event: event, source: source)
        // 不设 draggingFormation —— .stack 把 item 扇形铺开尾巴飞远,
        // .pile 用自己的算法把整个 pile 的 top-left 钉在光标导致视觉偏移。
        // 默认 .none 模式下 AppKit 用每个 item 自己的 draggingFrame 渲染,
        // N 个 item 同 frame 就紧贴叠在光标中心 —— 跟单文件视觉一致。
        // (代价:没自动数字角标。下方 DragSession 视情况可以补一张合成图。)
    }

    /// NSDraggingSource 实现。strong 单例 —— 保证 NSDraggingSession 持有期间
    /// source 不被释放。无状态,线程安全。
    final class Source: NSObject, NSDraggingSource {
        static let shared = Source()
        private override init() { super.init() }

        func draggingSession(_ session: NSDraggingSession,
                              sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                // Finder / Photos / 其他 app:同卷 move、跨卷 copy(系统决定);
                // 用户按 ⌥ 强制 copy。返回三选一让系统挑。
                return [.copy, .move, .link]
            case .withinApplication:
                // 暂不实现 app 内拖拽
                return []
            @unknown default:
                return [.copy]
            }
        }
    }
}
