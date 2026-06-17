import Foundation

/// 登録ルートの走査状態の診断結果。
public enum RootStatus: Sendable, Equatable {
    /// HTML が 1 件以上見つかった。
    case ok
    /// 到達可能・0 件・TCC 保護領域の外(本当に空のフォルダ)。
    case empty
    /// 到達可能・0 件・TCC 保護領域(`~/Documents` 等)配下。
    /// ad-hoc 再署名で許可がサイレント失効した疑いがあり、再許可の案内を出す。
    case tccLikelyBlocked
    /// 削除 / 移動 / 外付け unmount などで到達不能。
    case unreachable
}

/// 登録ルートの走査状態を UI 非依存で判定する純ロジック。
///
/// 再署名直後の TCC サイレント失効は「登録先はディスク上に在るのに走査 0 件」という
/// *予見可能・検知可能* な失敗。人間が `tccutil reset` を思い出す運用(L1)に委ねず、
/// アプリが検知して再許可を案内する(L2/L3)ための判定をここに置く。
public enum RootDiagnostics {
    /// macOS の TCC 保護下にある代表的なホーム直下ディレクトリ名。
    /// これらの配下は ad-hoc 再署名でアクセス許可がサイレント失効しうる。
    public static let protectedHomeSubdirectories: Set<String> = [
        "Documents", "Desktop", "Downloads",
    ]

    /// ルートの走査状態を判定する。
    /// - Parameters:
    ///   - isReachable: ディレクトリとして到達可能か(`fileExists` 等で判定済みの値)。
    ///   - fileCount: そのルート由来で見つかった HTML 件数。
    ///   - isUnderProtectedLocation: TCC 保護領域配下か。
    public static func classify(
        isReachable: Bool,
        fileCount: Int,
        isUnderProtectedLocation: Bool
    ) -> RootStatus {
        guard isReachable else { return .unreachable }
        if fileCount > 0 { return .ok }
        return isUnderProtectedLocation ? .tccLikelyBlocked : .empty
    }

    /// `path` が `home` 配下の TCC 保護ディレクトリ(Documents / Desktop / Downloads)
    /// 配下かを判定する。例: `~/Documents` と `~/Documents/sub` は true、`~/Projects` は false。
    public static func isUnderProtectedLocation(path: String, home: String) -> Bool {
        let homeBase = home.hasSuffix("/") ? String(home.dropLast()) : home
        for name in protectedHomeSubdirectories {
            let base = "\(homeBase)/\(name)"
            if path == base || path.hasPrefix(base + "/") { return true }
        }
        return false
    }
}
