import Foundation

/// 走査で発見された 1 つの HTML ファイル。
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

    public init(path: String, name: String, mtime: Date, rootPath: String, relativePath: String) {
        self.path = path
        self.name = name
        self.mtime = mtime
        self.rootPath = rootPath
        self.relativePath = relativePath
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
