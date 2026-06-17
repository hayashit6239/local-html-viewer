import Testing

@testable import HTMLViewerCore

// テストリスト(RootDiagnostics):
// [x] 到達不能なら他の条件によらず unreachable
// [x] ファイルがあれば ok
// [x] 到達可能・0 件・保護領域 → tccLikelyBlocked
// [x] 到達可能・0 件・保護領域外 → empty(本当に空)
// [x] home 配下の Documents/Desktop/Downloads とその配下は保護領域、それ以外は外
// [x] home の末尾スラッシュ有無に依存しない
//
// 注: パスは合成値。セキュリティ規約(実 /Users パス禁止)に従い、判定が純粋な
// 文字列 prefix 比較であることを利用して /Users を含まない合成 home で検証する。

@Suite("RootDiagnostics")
struct RootDiagnosticsTests {
    private let home = "/synthetic/home"

    @Test("到達不能なら(件数・保護領域によらず)unreachable")
    func unreachableDominates() {
        #expect(RootDiagnostics.classify(isReachable: false, fileCount: 0, isUnderProtectedLocation: true) == .unreachable)
        #expect(RootDiagnostics.classify(isReachable: false, fileCount: 5, isUnderProtectedLocation: false) == .unreachable)
    }

    @Test("ファイルがあれば ok")
    func okWhenFilesPresent() {
        #expect(RootDiagnostics.classify(isReachable: true, fileCount: 1, isUnderProtectedLocation: true) == .ok)
        #expect(RootDiagnostics.classify(isReachable: true, fileCount: 42, isUnderProtectedLocation: false) == .ok)
    }

    @Test("到達可能・0 件・保護領域 → TCC 失効の疑い")
    func tccLikelyBlockedWhenEmptyUnderProtected() {
        #expect(RootDiagnostics.classify(isReachable: true, fileCount: 0, isUnderProtectedLocation: true) == .tccLikelyBlocked)
    }

    @Test("到達可能・0 件・保護領域外 → 本当に空")
    func emptyWhenEmptyOutsideProtected() {
        #expect(RootDiagnostics.classify(isReachable: true, fileCount: 0, isUnderProtectedLocation: false) == .empty)
    }

    @Test("Documents/Desktop/Downloads 直下・配下は保護領域、それ以外は外")
    func detectsProtectedLocation() {
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Documents", home: home))
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Documents/reports", home: home))
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Desktop/a", home: home))
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Downloads", home: home))
        #expect(!RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Projects", home: home))
        // 前方一致の取り違え防止(DocumentsX を Documents 扱いしない)
        #expect(!RootDiagnostics.isUnderProtectedLocation(path: "\(home)/DocumentsX", home: home))
        // home 配下でない同名ディレクトリはマッチしない
        #expect(!RootDiagnostics.isUnderProtectedLocation(path: "/Documents", home: home))
    }

    @Test("home の末尾スラッシュ有無に依存しない")
    func homeTrailingSlashAgnostic() {
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Documents/x", home: "\(home)/"))
        #expect(RootDiagnostics.isUnderProtectedLocation(path: "\(home)/Documents/x", home: home))
    }
}
