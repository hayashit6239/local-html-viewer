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

        for root in roots {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
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

                if values?.isDirectory == true {
                    if IgnoreRules.shouldSkipDirectory(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard IgnoreRules.isHTMLFile(url.lastPathComponent) else { continue }

                if files.count >= maxFiles {
                    return ScanResult(files: files, truncated: true)
                }

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

        return ScanResult(files: files, truncated: false)
    }

    private static func relativePath(of path: String, under root: String) -> String {
        guard path.hasPrefix(root) else { return path }
        var rel = String(path.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }
}
