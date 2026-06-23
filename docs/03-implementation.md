# 03. 実装書(内部設計)

最終更新: 2026-06-12(骨子。各マイルストーン完了時に実装と同期して追記する)

## 1. ターゲット構成(SPM、Xcode 非依存)

| ターゲット | 種別 | 責務 |
|---|---|---|
| `HTMLViewerCore` | library | UI 非依存の判断ロジック全部。TDD 対象(`swift test`) |
| `HTMLViewer` | executable | SwiftUI シェル(Humble Object 層)。`.defaultIsolation(MainActor.self)` |
| `HTMLViewerCoreTests` | test | Swift Testing(`@Test`) |

```
Sources/HTMLViewerCore/
  Models.swift             # HTMLFile / TreeNode(Sendable)
  IgnoreRules.swift        # ignore dirs / .html .htm 判定 / 最大ファイル数
  FolderScanner.swift      # 再帰走査(nonisolated)
  SearchProvider.swift     # 検索抽象(初期実装はファイル名フィルタ。将来 FTS5 / embeddings)
  RecentSorter.swift       # mtime 降順
  TreeBuilder.swift        # 階層構築・展開ポリシー
  SelectionLogic.swift     # j/k 移動・選択維持
  PersistenceCodec.swift   # 登録フォルダ等の encode/decode(UserDefaults は注入)
  ExternalOpenPolicy.swift # 外部ファイルのピン留め・同一 URL 再 open の no-op 判定
  FileWatcher.swift        # FSEvents → AsyncStream(統合テスト対象)
Sources/HTMLViewer/
  HTMLViewerApp.swift      # @main。Window シーン + NSApplicationDelegateAdaptor
  AppDelegate.swift        # application(_:open:)(コールド起動時は pendingURLs にバッファ)
  AppState.swift           # @Observable オーケストレーション
  WebViewContainer.swift   # NSViewRepresentable(WKWebView)
  ContentView.swift / SidebarView.swift / FileRowView.swift / Theme.swift
```

## 2. 鍵となる技術判断(実装時に厳守)

1. エントリファイル名は `main.swift` 禁止(`@main` と衝突)→ `HTMLViewerApp.swift`
2. シーンは `Window`(`WindowGroup` はウィンドウ増殖の余地があるため不使用)
3. `open -b` 連携の成立条件: 正規 .app 構造 / `CFBundleDocumentTypes` で `public.html`(Role=Viewer, `LSHandlerRank=Alternate`)/ Launch Services 登録 / **バンドル経由起動**(`swift run` 直起動プロセスにはオープンイベントが届かない)
4. Info.plist: `CFBundleIdentifier=com.hayashi.htmlviewer`(不変)/ `CFBundleName=HTMLViewer`(スペースなし)/ `CFBundleExecutable` はバイナリ名と完全一致 / `LSUIElement` は設定しない
5. SPM の resources / `Bundle.module` は使わない(手組みバンドルで実行時クラッシュする)。テーマ・JS 文字列はコード内定数
6. FSEvents: 複数ルートを 1 ストリームで監視(latency 0.3s)。C コールバックへは `FSEventStreamContext.info` + `Unmanaged`。フォルダ追加時はストリーム再構築。消費側で ignore パスをフィルタ + 300ms debounce
7. WKWebView: リロードは `loadFileURL` 再実行(`reload()` 不使用)。`underPageBackgroundColor` で白フラッシュ防止。`isInspectable = true`。`lastLoadedURL` + `reloadToken` で再ロードループ防止。WKUIDelegate で JS の alert / confirm パネルを実装
8. 永続化: UserDefaults + 素のパス文字列(sandbox なしのため security-scoped bookmark 不要)

## 3. ビルド・署名・インストール(`scripts/build.sh`)

```
swift build -c release
→ .app 組み立て(Contents/MacOS/ にバイナリ、Info.plist は plutil -lint で検証)
→ codesign --force --sign -(ad-hoc。必ず最終ステップ — 署名後に plist を触ると起動時 SIGKILL)
→ 起動中の旧インスタンスを quit してから ~/Applications へ ditto
→ lsregister -f はインストール先のみに実行(dist/ を Launch Services に触れさせない)
```

## 4. TCC(フォルダアクセス許可)の運用

ad-hoc 署名は再ビルドごとに CDHash が変わるため、`~/Documents` 等への許可が**サイレント拒否**に転じることがある。

- 症状: 再ビルド後に走査結果が空になる(エラーは出ない)
- 対処: `tccutil reset SystemPolicyDocumentsFolder com.hayashi.htmlviewer` → アプリ再起動して再許可
- **アプリ内検知(M3 再レビューで追加)**: 「登録先は到達可能 かつ そのフォルダ配下 0 件 かつ TCC 保護領域(`~/Documents` / `~/Desktop` / `~/Downloads`)」を `RootDiagnostics`(Core)で `tccLikelyBlocked` と判定し、サイドバーに「アクセス許可」導線(システム設定の「ファイルとフォルダ」を開く + 上記 `tccutil` 案内)を出す。*予見可能・検知可能*な失敗を人間の記憶に委ねず案内する(L1→L2/L3)。ただし ad-hoc アプリは TCC を**自動付与できない**ため、できるのは検知 + 案内まで
- 検証の注意: TCC / UserDefaults / オープンイベントの動作確認は**必ずバンドル版**(`make install` 後)で行う。`swift run` 直起動はドメインが別

## 5. マイルストーン別 実装記録

### M0(2026-06-12)
- リポジトリ統治: CLAUDE.md / .claude/rules/security.md / .gitignore / LICENSE(MIT)/ Makefile(`make check`)
- docs/ 体系と本書を含む 5 文書を整備
- コミット author をリポジトリローカルで GitHub noreply に設定

### M1(2026-06-12)
- Package.swift: 3 ターゲット構成(Core / App / Tests)。tools-version 6.2、`.defaultIsolation(MainActor.self)` は CLT の Swift 6.3.2 で問題なくビルドできることを確認(フォールバック不要だった)
- 最小実装: `HTMLViewerApp`(`Window` シーン)/ `AppDelegate` / `Theme`(案 B パレット)/ `ContentView`(テーマ背景の空ウィンドウ)/ Core に `HTMLFile`
- **CLT 環境の swift test の罠(重要)**: 素の `swift test` は `no such module 'Testing'` で失敗する。Testing.framework は CLT 内(`$(xcode-select -p)/Library/Developer/Frameworks`)に存在するが検索パスが自動で渡らない。さらに実行時に `lib_TestingInterop.dylib`(`.../Library/Developer/usr/lib`)への rpath も必要。**対処: `make test` に -F / -rpath フラグを固定化済み**。テスト実行は必ず `make test` を使う(計画段階の「XCTest へフォールバック」は不要になった。なお CLT に XCTest.framework は存在しないため、XCTest フォールバックはそもそも不可能だった)

### M2(2026-06-12)
- `Support/Info.plist`: §2 の必須キー一式 + `CFBundleDocumentTypes`(public.html / Viewer / Alternate)+ フォルダ TCC の usage description。DocumentTypes はこの時点で宣言済み(受信ハンドラの実装は M2.5)
- `scripts/build.sh`: §3 の手順を罠対策込みで実装(plutil -lint → codesign 最終 → 旧インスタンス quit → ditto → lsregister はインストール先のみ)。`make install` で呼び出す
- 検証で確認できた事実: `open -a HTMLViewer`(名前解決)と `open -b com.hayashi.htmlviewer`(bundle id)の両方が機能し、**起動中の再 open でもプロセス数 1 のまま**(LS の単一インスタンス配送が手組みバンドルでも成立)。AppleScript の `tell application id ... to quit` も機能

### M3(2026-06-15)
- Core(TDD): `IgnoreRules`(html/htm 判定・ignore/隠しディレクトリ・MAX_FILES=5000)/ `FolderScanner`(再帰走査)/ `RecentSorter`(mtime 降順・同値はパス昇順)/ `PersistenceCodec`(登録フォルダの JSON encode/decode・重複除去)。テスト 18 件
- UI(Humble Object): `AppState`(@Observable。フォルダ登録・永続化・走査の結線。重い走査は `Task.detached`)/ `SidebarView`(NSOpenPanel 登録 + RECENT リスト)/ `FileRowView` / `ContentView`(サイドバー + プレビュー枠。プレビュー本体は M4)
- **symlink 解決の非対称(重要)**: `FileManager.enumerator` は `/var`→`/private/var` を解決したパスを返すが、`URL.resolvingSymlinksInPath()` はこの環境で `/var` を解決しない。rootPath を enumerator 出力と一致させるため `.canonicalPathKey` で正規パスを取得して prefix 一致(relativePath / 将来の allowingReadAccessTo)を保証
- 永続化キー: `registeredFolders.v1`(UserDefaults)。sandbox なしのため security-scoped bookmark は不使用(§2-8 の判断どおり)
- **観点レビュー(issue #8)反映のフォローアップ**:
  - MAX_FILES 打ち切りを決定論化(走査中の先着 → 全件走査後に mtime 降順で上位 N 保持)。走査順依存・新しいファイル脱落を解消
  - クロスフォルダ / 入れ子登録(A と A/sub)の重複を絶対パスで除去
  - symlink 非追従を `.isSymbolicLinkKey` で明示ガード(サイクル無限走査・ignore 回避防止。`FileManager.enumerator` の既定でも追従しないが版依存に頼らない)
  - stale フォルダ(削除/移動/unmount)は登録維持・走査スキップ + サイドバーに「見つかりません」表示(`AppState.isReachable`)
  - テスト計 20 件(truncation は「どの N 件か」まで、dedup・symlink 非追従を追加)
- **観点再レビュー(issue #8・2026-06-16)反映のフォローアップ**:
  - **ignore 判定を case-insensitive 化**(`IgnoreRules.shouldSkipDirectory` を `lowercased()` 比較に統一)。HTML 拡張子判定との非対称を解消し、`NODE_MODULES` 等の大文字表記・case-sensitive ボリュームでの除外漏れを防止
  - **TCC 失効の検知 + 再許可案内**: `RootDiagnostics`(Core 純関数: `classify` / `isUnderProtectedLocation`)で `tccLikelyBlocked` を判定し、`AppState.status(of:)`(入れ子登録に強い絶対パス prefix 計数)経由で `SidebarView` に導線を出す(§4 参照)
  - **外部 / ネットワークボリュームは stale パスと同扱い**(到達不能 → 登録維持・走査スキップ・「見つかりません」表示。再マウントで次回走査復帰)。ボリュームタイプ別の特別扱いは M3 スコープ外。`security-scoped bookmark` 不使用の方針は維持(§2-8)
  - **A-1(毎回フル走査)の撤退基準を明文化**(05 D9): 5000 件 ≈ 430 ms を実測。撤退路は M6 で FSEvents 増分 + 前回走査キャッシュ
  - テスト計 27 件(case-insensitive ignore +1、`RootDiagnostics` +6)

### M2.5(2026-06-18)
- Core(TDD): `OpenEventPolicy.acceptableHTMLPaths(from:fileExists:)` — 受信 URL を `.html`/`.htm`(`IgnoreRules.isHTMLFile` 再利用)かつ実在(`fileExists` 注入)のパスに絞る純関数。テスト 5 本(計 33 green)
- 受信機構: `AppDelegate.application(_:open:)` が `onOpen` 未設定なら `pendingURLs` にバッファ、設定済みなら即呼び。`HTMLViewerApp` の `.task` で `appDelegate.connect { app.handleOpenedURLs($0) }` を呼び、**register(onOpen 設定)→ 同期 drain** の順(間に await なし)でコールド起動レースを塞ぐ
- 観測点: `AppState.receivedPaths`(`selectedFile` 不使用)を `ContentView` 上部のバナーに表示。複数 URL は全列挙、連続受信は最新で置換(二重表示なし)
- **検証(バンドル版スモーク)で判明した事実**: `application(_:open:)` は SwiftUI(`@NSApplicationDelegateAdaptor`)ライフサイクルでも**発火する**(plan B の `kAEOpenDocuments` / `.onOpenURL` は不要だった)。コールド起動では odoc が **`didFinishLaunching` より前**に届き、バッファ → `.task` drain で取りこぼさないことを実機確認。単一インスタンス(`pgrep` で 1)・連続受信で二重なし・非 .html / 存在しないパスでクラッシュなしも確認
- 検証手段の知見: `NSLog` は `log show` で安定して拾えなかった。発火確認は一時的なセンチネルファイル(home 直下、検証後削除)で行った

### M4(2026-06-17)
- Core(TDD): `NavigationPolicy`(リンククリック由来の http/https のみ外部ブラウザ、それ以外は WebView 内許可)。テスト 5 本(計 33 green)。read-access スコープ・起動時選択は既存再利用で新規 Core 型を作らない(issue #11 決定: YAGNI)
- UI(Humble Object): `WebViewContainer`(NSViewRepresentable + Coordinator)。`loadFileURL(allowingReadAccessTo: 所属ルート)` / `underPageBackgroundColor=.white`(白フラッシュ防止)/ `isInspectable` / `lastLoadedPath`+`reloadToken` で再ロードループ防止 / 外部リンクは `NSWorkspace` / WKUIDelegate で JS alert・confirm・prompt パネル
- `AppState`: `reloadPreview()`(loadFileURL 再実行トークン)/ `revealInFinder`(`activateFileViewerSelecting`)/ `openInBrowser`。`ContentView` の topbar に 再読込 / Finder / ブラウザ ボタン、プレビュー枠を WebViewContainer に差し替え
- **WebKit デリゲートの罠(重要)**: completion handler は SDK で `WK_SWIFT_UI_ACTOR`(= `@MainActor`)宣言。`.defaultIsolation(MainActor.self)` 下でも closure に `@MainActor` を明示しないと「nearly matches optional requirement」警告となり**デリゲートが実行時に呼ばれない**(ナビゲーション制御・JS ダイアログが無効化)。各 completion handler に `@MainActor` を付与して解消(`@preconcurrency` 適合は無効だった)
- 削除時挙動: 「最新を再選択(0 件のみ空)」に統一(既存 `rescan` の挙動が正)、`docs/02 §2` を実装に合わせ修正。ライブ検知は M6
- **brush-up(2026-06-23)**: PR #15 の `/code-review` 指摘を反映
  - `NavigationPolicy` のスキーム分類を issue #11 決定の表どおりに実装: `http`/`https`/`mailto`/`tel`/`facetime`/`sms` を `openExternally`、`file`/`data`/`about`/`blob` を `allowInWebView` に明示。default は安全側で `allowInWebView`(未知スキームは WebView に委ねる)。`NavigationPolicyTests` を 5 本 → スキーム別 12 本に拡張(DoD 充足)
  - `WebViewContainer.createWebViewWith` を `decide` 経由に統一(`target="_blank"` で非 http のスキーム — `mailto:` 等 — も `NSWorkspace` に委譲)。`makeNSView` の空 `WKWebViewConfiguration()` 引数を削除(`WKWebView(frame:.zero)` で同義)

### M5(2026-06-23)
- Core(TDD): `ExternalOpenPolicy`(`isInside` 内外判定 / `makeExternalFile` EXTERNAL 合成 / `compose` 単一ピン先頭合成 + 既出 omit)。テスト 6 本。**不変条件**: パス比較は呼び出し側(AppState)が `.canonicalPathKey` 正規化した文字列で行う(Core は FS 非依存の純ロジック)
- `HTMLFile.isExternal`(既定 false)を追加。true で WebView の read-access はファイル単体、UI は EXTERNAL バッジ
- `AppState`: `handleOpenedURLs` を M2.5 のバナー観測点から M5 本実装へ置換。内外判定 → 外部=`pinnedExternal`(単一・非永続)/ 内部=通常選択。複数 URL は「外部最後 1 件ピン + 内部最後 1 件選択」。同一 external 再受信は `reloadToken` 強制インクリメント(reload・churn なし)。削除(fileExists false)で現ピンを落とす。canonicalPath nil は `unreadableExternalPath` で「読めない」表示・ピンせず。`recentFiles` は `ExternalOpenPolicy.compose` でピンを先頭合成(走査に出たら omit)。rescan の選択リセットは external を対象外(再走査でピン選択を奪わない)
- `WebViewContainer`: 外部ファイルは `allowingReadAccessTo` をファイル単体スコープに切替(登録外の周囲フォルダを晒さない)
- UI: `ContentView` の M2.5 受信バナーを撤去し、(a) サイドバー/トップバーの EXTERNAL バッジ、(b) 読めない外部ファイルの通知バナー、に置換
- スコープ外(確定): ライブ監視は M6(登録ルートのみ・M5 と非共有)。再表示は odoc 再受信(`open -b`)で賄う。`r` 再読込=M7 / hook 再発火=M8 は後続

### M6(2026-06-23)
- **着手前スモーク**: `FileWatcherTests` で temp dir に `.html` 作成 → イベント受信(timeLimit 付き)を実証。**FSEvents は CLT + 実行環境で実動**(0.45s で green)→ 撤退路ポーリング(D4/D9)は不要だった。flags `kFSEventStreamCreateFlagFileEvents | UseCFTypes | WatchRoot` も版差なし
- Core: `FileWatcher`(FSEvents → `AsyncStream<[String]>`。`@unchecked Sendable` + 専用 serial queue。C コールバックは `FSEventStreamContext.info` + `Unmanaged`。`stop()` は Stop→Invalidate→Release + `isStopping` ガード)/ `WatchEventPolicy`(`.ignore`/`.reloadDisplayed`/`.rescan` 判定。入力は canonical 正規化済み前提・純関数)/ `Debounce.coalesce`(debounce 意味論を決定論テストで固定)/ `PathNormalizer.canonical`(M5/M6 共通の正規化ヘルパ)。テスト計 61
- AppState 結線(薄い 4 段): `for await batch in watcher.events` → `pendingWatchPaths` 蓄積 + 300ms debounce(Task cancel)→ `WatchEventPolicy.decide`(canonical 正規化して投入)→ `rescan()` / `reloadPreview()`。フォルダ登録変更で `rebuildWatcher`(FSEvents はパス追加不可)。到達不能ルートは除外(fail-silent)。`reloadDisplayed` でも表示中が消えていれば `rescan`(M4 削除時挙動)
- `WebViewContainer`: reload 時にスクロール位置を退避(`evaluateJavaScript("[scrollX,scrollY]")`)→ `didFinish` で `scrollTo` + 200ms 後に再試行(二段・ベストエフォート)。ファイル切替時は復元しない
- 数値の根拠: latency `0.3s`(D4)/ debounce `300ms`(Claude の連続保存の典型間隔)/ 二段復元 `200ms`(`didFinish` 後のレンダリング完了 lag)
- スコープ外: TREE/検索/キー=M7。外部ファイル監視は持たない(M5 と非共有)。スクロール完全復元は非目標
- 波及: M5(#16)本文 Context の「M6 に相乗り」記述は監視非共有に対称修正済み

(M7 以降、完了時に追記)
