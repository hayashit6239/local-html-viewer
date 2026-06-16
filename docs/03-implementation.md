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

(M2.5 以降、完了時に追記)
