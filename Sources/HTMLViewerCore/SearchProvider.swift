import Foundation

/// ファイル一覧の検索抽象(D8 の布石)。
/// シグネチャは将来 D8(FTS5 / embeddings・本文/意味検索・スコア/ヒット情報)で**再設計する前提**。
/// M7 はファイル名フィルタに留め、将来形まで設計しない(破壊的変更は D8 の責任)。
public protocol SearchProvider: Sendable {
    func filter(_ files: [HTMLFile], query: String) -> [HTMLFile]
}

/// 既定実装: ファイル名の **NFC 正規化後 case-insensitive 部分一致**。空クエリは全件・順序保持。
/// NFC 正規化は macOS の NFD ファイル名(濁点分解等)での取りこぼしを防ぐ(M3 の case-insensitive と並列)。
public struct FilenameSearchProvider: SearchProvider {
    public init() {}

    public func filter(_ files: [HTMLFile], query: String) -> [HTMLFile] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return files }
        return files.filter { normalize($0.name).contains(needle) }
    }

    private func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }
}
