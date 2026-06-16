import Foundation

/// 走査の安全弁: 対象拡張子・除外ディレクトリ・上限の判定。
public enum IgnoreRules {
    /// 走査するファイル数の上限(これを超えたら打ち切る)。
    public static let maxFiles = 5000

    /// 走査時に丸ごとスキップするディレクトリ名(隠しディレクトリは別途 `shouldSkipDirectory` で処理)。
    public static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", "__pycache__", ".venv", "venv",
        ".next", ".cache", "dist", "build", ".idea", ".vscode",
    ]

    /// `.html` / `.htm`(大文字小文字無視)を HTML ファイルとみなす。
    public static func isHTMLFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".html") || lower.hasSuffix(".htm")
    }

    /// 除外ディレクトリ、または隠しディレクトリ(`.` 始まり)ならスキップ。
    /// 比較は大文字小文字を無視する(HTML 拡張子判定と対称。`NODE_MODULES` や
    /// case-sensitive フォーマットのボリュームでも除外漏れしないようにする)。
    public static func shouldSkipDirectory(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        return ignoredDirectories.contains(name.lowercased())
    }
}
