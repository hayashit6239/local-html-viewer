import AppKit
import Foundation
import HTMLViewerCore
import Observation

/// UI を駆動する中心状態。Core の判断ロジックを束ねるオーケストレーション層(Humble Object)。
/// 走査・除外・ソート・永続化の実体は HTMLViewerCore 側にあり、ここはその結線に徹する。
///
/// **隔離**: `@MainActor` を明示する。Package の `.defaultIsolation(MainActor.self)` で
/// HTMLViewer ターゲットは既定 MainActor だが、Swift 6 strict concurrency / SDK 更新 /
/// future package 設定変更で前提が崩れたとき、`AppState` 自体に注記が無いと `watchTask` /
/// `debounceTask` の `for await` / closure 経由で隔離が暗黙にずれる(`selectedFile` /
/// `pendingWatchPaths` 等への共有可変アクセスで data race の温床)。明示注記で自衛する。
@MainActor
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

    // MARK: - M7: 検索 / タブ / キーボード

    public enum SidebarTab: Sendable { case recent, tree }
    /// 表示タブ(RECENT / TREE)。TREE に切り替えたら選択を可視化する展開を取り直す。
    var selectedTab: SidebarTab = .recent {
        didSet { if selectedTab == .tree { recomputeTreeExpansion() } }
    }
    /// 検索フィールドが first responder か(`@FocusState` のミラー。キーモニタの透過判定に使う)。
    var isSearchFocused = false
    /// `/` キーで検索フィールドへフォーカスを要求(インクリメントで発火。SidebarView が監視)。
    private(set) var focusSearchRequest = 0
    func requestSearchFocus() { focusSearchRequest &+= 1 }
    /// インクリメンタル検索クエリ。変化のたびに展開を取り直し、選択を残存ヒットで維持・消えたら先頭へ。
    /// 展開を先に更新するのは、reconcile の入力 `visibleLeaves` が `expandedDirs` に依存するため。
    var searchText = "" {
        didSet {
            recomputeTreeExpansion()
            selectedFile = SelectionLogic.reconcile(previous: selectedFile, in: visibleLeaves)
        }
    }

    /// TREE タブで展開中の dir id 集合(`DisclosureGroup` の isExpanded バインディングの源)。
    /// 既定展開ポリシー・検索ヒット/選択の親 dir 自動展開・ユーザー手動トグルを束ねる(issue #18 決定)。
    private(set) var expandedDirs: Set<String> = []

    /// 現在の状態(検索中か / 選択中 leaf)から TREE 展開集合を `TreeBuilder` で取り直す。
    private func recomputeTreeExpansion() {
        expandedDirs = TreeBuilder.expansionSet(
            for: tree,
            searching: !searchText.isEmpty,
            selectedLeafPath: selectedFile?.path
        )
    }

    /// dir が展開中か(`SidebarView` の `DisclosureGroup` バインディング用)。
    func isExpanded(_ dirID: String) -> Bool { expandedDirs.contains(dirID) }

    /// dir の展開/折りたたみをユーザー操作で切り替える。
    func setExpanded(_ dirID: String, _ expanded: Bool) {
        if expanded { expandedDirs.insert(dirID) } else { expandedDirs.remove(dirID) }
    }

    private let search: SearchProvider = FilenameSearchProvider()

    /// 検索適用後のファイル(両タブ共通の入力)。
    private var filteredFiles: [HTMLFile] {
        search.filter(allFiles, query: searchText)
    }

    /// RECENT タブ用: 検索適用後を mtime 降順 + 先頭に EXTERNAL ピンを合成(既出なら omit = 二重解消)。
    /// 検索(M7)と EXTERNAL ピン(M5)の合成: フィルタ → ソート → ピン先頭合成。
    var recentFiles: [HTMLFile] {
        let sorted = RecentSorter.sortedByModificationDateDescending(filteredFiles)
        return ExternalOpenPolicy.compose(recent: sorted, pinned: pinnedExternal)
    }

    /// TREE タブ用: 検索適用後の階層。
    var tree: [TreeNode] {
        TreeBuilder.build(filteredFiles)
    }

    /// 現タブの可視 leaf 列(j/k の移動対象)。TREE は展開中 dir 配下のみ(折りたたみ dir は飛ばす)。
    private var visibleLeaves: [HTMLFile] {
        switch selectedTab {
        case .recent: return recentFiles
        case .tree: return TreeBuilder.visibleLeaves(tree, expanded: expandedDirs)
        }
    }

    /// j(down)/k(up)で選択を移動し即プレビュー。
    func moveSelection(_ direction: SelectionDirection) {
        selectedFile = SelectionLogic.next(after: selectedFile, in: visibleLeaves, direction: direction)
    }

    /// 選択中ファイルを Finder で表示(未選択なら no-op)。
    func revealSelectedInFinder() {
        guard let file = selectedFile else { return }
        revealInFinder(file)
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
        rebuildWatcher()  // 監視対象に新ルートを反映
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0.path == url.path }
        saveFolders()
        rescan()
        rebuildWatcher()
    }

    /// 表示中ファイルを再読込する(loadFileURL 再実行。reload() は使わない — docs/03 §2-7)。
    /// 未選択なら no-op(M7 決定)。
    func reloadPreview() {
        guard selectedFile != nil else { return }
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

    /// パスを canonical 正規化(M5/M6 共通の `PathNormalizer` に委譲)。
    private func canonicalPath(of path: String) -> String {
        PathNormalizer.canonical(path)
    }

    // MARK: - ファイル監視(M6)

    private var watcher: FileWatcher?
    private var watchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pendingWatchPaths: [String] = []

    /// 監視を開始(起動時に呼ぶ)。登録フォルダ群を FSEvents で監視する。
    func startWatching() {
        rebuildWatcher()
    }

    /// 登録フォルダの変更時に監視ストリームを作り直す(FSEvents はパス追加 API を持たない)。
    /// 到達不能なルート(外付け unmount 等)は除外(fail-silent)。
    private func rebuildWatcher() {
        watchTask?.cancel()
        watcher?.stop()
        let reachable = folders.filter { isReachable($0) }
        guard !reachable.isEmpty else { watcher = nil; return }
        let w = FileWatcher(roots: reachable)
        watcher = w
        w.start()
        watchTask = Task { [weak self] in
            for await batch in w.events {
                self?.scheduleWatchApply(batch)
            }
        }
    }

    /// 受信バッチを 300ms debounce(= Claude の連続保存の典型間隔)で集約し 1 回適用する。
    /// 結線は「for await → debounce → WatchEventPolicy 判定 → rescan/reload」の薄い 4 段のみ
    /// (debounce 意味論は Core `Debounce.coalesce` で、判定は `WatchEventPolicy` でテスト済み)。
    private func scheduleWatchApply(_ batch: [String]) {
        pendingWatchPaths.append(contentsOf: batch)
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let paths = self.pendingWatchPaths
            self.pendingWatchPaths = []
            self.applyWatch(paths)
        }
    }

    private func applyWatch(_ paths: [String]) {
        let normalized = paths.map { PathNormalizer.canonical($0) }
        let displayed = selectedFile.map { PathNormalizer.canonical($0.path) }
        switch WatchEventPolicy.decide(paths: normalized, displayedPath: displayed) {
        case .ignore:
            break
        case .reloadDisplayed:
            // 表示中が消えていたら reload(失敗)でなく rescan で一覧更新 + 選択移動(M4 削除時挙動)
            if let d = displayed, FileManager.default.fileExists(atPath: d) {
                reloadPreview()
            } else {
                rescan()
            }
        case .rescan:
            rescan()
        }
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
            // 走査でツリー構造が変わったので展開を取り直す(既定ポリシー + 選択の親 dir 自動展開)。
            recomputeTreeExpansion()
        }
    }
}
