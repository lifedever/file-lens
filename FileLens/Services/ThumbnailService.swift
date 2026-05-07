import Foundation
import AppKit
import QuickLookThumbnailing
import CryptoKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    /// Grid + Table 共享档。Table 18pt 显示由 NSImage interpolation 缩小,不为
    /// 18pt 单独跑 QL。Grid iconSize 滑到 160 时会有 ~25% upscale 轻微模糊,
    /// 接受 trade-off 换缓存命中率 —— 没必要为少数极大档再开第三档。
    static let smallSize = CGSize(width: 128, height: 128)

    /// Inspector 顶部预览档。@2x = 1024px,在 280pt 宽 inspector pane 内
    /// 即便 retina 也够清晰。
    static let largeSize = CGSize(width: 512, height: 512)

    /// `nonisolated` 的 cachedThumbnail / cachedFile 要从同步上下文访问它,
    /// 又因为它是 immutable let + Sendable(URL),actor 隔离对它没意义。
    nonisolated private let cacheDir: URL
    /// inflight key 含 size,避免同 URL 不同档位的请求互相等待错档结果。
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.FileLens"
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent(bundleID).appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// 异步生成 / 命中缓存。调用方等待结果,缓存未命中时会触发 QL 生成。
    func thumbnail(for url: URL, size: CGSize = ThumbnailService.smallSize) async -> NSImage? {
        let key = inflightKey(url: url, size: size)
        if let task = inflight[key] { return await task.value }
        let cached = cachedFile(for: url, size: size)
        let task = Task { () -> NSImage? in
            if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) {
                return img
            }
            return await self.generate(url: url, size: size, cacheTo: cached)
        }
        inflight[key] = task
        let img = await task.value
        inflight[key] = nil
        return img
    }

    /// 同步快查:只查磁盘缓存,**不触发**生成、**不**走 inflight 通道。
    /// 给 view 首帧 + DragSession 拖拽预览图用 —— 命中即换图,未命中再 await
    /// 完整 thumbnail()(view 场景)或退回扩展名图标(drag 场景)。
    /// `nonisolated`:让非 async 上下文也能直接调,内部只读 immutable cacheDir
    /// + FileManager + NSImage,无共享可变状态,actor 隔离对它没意义。
    nonisolated func cachedThumbnail(for url: URL, size: CGSize = ThumbnailService.smallSize) -> NSImage? {
        let cached = cachedFile(for: url, size: size)
        guard let data = try? Data(contentsOf: cached) else { return nil }
        return NSImage(data: data)
    }

    /// 缓存路径 key 含 path + mtime + bytes + size,任一变化老缓存失效:
    ///   - mtime/bytes:同名换内容(常见:截图覆盖、导出覆盖)→ 不复用旧缩略图
    ///   - size:smallSize / largeSize 各占独立缓存槽,互不覆盖
    /// 文件读不到 attrs 时退回 path-only key,行为等价于旧实现(不影响命中率)。
    /// `nonisolated` 同 cachedThumbnail —— 纯函数,无可变状态。
    nonisolated private func cachedFile(for url: URL, size: CGSize) -> URL {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let bytes = (attrs?[.size] as? Int64) ?? 0
        let key = "\(url.path)|\(mtime)|\(bytes)|\(Int(size.width))x\(Int(size.height))"
        let h = SHA256.hash(data: Data(key.utf8))
        let hex = h.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).png")
    }

    private func inflightKey(url: URL, size: CGSize) -> String {
        "\(url.path)|\(Int(size.width))x\(Int(size.height))"
    }

    private func generate(url: URL, size: CGSize, cacheTo: URL) async -> NSImage? {
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .all
        )
        do {
            let rep = try await withTimeout(seconds: 5) {
                try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
            }
            let img = rep.nsImage
            if let tiff = img.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: cacheTo)
            }
            return img
        } catch {
            return nil
        }
    }

    private func withTimeout<T>(seconds: Double, _ work: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
