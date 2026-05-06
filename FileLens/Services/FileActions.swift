import Foundation
import AppKit
import SwiftData

enum FileActions {
    static func reveal(_ file: FileNode) {
        guard let url = url(for: file) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ file: FileNode) {
        guard let url = url(for: file) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func moveToTrash(_ file: FileNode, modelContext: ModelContext) {
        guard let url = url(for: file) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            file.isPresent = false
            try? modelContext.save()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func url(for file: FileNode) -> URL? {
        guard let ws = file.workspace,
              let (folder, _) = try? BookmarkStore.resolve(bookmark: ws.bookmarkData) else { return nil }
        return folder.appendingPathComponent(file.relativePath)
    }
}
