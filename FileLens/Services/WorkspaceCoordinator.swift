import Foundation
import SwiftData

/// Manages per-workspace lifecycle: initial scan + live FSEvents subscription.
/// Owned by ContentView; restarts when the selected workspace changes.
@MainActor
final class WorkspaceCoordinator {
    private let container: ModelContainer
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
    }

    func activate(workspace: Workspace) async {
        await deactivate()

        let indexer = FileIndexer(container: container)
        do {
            try await indexer.scan(workspace: workspace)
        } catch {
            print("Initial scan failed: \(error)")
            return
        }

        let (folderURL, _) = (try? BookmarkStore.resolve(bookmark: workspace.bookmarkData)) ?? (URL(fileURLWithPath: "/"), false)
        let w = FolderWatcher()
        watcher = w
        watchTask = Task { [weak self] in
            for await _ in w.start(url: folderURL) {
                guard let self else { break }
                _ = self
                do {
                    try await indexer.scan(workspace: workspace)
                } catch {
                    print("Re-scan failed: \(error)")
                }
            }
        }
    }

    func deactivate() async {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }
}
