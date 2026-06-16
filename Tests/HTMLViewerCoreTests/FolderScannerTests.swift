import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(FolderScanner):
// [x] .html / .htm を再帰的に収集する(サブディレクトリ含む)
// [x] node_modules 等の ignore ディレクトリ配下を除外する
// [x] 隠しディレクトリ配下を除外する
// [x] HTML 以外の拡張子を除外する
// [x] relativePath / rootPath を正しく付与する
// [x] maxFiles を超えたら truncated=true で打ち切る

@Suite("FolderScanner")
struct FolderScannerTests {
    /// テスト用の一時ディレクトリにファイルを作る(合成データのみ)。
    private func makeTree(_ entries: [String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("htmlviewer-scan-\(UUID().uuidString)")
        for rel in entries {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("<html></html>".utf8).write(to: url)
        }
        return root
    }

    @Test("html/htm を再帰収集し ignore・隠し・非 HTML を除外する")
    func scansAndFilters() throws {
        let root = try makeTree([
            "alpha.html",
            "sub/beta.html",
            "gamma.htm",
            "readme.md",
            "node_modules/pkg/x.html",
            ".hidden/y.html",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = FolderScanner.scan(roots: [root])
        let names = Set(result.files.map(\.name))

        #expect(names == ["alpha.html", "beta.html", "gamma.htm"])
        #expect(!result.truncated)
    }

    @Test("隠しファイル・隠しディレクトリ配下は走査対象外(成果物は dotfile でない前提)")
    func skipsHiddenFilesAndDirectories() throws {
        let root = try makeTree([
            "visible.html",
            ".hidden.html",         // 隠しファイル
            ".config/inside.html",  // 隠しディレクトリ配下
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let names = Set(FolderScanner.scan(roots: [root]).files.map(\.name))
        #expect(names == ["visible.html"])
    }

    @Test("relativePath と rootPath を付与する")
    func assignsRelativePaths() throws {
        let root = try makeTree(["sub/deep/page.html"])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = FolderScanner.scan(roots: [root])
        let file = try #require(result.files.first)

        // rootPath は path の prefix である(allowingReadAccessTo / relativePath の不変条件)
        #expect(file.path.hasPrefix(file.rootPath))
        #expect(file.relativePath == "sub/deep/page.html")
        #expect(file.name == "page.html")
    }

    @Test("受け入れ条件: 走査→RECENT ソートで node_modules を除き mtime 降順になる")
    func scanThenSortAcceptance() throws {
        let fm = FileManager.default
        let root = try makeTree([
            "old.html",
            "newest.html",
            "mid.html",
            "node_modules/pkg/ignored.html",
        ])
        defer { try? fm.removeItem(at: root) }

        // mtime を制御(newest > mid > old)
        try setMtime(root.appendingPathComponent("old.html"), 1_000)
        try setMtime(root.appendingPathComponent("mid.html"), 2_000)
        try setMtime(root.appendingPathComponent("newest.html"), 3_000)

        let scanned = FolderScanner.scan(roots: [root]).files
        let recent = RecentSorter.sortedByModificationDateDescending(scanned)

        #expect(recent.map(\.name) == ["newest.html", "mid.html", "old.html"])
    }

    private func setMtime(_ url: URL, _ epoch: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: epoch)],
            ofItemAtPath: url.path
        )
    }

    @Test("maxFiles を超えたら mtime 降順で上位 N を決定論的に保持する")
    func truncatesToNewestN() throws {
        let root = try makeTree(["a.html", "b.html", "c.html", "d.html", "e.html"])
        defer { try? FileManager.default.removeItem(at: root) }

        // mtime: e > d > c > b > a
        try setMtime(root.appendingPathComponent("a.html"), 1_000)
        try setMtime(root.appendingPathComponent("b.html"), 2_000)
        try setMtime(root.appendingPathComponent("c.html"), 3_000)
        try setMtime(root.appendingPathComponent("d.html"), 4_000)
        try setMtime(root.appendingPathComponent("e.html"), 5_000)

        let result = FolderScanner.scan(roots: [root], maxFiles: 3)
        #expect(result.truncated)
        // 走査順に依存せず、必ず新しい 3 件
        #expect(Set(result.files.map(\.name)) == ["e.html", "d.html", "c.html"])
    }

    @Test("入れ子登録(A と A/sub)でも同一ファイルを重複させない")
    func dedupesNestedRoots() throws {
        let root = try makeTree(["a.html", "sub/b.html"])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = FolderScanner.scan(roots: [root, root.appendingPathComponent("sub")])
        #expect(result.files.map(\.name).sorted() == ["a.html", "b.html"])
        #expect(result.files.filter { $0.name == "b.html" }.count == 1)
    }

    @Test("symlink を追従しない(ディレクトリ symlink 経由で外部に出ない)")
    func doesNotFollowSymlinks() throws {
        let fm = FileManager.default
        let root = try makeTree(["inside.html"])
        defer { try? fm.removeItem(at: root) }

        // root の外にあるディレクトリ(追従したら拾えてしまう)
        let external = fm.temporaryDirectory.appendingPathComponent("htmlviewer-ext-\(UUID().uuidString)")
        try fm.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: external.appendingPathComponent("secret.html"))
        defer { try? fm.removeItem(at: external) }

        // root 内から external へのディレクトリ symlink
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: external)

        let result = FolderScanner.scan(roots: [root])
        #expect(Set(result.files.map(\.name)) == ["inside.html"])
    }
}
