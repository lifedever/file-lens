import AppKit
import Quartz

/// AppKit bridge for QLPreviewPanel.shared. SwiftUI doesn't expose a Quick Look modifier
/// for files, so we drive the panel directly. Keep one global instance referenced by
/// the panel's data source.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()
    private var urls: [URL] = []

    func show(urls: [URL]) {
        self.urls = urls
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
