import XCTest
import UniformTypeIdentifiers
@testable import FileLens

final class KindClassifierTests: XCTestCase {
    func test_image() {
        XCTAssertEqual(KindClassifier.bucket(for: .png), "image")
        XCTAssertEqual(KindClassifier.bucket(for: .jpeg), "image")
        XCTAssertEqual(KindClassifier.bucket(for: .heic), "image")
    }
    func test_movie() {
        XCTAssertEqual(KindClassifier.bucket(for: .movie), "movie")
        XCTAssertEqual(KindClassifier.bucket(for: .mpeg4Movie), "movie")
    }
    func test_audio() {
        XCTAssertEqual(KindClassifier.bucket(for: .audio), "audio")
        XCTAssertEqual(KindClassifier.bucket(for: .mp3), "audio")
    }
    func test_archive() {
        XCTAssertEqual(KindClassifier.bucket(for: .zip), "archive")
    }
    func test_pdf_is_document() {
        XCTAssertEqual(KindClassifier.bucket(for: .pdf), "document")
    }
    func test_unknown_falls_back_to_other() {
        let unknown = UTType("public.unknown-fake-type-xyz") ?? .data
        XCTAssertEqual(KindClassifier.bucket(for: unknown), "other")
    }
}
