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

### M8(2026-06-24)
- `hooks/open-html.sh`(新規): stdin JSON から `.tool_input.file_path` を抽出(`jq` → python3 フォールバック)→ `.html`/`.htm` 以外を no-op → 5 秒スロットル(`~/.cache/htmlviewer/last-open` に `<epoch>\t<path>` 記録)→ `open -g -b com.hayashi.htmlviewer`(D7)→ 常に `exit 0`(PostToolUse はブロック不能・stderr 抑止)
- `hooks/settings.json.example`(新規・最小手書き): `PostToolUse` × `Write|Edit|MultiEdit` matcher。command パスは `$HOME` プレースホルダ。**この example は純 JSON**(Claude Code hooks スキーマ未定義の `_comment` キーを置かない — 将来の strict 検証で弾かれないため。M8 review #2)。**設定手順は本書が正準**: ユーザーは `~/.claude/settings.json` に**マージ**する(全置換ではない)/ `command` パスを自分の clone 先に合わせて書き換える
- `scripts/test-hooks.sh` + `make test-hooks`: JSON fixture で入力解析・拡張子フィルタ・スロットルを検証。`OPEN_CMD` で `open` を stub に差し替え呼び出し回数を計測(`HTMLVIEWER_HOOK_THROTTLE` / `HTMLVIEWER_HOOK_STATE_DIR` で各テストを独立)。**19 ケース green**(初版 11 → review 各ラウンドの堅牢化で拡張)。セットアップ(`mktemp` / stub heredoc / `chmod`)失敗は `|| exit 1` で fail-loud にし、CI で fixture 環境が壊れた際の false-pass を防ぐ(M8 review #4)
- **テスト容易化の知見**: シェル hook は副作用(`open` の呼び出し回数 + 状態ファイルの更新)を観測点にした。Core(Swift)の TDD と非対称だが、シェルの責務が「フィルタ + スロットル + 起動」と少ないため十分担保できる
- **堅牢化(M8 review 第1ラウンド)**: `open-html.sh` のスロットルは `last_epoch` を**数値ガード**(`case`)してから算術展開する(state 破損で `$((...))` が stderr エラーを出さない・スロットル抜けで open 継続 — #1)。stdin 読取は `payload="$(cat 2>/dev/null)"`(コマンド置換は exit code 非伝播のため `|| true` は死コード — #3)
- **堅牢化(M8 review 第2ラウンド)**: (#1) `open` 起動に **`--`(end-of-options)** を置き、`-` 始まりの file_path を `open(1)` がオプション誤解釈するのを防ぐ(`-W.html` 等で誤起動する CONFIRMED bug)。(#2) `THROTTLE_SECONDS` env も読み取り時に **数値正規化**(非数値は既定 5)し、`[ -lt ]` の integer エラーを防ぐ(state 側 epoch ガードと対称)。(#3) state 書き込みを **tmp + `mv -f`(POSIX アトミック rename)** にし、並走 hook の truncate+write 交錯による部分破損を防ぐ。test-hooks を 12 → 15 ケースに拡張(`--` 付与 / THROTTLE 正規化 / tmp 残骸なし)
- **堅牢化(M8 review 第3ラウンド・10 件中 6 採用 / 3 不採用 / 1 取り下げ)**: (#2) state 読取を **tab 必須**化(`read` で 1 行 → tab 無し行は破損として無視)し、`last_path` に行全体が漏れる誤一致を防止。(#6) 拡張子フィルタを `printf|tr` から **`case` の文字クラス `*.[Hh][Tt][Mm][Ll]`** に、state 読取を `tail` から **builtin `read`** に置換(hot path の fork 2 個を削減)。(#5/#10) **`HTMLVIEWER_HOOK_DEBUG=1`** opt-in で open 失敗 / state 書込失敗を `$STATE_DIR/last-error` に 1 行記録する debug 口を追加(既定無効でトランスクリプトを汚さない)。(#7) docs の test-hooks ケース数表記を 19 に整合。(#8) `-a` 注入を含む `.html` パスの負テストを追加。test-hooks を 15 → 19 ケースに拡張。**不採用**: #1(`$HOME` は hook の shell form〔`args` 無し〕で展開されるため誤検知 — Claude Code docs で確認)/ #3(run() の test リファクタは低価値)/ #9(エディタ autosave の二重発火は Claude の Write トリガには非該当 — 実パスを書くため)。**取り下げ**: #4 の python3 分岐強制テスト(PATH を絞ると macOS `/usr/bin/python3` shim がハングし安定実行不可。dual fallback は維持)
- スコープ外: Bash heredoc 経由の HTML 生成検知(matcher 拡張は誤発火増で送り)・hook 設定の自動インストーラ(マージはユーザー手作業)

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
- **brush-up(2026-06-23)**: PR #22 `/code-review` 指摘を反映
  - `HTMLFile` の `==` / `hash(into:)` を **path のみ**で実装(同 path / 異 `isExternal` で値が一致するように)。SwiftUI `List(selection:)` の Hashable 照合と `Identifiable.id` を整合させ、EXTERNAL ピン内部化時の selection 同期ずれを根絶(🟡-1 / 🟡-4 同根)
  - `AppState.rescan` に「ピン内部化検知」を追加: `pinnedExternal.path` が `allFiles` に出現したら `pinnedExternal = nil` + `selectedFile` を内部版 `HTMLFile` に張り替え。declarative 二重解消が `recentFiles` 合成だけでなく `selectedFile` ステートでも一貫する(🟡-1)
  - `handleOpenedURLs` の `fileExists=false` ブランチで `unreadable` を立てる(ピン中以外の死パスでも silent drop しない)。ピン中の場合は `selectedFile?.path == cpath` なら同時にクリア(🟡-2)
  - docs/02 §2: 削除検知は **odoc 再受信時のみ**(`r` キー / 再読込ボタン経路は対象外、WebKit エラーで気づく前提)を明文化。受信時の読めないパスは「読めない」表示(ピンしない)を併記(🟡-3 仕様確定)

### M6(2026-06-23)
- **着手前スモーク**: `FileWatcherTests` で temp dir に `.html` 作成 → イベント受信(timeLimit 付き)を実証。**FSEvents は CLT + 実行環境で実動**(0.45s で green)→ 撤退路ポーリング(D4/D9)は不要だった。flags `kFSEventStreamCreateFlagFileEvents | UseCFTypes | WatchRoot` も版差なし
- Core: `FileWatcher`(FSEvents → `AsyncStream<[String]>`。`@unchecked Sendable` + 専用 serial queue。C コールバックは `FSEventStreamContext.info` + `Unmanaged`。`stop()` は Stop→Invalidate→Release + `isStopping` ガード)/ `WatchEventPolicy`(`.ignore`/`.reloadDisplayed`/`.rescan` 判定。入力は canonical 正規化済み前提・純関数)/ `Debounce.coalesce`(debounce 意味論を決定論テストで固定)/ `PathNormalizer.canonical`(M5/M6 共通の正規化ヘルパ)。テスト計 61
- AppState 結線(薄い 4 段): `for await batch in watcher.events` → `pendingWatchPaths` 蓄積 + 300ms debounce(Task cancel)→ `WatchEventPolicy.decide`(canonical 正規化して投入)→ `rescan()` / `reloadPreview()`。フォルダ登録変更で `rebuildWatcher`(FSEvents はパス追加不可)。到達不能ルートは除外(fail-silent)。`reloadDisplayed` でも表示中が消えていれば `rescan`(M4 削除時挙動)
- `WebViewContainer`: reload 時にスクロール位置を退避(`evaluateJavaScript("[scrollX,scrollY]")`)→ `didFinish` で `scrollTo` + 200ms 後に再試行(二段・ベストエフォート)。ファイル切替時は復元しない
- 数値の根拠: latency `0.3s`(D4)/ debounce `300ms`(Claude の連続保存の典型間隔)/ 二段復元 `200ms`(`didFinish` 後のレンダリング完了 lag)
- スコープ外: TREE/検索/キー=M7。外部ファイル監視は持たない(M5 と非共有)。スクロール完全復元は非目標
- 波及: M5(#16)本文 Context の「M6 に相乗り」記述は監視非共有に対称修正済み
- **brush-up(2026-06-23)**: PR #23 `/code-review` 指摘を反映
  - 🟡-3: `AppState` に `@MainActor` を明示注記(従来は `Package.swift` の `.defaultIsolation(MainActor.self)` で実質 MainActor だったが、`watchTask` / `debounceTask` の `for await` / closure 隔離が暗黙だった点を自衛。Swift 6 strict concurrency / SDK 更新 / 設定変更に対する前駆対策)
  - 🟡-2: **debounce の Core 純化(clock 注入式)は M9 ポリッシュ判断送り**で恒久化を明示(レビュー提案 (B))。Core 側は `Debounce.coalesce`(events 列 → fired 列の純関数)で意味論回帰を固定 + AppState は Task cancel + `Task.sleep` でランタイム実装、という二層構造を意図的に受け入れる。actor/clock 駆動への昇格は M9 で他のポリッシュとまとめて判断する
  - 🟡-1(典型条件 ~100KB の実測 1 行記録)は GUI 操作が必要なため、本 brush-up では **未充足のまま残置**。作者が手動 stopwatch で 100KB / 500KB / 1MB の再描画時間を計測 → `docs/04` M6 §5 注に追記して closure する(マージブロッカーではないがフォローアップ TODO)

### M7(2026-06-23)
- Core(TDD): `TreeBuilder`(階層構築・`allLeaves`/`visibleLeaves`/`defaultExpanded`/`ancestors`、ID は絶対 path)/ `SearchProvider`(`FilenameSearchProvider`: NFC 正規化後 case-insensitive 部分一致、D8 再設計前提)/ `SelectionLogic`(`next` クランプ移動 + `reconcile` フィルタ後保持、照合は id)/ `TreeNode` モデル。テスト計 61
- UI(Humble): `SidebarView` に検索フィールド(`@FocusState`、`/` フォーカス要求 → `onChange`、Esc は `onExitCommand` でクリア+blur)+ RECENT/TREE セグメント。`AppState` に `searchText`(didSet で展開取り直し + `reconcile`)/ `selectedTab` / `filteredFiles` / `tree` / `visibleLeaves` / `moveSelection`
- キーボード: `HTMLViewerApp` の **Scene 直下に local key monitor を 1 個**(`onAppear` 設置・`onDisappear` 解除)。`j/k`=`moveSelection`、`r`=`reloadPreview`(未選択 no-op)、`⌘⇧R`=`revealSelectedInFinder`、`/`=検索フォーカス要求。**`isSearchFocused`(@FocusState ミラー)中は j/k/r を透過**
- スコープ外: 全文検索=D8(本 PR はファイル名のみ)。タブ選択の永続化は未実装
- **brush-up(2026-06-24)**: PR #26 `/code-review` 指摘を反映
  - 🟡-1: 展開ポリシーを **UI 配線して issue #18 決定を充足**(初回レビューで「Core 実装済みだが UI 未採用」と指摘されていた簡略化を撤回)。`TreeBuilder.expansionSet(for:searching:selectedLeafPath:)` を Core に追加(`defaultExpanded` + 検索ヒット祖先 + 選択 leaf 祖先を合成・純関数・テスト 3 本追加)。`AppState` に `expandedDirs: Set<String>` + `recomputeTreeExpansion()`(searchText/selectedTab/rescan で取り直し)+ `isExpanded`/`setExpanded`。`SidebarView` の `OutlineGroup`(常時全展開・外部バインド不可)を **再帰 `DisclosureGroup(isExpanded:)`**(`TreeRowsView`)に置換し、`expandedDirs` にバインド。`visibleLeaves`(j/k 対象)も `allLeaves` → `visibleLeaves(tree, expanded:)` に切替えて折りたたみ dir を飛ばす。`recentFiles` は検索フィルタ(M7)と EXTERNAL ピン合成(M5)の両方を通す(filter → sort → compose)
  - 🟢-2: key monitor の `case "r"` を `where !cmd && !shift` に明示限定 + コメントで Shift+R="R" の分岐を説明(可読性)
  - 🟢-1(visibleLeaves 二重計算)/ 🟢-3(`FileWatcher.events` single consumer・M7 では未使用)は M9/後続送りで据え置き
  - テスト計 64(`TreeBuilder.expansionSet` +3)。展開 UX の目視確認は作者の GUI 検証に委ねる(再帰 DisclosureGroup の展開/折りたたみ挙動はユニットテスト対象外)
- **brush-up 第2ラウンド(2026-06-24・`/code-review high` 5 件)**:
  - #1: key monitor がテキスト入力フォーカス(検索フィールド + **プレビュー WKWebView 内の `<input>`/`<textarea>`**)を透過するよう、`isSearchFocused` に加えて `NSApp.keyWindow?.firstResponder` チェーン(`NSText` / `WKWebView` 祖先)を判定(`keyEventShouldYieldToFocus`)。in-page フォーム入力が j/k/r/`/` に飲まれる不具合を解消
  - #2: `recentFiles` で EXTERNAL ピンも検索クエリでフィルタ(`search.filter([pin], query:).first`)。非マッチのピンが検索結果に居残る・j/k 可視列に混入する不具合を解消
  - #3/#4: 選択が可視 leaf 外(TREE 折りたたみ / タブ切替で隠れた)のとき j/k が先頭ジャンプしていたのを、`SelectionLogic.next(after:in:fullOrder:direction:)` を追加し**全 leaf 順序基準で同方向の最近可視 leaf へ**移すよう改善(選択維持=プレビューは変えず、移動は j/k 時のみ)。共通パスは既存 `next` に委譲=回帰なし
  - #5: key monitor の修飾判定を `deviceIndependentFlagsMask` で正規化し、`option`/`control` が乗ったキー(⌥r='®' / ⌃r 等)を横取りしないよう全ビューアキー(j/k/r/`/`)に適用
  - テスト計 82(`SelectionLogic` 全順序オーバーロード +2)。#1 の WKWebView フォーカス透過挙動は firstResponder チェーン依存のためユニットテスト対象外 → 作者の GUI 検証に委ねる
- **brush-up 第3ラウンド(2026-06-24・`/code-review high` 10 件)**:
  - #1/#4(展開の sticky 化): `expandedDirs` が検索/再走査/タブ切替の自動再計算で**全置換**され、ユーザーの手動折りたたみが消える問題を解消。`userCollapsedDirs: Set<String>`(手動で閉じた dir を記録する overlay)を導入し、`recomputeTreeExpansion` で自動算出集合から差し引く。ただし選択中 leaf の祖先は折りたたみより優先して可視に残す。`setExpanded` が手動展開で overlay 解除・手動折りたたみで記録
  - #3: `searchText.didSet` で reconcile **後にも** `recomputeTreeExpansion` を呼び、reconcile が選び直した新選択の祖先 dir を展開して可視化(従来は reconcile 前の旧選択で展開していた)
  - #5: `handleOpenedURLs` が odoc で内部ファイルを選択したあと `recomputeTreeExpansion` を呼ぶ(>40 dir で折りたたみ中でも選択を TREE に可視化)
  - #6: `rescan` で検索中に rename 等により選択が filter から外れたら可視列へ reconcile(「存在するが検索結果に不可視」を解消)
  - #8: `TreeBuilder` の dir ノード id を**末尾 `/` 付き**にして leaf(`file.path`)と区別。dir 名と同名の `.html` ファイルが同階層に並んでも id 衝突しない(`expandedDirs` 誤照合・Identifiable 違反を防ぐ)。`ancestors`/`defaultExpanded`/`visibleLeaves` は全て `TreeNode.id` 参照のため `dirID` 1 箇所で一貫
  - #9: key monitor の `⌘⇧R`(reveal)も `option`/`control` を弾く(`⌘⇧⌥R` 等の別 bind と衝突しない・`r` と対称)
  - #2: `/` ケースも `shift` を弾く(`Shift+/`='?' を横取りしない・`r` と対称)
  - #10: `keyEventShouldYieldToFocus` で key window が `NSPanel`(`NSOpenPanel` 等のモーダル補助ダイアログ)のときビューアキーを透過(ダイアログ背後で選択移動/reload が走るのを防ぐ。本アプリは単一 Window 設計)
  - **#7 は不採用(spec 準拠)**: 「検索中に選択がヒットから外れると reconcile が先頭(=条件次第で EXTERNAL ピン)を選びプレビューが変わる」件は、issue #18 状態保持規則①「消えたら先頭」の仕様どおりの挙動。ピンは検索クエリにマッチした時のみ可視化される(第2ラウンド #2)ため、可視先頭を選ぶのは整合的。仕様を曲げてまで非外部優先にはしない
  - テスト計 83(`TreeBuilder` dir/leaf id 衝突回避 +1)。sticky 折りたたみ・odoc 展開・NSPanel 透過は AppState/AppKit 層のため GUI 検証は作者に委ねる
- **brush-up 第4ラウンド(2026-06-24・`/code-review high` 10 件 — 第3ラウンドの複雑化が生んだ派生 defect)**:
  - #1: `moveSelection` は `SelectionLogic.next` が nil(全 dir 折りたたみ等で可視列が空)のとき**現選択を維持**し、プレビューを消さない(`selectedFile = nil` の代入をやめる)
  - #7: `expansionSet(searching:)` を leaf ごとの `ancestors` O(L×N) DFS から **`allDirIDs` の O(N)** に置換(フィルタ後ツリーは全 leaf がヒットなので全 dir 展開と等価)。検索 1 文字あたりの main-thread ノード訪問を L×N → N に削減
  - #5: TREE の `List(selection:)` を **nil 書込を無視する `Binding`** に。tag 無し dir 行(DisclosureGroup ラベル)クリックで `selectedFile` が nil 化しプレビューが消える macOS 挙動を防ぐ(プログラム側の nil 化は AppState 直書きなので無影響)
  - #9: footer を `recentFiles.count`(検索フィルタ後)から **`allFiles.count`(総在庫)** 表示に。検索ヒット 0 で「0 ファイル」となりスキャン失敗/消失と誤解されるのを防ぎ、絞り込み中は「ヒット / 総数」表記
  - #2: `handleOpenedURLs` で odoc が開いた内部ファイルが検索 filter で隠れる場合 **`searchText` をクリア**して可視化(preview に映るのにリスト・j/k から不可視になるのを解消)
  - #4: `rescan` で `userCollapsedDirs` を現ツリーの dir id に `formIntersection` で prune。削除フォルダ id の蓄積リーク防止 + 同パス再登録時に「新規フォルダ」が前回の sticky 折りたたみを引き継がない
  - #3: `searchText.didSet` の reconcile を、**EXTERNAL ピン選択中はスキップ**(ピンは検索リストに出ないため reconcile が先頭へ飛ばし外部プレビューがスワップするのを防ぐ)
  - #10: `TreeBuilder` の dir パス結合を防御化(`joinDir`/`dirID` が trailing slash 付き root=`/` で `//` を作らない)。回帰テスト +1
  - #8: `docs/04` M7 行を `✅` → **`⚠️ 部分(Core ✅ / GUI 未実施)`** に修正。§5 手動 11 行が全 ⬜ でマージ前に作者の GUI 確認が必要な実態を明示(CLAUDE.md 進捗管理規約に合わせる)
  - **#6 は対応済みとして据え置き**: 「rescan fallback が折りたたみ祖先で alphabetic-first に化ける」件は、第3ラウンドで導入した `recomputeTreeExpansion` の「選択中 leaf の祖先は折りたたみより優先して可視に残す」ロジックにより、fallback 選択(mtime 最新)の祖先が展開され可視化されるため発生しない(reconcile も走らない)
  - テスト計 84(trailing slash root の `//` 回避 +1)。selection nil 化防止・NSPanel/WKWebView 透過・DisclosureGroup 選択挙動は AppKit/SwiftUI 層のため**マージ前の GUI 検証が必須**(docs/04 §5 M7)
- **brush-up 第5ラウンド(2026-06-24・`/code-review high` 3 件 — 第4ラウンドの派生 + Caps Lock エッジ)**: すべて採用
  - #1: `rescan` の `userCollapsedDirs.formIntersection` を、検索フィルタ後の `tree` ではなく **全ファイル(`result.files`)由来のツリー**で行う。検索中に rescan が走ったとき一時的に隠れている dir が evict され、検索クリア後に折りたたみ意図が失われる回帰を解消
  - #2: `rescan` の reconcile(round-4 #6)に **`!sel.isExternal` ガード**を追加(`searchText.didSet` と対称)。TREE で rescan 時に EXTERNAL ピンが内部ファイルへすり替わり外部プレビューが消えるのを防ぐ
  - #3: key monitor で `charactersIgnoringModifiers` を **小文字に正規化**してから判定。Caps Lock 有効時に 'r' が 'R' になり reload/reveal どちらにも落ちず沈黙する問題を解消。reload と reveal は文字でなく修飾(`cmd && shift` か否か)で振り分ける

### M9(2026-06-24)
- **.icns**: `Support/icon/AppIcon.svg`(案 B モノグラム = HTML ブラケット + amber ドット、合成ベクタ・個人意匠なし)→ `scripts/build-icon.sh` で `qlmanage` → `sips` 派生 → `iconutil -c icns` → `Support/icon/AppIcon.icns` を生成。`scripts/build.sh` が Resources にコピー、`Info.plist` に `CFBundleIconFile=AppIcon`
- **Theme.swift**: `Spacing` / `Radius` 定数を追加(画面間の余白・角丸の一貫性)。既存の色 swatch はそのまま。**call site への配線(既存 View の literal padding / cornerRadius を定数へ置換)は M7 マージ後にまとめて行うフォローアップ**とし、本 PR では定数定義のみ(M9 review #1: 現状 call site ゼロ=未配線である旨を明示し premature にしない)。配線を M7 後に送るのは、M7 の TREE UI(`TreeRowsView` 等)も同じ定数を使うため、UI が出揃ってから一括置換する方が衝突・取りこぼしが少ないため
- **README.md**(新規): セットアップ・hook 連携・キー操作・既知の制約・開発コマンド・docs リンク・MIT。**README はアプリ完成形を記載**(hooks=M8 / j/k=M7 / EXTERNAL=M5 等)。M9 は全マイルストーンの最後にマージする前提のため、M7/M8 マージ時にその実体(`hooks/` ディレクトリ・`make test-hooks`・TREE/キー UI)が揃って README と整合する(M9 review #2: マージ順 M5・M6〔済〕→ M7 → M8 → M9)
- スコープ(率直): 本ブランチは **M5/M6 を含む**(マージ済み main 由来)。**未マージは M7(TREE/検索/キー)/ M8(hooks)**。M7 申し送りの「TREE 展開ポリシー UI 採用」は M7 PR #26 側で対応済み(本 M では扱わない)。M9 が触る UI は Theme 定数定義のみで、サイドバー/プレビューのモック比較ポリッシュは M7 マージ後の別アクションが妥当(docs/04 §5 M9 に申し送り)
- スコープ外: 配布パッケージ・公証(D2)、メニューバー常駐(`LSUIElement` は引き続き設定しない)
- **brush-up 第2ラウンド(2026-06-24・`/code-review high` 5 件)**: すべて採用
  - #1: `Theme.Radius.badge` を **4 → 3** に整合(`FileRowView`/`ContentView` の既存 `cornerRadius:3` と一致)。配線は M7 後フォローアップのままだが、値を既存と合わせて「定数を編集したのに見た目が変わらない」罠を解消
  - #2: `build-icon.sh` は `iconutil` 直前に `rm -f "$ICNS"`。iconutil 失敗(set -e 停止)時に**古い .icns が残らず消える** → 次回 `make install` の fail-loud(build.sh)で「再生成したのに古いまま」のサイレント不整合を検知できる
  - #3: `AppIcon.svg` ハイライト rect の `rx=200`(height=60)を実効 `rx=30` に明示。コメントと実描画の乖離を解消(.icns 再生成。差分は最上部 5% ハイライトの角丸のみで視覚影響は微小)
  - #4: `qlmanage` の `2>&1` を外し **stderr を残す**(SVG renderer 不在 / QuickLook エラーの原因を握りつぶさない)
  - #5: iconset を repo 内ではなく `WORK`(mktemp)配下に作成。再生成のたびに `Support/icon/AppIcon.iconset/` 残骸が残らない(trap で自動掃除)
  - `make icon` で 1024×1024 .icns 再生成・repo に iconset 残骸が出ないことを確認
- **brush-up 第3ラウンド(2026-06-24・`/code-review high` 7 件)**: すべて採用
  - #2: `build-icon.sh` で **BASE が 1024px であることを検証**(`sips -g pixelWidth`)。qlmanage が非 1024 を返したとき `sips -z 1024` が silent upscale して blurry な @2x が .icns 化されるのを fail-loud で防ぐ
  - #3: `Info.plist` の **`CFBundleVersion` を 1 → 2** に bump。アイコンのみ変更でも `(bundle id + version)` で効く Launch Services の icon cache を無効化し、同名上書き install で旧アイコンが残る誤診断を防ぐ(docs/04 §5 M9 #3 に `killall Dock Finder` のフォールバックも併記)
  - #4: `build.sh` の icns コピーを **`plutil -extract CFBundleIconFile`** で plist から導出。アイコン名の二重定義(plist と build.sh)を解消し契約一致を機械保証
  - #5: iconset の `@2x ≡ 次サイズ 1x`(例 16x16@2x = 32 = 32x32)の invariant を sips 二重生成から **`cp`** に置換(無駄な sips 削減 + 片方差し替えの誘惑を断つ)
  - #6: `README.md` 開発セクションに **`make icon`** を追加(SVG 編集者が .icns 再生成に気付けるよう露出)
  - #1: `Theme.Radius.button=6` に「design-mock-b 想定値・call site 不在のため未検証」を明示(badge の値整合ルールと一貫)
  - #7: `Theme.swift` / `AppIcon.svg` のコメントから `— M9 review #N` の process trail を剥離(実体ある rationale は残す。art asset は review より長生きするため)
  - `make icon` で再生成 .icns はバイト同一(cp ベース化でも内容不変)/ build/test/check 維持
- **brush-up 第4ラウンド(2026-06-24・`/code-review high` 5 件)**: すべて採用
  - #1: `build.sh` の icns コピーが `plutil ... || true` + `if [ -n ]` で **silent skip に退行**していたのを fail-loud に戻す。`CFBundleIconFile` 抽出失敗/空(plist 破損)は `exit 1`(generic アイコンで build 成功してしまうのを防ぐ)
  - #3: `ICON_NAME="${ICON_NAME%.icns}"` で末尾 `.icns` を strip。`CFBundleIconFile=AppIcon.icns`(拡張子付きも legal)に変えても `AppIcon.icns.icns` 衝突で誤 abort しない
  - #2: `build.sh` で **SVG が .icns より新しければ警告**(`-nt`)。`make install` 単独で旧 .icns が bundle される SVG-newer ドリフトに気付かせる(fail はしない。fresh clone は mtime 同値で false-warn しない)
  - #4: `build-icon.sh` の BASE 検証を **pixelHeight も**に拡張。非正方 viewBox の SVG で width=1024 / height≠1024 の letterbox アイコンが iconutil を通るのを防ぐ
  - #5: visual asset 変更時の **`CFBundleVersion` +1 ポリシーを明文化**(`build-icon.sh` 末尾のリマインダ + 本節)。自動 bump は no-op 再生成でも version を膨らませるため採らず、リマインダに留める。LS icon cache(bundle id + version)無効化のため**アイコン/SVG を変えたら CFBundleVersion を +1 する**(docs/04 §5 M9 #3 の killall フォールバックと併用)

(M10 以降、完了時に追記)
