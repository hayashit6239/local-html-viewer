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
        #expect(root.id == "/R" && root.children != nil)
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
        // ルートのみ展開 → sub 配下は不可視、a.html のみ
        let rootOnly = TreeBuilder.visibleLeaves(tree, expanded: ["/R"])
        #expect(rootOnly.map(\.name) == ["a.html"])
        // sub も展開 → b.html も可視
        let all = TreeBuilder.visibleLeaves(tree, expanded: ["/R", "/R/sub"])
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
        #expect(anc == ["/R", "/R/x", "/R/x/y"])
    }

    @Test("展開ポリシー: 閾値以下は全 dir 展開")
    func defaultExpandedAll() {
        let files = [f(root: "/R", rel: "sub/b.html"), f(root: "/R", rel: "c.html")]
        let tree = TreeBuilder.build(files)
        #expect(TreeBuilder.defaultExpanded(tree) == ["/R", "/R/sub"])
    }
}
