import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(PersistenceCodec):
// [x] エンコード→デコードで順序を保ってラウンドトリップする
// [x] nil をデコードすると空配列
// [x] 壊れた Data をデコードすると空配列
// [x] 重複パスは最初の出現だけ残す

@Suite("PersistenceCodec")
struct PersistenceCodecTests {
    @Test("ラウンドトリップで順序を保つ")
    func roundTrip() {
        let paths = ["/a", "/b/c", "/d"]
        let decoded = PersistenceCodec.decodeFolderPaths(PersistenceCodec.encodeFolderPaths(paths))
        #expect(decoded == paths)
    }

    @Test("nil は空配列")
    func nilIsEmpty() {
        #expect(PersistenceCodec.decodeFolderPaths(nil).isEmpty)
    }

    @Test("壊れた Data は空配列")
    func garbageIsEmpty() {
        #expect(PersistenceCodec.decodeFolderPaths(Data([0x00, 0x01, 0x02])).isEmpty)
    }

    @Test("重複は最初の出現だけ残す")
    func dedupesPreservingOrder() {
        let decoded = PersistenceCodec.decodeFolderPaths(
            PersistenceCodec.encodeFolderPaths(["/a", "/b", "/a"])
        )
        #expect(decoded == ["/a", "/b"])
    }
}
