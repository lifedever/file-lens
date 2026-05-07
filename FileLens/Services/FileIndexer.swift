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
    ///
    /// 行为受 workspace 自身设置控制:
    /// - `recursive == false` → 只索引顶层文件,完全不进任何子目录
    /// - `recursive == true && maxDepth == 0` → 全量递归(默认旧行为)
    /// - `recursive == true && maxDepth == N` → 顶层算 1 级,最多递归到第 N 级
    /// - `extraIgnoreFolders` → workspace 私有的额外排除项,跟全局列表合并
    func scan(workspace: Workspace) async throws {
        let ctx = container.mainContext
        let (folderURL, _) = try BookmarkStore.resolve(bookmark: workspace.bookmarkData)

        let scanStart = Date()
        let existing = workspace.files
        var byPath: [String: FileNode] = [:]
        for node in existing { byPath[node.relativePath] = node }

        // 用户可在 设置 → 索引 里关闭跳过隐藏文件,以及配置忽略目录列表
        let defaults = UserDefaults.standard
        let ignoreHidden = (defaults.object(forKey: "filelens.ignoreHidden") as? Bool) ?? true
        let globalRaw = defaults.string(forKey: "filelens.ignoreFolders")
            ?? ".git,node_modules,.build,Pods,DerivedData,.next,.cache"
        let perWorkspaceRaw = workspace.extraIgnoreFolders
        // 全局 + 该 workspace 专属:并集
        let ignoreFolders = Set(
            (globalRaw + "," + perWorkspaceRaw)
                .split(whereSeparator: { ",\n".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        let recursive = workspace.recursive
        let maxDepth = workspace.maxDepth   // 0 = 无限制
        let includeFolders = workspace.includeFolders

        var enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if ignoreHidden { enumOptions.insert(.skipsHiddenFiles) }
        if !recursive {
            // 关键 flag:让 enumerator 只看顶层一层,不下钻
            enumOptions.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .addedToDirectoryDateKey,
                                         .contentModificationDateKey, .fileResourceIdentifierKey,
                                         .isDirectoryKey, .isHiddenKey],
            options: enumOptions
        ) else {
            return
        }

        let folderPathPrefix = folderURL.path + "/"

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey,
                                                          .addedToDirectoryDateKey,
                                                          .contentModificationDateKey,
                                                          .fileResourceIdentifierKey,
                                                          .isDirectoryKey])

            let relForCheck = url.path.replacingOccurrences(of: folderPathPrefix, with: "")
            let parts = relForCheck.split(separator: "/")
            let isDirectory = (values.isDirectory == true)

            // 命中忽略列表的目录:整个子树跳过,避免遍历 node_modules / .git
            if isDirectory, ignoreFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue   // 这种目录本身也不索引(用户压根不想看到)
            }
            // 命中忽略列表的文件名(如 .DS_Store / Thumbs.db):跳过这一个
            if !isDirectory, ignoreFolders.contains(url.lastPathComponent) {
                continue
            }
            // 防御性:即使父目录未被 skipDescendants(枚举顺序意外),
            // 也按路径过滤掉所有忽略目录里的条目
            if parts.dropLast().contains(where: { ignoreFolders.contains(String($0)) }) {
                continue
            }
            // 防御性深度限制:如果 enumerator 吐出超深的条目,按 maxDepth 过滤
            if recursive, maxDepth > 0, parts.count > maxDepth {
                continue
            }

            // maxDepth 时点:目录到达 maxDepth 之后停止下钻 (它本身仍被索引,
            // 用户能看到这个文件夹条目,只是不展开其内部)
            if isDirectory, recursive, maxDepth > 0 {
                let depth = parts.count
                if depth >= maxDepth {
                    enumerator.skipDescendants()
                }
            }

            // 用户在 workspace 设置里关掉了"包含文件夹":目录本身不索引,
            // 但仍要继续往下走(会进 enumerator 子树),让里面的文件被收
            if isDirectory, !includeFolders {
                continue
            }

            let relPath = relForCheck
            let name = url.lastPathComponent
            // 文件夹:ext / size 留空,kind 用 "folder";文件按原逻辑分类
            let ext = isDirectory ? "" : url.pathExtension.lowercased()
            let size = isDirectory ? Int64(0) : Int64(values.fileSize ?? 0)
            let dateAdded = values.addedToDirectoryDate ?? .now
            let dateModified = values.contentModificationDate ?? .now
            let kind = isDirectory ? "folder" : KindClassifier.bucket(for: values.contentType ?? .data)
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
                existingNode.isDirectory = isDirectory
            } else {
                let node = FileNode(
                    relativePath: relPath, name: name, ext: ext, size: size,
                    dateAdded: dateAdded, dateModified: dateModified, kind: kind,
                    lastSeenAt: scanStart, isPresent: true, fileResourceID: resID,
                    isDirectory: isDirectory
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
