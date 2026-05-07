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
    /// DMG 下载源(按优先级排,通常 [Gitee, GitHub])。下载器从第一个开始,
    /// 失败自动切下一个。空数组 = 没有可下载的 DMG(不应发生)。
    let downloadURLs: [URL]
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private struct Manifest: Decodable {
        let version: String
        let tag: String
        let url: String
        let notes: String?
        /// 按架构分组:assets.arm64.dmg_urls / assets.x86_64.dmg_urls。
        /// 每个架构下是一个 URL 优先级数组(Gitee 优先 / GitHub 兜底)。
        let assets: [String: ArchAsset]?
        /// 兼容字段:老版本 manifest 用平铺数组(默认所有架构同一个 universal DMG)。
        let dmg_urls: [String]?
        /// 更老兼容字段:单一 URL。
        let dmg_url: String?
    }

    private struct ArchAsset: Decodable {
        let dmg_urls: [String]
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

        // 选 URL 列表,按 fallback 优先级:
        //   1. 新 schema:assets.<currentArch>.dmg_urls(arm64 / x86_64 各自)
        //   2. 老 schema:平铺 dmg_urls(universal DMG)
        //   3. 最老 schema:单一 dmg_url
        let arch = Self.currentArch()
        let urlStrings: [String]
        if let archAsset = manifest.assets?[arch] {
            urlStrings = archAsset.dmg_urls
        } else if let flat = manifest.dmg_urls {
            urlStrings = flat
        } else if let single = manifest.dmg_url {
            urlStrings = [single]
        } else {
            urlStrings = []
        }
        let urls = urlStrings.compactMap(URL.init(string:))

        return UpdateInfo(
            latestTag: manifest.tag,
            releaseURL: manifest.url,
            body: manifest.notes,
            downloadURLs: urls
        )
    }

    /// 当前 binary 跑在哪个架构。Universal binary 在 arm64 Mac 上跑 arm64 slice,
    /// 在 Intel Mac 上跑 x86_64 slice,所以编译时 #if arch 判断就能反映运行时。
    private static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "arm64"  // 兜底
        #endif
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
        // GitHub API fallback:按当前架构拼 release asset 直链;只有一条 GitHub
        // 直链,没 mirror。文件名约定 `FileLens-<version>-<arch>.dmg`。
        let arch = Self.currentArch()
        let dmgURL = "https://github.com/lifedever/file-lens/releases/download/\(release.tag_name)/FileLens-\(stripV(release.tag_name))-\(arch).dmg"
        let urls = [URL(string: dmgURL)].compactMap { $0 }
        return UpdateInfo(
            latestTag: release.tag_name,
            releaseURL: release.html_url,
            body: release.body,
            downloadURLs: urls
        )
    }

    private func stripV(_ s: String) -> String {
        s.hasPrefix("v") ? String(s.dropFirst()) : s
    }
}
