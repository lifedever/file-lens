import AppKit

/// 按 path-extension 缓存 NSWorkspace icon。`NSWorkspace.shared.icon(forFile:)`
/// 是同步访问 Launch Services 的调用,在表格 / 网格里 N 行同时刷新时会
/// 严重卡主线程(每行一次 IO 命中)。绝大多数同扩展名文件的 icon 是一样的,
/// 按 ext 缓存就能把 N 次 IO 压到几次。
///
/// 该缓存设计为 main-actor 隔离:
/// - 视图层全部在主线程读它,避免锁
/// - icon(forExt:fallbackPath:) 从不返回 nil(失败回落到 .data 系统 icon)
@MainActor
enum FileIconCache {
    private static var byExt: [String: NSImage] = [:]
    private static var genericData: NSImage?

    /// 取扩展名对应的图标。如果当前 ext 缓存没有,会用 fallbackPath 同步
    /// 命中一次 Launch Services 然后写入缓存。
    static func icon(ext: String, fallbackPath: String?) -> NSImage {
        let key = ext.lowercased()
        if !key.isEmpty, let cached = byExt[key] { return cached }

        let loaded: NSImage
        if let path = fallbackPath {
            loaded = NSWorkspace.shared.icon(forFile: path)
        } else {
            loaded = genericData ?? NSWorkspace.shared.icon(for: .data)
        }
        if !key.isEmpty {
            byExt[key] = loaded
        } else if genericData == nil {
            genericData = loaded
        }
        return loaded
    }

    /// 给 FileNode 直接传:取它的 ext + 可解出的真实路径。路径可解就用真路径
    /// 命中(更准),解不出退回 ext-only 缓存。文件夹 → 系统通用文件夹图标
    /// (不用真路径,所有文件夹共享同一图标避免 N 行同步 IO)。
    static func icon(for file: FileNode) -> NSImage {
        if file.isDirectory {
            if let cached = folderIcon { return cached }
            let icon = NSWorkspace.shared.icon(for: .folder)
            folderIcon = icon
            return icon
        }
        return icon(ext: file.ext, fallbackPath: FileActions.url(for: file)?.path)
    }

    private static var folderIcon: NSImage?
}
