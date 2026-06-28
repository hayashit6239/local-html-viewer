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

    // MARK: - nextRow / reconcile(行版・#32)
    // テストリスト:
    // [x] 空 visible は nil
    // [x] 未選択 + down は最初の行、up は最後の行
    // [x] dir → file → dir の混在で down/up が順に隣へ
    // [x] 端クランプ(回り込みなし)
    // [x] 選択が visible に無い場合は端から開始(行版は単純化、fullOrder は持たない)
    // [x] reconcile(行版): 残存(file/dir)維持・消えたら先頭・空 nil・nil → 先頭

    private func rowsExample() -> [TreeRow] {
        // 模式図: [dir "/R/", dir "/R/sub/", file b, file a]
        [
            .dir(id: "/R/"),
            .dir(id: "/R/sub/"),
            .file(f("b")),
            .file(f("a")),
        ]
    }

    @Test("nextRow: 空 visible は nil")
    func nextRowEmpty() {
        #expect(SelectionLogic.nextRow(after: nil, in: [], direction: .down) == nil)
        #expect(SelectionLogic.nextRow(after: .file(f("a")), in: [], direction: .up) == nil)
    }

    @Test("nextRow: 未選択は端から開始(down=先頭、up=末尾)")
    func nextRowFromNil() {
        let rows = rowsExample()
        #expect(SelectionLogic.nextRow(after: nil, in: rows, direction: .down) == .dir(id: "/R/"))
        #expect(SelectionLogic.nextRow(after: nil, in: rows, direction: .up) == .file(f("a")))
    }

    // round-4 #7: 1 @Test に束ねていた 5 観点を「隣接遷移(dir↔dir / dir↔file)」と「端クランプ」に分離。
    // Swift Testing の `#expect` は失敗継続だが、@Test 名で観点が分かる方が診断が早い。

    @Test("nextRow: dir/file 混在で隣接遷移(dir↔dir / dir↔file)")
    func nextRowAdjacentMixed() {
        let rows = rowsExample()
        // dir "/R/" → 次は dir "/R/sub/"
        #expect(
            SelectionLogic.nextRow(after: .dir(id: "/R/"), in: rows, direction: .down)
                == .dir(id: "/R/sub/"))
        // dir "/R/sub/" → 次は file b
        #expect(
            SelectionLogic.nextRow(after: .dir(id: "/R/sub/"), in: rows, direction: .down)
                == .file(f("b")))
        // file b → up は dir "/R/sub/"
        #expect(
            SelectionLogic.nextRow(after: .file(f("b")), in: rows, direction: .up)
                == .dir(id: "/R/sub/"))
    }

    @Test("nextRow: 端クランプ(末尾 down / 先頭 up は同位置)")
    func nextRowClamp() {
        let rows = rowsExample()
        // 末尾 file a で down → クランプ(同位置)
        #expect(
            SelectionLogic.nextRow(after: .file(f("a")), in: rows, direction: .down)
                == .file(f("a")))
        // 先頭 dir "/R/" で up → クランプ
        #expect(
            SelectionLogic.nextRow(after: .dir(id: "/R/"), in: rows, direction: .up)
                == .dir(id: "/R/"))
    }

    @Test("reconcile(行版): previous=.file が visibleRows に無いと先頭(dir に倒れうる)を返す")
    func reconcileRowMayFallToDir() {
        // 行版 reconcile は呼び出し側で「previous が .file の場合は leaf 版に分岐」する責務がある
        // ことを Core 側で文書化するための回帰テスト(AppState 側で round-4 #1 として遵守)。
        let rows = rowsExample()  // [dir "/R/", dir "/R/sub/", file b, file a]
        // 存在しない file を previous にすると visibleRows.first(=dir "/R/")が返る
        #expect(
            SelectionLogic.reconcile(previous: .file(f("z")), in: rows) == .dir(id: "/R/"))
    }

    @Test("nextRow: visible に無い選択(折りたたみ等で消えた dir)は端から開始")
    func nextRowMissing() {
        let rows = rowsExample()
        let ghost: SidebarSelection = .dir(id: "/R/sub/gone/")
        #expect(
            SelectionLogic.nextRow(after: ghost, in: rows, direction: .down) == .dir(id: "/R/"))
        #expect(
            SelectionLogic.nextRow(after: ghost, in: rows, direction: .up) == .file(f("a")))
    }

    @Test("reconcile(行版): 残存(file/dir)維持・消えたら先頭・空 nil・nil → 先頭")
    func reconcileRow() {
        let rows = rowsExample()
        // file 維持
        #expect(
            SelectionLogic.reconcile(previous: .file(f("b")), in: rows) == .file(f("b")))
        // dir 維持
        #expect(
            SelectionLogic.reconcile(previous: .dir(id: "/R/sub/"), in: rows)
                == .dir(id: "/R/sub/"))
        // 消えた file → 先頭(= 最初の dir 行)
        #expect(
            SelectionLogic.reconcile(previous: .file(f("z")), in: rows) == .dir(id: "/R/"))
        // 消えた dir → 先頭
        #expect(
            SelectionLogic.reconcile(previous: .dir(id: "/missing/"), in: rows)
                == .dir(id: "/R/"))
        // 空 → nil
        #expect(SelectionLogic.reconcile(previous: .file(f("a")), in: []) == nil)
        // nil → 先頭
        #expect(SelectionLogic.reconcile(previous: nil, in: rows) == .dir(id: "/R/"))
    }

    @Test("matches(public): file ↔ file は id 一致、dir ↔ dir は id 一致、case 違いは false")
    func matchesPublic() {
        let fa = f("a")
        // 同 case 一致
        #expect(SelectionLogic.matches(.file(fa), .file(fa)))
        #expect(SelectionLogic.matches(.dir(id: "/R/"), .dir(id: "/R/")))
        // 同 case 不一致
        #expect(!SelectionLogic.matches(.file(fa), .file(f("b"))))
        #expect(!SelectionLogic.matches(.dir(id: "/R/"), .dir(id: "/Q/")))
        // case 違い(file ↔ dir / dir ↔ file)は常に false
        #expect(!SelectionLogic.matches(.file(fa), .dir(id: "/R/")))
        #expect(!SelectionLogic.matches(.dir(id: "/R/"), .file(fa)))
    }
}
