import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(OpenEventPolicy):
// [x] .html / .htm かつ存在するパスだけ通す
// [x] 非 HTML 拡張子は弾く
// [x] 存在しないパスは弾く(fileExists 注入)
// [x] 拡張子判定は case-insensitive(.HTM も通す)
// [x] 受信順を保つ

@Suite("OpenEventPolicy")
struct OpenEventPolicyTests {
    private func urls(_ paths: [String]) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    @Test(".html/.htm かつ存在するパスだけ通す")
    func keepsExistingHTML() {
        let input = urls(["/a/report.html", "/a/notes.md", "/a/page.htm"])
        let existing: Set<String> = ["/a/report.html", "/a/notes.md", "/a/page.htm"]
        let result = OpenEventPolicy.acceptableHTMLPaths(from: input) { existing.contains($0) }
        #expect(result == ["/a/report.html", "/a/page.htm"])
    }

    @Test("存在しない HTML は弾く")
    func dropsMissing() {
        let input = urls(["/a/here.html", "/a/gone.html"])
        let result = OpenEventPolicy.acceptableHTMLPaths(from: input) { $0 == "/a/here.html" }
        #expect(result == ["/a/here.html"])
    }

    @Test("拡張子判定は case-insensitive")
    func caseInsensitive() {
        let input = urls(["/a/Report.HTML", "/a/X.HTM"])
        let result = OpenEventPolicy.acceptableHTMLPaths(from: input) { _ in true }
        #expect(result == ["/a/Report.HTML", "/a/X.HTM"])
    }

    @Test("受信順を保つ")
    func preservesOrder() {
        let input = urls(["/a/3.html", "/a/1.html", "/a/2.html"])
        let result = OpenEventPolicy.acceptableHTMLPaths(from: input) { _ in true }
        #expect(result == ["/a/3.html", "/a/1.html", "/a/2.html"])
    }

    @Test("空入力は空")
    func emptyStaysEmpty() {
        #expect(OpenEventPolicy.acceptableHTMLPaths(from: [], fileExists: { _ in true }).isEmpty)
    }
}
