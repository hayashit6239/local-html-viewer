import Testing

@testable import HTMLViewerCore

// テストリスト(IgnoreRules):
// [x] .html / .htm を HTML と判定する(大文字小文字を無視)
// [x] .md / 拡張子なし / .htmlx は HTML と判定しない
// [x] ignore ディレクトリ(node_modules 等)はスキップ対象
// [x] ignore ディレクトリ判定は大文字小文字を無視する(NODE_MODULES 等)
// [x] 隠しディレクトリ(. 始まり)はスキップ対象
// [x] 通常ディレクトリはスキップしない

@Suite("IgnoreRules")
struct IgnoreRulesTests {
    @Test("html / htm を拡張子大文字小文字問わず HTML と判定")
    func detectsHTML() {
        #expect(IgnoreRules.isHTMLFile("a.html"))
        #expect(IgnoreRules.isHTMLFile("a.htm"))
        #expect(IgnoreRules.isHTMLFile("REPORT.HTML"))
        #expect(IgnoreRules.isHTMLFile("Index.Htm"))
    }

    @Test("html/htm 以外は HTML と判定しない")
    func rejectsNonHTML() {
        #expect(!IgnoreRules.isHTMLFile("notes.md"))
        #expect(!IgnoreRules.isHTMLFile("Makefile"))
        #expect(!IgnoreRules.isHTMLFile("a.htmlx"))
        #expect(!IgnoreRules.isHTMLFile("a.xhtml"))
    }

    @Test("ignore ディレクトリはスキップ対象")
    func skipsIgnoredDirectories() {
        #expect(IgnoreRules.shouldSkipDirectory("node_modules"))
        #expect(IgnoreRules.shouldSkipDirectory(".git"))
        #expect(IgnoreRules.shouldSkipDirectory("dist"))
        #expect(IgnoreRules.shouldSkipDirectory("build"))
    }

    @Test("ignore ディレクトリ判定は大文字小文字を無視する")
    func skipsIgnoredDirectoriesCaseInsensitively() {
        // case-sensitive ボリュームや大文字表記でも除外漏れしない(HTML 拡張子判定との対称性)
        #expect(IgnoreRules.shouldSkipDirectory("NODE_MODULES"))
        #expect(IgnoreRules.shouldSkipDirectory("Node_Modules"))
        #expect(IgnoreRules.shouldSkipDirectory("DIST"))
        #expect(IgnoreRules.shouldSkipDirectory("Build"))
    }

    @Test("隠しディレクトリはスキップ対象")
    func skipsHiddenDirectories() {
        #expect(IgnoreRules.shouldSkipDirectory(".hidden"))
        #expect(IgnoreRules.shouldSkipDirectory(".cache"))
    }

    @Test("通常ディレクトリはスキップしない")
    func keepsNormalDirectories() {
        #expect(!IgnoreRules.shouldSkipDirectory("sub"))
        #expect(!IgnoreRules.shouldSkipDirectory("reports"))
    }
}
