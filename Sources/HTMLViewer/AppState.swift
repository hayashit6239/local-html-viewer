import AppKit
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
    /// 選択中ファイル。WebView でプレビューする。
    var selectedFile: HTMLFile?
    /// プレビューの明示リロード要求(loadFileURL 再実行を発火させる単調増加トークン)。
    private(set) var reloadToken = 0
    /// 登録フォルダ外を受信した EXTERNAL ピン(単一・セッション限り・非永続)。RECENT 先頭に合成する。
    private(set) var pinnedExternal: HTMLFile?
    /// 読めない(canonicalPath nil 等)受信パス。サイドバーの「読めない」表示に使う。
    private(set) var unreadableExternalPath: String?

    /// RECENT タブ用: mtime 降順 + 先頭に EXTERNAL ピンを合成(既出なら omit = 二重解消)。
    var recentFiles: [HTMLFile] {
        let sorted = RecentSorter.sortedByModificationDateDescending(allFiles)
        return ExternalOpenPolicy.compose(recent: sorted, pinned: pinnedExternal)
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

    /// 表示中ファイルを再読込する(loadFileURL 再実行。reload() は使わない — docs/03 §2-7)。
    func reloadPreview() {
        reloadToken &+= 1
    }

    /// Finder で選択表示する。
    func revealInFinder(_ file: HTMLFile) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    /// 既定ブラウザで開く(LSHandlerRank=Alternate のため .html の既定ハンドラはブラウザ)。
    func openInBrowser(_ file: HTMLFile) {
        NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
    }

    /// odoc 受信 URL を内外判定し、外部=EXTERNAL ピン / 内部=通常選択する(M5)。
    /// 複数 URL は「外部の最後 1 件をピン + 内部の最後 1 件を選択」(併存)。
    /// 同一 external の再受信は reload(`reloadToken` 強制インクリメント)でピン churn なし。
    /// パス比較はすべて `.canonicalPathKey` 正規化後で揃える(`ExternalOpenPolicy` の不変条件)。
    func handleOpenedURLs(_ urls: [URL]) {
        let fm = FileManager.default
        let rootsCanonical = folders.map { canonicalPath(of: $0.path) }

        var lastExternal: (path: String, mtime: Date)?
        var lastInternal: HTMLFile?
        var unreadable: String?

        for url in urls where IgnoreRules.isHTMLFile(url.lastPathComponent) {
            guard let cpath = try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath else {
                unreadable = url.path  // canonicalPath nil = 読めない(ピンしない)
                continue
            }
            guard fm.fileExists(atPath: cpath) else {
                // 削除 → ピン落とし & 選択クリア(ピン中なら)。
                if cpath == pinnedExternal?.path {
                    pinnedExternal = nil
                    if selectedFile?.path == cpath { selectedFile = nil }
                }
                // ピン中でない死パスでも silent drop しない(🟡-2): 「読めない」表示で UI 無反応を回避。
                unreadable = url.path
                continue
            }
            if ExternalOpenPolicy.isInside(cpath, registeredRoots: rootsCanonical) {
                if let match = allFiles.first(where: { $0.path == cpath }) { lastInternal = match }
            } else {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
                lastExternal = (cpath, mtime)
            }
        }

        if let ext = lastExternal {
            if ext.path != pinnedExternal?.path {
                pinnedExternal = ExternalOpenPolicy.makeExternalFile(path: ext.path, mtime: ext.mtime)
            }
            reloadToken &+= 1  // 新規ピンも同一再受信も reload(再生成内容を反映)
            unreadableExternalPath = nil
        }
        if let inter = lastInternal {
            selectedFile = inter
            unreadableExternalPath = nil
        } else if lastExternal != nil {
            selectedFile = pinnedExternal  // 内部が無ければ外部ピンを選択
        }
        if lastExternal == nil, lastInternal == nil, let u = unreadable {
            unreadableExternalPath = u  // 読めない受信のみ
        }
    }

    /// パスを `.canonicalPathKey` で正規化(`/var`→`/private/var`)。取得不能時は元のパス。
    private func canonicalPath(of path: String) -> String {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? path
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

            // EXTERNAL ピンが新規登録フォルダ等で「内部化」されたら、ピンを落として
            // 内部版に張り替える(declarative 二重解消の一貫性を確保 — 🟡-1):
            // - WebView の read-access スコープが単体 → ルートに切り替わる
            // - List(selection:) の Hashable 照合が path のみ(HTMLFile == 修正済み)で一致
            if let ext = pinnedExternal,
                let internalVersion = result.files.first(where: { $0.path == ext.path }) {
                pinnedExternal = nil
                if selectedFile?.path == ext.path {
                    selectedFile = internalVersion
                }
            }

            // 選択中ファイルが消えていたら解除し、未選択なら最新を選ぶ。
            // EXTERNAL ピンは走査結果に出ないため対象外(再走査で選択を奪わない)。
            if let sel = selectedFile, !sel.isExternal,
                !result.files.contains(where: { $0.path == sel.path }) {
                selectedFile = nil
            }
            if selectedFile == nil {
                selectedFile = recentFiles.first
            }
        }
    }
}
