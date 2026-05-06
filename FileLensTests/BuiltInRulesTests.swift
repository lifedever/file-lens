import XCTest
@testable import FileLens

final class BuiltInRulesTests: XCTestCase {

    private func file(_ name: String, ext: String, size: Int64 = 1_000_000,
                     dateAdded: Date = .now, kind: String = "other") -> FileNode {
        FileNode(relativePath: name, name: name, ext: ext, size: size,
                 dateAdded: dateAdded, dateModified: dateAdded, kind: kind)
    }

    func test_all_returns_thirteen_rules() {
        XCTAssertEqual(BuiltInRules.all().count, 13)
    }

    func test_dmg_tagged_as_installers() {
        let tags = RuleEngine.tags(for: file("MyApp-1.0.dmg", ext: "dmg"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains("Installers"))
    }

    func test_png_tagged_as_images() {
        let tags = RuleEngine.tags(for: file("photo.png", ext: "png", kind: "image"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains("Images"))
    }

    func test_pdf_tagged_as_pdf_and_documents() {
        let tags = RuleEngine.tags(for: file("report.pdf", ext: "pdf"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains("PDF"))
        XCTAssertFalse(tags.contains("Documents"))
    }

    func test_screenshot_chinese_filename() {
        let tags = RuleEngine.tags(for: file("截屏2026-05-06.png", ext: "png", kind: "image"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains("Screenshots"))
        XCTAssertTrue(tags.contains("Images"))
    }

    func test_large_video_gets_videos_and_large_tags() {
        let tags = RuleEngine.tags(
            for: file("bigmovie.mkv", ext: "mkv", size: 1_200_000_000, kind: "movie"),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains("Videos"))
        XCTAssertTrue(tags.contains("Large files"))
    }

    func test_fresh_file_gets_new_arrivals() {
        let tags = RuleEngine.tags(
            for: file("new.txt", ext: "txt", dateAdded: Date(timeIntervalSinceNow: -86400)),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains("New arrivals"))
    }

    func test_old_file_gets_stale() {
        let tags = RuleEngine.tags(
            for: file("ancient.txt", ext: "txt", dateAdded: Date(timeIntervalSinceNow: -45 * 86400)),
            rules: BuiltInRules.all()
        )
        XCTAssertTrue(tags.contains("Stale"))
    }

    func test_partial_download_tagged_downloading() {
        let tags = RuleEngine.tags(for: file("foo.crdownload", ext: "crdownload"), rules: BuiltInRules.all())
        XCTAssertTrue(tags.contains("Downloading"))
    }

    func test_all_rules_are_marked_isBuiltIn() {
        XCTAssertTrue(BuiltInRules.all().allSatisfy { $0.isBuiltIn })
    }
}
