import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(RecentSorter):
// [x] mtime 降順に並ぶ
// [x] mtime 同値はパス昇順で安定ソート
// [x] 空配列は空のまま

@Suite("RecentSorter")
struct RecentSorterTests {
    private func file(_ name: String, _ epoch: TimeInterval) -> HTMLFile {
        HTMLFile(
            path: "/root/\(name)",
            name: name,
            mtime: Date(timeIntervalSince1970: epoch),
            rootPath: "/root",
            relativePath: name
        )
    }

    @Test("mtime 降順に並ぶ")
    func sortsDescending() {
        let input = [file("old.html", 100), file("new.html", 300), file("mid.html", 200)]
        let sorted = RecentSorter.sortedByModificationDateDescending(input)
        #expect(sorted.map(\.name) == ["new.html", "mid.html", "old.html"])
    }

    @Test("mtime 同値はパス昇順で安定")
    func tieBreaksByPath() {
        let input = [file("b.html", 100), file("a.html", 100)]
        let sorted = RecentSorter.sortedByModificationDateDescending(input)
        #expect(sorted.map(\.name) == ["a.html", "b.html"])
    }

    @Test("空配列は空のまま")
    func emptyStaysEmpty() {
        #expect(RecentSorter.sortedByModificationDateDescending([]).isEmpty)
    }
}
