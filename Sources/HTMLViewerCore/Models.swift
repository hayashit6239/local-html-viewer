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
}
