import Foundation

/// パスの canonical 正規化(`/var`→`/private/var` 等)。M5/M6 で同じ不変条件を二度書かないための共通ヘルパ。
/// 取得不能(削除/読めない)時は元のパスを返す。FS 問い合わせを伴うため Core の I/O ヘルパとして置く。
public enum PathNormalizer {
    public static func canonical(_ path: String) -> String {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? path
    }
}
