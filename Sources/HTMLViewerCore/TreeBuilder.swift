import Foundation

/// TREE タブの階層構築・展開ポリシー(UI 非依存)。
public enum TreeBuilder {
    /// この dir 総数以下なら全展開、超過なら第一階層(ルート)のみ展開(heuristic・調整可能)。
    public static let autoExpandDirThreshold = 40

    /// `[HTMLFile]` から階層を構築する。複数ルートを跨いで束ね(ルートごとのサブツリー)、
    /// `relativePath` を分解して dir/leaf ノードを作る。dir 先・leaf 後、各々名前昇順で安定。
    public static func build(_ files: [HTMLFile]) -> [TreeNode] {
        let byRoot = Dictionary(grouping: files, by: \.rootPath)
        return byRoot.keys.sorted().map { root in
            let entries = byRoot[root]!.map {
                (components: ($0.relativePath as NSString).pathComponents, file: $0)
            }
            return TreeNode(
                id: dirID(root),
                name: (root as NSString).lastPathComponent,
                file: nil,
                children: level(parent: root, entries: entries)
            )
        }
    }

    /// dir ノードの id は**末尾 `/` 付き**にして leaf(= `file.path`、末尾スラッシュ無し)と区別する。
    /// dir 名と同名の `.html` ファイルが同階層に並んでも id が衝突しない(SwiftUI Identifiable /
    /// `expandedDirs` の誤照合を防ぐ)。`ancestors`/`defaultExpanded`/`visibleLeaves`
    /// はすべて `TreeNode.id` を参照するため、この 1 箇所の付与で一貫する。
    /// 既に末尾 `/`(root=`/` や trailing slash 付き rootPath)なら二重付与しない。
    private static func dirID(_ path: String) -> String { path.hasSuffix("/") ? path : path + "/" }

    /// dir パスを連結する。`parent` が既に末尾 `/`(root=`/` 等)なら二重スラッシュを混入させない。
    private static func joinDir(_ parent: String, _ component: String) -> String {
        parent.hasSuffix("/") ? parent + component : parent + "/" + component
    }

    private static func level(
        parent: String,
        entries: [(components: [String], file: HTMLFile)]
    ) -> [TreeNode] {
        var leaves: [TreeNode] = []
        var groups: [String: [(components: [String], file: HTMLFile)]] = [:]
        for e in entries {
            if e.components.count <= 1 {
                leaves.append(TreeNode(id: e.file.path, name: e.file.name, file: e.file, children: nil))
            } else {
                groups[e.components[0], default: []].append(
                    (components: Array(e.components.dropFirst()), file: e.file)
                )
            }
        }
        let dirs = groups.keys.sorted().map { dir -> TreeNode in
            let dirPath = joinDir(parent, dir)
            return TreeNode(id: dirID(dirPath), name: dir, file: nil, children: level(parent: dirPath, entries: groups[dir]!))
        }
        return dirs + leaves.sorted { $0.name < $1.name }
    }

    /// 既定の展開集合。dir 総数 ≤ 閾値なら全 dir、超過ならルート(第一階層)のみ。
    public static func defaultExpanded(_ nodes: [TreeNode]) -> Set<String> {
        let all = allDirIDs(nodes)
        if all.count <= autoExpandDirThreshold { return all }
        return Set(nodes.map(\.id))
    }

    /// TREE に表示すべき展開集合を状態から合成する(UI 非依存・純関数)。
    /// 個別ポリシー(`defaultExpanded` / `ancestors`)をまとめ、UI 側の結線を薄く保つ:
    /// - 基底: `defaultExpanded`(dir 総数 ≤ 閾値で全展開・超過は第一階層のみ)
    /// - 検索中: `nodes` は既にフィルタ後ツリー(全 leaf がヒット)なので**全 dir を展開**して
    ///   ヒットを可視化する(クエリ消去で基底へ復帰)。leaf ごとに `ancestors` を引く O(L×N) DFS は
    ///   `allDirIDs` の O(N) と等価結果かつ高速なので後者を使う(M7 review #7)
    /// - 選択中 leaf があれば、その祖先も展開(閉じた dir 内の選択を親 dir 自動展開で可視化)
    public static func expansionSet(
        for nodes: [TreeNode],
        searching: Bool,
        selectedLeafPath: String?
    ) -> Set<String> {
        var set = defaultExpanded(nodes)
        if searching {
            set.formUnion(allDirIDs(nodes))
        }
        if let selectedLeafPath {
            set.formUnion(ancestors(ofLeaf: selectedLeafPath, in: nodes))
        }
        return set
    }

    /// leaf を可視化するために展開すべき祖先 dir の id 集合(ルートまで再帰)。
    public static func ancestors(ofLeaf leafPath: String, in nodes: [TreeNode]) -> Set<String> {
        var result = Set<String>()
        _ = findLeafPath(leafPath, in: nodes, accumulated: [], into: &result)
        return result
    }

    /// dir 自身を可視化するために展開すべき祖先 dir の id 集合(自身は含まない・ルートまで再帰)。
    /// `.dir` 選択を見せる際の祖先保護(`recomputeTreeExpansion`)で使う(#33 round-2 #2)。
    public static func ancestors(ofDir dirID: String, in nodes: [TreeNode]) -> Set<String> {
        var result = Set<String>()
        _ = findDirPath(dirID, in: nodes, accumulated: [], into: &result)
        return result
    }

    /// 指定 dir id が現ツリーに存在するか(`.dir` 選択の stale 検出に使う — #33 round-2 #1)。
    public static func containsDir(_ dirID: String, in nodes: [TreeNode]) -> Bool {
        for node in nodes {
            if !node.isLeaf {
                if node.id == dirID { return true }
                if let children = node.children, containsDir(dirID, in: children) { return true }
            }
        }
        return false
    }

    /// 全 leaf を visit 順に平坦化(OutlineGroup が全展開で描画する TREE の j/k 用)。
    public static func allLeaves(_ nodes: [TreeNode]) -> [HTMLFile] {
        nodes.flatMap { node -> [HTMLFile] in
            if let file = node.file { return [file] }
            return allLeaves(node.children ?? [])
        }
    }

    /// 展開済み dir 配下の leaf を visit 順に平坦化(j/k の可視 leaf 列)。
    public static func visibleLeaves(_ nodes: [TreeNode], expanded: Set<String>) -> [HTMLFile] {
        var out: [HTMLFile] = []
        for node in nodes {
            if let file = node.file {
                out.append(file)
            } else if let children = node.children, expanded.contains(node.id) {
                out.append(contentsOf: visibleLeaves(children, expanded: expanded))
            }
        }
        return out
    }

    /// 展開状態に応じた可視行列(dir + leaf)。`#32` の方向キー移動・Enter 展開のために
    /// dir 行も同列に扱う。dir は折りたたみ中でも**自分自身は可視**(配下のみ非表示)で、
    /// これが「dir を選んで Enter で展開する」操作経路を成立させる。
    public static func visibleRows(_ nodes: [TreeNode], expanded: Set<String>) -> [TreeRow] {
        var out: [TreeRow] = []
        walk(nodes, expanded: expanded, into: &out)
        return out
    }

    private static func walk(
        _ nodes: [TreeNode],
        expanded: Set<String>,
        into out: inout [TreeRow]
    ) {
        for node in nodes {
            if let file = node.file {
                out.append(.file(file))
            } else {
                out.append(.dir(id: node.id))
                if let children = node.children, expanded.contains(node.id) {
                    walk(children, expanded: expanded, into: &out)
                }
            }
        }
    }

    // MARK: - helpers

    /// ツリー内の全 dir ノード id(`userCollapsedDirs` の prune 等で使う)。
    public static func allDirIDs(_ nodes: [TreeNode]) -> Set<String> {
        var ids = Set<String>()
        for node in nodes where node.children != nil {
            ids.insert(node.id)
            ids.formUnion(allDirIDs(node.children!))
        }
        return ids
    }

    @discardableResult
    private static func findLeafPath(
        _ leafPath: String,
        in nodes: [TreeNode],
        accumulated: [String],
        into result: inout Set<String>
    ) -> Bool {
        for node in nodes {
            if node.isLeaf {
                if node.id == leafPath { result.formUnion(accumulated); return true }
            } else if let children = node.children {
                if findLeafPath(leafPath, in: children, accumulated: accumulated + [node.id], into: &result) {
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    private static func findDirPath(
        _ dirID: String,
        in nodes: [TreeNode],
        accumulated: [String],
        into result: inout Set<String>
    ) -> Bool {
        for node in nodes where !node.isLeaf {
            if node.id == dirID { result.formUnion(accumulated); return true }
            if let children = node.children,
                findDirPath(dirID, in: children, accumulated: accumulated + [node.id], into: &result) {
                return true
            }
        }
        return false
    }
}
