import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(ExternalOpenPolicy):
// 前提: path 比較はすべて正規化済(canonicalPath)文字列で行う(呼び出し側 = AppState が正規化)。
// [x] 内外判定: 登録ルート配下なら inside、外なら outside、exact root も inside
// [x] EXTERNAL HTMLFile 合成: name=末尾 / rootPath=親 dir / relativePath=name / isExternal=true
// [x] リスト合成: 単一ピンを先頭に置く
// [x] リスト合成: pin path が recent に既出なら omit(二重解消)
// [x] リスト合成: pin が nil なら recent そのまま
// [x] 内部ファイル受信は「ピンを返さない」契約(makeExternalFile は外部専用)

@Suite("ExternalOpenPolicy")
struct ExternalOpenPolicyTests {
    private func file(_ path: String, external: Bool = false) -> HTMLFile {
        HTMLFile(
            path: path,
            name: (path as NSString).lastPathComponent,
            mtime: Date(timeIntervalSince1970: 0),
            rootPath: (path as NSString).deletingLastPathComponent,
            relativePath: (path as NSString).lastPathComponent,
            isExternal: external
        )
    }

    @Test("内外判定: 配下 inside / 外 outside / exact root inside")
    func insideOutside() {
        let roots = ["/Registered/a", "/Registered/b"]
        #expect(ExternalOpenPolicy.isInside("/Registered/a/x.html", registeredRoots: roots))
        #expect(ExternalOpenPolicy.isInside("/Registered/a", registeredRoots: roots))
        #expect(!ExternalOpenPolicy.isInside("/tmp/x.html", registeredRoots: roots))
        // prefix の部分一致誤検知を防ぐ(/Registered/abc は /Registered/a 配下ではない)
        #expect(!ExternalOpenPolicy.isInside("/Registered/abc/x.html", registeredRoots: roots))
    }

    @Test("EXTERNAL HTMLFile 合成")
    func makeExternal() {
        let f = ExternalOpenPolicy.makeExternalFile(path: "/tmp/report.html", mtime: Date(timeIntervalSince1970: 100))
        #expect(f.path == "/tmp/report.html")
        #expect(f.name == "report.html")
        #expect(f.rootPath == "/tmp")
        #expect(f.relativePath == "report.html")
        #expect(f.isExternal)
    }

    @Test("リスト合成: 単一ピンを先頭に置く")
    func composePrepend() {
        let recent = [file("/Registered/a/x.html"), file("/Registered/a/y.html")]
        let pin = ExternalOpenPolicy.makeExternalFile(path: "/tmp/z.html", mtime: Date())
        let out = ExternalOpenPolicy.compose(recent: recent, pinned: pin)
        #expect(out.first?.path == "/tmp/z.html")
        #expect(out.count == 3)
    }

    @Test("リスト合成: pin が recent に既出なら omit(二重解消)")
    func composeOmitDuplicate() {
        let shared = "/Registered/a/x.html"
        let recent = [file(shared)]
        let pin = ExternalOpenPolicy.makeExternalFile(path: shared, mtime: Date())
        let out = ExternalOpenPolicy.compose(recent: recent, pinned: pin)
        #expect(out.map(\.path) == [shared])  // ピンを足さず recent のまま
    }

    @Test("リスト合成: pin が nil なら recent そのまま")
    func composeNilPin() {
        let recent = [file("/Registered/a/x.html")]
        #expect(ExternalOpenPolicy.compose(recent: recent, pinned: nil).map(\.path) == recent.map(\.path))
    }
}
