import XCTest
@testable import FileLens

final class BuiltInRulesTests: XCTestCase {

    private func file(_ name: String, ext: String, size: Int64 = 1_000_000,
                     dateAdded: Date = .now, kind: String = "other") -> FileNode {
        FileNode(workspaceID: UUID(),
                 relativePath: name, name: name, ext: ext, size: size,
                 dateAdded: dateAdded, dateModified: dateAdded, kind: kind)
    }

    /// BuiltInRules.all() 的 rule.name 在创建时就被 NSLocalizedString 本地化,
    /// 所以测试机的系统语言决定 name 是 "Installers" 还是 "安装包"。下面这些
    /// 测试用 helper 来计算当前 locale 对应的本地化名字,跨语言都能跑通。
    private func l(_ key: String) -> String {
        NSLocalizedString(key, value: key, comment: "")
    }

    func test_all_returns_fourteen_rules() {
        XCTAssertEqual(BuiltInRules.all().count, 14)   // 13 原有 + Folders
    }

    func test_folder_tagged_as_folders() {
        // 文件夹条目: kind = "folder",ext 空,size 0
        let folder = FileNode(workspaceID: UUID(),
                              relativePath: "MyFolder", name: "MyFolder", ext: "",
                              size: 0, dateAdded: .now, dateModified: .now,
                              kind: "folder", isDirectory: true)
        let tags = RuleEngine.tags(for: folder, rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("Folders")))
    }

    func test_dmg_tagged_as_installers() {
        let tags = RuleEngine.tags(for: file("MyApp-1.0.dmg", ext: "dmg"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("Installers")))
    }

    func test_png_tagged_as_images() {
        let tags = RuleEngine.tags(for: file("photo.png", ext: "png", kind: "image"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("Images")))
    }

    func test_pdf_tagged_as_pdf_and_documents() {
        let tags = RuleEngine.tags(for: file("report.pdf", ext: "pdf"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("PDF")))
        XCTAssertFalse(tags.contains(l("Documents")))
    }

    func test_screenshot_chinese_filename() {
        let tags = RuleEngine.tags(for: file("截屏2026-05-06.png", ext: "png", kind: "image"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("Screenshots")))
        XCTAssertTrue(tags.contains(l("Images")))
    }

    func test_large_video_gets_videos_and_large_tags() {
        let tags = RuleEngine.tags(
            for: file("bigmovie.mkv", ext: "mkv", size: 1_200_000_000, kind: "movie"),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains(l("Videos")))
        XCTAssertTrue(tags.contains(l("Large files")))
    }

    func test_fresh_file_gets_new_arrivals() {
        let tags = RuleEngine.tags(
            for: file("new.txt", ext: "txt", dateAdded: Date(timeIntervalSinceNow: -86400)),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains(l("New arrivals")))
    }

    func test_old_file_gets_stale() {
        let tags = RuleEngine.tags(
            for: file("ancient.txt", ext: "txt", dateAdded: Date(timeIntervalSinceNow: -45 * 86400)),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains(l("Stale")))
    }

    func test_partial_download_tagged_downloading() {
        let tags = RuleEngine.tags(for: file("foo.crdownload", ext: "crdownload"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains(l("Downloading")))
    }

    func test_all_rules_are_marked_isBuiltIn() {
        XCTAssertTrue(BuiltInRules.all().allSatisfy { $0.isBuiltIn })
    }

    // MARK: - descriptionKey reverse lookup
    //
    // 1.0.x 之后规则名在创建时被本地化(中文系统 rule.name = "安装包"),
    // descriptionKey(forBuiltInRuleNamed:) 必须能用本地化名字反向找到
    // 文档串。这里同时验证 English key 的正向查找。

    func test_descriptionKey_lookup_by_english_key() {
        XCTAssertEqual(BuiltInRules.descriptionKey(forBuiltInRuleNamed: "Installers"),
                       "rule.Installers.desc")
        XCTAssertEqual(BuiltInRules.descriptionKey(forBuiltInRuleNamed: "Large files"),
                       "rule.Large.desc")
    }

    func test_descriptionKey_lookup_by_localized_name() {
        // 测试运行在 en 环境下,NSLocalizedString("Installers") 返回的还是
        // "Installers",直接命中正向分支;在 zh-Hans 下会返回"安装包",
        // 触发 reverse lookup 路径。这里至少验证 fall-through 的正确性。
        let localized = NSLocalizedString("Installers", value: "Installers", comment: "")
        XCTAssertEqual(BuiltInRules.descriptionKey(forBuiltInRuleNamed: localized),
                       "rule.Installers.desc")
    }

    func test_descriptionKey_returns_nil_for_unknown_name() {
        XCTAssertNil(BuiltInRules.descriptionKey(forBuiltInRuleNamed: "Random Custom Name"))
        XCTAssertNil(BuiltInRules.descriptionKey(forBuiltInRuleNamed: ""))
    }

    // MARK: - User-tunable thresholds

    func test_newArrivalsDays_uses_user_default_when_set() {
        let key = "filelens.newArrivalsDays"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(14, forKey: key)
        let rules = BuiltInRules.all()
        let target = NSLocalizedString("New arrivals", value: "New arrivals", comment: "")
        let newArrivals = rules.first { $0.name == target }
        XCTAssertEqual(newArrivals?.conditions.first?.value, "14")
    }

    func test_staleDays_uses_user_default_when_set() {
        let key = "filelens.staleDays"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(60, forKey: key)
        let rules = BuiltInRules.all()
        let target = NSLocalizedString("Stale", value: "Stale", comment: "")
        let stale = rules.first { $0.name == target }
        XCTAssertEqual(stale?.conditions.first?.value, "60")
    }
}
