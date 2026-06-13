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
