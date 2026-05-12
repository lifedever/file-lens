import Foundation
import SwiftData
import UniformTypeIdentifiers
import OSLog

private let perfLog = Logger(subsystem: "com.lifedever.FileLens", category: "perf")

/// 文件枚举阶段产出的中间值,Sendable —— 让 file IO 跑在 Task.detached
/// 背景线程上,IO 阶段完全不碰 SwiftData。回到主 context 后再批量 insert。
struct FileMetadata: Sendable {
    let relativePath: String
    let name: String
    let ext: String
    let size: Int64
    let dateAdded: Date
    let dateModified: Date
    let kind: String
    let isDirectory: Bool
    let fileResourceID: String?
}

/// IO 阶段的配置快照,Sendable。
struct ScanOptions: Sendable {
    let recursive: Bool
    let maxDepth: Int
    let includeFolders: Bool
    let ignoreHidden: Bool
    let ignoreFolders: Set<String>
}

/// 双 store 架构:
/// - **catalog**: Workspace 元数据 + Rules + Conditions
/// - **per-workspace store**: 单一 workspace 的 FileNode + FileTag
///
/// `FileIndexer` 同时持有这两个 container 的 mainContext,scan 时:
/// - 工作空间状态(indexStateRaw / progressDone / fileCount)写 catalog
/// - 文件节点 / tag 写 workspace store
///
/// 删除 workspace 不再走 cascade,改为 `WorkspaceStoreManager.deleteStore` 直接
/// `rm` 文件,毫秒级。这里 `deleteWorkspace` 现在只负责清 catalog 那行。
@MainActor
final class FileIndexer {
    private let storeManager: WorkspaceStoreManager

    init(storeManager: WorkspaceStoreManager) {
        self.storeManager = storeManager
    }

    /// 测试用 —— 验证 IO 阶段是否真的脱离主线程。
    func _testIOOffMainThread() async -> Bool {
        let onMain = await Task.detached { pthread_main_np() != 0 }.value
        return onMain == false
    }

    func scan(workspaceID: UUID, silent: Bool = false) async throws {
        let catalogCtx = storeManager.catalog.mainContext
        let descriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { $0.id == workspaceID }
        )
        guard let workspace = try? catalogCtx.fetch(descriptor).first else { return }
        let (folderURL, _) = try BookmarkStore.resolve(bookmark: workspace.bookmarkData)

        // workspace store —— FileNode/FileTag 都写到这里
        let storeCtx = try storeManager.store(for: workspaceID).mainContext

        let probeStart = Date()
        func probe(_ tag: String, _ extra: Int = 0) {
            let ms = Int(Date().timeIntervalSince(probeStart) * 1000)
            perfLog.notice("t=\(ms, privacy: .public)ms tag=\(tag, privacy: .public) n=\(extra, privacy: .public)")
        }
        probe("scan-entry")

        // 进入 scanning,UI gate 显示进度。silent=true(FSEvents 增量触发)跳过。
        if !silent {
            workspace.indexStateRaw = 1
            workspace.indexProgressDone = 0
            workspace.indexProgressTotal = 0
            try catalogCtx.save()
        }

        do {
            try await runScanBody(
                workspace: workspace,
                catalogCtx: catalogCtx,
                storeCtx: storeCtx,
                folderURL: folderURL,
                silent: silent,
                probe: probe
            )
        } catch {
            // cancel / 异常 —— 重置 indexState,不动 store(那边的部分数据保留即可,
            // 重新 scan 时 byPath 会找回)
            if !silent {
                workspace.indexStateRaw = 0
                workspace.indexProgressDone = 0
                workspace.indexProgressTotal = 0
                try? catalogCtx.save()
            }
            throw error
        }
    }

    private func runScanBody(
        workspace: Workspace,
        catalogCtx: ModelContext,
        storeCtx: ModelContext,
        folderURL: URL,
        silent: Bool,
        probe: (String, Int) -> Void
    ) async throws {
        // === 阶段 1:文件 IO 在 detached task 跑(背景线程,主线程不堵)===
        let options = Self.makeScanOptions(workspace: workspace)
        let rawMetadata: [FileMetadata] = try await Task.detached(priority: .userInitiated) {
            try Self.enumerateFiles(at: folderURL, options: options)
        }.value
        probe("io-end", rawMetadata.count)

        // 闸 1: enumerator 在 FS 快速变动时偶发对同名 entry 双吐(Chrome
        // .crdownload → final rename 期间的 readdir race 复现稳定),按
        // relativePath dedup,保留最后一份(resourceValues 最新)。
        // 不做这层 → 同次 scan 里同 path 的两份 meta,byPath 是 fetch 快照
        // 不会反映本次 insert,第二份走 insert 分支 → 数据库出现两条
        // 同 relativePath 的 FileNode(历史脏数据来源)。
        let metadata: [FileMetadata] = {
            var seen: [String: Int] = [:]
            var result: [FileMetadata] = []
            result.reserveCapacity(rawMetadata.count)
            for m in rawMetadata {
                if let idx = seen[m.relativePath] {
                    result[idx] = m
                } else {
                    seen[m.relativePath] = result.count
                    result.append(m)
                }
            }
            return result
        }()
        if metadata.count != rawMetadata.count {
            probe("meta-dedup-collapsed", rawMetadata.count - metadata.count)
        }

        // === 阶段 2:回主线程,在 workspace store 上批量 insert/update FileNode ===
        let scanStart = Date()
        // 这个 store 里所有 FileNode 都是这一个 workspace 的(per-workspace store!)
        // 所以查全表就行,不需要 predicate 过滤 —— 也没 ws.files O(N²) 问题。
        let existing = (try? storeCtx.fetch(FetchDescriptor<FileNode>())) ?? []
        var byPath: [String: FileNode] = [:]
        byPath.reserveCapacity(existing.count)
        // 闸 2 自愈: existing 已有同 relativePath 多条(早期 byPath dedup
        // miss 遗留的历史脏数据),留 lastSeenAt 最新一条,其余物理 delete
        // —— 不是 isPresent=false,免得永久占行。新装用户 existing 空,
        // 这段是 no-op;老用户跑一次就清干净,后续 scan 不再触发。
        var selfHealedDuplicates = 0
        var deletedNodeIDs: Set<UUID> = []
        for node in existing {
            if let prev = byPath[node.relativePath] {
                let (keep, drop) = prev.lastSeenAt >= node.lastSeenAt
                    ? (prev, node)
                    : (node, prev)
                storeCtx.delete(drop)
                deletedNodeIDs.insert(drop.id)
                byPath[node.relativePath] = keep
                selfHealedDuplicates += 1
            } else {
                byPath[node.relativePath] = node
            }
        }
        if selfHealedDuplicates > 0 {
            probe("self-heal-duplicates", selfHealedDuplicates)
        }
        probe("existing-loaded", existing.count)

        if !silent {
            workspace.indexProgressTotal = metadata.count
            try catalogCtx.save()
        }

        let workspaceID = workspace.id
        // rules snapshot —— catalog 上读出来,scan 期间快照不变
        let rules = workspace.rules
        var allPresentNodes: [FileNode] = []
        allPresentNodes.reserveCapacity(metadata.count)
        var newNodesCount = 0

        for (idx, meta) in metadata.enumerated() {
            let node: FileNode
            if let existingNode = byPath[meta.relativePath] {
                // silent fast path:同 path → 假设 file 没变,仅刷 lastSeenAt
                // 跟 isPresent。代价是 silent 模式下用户外部修改文件大小 / 重
                // 命名后,UI 显示的元数据短暂 stale,直到下次 forceRescan
                // (右键「立即重索引」)。trade-off 是避免 11k 次属性赋值的
                // 主线程开销。
                let dateModifiedChanged = existingNode.dateModified != meta.dateModified
                let sizeChanged = existingNode.size != meta.size
                if silent && !dateModifiedChanged && !sizeChanged {
                    existingNode.lastSeenAt = scanStart
                    if !existingNode.isPresent { existingNode.isPresent = true }
                } else {
                    existingNode.name = meta.name
                    existingNode.ext = meta.ext
                    existingNode.size = meta.size
                    existingNode.dateAdded = meta.dateAdded
                    existingNode.dateModified = meta.dateModified
                    existingNode.kind = meta.kind
                    existingNode.lastSeenAt = scanStart
                    existingNode.isPresent = true
                    existingNode.fileResourceID = meta.fileResourceID
                    existingNode.isDirectory = meta.isDirectory
                }
                node = existingNode
            } else {
                node = FileNode(
                    workspaceID: workspaceID,
                    relativePath: meta.relativePath, name: meta.name, ext: meta.ext,
                    size: meta.size, dateAdded: meta.dateAdded, dateModified: meta.dateModified,
                    kind: meta.kind, lastSeenAt: scanStart, isPresent: true,
                    fileResourceID: meta.fileResourceID, isDirectory: meta.isDirectory
                )
                storeCtx.insert(node)
                // 兜底:写回 byPath。本来 metadata 已 dedup 不会再撞,但加这
                // 一行后即使将来 enumerator 出新花样也不会形成重复 insert。
                byPath[meta.relativePath] = node
                newNodesCount += 1
            }
            allPresentNodes.append(node)

            let processed = idx + 1
            if processed.isMultiple(of: 25) {
                await Task.yield()
                try Task.checkCancellation()
            }
            // silent 模式(后台对账,UI 已经 ready 显示老数据)中间一次都不
            // save,只末尾(下面的 `try storeCtx.save()`)统一写入。
            // 每次 storeCtx.save 都触发 SwiftData observation 通知,SwiftUI
            // Table 持有的 11k+ FileNode 数组就跟着 diff/rerender,主线程被
            // 吃满 → 用户切 selection 卡。silent 时数据要等 scan 完才呈现
            // 最终态,中间状态用户根本看不到,save 没意义。
            // 非 silent(用户主动右键重索引)保留 200,因为 progress 视图就是
            // 在显示进度,save 频率正是进度更新频率。
            if !silent, processed.isMultiple(of: 200) {
                workspace.indexProgressDone = processed
                try catalogCtx.save()
                try storeCtx.save()
            }
            if processed.isMultiple(of: 1000) { probe("scan-progress", processed) }
        }
        try storeCtx.save()
        probe("scan-loop-end", metadata.count)

        // 这一批没扫到的旧节点标记 vanished。跳过 self-heal 已经 storeCtx.delete
        // 的节点 —— 它们已经物理删,访问属性可能触发 SwiftData runtime error。
        var vanishedCount = 0
        for node in existing where !deletedNodeIDs.contains(node.id)
                                 && node.lastSeenAt < scanStart
                                 && node.isPresent {
            node.isPresent = false
            vanishedCount += 1
        }
        try storeCtx.save()
        probe("vanished-marked", vanishedCount)

        // silent 模式 fast path:文件夹完全没变化(没新增、没消失、没 self-heal)
        // → 跳过 applyRules + count + catalog save。FolderWatcher 会大量触发
        // 这种"没变化"的 scan(任何文件 atime/mtime 改动都触发,但绝大多数
        // 文件不在 watch 关注的属性上有变化)。直接 return 把主线程从十几秒
        // 占用降到只有 IO + main loop 那 1-2s。
        // self-heal 也算"变化"(物理删了脏数据行),走 full path 让
        // scanGeneration bump + cache 失效。
        if silent && newNodesCount == 0 && vanishedCount == 0 && selfHealedDuplicates == 0 {
            probe("silent-noop-exit", allPresentNodes.count)
            return
        }

        // === 阶段 3:applyRules,单独一遍,workspace store 上跑 ===
        if !rules.isEmpty {
            if !silent {
                workspace.indexProgressDone = 0
                workspace.indexProgressTotal = allPresentNodes.count
                try catalogCtx.save()
            }
            // silent 模式只对新增 / 从未评估过的 file applyRules(rulesEvaluatedAt
            // 为 nil 的)。rules 没改时存量 file 的 tags 不会变,没必要重新算
            // 11k 次主线程操作 —— 那是用户报「app 启动后 20+ 秒内切 selection
            // 仍卡」的原因。用户改 rule 由 reapplyRulesIfNeeded 触发全量。
            // 非 silent(首次添加 / 右键重索引)走全量。
            let nodesToApply: [FileNode] = silent
                ? allPresentNodes.filter { $0.rulesEvaluatedAt == nil }
                : allPresentNodes
            probe("rules-start", nodesToApply.count)
            var ruleProcessed = 0
            for node in nodesToApply {
                applyRulesInline(to: node, rules: rules, ctx: storeCtx)
                ruleProcessed += 1
                if ruleProcessed.isMultiple(of: 50) {
                    await Task.yield()
                    try Task.checkCancellation()
                }
                // silent 同样不中间 save,末尾统一一次。
                if !silent, ruleProcessed.isMultiple(of: 200) {
                    workspace.indexProgressDone = ruleProcessed
                    try catalogCtx.save()
                    try storeCtx.save()
                }
            }
            try storeCtx.save()
            probe("rules-end", ruleProcessed)
        }

        // 收尾:把所有 sidebar 需要的 count 一次性算好回写 catalog。
        var presentCount = 0
        var uncategorized = 0
        var ruleCounts: [String: Int] = [:]
        for node in allPresentNodes where node.isPresent {
            presentCount += 1
            let ruleIDs = Set(node.tags.compactMap { $0.ruleID })
            if ruleIDs.isEmpty {
                uncategorized += 1
            } else {
                for rid in ruleIDs {
                    ruleCounts[rid.uuidString, default: 0] += 1
                }
            }
        }
        workspace.fileCount = presentCount
        workspace.uncategorizedCount = uncategorized
        // bump 单调代数,让 FilesMemo cache 一定失效 —— 即使 presentCount
        // 跟上次完全一样(Chrome download → rename 这种增删抵消场景)也
        // 能让 UI 看到最新 isPresent 集合。
        workspace.scanGeneration &+= 1
        if let data = try? JSONEncoder().encode(ruleCounts),
           let json = String(data: data, encoding: .utf8) {
            workspace.ruleCountsJSON = json
        }
        if !silent {
            workspace.indexStateRaw = 0
            workspace.indexProgressDone = 0
            workspace.indexProgressTotal = 0
        }
        try catalogCtx.save()
        probe("ready", presentCount)
    }

    /// reapplyRulesIfNeeded 用:用户编辑了规则,重新跑一遍 tag。
    func applyRules(workspaceID: UUID) async throws {
        let catalogCtx = storeManager.catalog.mainContext
        let descriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { $0.id == workspaceID }
        )
        guard let workspace = try? catalogCtx.fetch(descriptor).first else { return }
        let storeCtx = try storeManager.store(for: workspaceID).mainContext

        let rules = workspace.rules
        let nodes = (try? storeCtx.fetch(FetchDescriptor<FileNode>(
            predicate: #Predicate<FileNode> { $0.isPresent }
        ))) ?? []
        var processed = 0
        for node in nodes {
            applyRulesInline(to: node, rules: rules, ctx: storeCtx)
            processed += 1
            if processed.isMultiple(of: 50) {
                await Task.yield()
                try Task.checkCancellation()
            }
            if processed.isMultiple(of: 200) {
                try storeCtx.save()
            }
        }
        try storeCtx.save()
    }

    // MARK: - Private

    /// 给单个节点重打 rule tag。
    private func applyRulesInline(to node: FileNode, rules: [Rule], ctx: ModelContext) {
        let manualTags = node.tags.filter { $0.source == "manual" }
        for tag in node.tags where tag.source == "rule" {
            ctx.delete(tag)
        }
        node.tags = manualTags

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

    private static func makeScanOptions(workspace: Workspace) -> ScanOptions {
        let defaults = UserDefaults.standard
        let ignoreHidden = (defaults.object(forKey: "filelens.ignoreHidden") as? Bool) ?? true
        let globalRaw = defaults.string(forKey: "filelens.ignoreFolders")
            ?? ".git,node_modules,.build,Pods,DerivedData,.next,.cache"
        let perWorkspaceRaw = workspace.extraIgnoreFolders
        let ignoreFolders = Set(
            (globalRaw + "," + perWorkspaceRaw)
                .split(whereSeparator: { ",\n".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        return ScanOptions(
            recursive: workspace.recursive,
            maxDepth: workspace.maxDepth,
            includeFolders: workspace.includeFolders,
            ignoreHidden: ignoreHidden,
            ignoreFolders: ignoreFolders
        )
    }

    nonisolated static func enumerateFiles(at folderURL: URL,
                                           options: ScanOptions) throws -> [FileMetadata] {
        var enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if options.ignoreHidden { enumOptions.insert(.skipsHiddenFiles) }
        if !options.recursive {
            enumOptions.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey, .addedToDirectoryDateKey,
                                         .contentModificationDateKey, .fileResourceIdentifierKey,
                                         .isDirectoryKey, .isHiddenKey],
            options: enumOptions
        ) else { return [] }

        let folderPathPrefix = folderURL.path + "/"
        var result: [FileMetadata] = []
        result.reserveCapacity(1024)

        while let object = enumerator.nextObject() {
            guard let url = object as? URL else { continue }

            let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey,
                                                          .addedToDirectoryDateKey,
                                                          .contentModificationDateKey,
                                                          .fileResourceIdentifierKey,
                                                          .isDirectoryKey])

            let relForCheck = url.path.replacingOccurrences(of: folderPathPrefix, with: "")
            let parts = relForCheck.split(separator: "/")
            let isDirectory = (values.isDirectory == true)

            if isDirectory, options.ignoreFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if !isDirectory, options.ignoreFolders.contains(url.lastPathComponent) {
                continue
            }
            if parts.dropLast().contains(where: { options.ignoreFolders.contains(String($0)) }) {
                continue
            }
            if options.recursive, options.maxDepth > 0, parts.count > options.maxDepth {
                continue
            }
            if isDirectory, options.recursive, options.maxDepth > 0 {
                let depth = parts.count
                if depth >= options.maxDepth {
                    enumerator.skipDescendants()
                }
            }
            if isDirectory, !options.includeFolders {
                continue
            }

            let name = url.lastPathComponent
            let ext = isDirectory ? "" : url.pathExtension.lowercased()
            let size = isDirectory ? Int64(0) : Int64(values.fileSize ?? 0)
            let dateAdded = values.addedToDirectoryDate ?? .now
            let dateModified = values.contentModificationDate ?? .now
            let kind = isDirectory ? "folder" : KindClassifier.bucket(for: values.contentType ?? .data)
            let resID = (values.fileResourceIdentifier as? NSObject)?.description

            result.append(FileMetadata(
                relativePath: relForCheck, name: name, ext: ext, size: size,
                dateAdded: dateAdded, dateModified: dateModified, kind: kind,
                isDirectory: isDirectory, fileResourceID: resID
            ))
        }
        return result
    }
}
