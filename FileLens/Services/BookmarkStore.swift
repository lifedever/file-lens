import Foundation

enum BookmarkStore {
    /// Creates a (non-security-scoped, v1) bookmark. Future-proofed: switching to
    /// `.withSecurityScope` for sandbox is a single-flag change here.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark back to a URL, reporting staleness (caller may want to refresh).
    static func resolve(bookmark: Data) throws -> (URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}
