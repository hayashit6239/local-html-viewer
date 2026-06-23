import Foundation

/// オープンイベント(odoc / `application(_:open:)`)で受け取った URL 群を、
/// 表示対象として受理できる `.html`/`.htm` かつ実在するパスだけに絞る純ロジック(UI 非依存)。
/// 存在チェックは `fileExists` を注入してテスト可能にする(実行時は `FileManager` を渡す)。
public enum OpenEventPolicy {
    public static func acceptableHTMLPaths(
        from urls: [URL],
        fileExists: (String) -> Bool
    ) -> [String] {
        urls.compactMap { url in
            let path = url.path
            // 拡張子判定は M3 の case-insensitive 判定を再利用(DRY・非対称防止)
            guard IgnoreRules.isHTMLFile(url.lastPathComponent), fileExists(path) else { return nil }
            return path
        }
    }
}
