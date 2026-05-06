import Foundation

/// Lightweight update check via the GitHub Releases API.
/// Compares the running app's CFBundleShortVersionString against the latest tag
/// on `lifedever/file-lens`. Surfaces a `Result` the UI can present.
struct UpdateInfo: Equatable {
    let latestTag: String       // e.g. "v0.2.0"
    let releaseURL: String      // browser link
    let body: String?           // release notes
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Returns a non-nil UpdateInfo iff a strictly-newer release is available.
    func checkForUpdate(currentVersion: String) async -> UpdateInfo? {
        guard let url = URL(string: "https://api.github.com/repos/lifedever/file-lens/releases/latest") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true,
              release.prerelease != true else {
            return nil
        }

        let latest = stripV(release.tag_name)
        let current = stripV(currentVersion)
        guard latest.compare(current, options: .numeric) == .orderedDescending else {
            return nil
        }
        return UpdateInfo(
            latestTag: release.tag_name,
            releaseURL: release.html_url,
            body: release.body
        )
    }

    private func stripV(_ s: String) -> String {
        s.hasPrefix("v") ? String(s.dropFirst()) : s
    }
}
