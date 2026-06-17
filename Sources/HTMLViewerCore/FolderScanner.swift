import Foundation

/// 走査結果。`truncated` は maxFiles に達して打ち切ったかどうか。
public struct ScanResult: Sendable, Equatable {
    public let files: [HTMLFile]
    public let truncated: Bool

    public init(files: [HTMLFile], truncated: Bool) {
        self.files = files
        self.truncated = truncated
    }
}

/// 登録ルート群を再帰走査して HTML ファイルを集める(UI 非依存・nonisolated)。
public enum FolderScanner {
    /// 各ルートを走査し、ignore ディレクトリ・隠し・非 HTML を除外して `HTMLFile` を返す。
    /// 並べ替えは行わない(呼び出し側で `RecentSorter` 等を適用する)。
    public static func scan(roots: [URL], maxFiles: Int = IgnoreRules.maxFiles) -> ScanResult {
        let fm = FileManager.default
        var files: [HTMLFile] = []
        var seenPaths = Set<String>()

        for root in roots {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
            // .skipsHiddenFiles は隠しディレクトリだけでなく隠しファイル(`.report.html` 等)も
            // 除外する。本アプリの対象は Claude 生成の成果物であり dotfile は成果物ではないため、
            // この「隠しファイル・ディレクトリ双方を除外」は意図的な仕様(契約は FolderScannerTests で固定)。
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            // enumerator は symlink 解決済みパス(/var → /private/var)を返すため、rootPath も
            // FS 正規パス(canonicalPath)に揃えて relativePath / allowingReadAccessTo の prefix 一致を保証する。
            // (resolvingSymlinksInPath は環境により /var を解決しないため canonicalPathKey を使う)
            let rootPath = (try? root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? root.path

            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))

                // symlink は追従しない(サイクルによる無限走査・symlink 経由の ignore 回避を防ぐ)。
                // FileManager の既定でも追従しないが、版依存の挙動に頼らず明示的にスキップする。
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }

                if values?.isDirectory == true {
                    if IgnoreRules.shouldSkipDirectory(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard IgnoreRules.isHTMLFile(url.lastPathComponent) else { continue }

                // クロスフォルダ / 入れ子登録(A と A/sub)の重複を絶対パスで除去する
                guard seenPaths.insert(url.path).inserted else { continue }

                files.append(
                    HTMLFile(
                        path: url.path,
                        name: url.lastPathComponent,
                        mtime: values?.contentModificationDate ?? .distantPast,
                        rootPath: rootPath,
                        relativePath: relativePath(of: url.path, under: rootPath)
                    )
                )
            }
        }

        // 上限超過時は mtime 降順で上位 N を保持し、打ち切りを決定論的にする。
        // (走査順の先着打ち切りは非決定的で、新しい=探しているファイルが落ちうるため)
        if files.count > maxFiles {
            let kept = Array(RecentSorter.sortedByModificationDateDescending(files).prefix(maxFiles))
            return ScanResult(files: kept, truncated: true)
        }
        return ScanResult(files: files, truncated: false)
    }

    private static func relativePath(of path: String, under root: String) -> String {
        guard path.hasPrefix(root) else { return path }
        var rel = String(path.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }
}
