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
}
