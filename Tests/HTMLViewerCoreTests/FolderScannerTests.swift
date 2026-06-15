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

    @Test("maxFiles を超えたら打ち切る")
    func truncatesAtMaxFiles() throws {
        let root = try makeTree(["a.html", "b.html", "c.html", "d.html", "e.html"])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = FolderScanner.scan(roots: [root], maxFiles: 3)
        #expect(result.files.count == 3)
        #expect(result.truncated)
    }
}
