import Foundation
import CoreServices

/// FSEvents-backed folder watcher. Emits batched events (paths) after a 1-second
/// debounce on top of FSEvents' built-in 200ms latency coalescing. Designed to absorb
/// unzip / git-clone storms without flooding consumers.
@MainActor
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<[String]>.Continuation?
    private var debounceTask: Task<Void, Never>?
    private var pendingPaths: Set<String> = []

    /// Starts watching `url`. Returns a stream that yields arrays of changed paths,
    /// debounced to at most one yield per ~1s during a burst.
    func start(url: URL) -> AsyncStream<[String]> {
        return AsyncStream { continuation in
            self.continuation = continuation

            let pathsToWatch = [url.path] as CFArray
            var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)

            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let cfPaths = unsafeBitCast(paths, to: CFArray.self)
                var changed: [String] = []
                for i in 0..<count {
                    if let p = CFArrayGetValueAtIndex(cfPaths, i) {
                        let s = unsafeBitCast(p, to: CFString.self) as String
                        changed.append(s)
                    }
                }
                Task { @MainActor in watcher.handleEvents(changed) }
            }

            let s = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &ctx, pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.2,  // 200ms system-level coalescing
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            )
            self.stream = s
            FSEventStreamSetDispatchQueue(s!, .main)
            FSEventStreamStart(s!)

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in self.stop() }
            }
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        continuation?.finish()
        continuation = nil
    }

    private func handleEvents(_ paths: [String]) {
        pendingPaths.formUnion(paths)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            let batch = Array(self.pendingPaths)
            self.pendingPaths.removeAll()
            self.continuation?.yield(batch)
        }
    }
}
