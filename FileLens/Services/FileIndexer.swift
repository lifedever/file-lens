import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class FileIndexer {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Full scan of the workspace folder. Creates new FileNodes, updates existing ones'
    /// lastSeenAt + metadata, marks vanished files isPresent=false. Re-evaluates rules.
    func scan(workspace: Workspace) async throws {
        let ctx = container.mainContext
        let (folderURL, _) = try BookmarkStore.resolve(bookmark: workspace.bookmarkData)

        let scanStart = Date()
        let existing = workspace.files
        var byPath: [String: FileNode] = [:]
        for node in existing { byPath[node.relativePath] = node }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .addedToDirectoryDateKey,
                                         .contentModificationDateKey, .fileResourceIdentifierKey,
                                         .isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey,
                                                          .addedToDirectoryDateKey,
                                                          .contentModificationDateKey,
                                                          .fileResourceIdentifierKey,
                                                          .isDirectoryKey])
            if values.isDirectory == true { continue }

            let relPath = url.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let size = Int64(values.fileSize ?? 0)
            let dateAdded = values.addedToDirectoryDate ?? .now
            let dateModified = values.contentModificationDate ?? .now
            let kind = KindClassifier.bucket(for: values.contentType ?? .data)
            let resID = (values.fileResourceIdentifier as? NSObject)?.description

            if let existingNode = byPath[relPath] {
                existingNode.name = name
                existingNode.ext = ext
                existingNode.size = size
                existingNode.dateAdded = dateAdded
                existingNode.dateModified = dateModified
                existingNode.kind = kind
                existingNode.lastSeenAt = scanStart
                existingNode.isPresent = true
                existingNode.fileResourceID = resID
            } else {
                let node = FileNode(
                    relativePath: relPath, name: name, ext: ext, size: size,
                    dateAdded: dateAdded, dateModified: dateModified, kind: kind,
                    lastSeenAt: scanStart, isPresent: true, fileResourceID: resID
                )
                node.workspace = workspace
                ctx.insert(node)
            }
        }

        // Mark vanished files
        for node in existing where node.lastSeenAt < scanStart && node.isPresent {
            node.isPresent = false
        }

        // Re-apply rules
        try ctx.save()
        try applyRules(workspace: workspace)
        try ctx.save()
    }

    /// Recompute FileTags (source=rule) for all present files in this workspace.
    func applyRules(workspace: Workspace) throws {
        let ctx = container.mainContext
        let rules = workspace.rules
        for node in workspace.files where node.isPresent {
            // Drop existing rule-sourced tags (manual tags retained)
            let manualTags = node.tags.filter { $0.source == "manual" }
            for tag in node.tags where tag.source == "rule" {
                ctx.delete(tag)
            }
            node.tags = manualTags

            // Add fresh rule tags
            let names = RuleEngine.tags(for: node, rules: rules)
            for name in names {
                let rule = rules.first(where: { $0.name == name })
                let tag = FileTag(name: name, source: "rule", ruleID: rule?.id)
                tag.file = node
                ctx.insert(tag)
                node.tags.append(tag)
            }
            node.rulesEvaluatedAt = .now
        }
    }
}
