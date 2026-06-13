import Foundation
import Testing

@testable import HTMLViewerCore

// M1 テストリスト:
// [x] Swift Testing が CLT toolchain の swift test で実行できる(テスト基盤のスモーク)
// [x] HTMLFile の id は path と一致する

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
