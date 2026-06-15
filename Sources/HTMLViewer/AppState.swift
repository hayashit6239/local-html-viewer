import Foundation
import HTMLViewerCore
import Observation

/// UI を駆動する中心状態。Core の判断ロジックを束ねるオーケストレーション層(Humble Object)。
/// 走査・除外・ソート・永続化の実体は HTMLViewerCore 側にあり、ここはその結線に徹する。
@Observable
final class AppState {
    private let defaults: UserDefaults
    private static let foldersKey = "registeredFolders.v1"

    /// 登録フォルダ(永続化対象)。
    private(set) var folders: [URL] = []
    /// 直近の走査結果(未ソート)。
    private(set) var allFiles: [HTMLFile] = []
    /// MAX_FILES 到達で打ち切ったか。
    private(set) var scanTruncated = false
    /// 選択中ファイル(プレビューは M4 で実装)。
    var selectedFile: HTMLFile?

    /// RECENT タブ用: mtime 降順。
    var recentFiles: [HTMLFile] {
        RecentSorter.sortedByModificationDateDescending(allFiles)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFolders()
    }

    private func loadFolders() {
        let paths = PersistenceCodec.decodeFolderPaths(defaults.data(forKey: Self.foldersKey))
        folders = paths.map { URL(fileURLWithPath: $0) }
    }

    private func saveFolders() {
        defaults.set(PersistenceCodec.encodeFolderPaths(folders.map(\.path)), forKey: Self.foldersKey)
    }

    func addFolder(_ url: URL) {
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        folders.append(url)
        saveFolders()
        rescan()
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0.path == url.path }
        saveFolders()
        rescan()
    }

    /// 登録フォルダが現在到達可能か(削除/移動/外付け unmount の検出)。
    /// 到達不能でも登録は維持し(一時的な unmount で登録を失わない)、UI に stale 表示する。
    func isReachable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 登録フォルダ群を再走査してリストを差し替える。重い走査は detached で UI を止めない。
    func rescan() {
        let roots = folders
        Task {
            let result = await Task.detached { FolderScanner.scan(roots: roots) }.value
            allFiles = result.files
            scanTruncated = result.truncated

            // 選択中ファイルが消えていたら解除し、未選択なら最新を選ぶ
            if let sel = selectedFile, !result.files.contains(where: { $0.path == sel.path }) {
                selectedFile = nil
            }
            if selectedFile == nil {
                selectedFile = recentFiles.first
            }
        }
    }
}
