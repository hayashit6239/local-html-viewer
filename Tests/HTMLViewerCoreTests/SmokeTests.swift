import Foundation
import Testing

@testable import HTMLViewerCore

// M1 テストリスト:
// [x] Swift Testing が CLT toolchain の swift test で実行できる(テスト基盤のスモーク)
// [x] HTMLFile の id は path と一致する
// M5 brush-up テストリスト:
// [x] 同 path・異 isExternal の HTMLFile は == で等価(Identifiable と Hashable を整合)

@Test("Swift Testing が CLT で動作する")
func testHarnessSmoke() {
    #expect(1 + 1 == 2)
}

@Test("HTMLFile の id は path と一致する")
func htmlFileIdentity() {
    let file = HTMLFile(
        path: "/tmp/sample/a.html",
        name: "a.html",
        mtime: Date(timeIntervalSince1970: 0),
        rootPath: "/tmp/sample",
        relativePath: "a.html"
    )
    #expect(file.id == "/tmp/sample/a.html")
}

@Test("HTMLFile は path のみで等価(isExternal / mtime / rootPath を比較に含めない)")
func htmlFileEqualsByPathOnly() {
    let external = HTMLFile(
        path: "/tmp/sample/a.html",
        name: "a.html",
        mtime: Date(timeIntervalSince1970: 100),
        rootPath: "/tmp/sample",
        relativePath: "a.html",
        isExternal: true
    )
    let internalVersion = HTMLFile(
        path: "/tmp/sample/a.html",
        name: "a.html",
        mtime: Date(timeIntervalSince1970: 200),  // mtime 違い
        rootPath: "/tmp/other",  // rootPath 違い
        relativePath: "a.html",
        isExternal: false  // isExternal 違い
    )
    #expect(external == internalVersion)
    #expect(external.hashValue == internalVersion.hashValue)

    // path が違えば不等(対偶)
    let other = HTMLFile(
        path: "/tmp/sample/b.html",
        name: "b.html",
        mtime: Date(timeIntervalSince1970: 100),
        rootPath: "/tmp/sample",
        relativePath: "b.html"
    )
    #expect(external != other)
}
