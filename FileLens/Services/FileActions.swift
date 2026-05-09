import Foundation
import AppKit
import SwiftData

@MainActor
enum FileActions {

    // MARK: - Reveal

    static func reveal(_ file: FileNode) { reveal([file]) }

    /// Selects one or many files in a single Finder window. activateFileViewer
    /// silently fails to highlight when the URL still contains symlinks or a
    /// `/private` prefix, so we resolve and standardize first.
    static func reveal(_ files: [FileNode]) {
        let urls = files.compactMap(url(for:))
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Open

    static func open(_ file: FileNode) { open([file]) }

    static func open(_ files: [FileNode]) {
        for f in files {
            if let url = url(for: f) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Trash

    @MainActor
    static func moveToTrash(_ file: FileNode, modelContext: ModelContext) {
        moveToTrash([file], modelContext: modelContext)
    }

    @MainActor
    static func moveToTrash(_ files: [FileNode], modelContext: ModelContext) {
        guard !files.isEmpty else { return }

        // 移到废纸篓不是不可逆的(系统废纸篓可以恢复),但用户键盘误触
        // ⌘Delete 时常会出戏。模仿 Finder,先弹一个 NSAlert 确认。
        let alert = NSAlert()
        alert.alertStyle = .warning
        if files.count == 1, let only = files.first {
            alert.messageText = String(format:
                NSLocalizedString("trash.confirm.title.single.format",
                    value: "Move “%@” to the Trash?", comment: ""),
                only.name)
        } else {
            alert.messageText = String(format:
                NSLocalizedString("trash.confirm.title.multi.format",
                    value: "Move %lld items to the Trash?", comment: ""),
                Int64(files.count))
        }
        alert.informativeText = NSLocalizedString("trash.confirm.body",
            value: "You can restore them from the Trash later.",
            comment: "")
        alert.addButton(withTitle: NSLocalizedString("Move to Trash",
            value: "Move to Trash", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel",
            value: "Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var errors: [Error] = []
        var moved = 0
        for f in files {
            guard let url = url(for: f) else { continue }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                f.isPresent = false
                moved += 1
            } catch {
                errors.append(error)
            }
        }
        try? modelContext.save()
        if let first = errors.first { NSAlert(error: first).runModal() }
        if moved > 0 { ToastCenter.shared.success(toastMessage("Moved to Trash", count: moved)) }
    }

    // MARK: - Copy / Move to…

    @MainActor
    static func copyTo(_ files: [FileNode]) {
        guard !files.isEmpty,
              let dest = pickDestination(prompt: NSLocalizedString("Copy", value: "Copy", comment: "")) else { return }
        var errors: [Error] = []
        var copied = 0
        for f in files {
            guard let src = url(for: f) else { continue }
            let target = uniqueDestination(in: dest, for: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: target)
                copied += 1
            } catch {
                errors.append(error)
            }
        }
        if let first = errors.first { NSAlert(error: first).runModal() }
        if copied > 0 { ToastCenter.shared.success(toastMessage("Copied", count: copied)) }
    }

    @MainActor
    static func moveTo(_ files: [FileNode], modelContext: ModelContext) {
        guard !files.isEmpty,
              let dest = pickDestination(prompt: NSLocalizedString("Move", value: "Move", comment: "")) else { return }
        var errors: [Error] = []
        var moved = 0
        for f in files {
            guard let src = url(for: f) else { continue }
            let target = uniqueDestination(in: dest, for: src.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: src, to: target)
                // FSEvents will catch this too, but flip the flag immediately
                // so the UI doesn't show a stale "still here" row.
                f.isPresent = false
                moved += 1
            } catch {
                errors.append(error)
            }
        }
        try? modelContext.save()
        if let first = errors.first { NSAlert(error: first).runModal() }
        if moved > 0 { ToastCenter.shared.success(toastMessage("Moved", count: moved)) }
    }

    // MARK: - Copy path

    /// Pastes the absolute paths to the clipboard, one per line (Finder's
    /// "Copy as Pathname" convention).
    @MainActor
    static func copyPath(_ files: [FileNode]) {
        let paths = files.compactMap { url(for: $0)?.path }
        guard !paths.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)

        // 单文件:在 toast 里直接把路径秀出来 —— 用 ~ 缩写 home 目录,
        // 显示更友好(/Users/foo/Downloads/x → ~/Downloads/x)。
        // 多文件:路径太长不适合塞 toast,只显示数量。
        let toast: String
        if paths.count == 1 {
            let abbrev = (paths[0] as NSString).abbreviatingWithTildeInPath
            toast = String(format: NSLocalizedString("path.copied.single.format",
                value: "Path copied: %@", comment: ""), abbrev)
        } else {
            toast = String(format: NSLocalizedString("path.copied.multi.format",
                value: "Copied %lld paths", comment: ""), Int64(paths.count))
        }
        ToastCenter.shared.success(toast)
    }

    // MARK: - Rename

    /// Renames a single file in place. Multi-file rename is intentionally
    /// not supported here — Finder's batch rename is a much larger feature.
    @MainActor
    static func rename(_ file: FileNode, modelContext: ModelContext) {
        guard let src = url(for: file) else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Rename", value: "Rename", comment: "")
        alert.informativeText = String(format:
            NSLocalizedString("dialog.rename.format",
                value: "Enter a new name for “%@”.", comment: ""), file.name)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = file.name
        alert.accessoryView = field
        alert.addButton(withTitle: NSLocalizedString("Rename", value: "Rename", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", value: "Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != file.name else { return }
        let dest = src.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            // FSEvents will reconcile, but updating immediately keeps the UI snappy.
            let parent = (file.relativePath as NSString).deletingLastPathComponent
            file.name = newName
            file.relativePath = parent.isEmpty
                ? newName
                : (parent as NSString).appendingPathComponent(newName)
            file.ext = (newName as NSString).pathExtension.lowercased()
            try? modelContext.save()
            ToastCenter.shared.success(NSLocalizedString("Renamed", value: "Renamed", comment: ""))
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Share

    @MainActor
    static func share(_ files: [FileNode], from view: NSView?) {
        let urls = files.compactMap(url(for:))
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let window = NSApp.keyWindow, let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    // MARK: - URL

    @MainActor
    static func url(for file: FileNode) -> URL? {
        // FileNode 现在不持有 workspace 关系(跨 store)。通过全局注册表查
        // workspaceID → folder URL。注册由 WorkspaceCoordinator.activate 完成。
        FileURLResolver.shared.url(for: file)
    }

    // MARK: - Helpers

    /// Builds a toast string like "Moved" (count == 1) or "Moved 3 files"
    /// (count > 1). Both forms are translated via xcstrings.
    private static func toastMessage(_ baseKey: String, count: Int) -> String {
        if count <= 1 {
            return NSLocalizedString(baseKey, value: baseKey, comment: "")
        }
        let formatKey = "\(baseKey) %lld files"
        let format = NSLocalizedString(formatKey, value: formatKey, comment: "")
        return String(format: format, count)
    }

    @MainActor
    private static func pickDestination(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Finder-style "name 2.ext", "name 3.ext"… when a file with the same
    /// name already exists at `dir`.
    private static func uniqueDestination(in dir: URL, for filename: String) -> URL {
        let candidate = dir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        for n in 2...99 {
            let next = dir.appendingPathComponent(
                ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            )
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return candidate  // give up after 99; copy will throw and we'll surface the error
    }
}
