import Foundation

/// 走査で発見された 1 つの HTML ファイル。
///
/// `Identifiable` の `id == path` に合わせて `Hashable` / `Equatable` も **path のみ**で実装する。
/// 自動合成の全フィールド比較だと、同 path / 異 `isExternal` の 2 つのインスタンス
/// (例: EXTERNAL ピンと内部走査結果の同一ファイル)が異値扱いとなり、SwiftUI の
/// `List(selection:)` 等で selection 同期がずれる。`id` ベースの diff と `Hashable`
/// 照合を整合させるため明示的に path のみで比較する。
public struct HTMLFile: Identifiable, Hashable, Sendable {
    public var id: String { path }

    /// 絶対パス
    public let path: String
    /// ファイル名(拡張子含む)
    public let name: String
    /// 最終更新日時
    public let mtime: Date
    /// 所属する登録ルートフォルダの絶対パス
    public let rootPath: String
    /// ルートからの相対パス
    public let relativePath: String
    /// 登録フォルダ外を odoc で受信したファイル(M5: EXTERNAL ピン)。
    /// true のとき WebView の read-access はファイル単体スコープ、UI は EXTERNAL バッジ表示。
    public let isExternal: Bool

    public init(
        path: String,
        name: String,
        mtime: Date,
        rootPath: String,
        relativePath: String,
        isExternal: Bool = false
    ) {
        self.path = path
        self.name = name
        self.mtime = mtime
        self.rootPath = rootPath
        self.relativePath = relativePath
        self.isExternal = isExternal
    }

    public static func == (lhs: HTMLFile, rhs: HTMLFile) -> Bool {
        lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

/// TREE タブの階層ノード(M7)。`id` は絶対パス(dir は dir の絶対パス / leaf は file.path)で、
/// 検索でツリー入力が変わっても OutlineGroup の差分更新・展開状態が崩れないようにする。
public struct TreeNode: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// leaf のとき対応ファイル。dir のとき nil。
    public let file: HTMLFile?
    /// nil = leaf。非 nil(空配列含む)= dir。
    public let children: [TreeNode]?

    public var isLeaf: Bool { children == nil }

    public init(id: String, name: String, file: HTMLFile?, children: [TreeNode]?) {
        self.id = id
        self.name = name
        self.file = file
        self.children = children
    }
}

/// サイドバーの選択対象(#32)。
/// TREE タブで「方向キーで dir も file も舐める」+「Enter で dir 展開トグル」を表現するため、
/// 従来の `HTMLFile?`(file のみ)から拡張する。`AppState.selectedFile` は本型から `.file` を
/// 抽出する computed property として後方互換を維持する。
public enum SidebarSelection: Hashable, Sendable {
    case file(HTMLFile)
    /// `id` は `TreeNode.id`(dir パス + 末尾 `/`)。`expandedDirs` と同じ id 空間。
    case dir(id: String)
}

/// TREE タブの可視行(#32)。`visibleRows` が展開済み dir 配下を depth-first に平坦化した結果で、
/// 方向キーでの行移動(file と dir を同列に舐める)に使う。
public enum TreeRow: Hashable, Sendable {
    case file(HTMLFile)
    case dir(id: String, depth: Int)
}
