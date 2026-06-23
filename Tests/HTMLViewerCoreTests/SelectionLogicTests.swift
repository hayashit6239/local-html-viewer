import Foundation
import Testing

@testable import HTMLViewerCore

@Suite("SelectionLogic")
struct SelectionLogicTests {
    private func f(_ name: String) -> HTMLFile {
        HTMLFile(path: "/r/\(name)", name: name, mtime: Date(timeIntervalSince1970: 0), rootPath: "/r", relativePath: name)
    }

    @Test("down/up で隣へ、端はクランプ")
    func nextClamp() {
        let list = [f("a"), f("b"), f("c")]
        #expect(SelectionLogic.next(after: f("a"), in: list, direction: .down)?.name == "b")
        #expect(SelectionLogic.next(after: f("b"), in: list, direction: .up)?.name == "a")
        #expect(SelectionLogic.next(after: f("c"), in: list, direction: .down)?.name == "c")  // 下端クランプ
        #expect(SelectionLogic.next(after: f("a"), in: list, direction: .up)?.name == "a")     // 上端クランプ
    }

    @Test("未選択は端から開始")
    func nextFromNil() {
        let list = [f("a"), f("b")]
        #expect(SelectionLogic.next(after: nil, in: list, direction: .down)?.name == "a")
        #expect(SelectionLogic.next(after: nil, in: list, direction: .up)?.name == "b")
    }

    @Test("空は nil")
    func nextEmpty() {
        #expect(SelectionLogic.next(after: f("a"), in: [], direction: .down) == nil)
    }

    @Test("reconcile: 残存なら維持・消えたら先頭・空なら nil")
    func reconcile() {
        let list = [f("a"), f("b")]
        #expect(SelectionLogic.reconcile(previous: f("b"), in: list)?.name == "b")  // 維持
        #expect(SelectionLogic.reconcile(previous: f("z"), in: list)?.name == "a")  // 消えた→先頭
        #expect(SelectionLogic.reconcile(previous: f("a"), in: [])?.name == nil)    // 空→nil
        #expect(SelectionLogic.reconcile(previous: nil, in: list)?.name == "a")     // 未選択→先頭
    }
}
