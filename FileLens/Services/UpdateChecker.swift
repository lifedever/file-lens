import Foundation

/// 检查 FileLens 的更新版本。
///
/// **首选**:GitHub Pages 上的静态 JSON 清单
/// `https://lifedever.github.io/file-lens/api/latest.json`,无 API 限流,
/// CDN 抗压。
///
/// **回退**:GitHub Releases API。Pages 走不通时(用户首次升级到带新逻辑的
/// 版本前发版的、Pages 部署还没生效、清单格式不对……)兜底。GitHub API
/// 未鉴权 60 次/小时/IP,够普通用户用,但共享出口 IP(公司网)可能撞限流。
struct UpdateInfo: Equatable {
    let latestTag: String       // e.g. "v1.1.0"
    let releaseURL: String      // 浏览器打开的链接
    let body: String?           // release notes(markdown)
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private struct Manifest: Decodable {
        let version: String         // "1.1.0"
        let tag: String             // "v1.1.0"
        let url: String             // release page URL
        let notes: String?          // markdown body
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    /// 返回非 nil iff 远端有严格更新版本。
    func checkForUpdate(currentVersion: String) async -> UpdateInfo? {
        // 先打 Pages 清单
        if let info = await fetchFromPages(currentVersion: currentVersion) {
            return info
        }
        // Pages 走不通 → GitHub API 兜底
        return await fetchFromGitHub(currentVersion: currentVersion)
    }

    private func fetchFromPages(currentVersion: String) async -> UpdateInfo? {
        guard let url = URL(string: "https://lifedever.github.io/file-lens/api/latest.json") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        // Pages CDN 偶尔会返回旧缓存,加个 cache-buster query 强制 revalidate
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return nil
        }
        let latest = stripV(manifest.version)
        let current = stripV(currentVersion)
        guard latest.compare(current, options: .numeric) == .orderedDescending else {
            return nil
        }
        return UpdateInfo(
            latestTag: manifest.tag,
            releaseURL: manifest.url,
            body: manifest.notes
        )
    }

    private func fetchFromGitHub(currentVersion: String) async -> UpdateInfo? {
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
