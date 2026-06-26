import Foundation
import Testing

@testable import HTMLViewerCore

@Suite("TreeBuilder")
struct TreeBuilderTests {
    private func f(root: String, rel: String) -> HTMLFile {
        HTMLFile(
            path: root + "/" + rel, name: (rel as NSString).lastPathComponent,
            mtime: Date(timeIntervalSince1970: 0), rootPath: root, relativePath: rel
        )
    }

    @Test("単一ルート: dir/leaf 階層を構築")
    func singleRoot() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let tree = TreeBuilder.build(files)
        #expect(tree.count == 1)
        let root = tree[0]
        #expect(root.id == "/R/" && root.children != nil)  // dir id は末尾 "/"(leaf と区別)
        // dir(sub) 先・leaf(a.html) 後
        #expect(root.children?.map(\.name) == ["sub", "a.html"])
        let sub = root.children!.first!
        #expect(sub.children?.first?.file?.path == "/R/sub/b.html")
    }

    @Test("複数ルートを跨いで束ねる")
    func multiRoot() {
        let files = [f(root: "/A", rel: "x.html"), f(root: "/B", rel: "y.html")]
        #expect(TreeBuilder.build(files).map(\.name) == ["A", "B"])
    }

    @Test("空は空")
    func empty() {
        #expect(TreeBuilder.build([]).isEmpty)
    }

    @Test("可視 leaf 列: 展開済み dir のみ平坦化")
    func visibleLeaves() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let tree = TreeBuilder.build(files)
        // ルートのみ展開 → sub 配下は不可視、a.html のみ(dir id は末尾 "/")
        let rootOnly = TreeBuilder.visibleLeaves(tree, expanded: ["/R/"])
        #expect(rootOnly.map(\.name) == ["a.html"])
        // sub も展開 → b.html も可視
        let all = TreeBuilder.visibleLeaves(tree, expanded: ["/R/", "/R/sub/"])
        #expect(Set(all.map(\.name)) == ["a.html", "b.html"])
    }

    @Test("allLeaves: 全 leaf を visit 順に平坦化")
    func allLeaves() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let names = TreeBuilder.allLeaves(TreeBuilder.build(files)).map(\.name)
        #expect(Set(names) == ["a.html", "b.html"])
    }

    @Test("ancestors: leaf を見せる祖先 dir をルートまで返す")
    func ancestors() {
        let files = [f(root: "/R", rel: "x/y/z.html")]
        let tree = TreeBuilder.build(files)
        let anc = TreeBuilder.ancestors(ofLeaf: "/R/x/y/z.html", in: tree)
        #expect(anc == ["/R/", "/R/x/", "/R/x/y/"])  // dir id は末尾 "/"
    }

    @Test("展開ポリシー: 閾値以下は全 dir 展開")
    func defaultExpandedAll() {
        let files = [f(root: "/R", rel: "sub/b.html"), f(root: "/R", rel: "c.html")]
        let tree = TreeBuilder.build(files)
        #expect(TreeBuilder.defaultExpanded(tree) == ["/R/", "/R/sub/"])
    }

    @Test("dir/leaf id 衝突回避: 同名 .html の dir と file が同階層でも id が異なる")
    func dirLeafIdNoCollision() {
        // report.html(dir、配下に index.html)と report.html(file)が同一親に並ぶ
        let files = [
            f(root: "/R", rel: "report.html/index.html"),
            f(root: "/R", rel: "report.html"),
        ]
        let tree = TreeBuilder.build(files)
        let root = tree[0]
        let children = root.children ?? []
        let dirNode = children.first { !$0.isLeaf }
        let leafNode = children.first { $0.isLeaf }
        #expect(dirNode?.id == "/R/report.html/")   // dir は末尾 "/"
        #expect(leafNode?.id == "/R/report.html")   // leaf は file.path(末尾なし)
        #expect(dirNode?.id != leafNode?.id)         // 衝突しない
    }

    @Test("trailing slash 付き root でも二重スラッシュを混入させない(M7 review #10)")
    func rootTrailingSlashNoDoubleSlash() {
        // rootPath が末尾 "/"(root='/' / URL.path 由来の trailing slash)のケース
        let file = HTMLFile(
            path: "/sub/a.html", name: "a.html", mtime: Date(timeIntervalSince1970: 0),
            rootPath: "/", relativePath: "sub/a.html")
        let tree = TreeBuilder.build([file])
        #expect(tree[0].id == "/")           // dirID("/") は "//" にしない
        let subDir = tree[0].children?.first { !$0.isLeaf }
        #expect(subDir?.id == "/sub/")       // "//sub/" にならない
        // ancestors も末尾正規化された dir id を返し、selectedLeafPath で展開できる
        let anc = TreeBuilder.ancestors(ofLeaf: "/sub/a.html", in: tree)
        #expect(anc == ["/", "/sub/"])
    }

    @Test("展開合成: 非検索・未選択は defaultExpanded と一致")
    func expansionSetDefault() {
        let files = [f(root: "/R", rel: "sub/b.html"), f(root: "/R", rel: "c.html")]
        let tree = TreeBuilder.build(files)
        let set = TreeBuilder.expansionSet(for: tree, searching: false, selectedLeafPath: nil)
        #expect(set == TreeBuilder.defaultExpanded(tree))
    }

    @Test("展開合成: 選択中 leaf の祖先 dir を展開(親 dir 自動展開)")
    func expansionSetSelectedAncestors() {
        // 閾値超過を模さず、選択祖先が必ず含まれることを確認(deep leaf)
        let files = [f(root: "/R", rel: "x/y/z.html")]
        let tree = TreeBuilder.build(files)
        let set = TreeBuilder.expansionSet(
            for: tree, searching: false, selectedLeafPath: "/R/x/y/z.html"
        )
        #expect(set.isSuperset(of: ["/R/", "/R/x/", "/R/x/y/"]))
    }

    @Test("展開合成: 検索中は全ヒットの祖先を展開して可視化")
    func expansionSetSearchingExpandsHits() {
        let files = [f(root: "/R", rel: "deep/nested/hit.html")]
        let tree = TreeBuilder.build(files)
        // 検索中フラグで、ヒット(= フィルタ後 leaf)の祖先がすべて展開される
        let set = TreeBuilder.expansionSet(for: tree, searching: true, selectedLeafPath: nil)
        #expect(set.isSuperset(of: ["/R/", "/R/deep/", "/R/deep/nested/"]))
    }

    // MARK: - visibleRows(#32 行ベース可視列)
    // テストリスト:
    // [x] 空ツリーは空配列
    // [x] 全展開で dir 行 + leaf 行が depth-first 順(visibleLeaves と一致する file 部分)
    // [x] ルートのみ展開なら dir 配下の dir/leaf は不可視
    // [x] depth はルート dir=0、子=1、…(UI 側のインデント用)
    // [x] dir/leaf 同階層の並びは TreeNode の build と同じ(dir 先・leaf 後)

    @Test("visibleRows: 空ツリーは空配列")
    func visibleRowsEmpty() {
        #expect(TreeBuilder.visibleRows([], expanded: []).isEmpty)
    }

    @Test("visibleRows: 全展開で dir/leaf を depth-first 順に平坦化(depth 付き)")
    func visibleRowsFullyExpanded() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let tree = TreeBuilder.build(files)
        let rows = TreeBuilder.visibleRows(tree, expanded: ["/R/", "/R/sub/"])
        // 期待: [dir "/R/" depth=0, dir "/R/sub/" depth=1, file b.html, file a.html]
        // (build は dir 先・leaf 後、各々名前昇順)
        guard rows.count == 4 else {
            #expect(rows.count == 4); return
        }
        guard case .dir(let id0, let d0) = rows[0] else { #expect(Bool(false)); return }
        #expect(id0 == "/R/" && d0 == 0)
        guard case .dir(let id1, let d1) = rows[1] else { #expect(Bool(false)); return }
        #expect(id1 == "/R/sub/" && d1 == 1)
        guard case .file(let bFile) = rows[2] else { #expect(Bool(false)); return }
        #expect(bFile.name == "b.html")
        guard case .file(let aFile) = rows[3] else { #expect(Bool(false)); return }
        #expect(aFile.name == "a.html")
    }

    @Test("visibleRows: ルートのみ展開で dir 配下は不可視(dir 自体は出る)")
    func visibleRowsRootOnly() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let tree = TreeBuilder.build(files)
        let rows = TreeBuilder.visibleRows(tree, expanded: ["/R/"])
        // 期待: [dir "/R/", dir "/R/sub/"(折りたたみ中で配下不可視), file a.html]
        guard rows.count == 3 else { #expect(rows.count == 3); return }
        guard case .dir(let id0, _) = rows[0] else { #expect(Bool(false)); return }
        #expect(id0 == "/R/")
        guard case .dir(let id1, let d1) = rows[1] else { #expect(Bool(false)); return }
        #expect(id1 == "/R/sub/" && d1 == 1)  // dir 行は出るが子は出ない
        guard case .file(let aFile) = rows[2] else { #expect(Bool(false)); return }
        #expect(aFile.name == "a.html")
    }

    @Test("visibleRows: ルート未展開なら配下は dir も leaf も出ない")
    func visibleRowsAllCollapsed() {
        let files = [f(root: "/R", rel: "a.html"), f(root: "/R", rel: "sub/b.html")]
        let tree = TreeBuilder.build(files)
        let rows = TreeBuilder.visibleRows(tree, expanded: [])
        // 期待: [dir "/R/"](ルート dir 自身は常に表示、配下は折りたたみで非表示)
        #expect(rows.count == 1)
        guard case .dir(let id0, let d0) = rows[0] else { #expect(Bool(false)); return }
        #expect(id0 == "/R/" && d0 == 0)
    }

    @Test("ancestors(ofDir:): dir 自身は含まず祖先 dir のみ・ルートまで再帰(#33 round-2 #2)")
    func ancestorsOfDir() {
        let files = [f(root: "/R", rel: "x/y/z.html")]
        let tree = TreeBuilder.build(files)
        // 深い dir の祖先(自身は含まない)
        #expect(TreeBuilder.ancestors(ofDir: "/R/x/y/", in: tree) == ["/R/", "/R/x/"])
        // 浅い dir の祖先(ルートのみ・自身は含まない)
        #expect(TreeBuilder.ancestors(ofDir: "/R/x/", in: tree) == ["/R/"])
        // ルート自身の祖先(空)
        #expect(TreeBuilder.ancestors(ofDir: "/R/", in: tree) == [])
        // 存在しない dir(空)
        #expect(TreeBuilder.ancestors(ofDir: "/missing/", in: tree) == [])
    }

    @Test("containsDir: 現ツリーに dir が存在するか(#33 round-2 #1)")
    func containsDirCheck() {
        let files = [f(root: "/R", rel: "x/y/z.html")]
        let tree = TreeBuilder.build(files)
        #expect(TreeBuilder.containsDir("/R/", in: tree))
        #expect(TreeBuilder.containsDir("/R/x/", in: tree))
        #expect(TreeBuilder.containsDir("/R/x/y/", in: tree))
        #expect(!TreeBuilder.containsDir("/R/x/y/z.html", in: tree))  // leaf は dir でない
        #expect(!TreeBuilder.containsDir("/missing/", in: tree))
    }

    @Test("visibleRows: visibleLeaves と file 部分が一致(後方互換確認)")
    func visibleRowsFilesMatchVisibleLeaves() {
        let files = [
            f(root: "/R", rel: "a.html"),
            f(root: "/R", rel: "sub/b.html"),
            f(root: "/R", rel: "sub/c.html"),
        ]
        let tree = TreeBuilder.build(files)
        let expanded: Set<String> = ["/R/", "/R/sub/"]
        let rows = TreeBuilder.visibleRows(tree, expanded: expanded)
        let leaves = TreeBuilder.visibleLeaves(tree, expanded: expanded)
        let rowFiles = rows.compactMap { row -> HTMLFile? in
            if case .file(let f) = row { return f } else { return nil }
        }
        #expect(rowFiles == leaves)
    }
}
