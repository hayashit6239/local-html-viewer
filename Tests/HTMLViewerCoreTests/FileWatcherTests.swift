import Foundation
import Testing

@testable import HTMLViewerCore

// M6 着手前スモーク: CLT + 実行環境で FSEvents が実動するかを最初に実証する。
// これが落ちたら本実装に進まず Alternative B(ポーリング)へ切替(05 D4 撤退路)。

@Suite("FileWatcher")
struct FileWatcherTests {
    @Test("FSEvents: temp dir のファイル作成イベントを受信する", .timeLimit(.minutes(1)))
    func receivesFileEvents() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("htmlviewer-fsw-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let watcher = FileWatcher(roots: [root])
        watcher.start()
        defer { watcher.stop() }

        // ストリーム稼働を待ってから書き込む(start 直後の取りこぼし回避)
        try await Task.sleep(for: .milliseconds(400))
        try Data("<html></html>".utf8).write(to: root.appendingPathComponent("a.html"))

        var hit = false
        for await batch in watcher.events {
            if batch.contains(where: { $0.contains("a.html") }) { hit = true; break }
        }
        #expect(hit)
    }
}
