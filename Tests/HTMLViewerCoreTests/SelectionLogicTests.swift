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

    @Test("隠れた選択: 可視なら通常移動・隠れたら全順序基準で同方向の最近可視へ")
    func nextWithFullOrder() {
        let full = [f("a"), f("b"), f("c"), f("d"), f("e")]
        let visible = [f("a"), f("e")]  // b/c/d が折りたたみで不可視

        // 可視な選択(a)は通常移動(visible 内の隣 = e)
        #expect(
            SelectionLogic.next(after: f("a"), in: visible, fullOrder: full, direction: .down)?.name
                == "e")
        // 隠れた選択(c)から down → 全順序で c の次以降の最初の可視(e)
        #expect(
            SelectionLogic.next(after: f("c"), in: visible, fullOrder: full, direction: .down)?.name
                == "e")
        // 隠れた選択(c)から up → 全順序で c の前の最後の可視(a)
        #expect(
            SelectionLogic.next(after: f("c"), in: visible, fullOrder: full, direction: .up)?.name
                == "a")
        // 隠れた選択(d)から down → 同方向に可視 leaf 無し → 端(末尾 e)
        #expect(
            SelectionLogic.next(after: f("d"), in: visible, fullOrder: full, direction: .down)?.name
                == "e")
    }

    @Test("隠れた選択: 全順序にも無い(外部ピン等)は端から開始")
    func nextWithFullOrderUnknown() {
        let full = [f("a"), f("b")]
        let visible = [f("a"), f("b")]
        let external = HTMLFile(
            path: "/tmp/x.html", name: "x.html", mtime: Date(timeIntervalSince1970: 0),
            rootPath: "/tmp", relativePath: "x.html", isExternal: true)
        #expect(
            SelectionLogic.next(after: external, in: visible, fullOrder: full, direction: .down)?
                .name == "a")
        #expect(
            SelectionLogic.next(after: external, in: visible, fullOrder: full, direction: .up)?.name
                == "b")
    }
}
