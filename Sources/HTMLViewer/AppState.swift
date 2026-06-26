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
    /// サイドバーの選択(#32 で `HTMLFile?` から拡張)。TREE で dir を選択できるようになり、
    /// Enter キー(`activateSelection`)で展開トグルする経路が成立する。プレビュー(`selectedFile`)は
    /// `.file` のときのみ追従。`.dir` 選択中は直前のファイルプレビューが残る(ちらつき回避)。
    var selection: SidebarSelection?

    /// プレビュー対象ファイル(後方互換 computed)。`selection` から `.file` を抽出する。
    /// 既存の `selectedFile = X` 形式の代入は setter で `selection = .file(X)` に橋渡し。
    /// `.dir` 選択中は nil ではなく直前の `.file` を保つために、setter のみで `selection` を上書きする
    /// (getter は常に `selection` の `.file` のみを返す = `.dir` 選択中は nil)。
    var selectedFile: HTMLFile? {
        get {
            if case .file(let f) = selection { return f }
            return nil
        }
        set {
            selection = newValue.map { .file($0) }
        }
    }
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
    /// 展開を 2 回取り直すのは: ①reconcile の入力 `visibleLeaves` が `expandedDirs` に依存するため
    /// 先に検索ヒットを展開し、②reconcile が選び直した新選択の祖先も展開して可視化するため(M7 review #3)。
    var searchText = "" {
        didSet {
            recomputeTreeExpansion()
            // EXTERNAL ピンを選択中は検索で選択をすり替えない。ピンは検索リストに出ないため
            // reconcile が先頭へ飛ばし、見ていた外部プレビューが無関係ファイルへスワップするのを防ぐ(M7 review #3)。
            if case .file(let f) = selection, f.isExternal {
                // keep
            } else {
                switch selectedTab {
                case .recent:
                    selectedFile = SelectionLogic.reconcile(previous: selectedFile, in: visibleLeaves)
                case .tree:
                    selection = SelectionLogic.reconcile(previous: selection, in: visibleRows)
                }
            }
            recomputeTreeExpansion()
        }
    }

    /// TREE タブで展開中の dir id 集合(`DisclosureGroup` の isExpanded バインディングの源)。
    /// 既定展開ポリシー・検索ヒット/選択の親 dir 自動展開・ユーザー手動トグルを束ねる(issue #18 決定)。
    private(set) var expandedDirs: Set<String> = []
    /// ユーザーが**明示的に折りたたんだ** dir(sticky)。検索/再走査/タブ切替の自動再計算で
    /// 勝手に開き直さないための overlay(M7 review #1/#4)。手動展開で解除。
    private var userCollapsedDirs: Set<String> = []

    /// 現在の状態(検索中か / 選択中の行)から TREE 展開集合を `TreeBuilder` で取り直す。
    /// 自動算出した展開集合から「ユーザーが閉じた dir」を差し引く(sticky 折りたたみ)。
    /// ただし選択中の行(`.file` / `.dir` 両方)を見せるための祖先は折りたたみより優先して残す
    /// (選択は常に可視)。`.dir` 選択時は dir 自身も保護対象に含める(#33 round-2 #2)。
    private func recomputeTreeExpansion() {
        var set = TreeBuilder.expansionSet(
            for: tree,
            searching: !searchText.isEmpty,
            selectedLeafPath: selectedFile?.path
        )
        let nodes = tree
        var selectionAncestors: Set<String> = []
        switch selection {
        case .file(let f):
            selectionAncestors = TreeBuilder.ancestors(ofLeaf: f.path, in: nodes)
        case .dir(let id):
            // dir 自身も折りたたみから保護(自身が `userCollapsedDirs` にあっても展開維持)+ 祖先も。
            selectionAncestors = TreeBuilder.ancestors(ofDir: id, in: nodes).union([id])
        case .none:
            break
        }
        set.subtract(userCollapsedDirs.subtracting(selectionAncestors))
        expandedDirs = set
    }

    /// dir が展開中か(`SidebarView` の `DisclosureGroup` バインディング用)。
    func isExpanded(_ dirID: String) -> Bool { expandedDirs.contains(dirID) }

    /// dir の展開/折りたたみをユーザー操作で切り替える。手動操作は `userCollapsedDirs` に記録し、
    /// 後続の自動再計算で意図が保持されるようにする(M7 review #1)。
    func setExpanded(_ dirID: String, _ expanded: Bool) {
        if expanded {
            expandedDirs.insert(dirID)
            userCollapsedDirs.remove(dirID)  // 手動展開で sticky collapse を解除
        } else {
            expandedDirs.remove(dirID)
            userCollapsedDirs.insert(dirID)  // 手動折りたたみを sticky 記録
        }
    }

    private let search: SearchProvider = FilenameSearchProvider()

    /// 検索適用後のファイル(両タブ共通の入力)。
    private var filteredFiles: [HTMLFile] {
        search.filter(allFiles, query: searchText)
    }

    /// RECENT タブ用: 検索適用後を mtime 降順 + 先頭に EXTERNAL ピンを合成(既出なら omit = 二重解消)。
    /// 検索(M7)と EXTERNAL ピン(M5)の合成: フィルタ → ソート → ピン先頭合成。
    /// ピンも検索クエリでフィルタする(非マッチのピンを検索結果に居残らせない — M7 review #2)。
    var recentFiles: [HTMLFile] {
        let sorted = RecentSorter.sortedByModificationDateDescending(filteredFiles)
        let visiblePin = pinnedExternal.flatMap { search.filter([$0], query: searchText).first }
        return ExternalOpenPolicy.compose(recent: sorted, pinned: visiblePin)
    }

    /// TREE タブ用: 検索適用後の階層。
    var tree: [TreeNode] {
        TreeBuilder.build(filteredFiles)
    }

    /// 現タブの可視 leaf 列(RECENT の j/k 移動対象 / 検索 reconcile 用)。
    /// TREE は展開中 dir 配下の leaf のみ(folder 行は含まない — 行ベースの可視列は `visibleRows`)。
    private var visibleLeaves: [HTMLFile] {
        switch selectedTab {
        case .recent: return recentFiles
        case .tree: return TreeBuilder.visibleLeaves(tree, expanded: expandedDirs)
        }
    }

    /// TREE タブの可視行列(dir + leaf。#32 の方向キー/Enter で扱う列)。
    private var visibleRows: [TreeRow] {
        TreeBuilder.visibleRows(tree, expanded: expandedDirs)
    }

    /// 方向キー/j/k で選択を移動。RECENT は leaf のみ(従来通り fullOrder 補正で「隠れた選択」救済)、
    /// TREE は **dir も含めた行列**(#32)で移動する。可視列が空のときは現選択を維持(プレビューを消さない)。
    func moveSelection(_ direction: SelectionDirection) {
        switch selectedTab {
        case .recent:
            if let next = SelectionLogic.next(
                after: selectedFile, in: recentFiles, fullOrder: recentFiles, direction: direction
            ) {
                selectedFile = next
            }
        case .tree:
            if let next = SelectionLogic.nextRow(
                after: selection, in: visibleRows, direction: direction
            ) {
                selection = next
            }
        }
    }

    /// Enter キー: TREE で dir が選択されていれば展開トグル(`activate`)。file 選択 / RECENT は no-op。
    /// 展開後、続けて方向キーで dir 配下のファイルが順に選択できる(#32)。
    func activateSelection() {
        guard case .dir(let id) = selection else { return }
        setExpanded(id, !isExpanded(id))
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
            // 検索中に odoc で開いたファイルが filter で隠れるならクエリをクリアして可視化する
            // (preview には映るのにリスト・j/k から不可視になるのを防ぐ — M7 review #2)。
            // searchText の didSet が走るが、直後に selectedFile を inter で上書きするので影響なし。
            if !searchText.isEmpty, !filteredFiles.contains(where: { $0.path == inter.path }) {
                searchText = ""
            }
            selectedFile = inter
            unreadableExternalPath = nil
            recomputeTreeExpansion()  // odoc で選んだ内部ファイルの祖先 dir を TREE で可視化(M7 review #5)
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

            // 選択中の行が走査結果から消えていたら解除する。`.file`/`.dir` を `selection` 全体で
            // 見ることで、round-1 #1 で塞いだ `selectedFile` 上書きと対称に、消えた `.dir` 選択も
            // 同じ経路で扱う(round-2 #1)。新ツリーは `result.files` 由来で構築して判定する。
            let newNodes = TreeBuilder.build(result.files)
            switch selection {
            case .file(let f) where !f.isExternal:
                if !result.files.contains(where: { $0.path == f.path }) { selection = nil }
            case .dir(let id):
                if !TreeBuilder.containsDir(id, in: newNodes) { selection = nil }
            default:
                break  // EXTERNAL ピンは走査結果に出ないため対象外(再走査で選択を奪わない)
            }
            // 未選択時のみ最新ファイルを補充する。`selectedFile` getter は `.dir` 選択中も nil を
            // 返すため、ここを `selectedFile == nil` で見ると dir 選択を上書きしてしまう。`selection`
            // で判定して .dir 選択を保持する(設計コメント L33-34 参照 — PR #33 round-1 #1)。
            if selection == nil {
                selectedFile = recentFiles.first
            }
            // 削除/再走査で消えた dir id を userCollapsedDirs から除去する。蓄積メモリリークを防ぎ、
            // 同パスのフォルダが後で再登録/再マウントされたとき「新規フォルダ」が前回の sticky 折りたたみ
            // を引き継がず初期状態(既定展開)で出るようにする(M7 review #4)。
            // **全ファイル(result.files)由来のツリー**で intersection する。検索フィルタ後の `tree` で
            // 行うと、検索中に rescan が走ったとき一時的に隠れている dir が evict され、検索クリア後に
            // 折りたたみ意図が失われる(round-5 #1)。
            // 上の stale 判定で構築した `newNodes` を再利用(同 `result.files` から同ツリーが
            // 出るため二重ビルドを避ける — #33 round-3)。
            userCollapsedDirs.formIntersection(TreeBuilder.allDirIDs(newNodes))
            // 走査でツリー構造が変わったので展開を取り直す(既定ポリシー + 選択の親 dir 自動展開)。
            recomputeTreeExpansion()
            // 検索中に rename 等で選択が filter から外れたら可視列へ reconcile し、
            // 「ファイルは存在するが検索結果に不可視」状態を解消する(M7 review #6)。
            // ただし EXTERNAL ピンは visibleLeaves に出ないため、reconcile で内部ファイルに
            // すり替わり外部プレビューが消えるのを防ぐ(searchText.didSet と同じガード — round-5 #2)。
            // TREE タブは dir 選択も拾えるよう行版 reconcile を使う(#32)。
            if !searchText.isEmpty {
                if case .file(let f) = selection, f.isExternal {
                    // EXTERNAL ピン保持
                } else {
                    switch selectedTab {
                    case .recent:
                        if let sel = selectedFile,
                           !visibleLeaves.contains(where: { $0.id == sel.id }) {
                            selectedFile = SelectionLogic.reconcile(previous: selectedFile, in: visibleLeaves)
                            recomputeTreeExpansion()
                        }
                    case .tree:
                        if let sel = selection,
                           !visibleRows.contains(where: { SelectionLogic.matches($0, sel) }) {
                            selection = SelectionLogic.reconcile(previous: selection, in: visibleRows)
                            recomputeTreeExpansion()
                        }
                    }
                }
            }
        }
    }
}
