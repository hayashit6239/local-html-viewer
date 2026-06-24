import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(WatchEventPolicy):
// 入力契約: paths / displayedPath は canonical 正規化済み(消費側 = AppState が正規化)。
// [x] ignore ディレクトリ配下のみ → .ignore(node_modules churn 暴走防止)
// [x] .tmp / 隠しファイルのみ → .ignore(アトミック保存の中間物)
// [x] 表示中ファイルが含まれる → .reloadDisplayed
// [x] 新規(表示中でない関連パス)→ .rescan
// [x] mustScanSubDirs → .rescan
// [x] 混在(ignore + 表示中)→ .reloadDisplayed

@Suite("WatchEventPolicy")
struct WatchEventPolicyTests {
    @Test("ignore 配下のみは無視")
    func ignoreOnly() {
        let paths = ["/r/node_modules/x.html", "/r/.git/y"]
        #expect(WatchEventPolicy.decide(paths: paths, displayedPath: nil) == .ignore)
    }

    @Test(".tmp / 隠しファイルのみは無視")
    func tempOnly() {
        let paths = ["/r/.a.html.tmp", "/r/.hidden.html", "/r/page.html.tmp"]
        #expect(WatchEventPolicy.decide(paths: paths, displayedPath: nil) == .ignore)
    }

    @Test("表示中ファイルが含まれたら reload")
    func reloadDisplayed() {
        let paths = ["/r/a.html"]
        #expect(WatchEventPolicy.decide(paths: paths, displayedPath: "/r/a.html") == .reloadDisplayed)
    }

    @Test("新規(表示中でない)関連パスは rescan")
    func newFileRescan() {
        let paths = ["/r/new.html"]
        #expect(WatchEventPolicy.decide(paths: paths, displayedPath: "/r/a.html") == .rescan)
    }

    @Test("mustScanSubDirs は rescan")
    func mustScan() {
        #expect(WatchEventPolicy.decide(paths: [], displayedPath: nil, mustScanSubDirs: true) == .rescan)
    }

    @Test("混在(ignore + 表示中)は reload")
    func mixed() {
        let paths = ["/r/node_modules/x.html", "/r/a.html"]
        #expect(WatchEventPolicy.decide(paths: paths, displayedPath: "/r/a.html") == .reloadDisplayed)
    }
}
