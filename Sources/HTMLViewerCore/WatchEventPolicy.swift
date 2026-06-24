import Foundation

/// ファイル監視イベントへの応答を決める純ロジック(UI 非依存)。
/// **入力契約**: `paths` / `displayedPath` は呼び出し側(AppState)が canonical 正規化済みで渡す
/// (FSEvents は `/private/var/...` を返すため、正規化を経ないと表示中ファイル一致判定が外れる)。
public enum WatchDecision: Sendable, Equatable {
    /// ignore 配下・中間物のみ → 何もしない(churn 暴走防止)。
    case ignore
    /// 表示中ファイルが変更された → プレビュー再読込。
    case reloadDisplayed
    /// 新規/削除/その他 → 再走査。
    case rescan
}

public enum WatchEventPolicy {
    public static func decide(
        paths: [String],
        displayedPath: String?,
        mustScanSubDirs: Bool = false
    ) -> WatchDecision {
        if mustScanSubDirs { return .rescan }
        let relevant = paths.filter(isRelevant)
        if relevant.isEmpty { return .ignore }
        if let displayedPath, relevant.contains(displayedPath) { return .reloadDisplayed }
        return .rescan
    }

    /// 隠しファイル(`.` 始まり)・`.tmp`(アトミック保存の中間物)・ignore ディレクトリ配下は無視。
    private static func isRelevant(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(".") || name.hasSuffix(".tmp") { return false }
        let components = (path as NSString).pathComponents
        if components.contains(where: { IgnoreRules.shouldSkipDirectory($0) }) { return false }
        return true
    }
}
