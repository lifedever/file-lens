import Foundation
import AppKit
import QuickLookThumbnailing
import CryptoKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cacheDir: URL
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.lifedever.FileLens"
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent(bundleID).appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func thumbnail(for url: URL, size: CGSize = CGSize(width: 256, height: 256)) async -> NSImage? {
        if let task = inflight[url] { return await task.value }
        let task = Task { () -> NSImage? in
            let cached = self.cachedFile(for: url)
            if let data = try? Data(contentsOf: cached), let img = NSImage(data: data) {
                return img
            }
            return await self.generate(url: url, size: size, cacheTo: cached)
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        return img
    }

    private func cachedFile(for url: URL) -> URL {
        let h = SHA256.hash(data: Data(url.path.utf8))
        let hex = h.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).png")
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
