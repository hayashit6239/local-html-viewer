import Foundation
import Testing

@testable import HTMLViewerCore

@Suite("SearchProvider")
struct SearchProviderTests {
    private let sut = FilenameSearchProvider()
    private func f(_ name: String) -> HTMLFile {
        HTMLFile(path: "/r/\(name)", name: name, mtime: Date(timeIntervalSince1970: 0), rootPath: "/r", relativePath: name)
    }

    @Test("部分一致(case-insensitive)")
    func substringCaseInsensitive() {
        let files = [f("Report.html"), f("dashboard.html"), f("notes.md.html")]
        #expect(sut.filter(files, query: "report").map(\.name) == ["Report.html"])
        #expect(sut.filter(files, query: "HTML").count == 3)
    }

    @Test("空クエリは全件・順序保持")
    func emptyQueryAll() {
        let files = [f("b.html"), f("a.html")]
        #expect(sut.filter(files, query: "").map(\.name) == ["b.html", "a.html"])
    }

    @Test("ヒットなしは空")
    func noHit() {
        #expect(sut.filter([f("a.html")], query: "zzz").isEmpty)
    }

    @Test("NFC/NFD 混在でも一致(濁点)")
    func unicodeNFCNFD() {
        // "が" を NFD(か + 濁点)で持つファイル名を NFC クエリで検索
        let nfd = "\u{304B}\u{3099}.html"  // か + 結合濁点
        let files = [f(nfd)]
        #expect(sut.filter(files, query: "\u{304C}").count == 1)  // NFC の が
    }
}
