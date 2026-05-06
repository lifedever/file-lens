import Foundation

enum StoreMigration {
    /// Resolves the SwiftData store URL under <appSupportRoot>/<bundleID>/default.store.
    /// Creates the parent directory if missing. Per CLAUDE.md TaskTick #22, stores must
    /// never live in the bare Application Support root.
    static func resolveStoreURL(
        bundleID: String,
        appSupportRoot: URL = URL.applicationSupportDirectory
    ) throws -> URL {
        let namespaceDir = appSupportRoot.appendingPathComponent(bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: namespaceDir, withIntermediateDirectories: true)
        return namespaceDir.appendingPathComponent("default.store")
    }
}
