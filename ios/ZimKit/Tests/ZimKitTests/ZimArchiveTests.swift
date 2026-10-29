import XCTest
@testable import ZimKit

/// Fixture built by Tests/make_fixture.py with python-libzim (zstd clusters, ZIM 6.3 namespace scheme).
final class ZimArchiveTests: XCTestCase {
    private var archive: ZimArchive!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "fixture", withExtension: "zim", subdirectory: "Fixtures"))
        archive = try ZimArchive(url: url)
    }

    func testHeaderAndMetadata() {
        XCTAssertEqual(archive.entryCount, 16)
        XCTAssertEqual(archive.contentNamespace, "C")
        XCTAssertEqual(archive.title, "NOMAD Test")
        XCTAssertTrue(archive.mimeTypes.contains("text/html"))
    }

    func testMainPageFollowsRedirect() throws {
        let main = try XCTUnwrap(archive.mainEntry())
        XCTAssertEqual(main.fullPath, "C/Home")
        let content = try archive.content(of: main)
        XCTAssertEqual(content.mimeType, "text/html")
        XCTAssertTrue(String(decoding: content.data, as: UTF8.self).contains("<h1>Home</h1>"))
    }

    func testRedirectEntryResolvesToTarget() throws {
        let redirect = try XCTUnwrap(archive.entry(namespace: "C", path: "Water"))
        XCTAssertTrue(redirect.isRedirect)
        let content = try archive.content(of: redirect)
        XCTAssertEqual(content.entry.path, "Water_purification")
        XCTAssertTrue(String(decoding: content.data, as: UTF8.self).contains("Boil water"))
    }

    func testNestedPathAndMimeType() throws {
        let image = try XCTUnwrap(archive.entry(namespace: "C", path: "img/dot.svg"))
        XCTAssertEqual(try archive.content(of: image).mimeType, "image/svg+xml")
    }

    func testMissingPathReturnsNil() throws {
        XCTAssertNil(try archive.entry(namespace: "C", path: "Does_not_exist"))
    }

    func testTitleSearchCapitalisesFirstLetter() throws {
        let results = try archive.searchTitles("w")
        XCTAssertEqual(Set(results.map(\.path)), ["Water_purification", "Wound_care"])
        XCTAssertEqual(try archive.searchTitles("Wat").map(\.title), ["Water purification"])
        XCTAssertTrue(try archive.searchTitles("zzz").isEmpty)
    }

    func testRejectsNonZimFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-zim.zim")
        try Data(repeating: 7, count: 200).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ZimArchive(url: url))
    }
}
