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

    /// 登録ルートの走査状態を診断する。判定ロジックは `RootDiagnostics`(Core)に委譲し、
    /// ここは FS 問い合わせ(到達可能性・件数・保護領域)の結線に徹する。
    /// 「到達可能 かつ そのフォルダ配下 0 件 かつ TCC 保護領域」を `tccLikelyBlocked` として
    /// 検知し、再署名による TCC サイレント失効をサイドバーで再許可案内できるようにする。
    func status(of url: URL) -> RootStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return RootDiagnostics.classify(
            isReachable: isReachable(url),
            fileCount: fileCount(under: url),
            isUnderProtectedLocation: RootDiagnostics.isUnderProtectedLocation(path: url.path, home: home)
        )
    }

    /// `url` 配下に物理的に存在する HTML 件数。入れ子登録(A と A/sub)でも親に件数を
    /// 奪われないよう rootPath ではなく絶対パスの prefix 一致で数える。走査時の正規化で
    /// `/var`→`/private/var` が入りうるため、登録パスと canonicalPath の両方で判定する。
    private func fileCount(under url: URL) -> Int {
        var prefixes = [url.path]
        if let canonical = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath {
            prefixes.append(canonical)
        }
        let normalized = prefixes.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return allFiles.filter { file in
            normalized.contains { file.path.hasPrefix($0) }
        }.count
    }

    private var scanGeneration = 0

    /// 登録フォルダ群を再走査してリストを差し替える。重い走査は detached で UI を止めない。
    func rescan() {
        let roots = folders
        scanGeneration &+= 1
        let generation = scanGeneration
        Task {
            let result = await Task.detached { FolderScanner.scan(roots: roots) }.value
            // 連打で複数の走査が走った場合、最後に開始した rescan の結果だけを適用する
            // (先発の走査が後から完了して古い状態へ巻き戻すのを防ぐ)。AppState は MainActor 隔離。
            guard generation == scanGeneration else { return }
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
