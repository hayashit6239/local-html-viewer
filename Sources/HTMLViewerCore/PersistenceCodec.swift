import Foundation

/// 登録フォルダのパス配列を永続化用に encode/decode する(保存先 UserDefaults は呼び出し側が注入)。
public enum PersistenceCodec {
    /// 重複を最初の出現だけ残して JSON データにする。
    public static func encodeFolderPaths(_ paths: [String]) -> Data {
        let deduped = dedupe(paths)
        return (try? JSONEncoder().encode(deduped)) ?? Data("[]".utf8)
    }

    /// JSON データをパス配列に戻す。nil / 壊れたデータは空配列。
    public static func decodeFolderPaths(_ data: Data?) -> [String] {
        guard let data, let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return dedupe(paths)
    }

    private static func dedupe(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
