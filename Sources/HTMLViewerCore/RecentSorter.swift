import Foundation

/// RECENT タブ用の並べ替え: 更新日時の新しい順。
public enum RecentSorter {
    /// mtime 降順に並べる。同値はパス昇順で安定させる(描画のちらつき防止)。
    public static func sortedByModificationDateDescending(_ files: [HTMLFile]) -> [HTMLFile] {
        files.sorted { lhs, rhs in
            if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
            return lhs.path < rhs.path
        }
    }
}
