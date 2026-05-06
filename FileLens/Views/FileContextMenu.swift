import SwiftUI
import SwiftData
import AppKit

/// Shared right-click menu for the file table and grid. All entries operate
/// on the passed-in `files` array, so multi-selection just works.
///
/// Keeping the menu here means there's one place to add or rename actions,
/// and Table/Grid don't drift apart visually.
struct FileContextMenu: View {
    let files: [FileNode]
    let modelContext: ModelContext

    var body: some View {
        if files.isEmpty {
            EmptyView()
        } else {
            Button("Open With Default App") { FileActions.open(files) }
            Button("Reveal in Finder") { FileActions.reveal(files) }
            Button("Quick Look") {
                let urls = files.compactMap { FileActions.url(for: $0) }
                if !urls.isEmpty { QuickLookCoordinator.shared.show(urls: urls) }
            }

            Divider()

            Button("Copy to…") { FileActions.copyTo(files) }
            Button("Move to…") { FileActions.moveTo(files, modelContext: modelContext) }
            Button("Copy Path") { FileActions.copyPath(files) }
            // Rename is a single-file action — Finder's batch rename is a much
            // larger feature than v1 needs.
            if files.count == 1 {
                Button("Rename…") { FileActions.rename(files[0], modelContext: modelContext) }
            }
            Button("Share…") { FileActions.share(files, from: nil) }

            Divider()

            Button("Move to Trash", role: .destructive) {
                FileActions.moveToTrash(files, modelContext: modelContext)
            }
        }
    }
}
