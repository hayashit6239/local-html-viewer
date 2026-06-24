# 04. 検証計画書

最終更新: 2026-06-16(M3 再レビュー反映: 手動検証チェックリスト §5 を追加)

## 1. 開発・検証方針(TDD)

- **t_wada 流 TDD**: 着手前にテストリストを書き出し、Red(失敗するテストを先に書く)→ Green(仮実装で通す)→ Refactor の小さなサイクル。実装戦略は 仮実装 → 三角測量 → 明白な実装 を使い分ける。コミットは Green ごとに小さく
- **進行プロセス**: マイルストーンごとに検証ゴールを満たし、ユーザーの承諾を得てから次へ進む

## 2. テスト境界(何を自動テストし、何をしないか)

| 区分 | 対象 | 手段 |
|---|---|---|
| `swift test` でカバー | 走査・ignore 規則・ソート・検索・ツリー構築・選択移動・永続化コーデック・外部オープンポリシー | Swift Testing(単体) |
| 〃(統合) | FileWatcher(FSEvents) | temp dir に書き込み → イベント受信を timeout 付きで検証。flaky 時は 1 回リトライ。**M6 着手時は本実装前に最初のスモークで CLT+ad-hoc 環境での FSEvents 実動を実証する**(未実証の継承を断つ。05 D4) |
| 自動テスト不能 | SwiftUI 描画 / オープンイベント配送 / TCC / WKWebView 表示・スクロール復元 | マイルストーンの手動検証ゴール(下表)で担保 |
| セキュリティ | 実パス混入 / .gitignore 機能 | `make check`(全 M 共通ゲート) |
| hook | open-html.sh の入力処理・スロットル | `scripts/test-hooks.sh`(JSON fixture を流す) |

## 3. マイルストーン別 検証ゴール

| M | 内容 | 検証ゴール | 結果 |
|---|---|---|---|
| M0 | リポジトリ統治 + docs 基盤 | `make check` が 0 / 初回コミットに統治・docs のみ | ✅ 2026-06-12 |
| M1 | SPM 3 ターゲット + 空ウィンドウ + ダミーテスト | `swift build && swift run` でウィンドウ表示 / `make test` が 0(Swift Testing の CLT 動作確認) | ✅ 2026-06-12(素の `swift test` は CLT で不動作 → `make test` にフラグ固定化。詳細: 03 §5 M1) |
| M2 | Info.plist + build.sh + Makefile 拡張 | `make install && open -a HTMLViewer` で起動 / `codesign -dv` が通る | ✅ 2026-06-12(`open -b` の単一インスタンス配送も確認。詳細: 03 §5 M2) |
| M2.5 | オープンイベント受信スモーク(最大リスク前倒し) | 未起動で `open -b com.hayashi.htmlviewer <合成.html>` → 受信パスがバナー表示 / 起動中再実行でプロセス数 1(`pgrep -x HTMLViewer \| wc -l`) | ✅ 2026-06-18(`OpenEventPolicy` 5 テスト → 計 33 green。バンドル版で odoc 受信を実機確認: コールド起動受信〔odoc は didFinishLaunching 前に到達 → バッファ→drain〕・単一インスタンス・連続受信で二重なし・異常系クラッシュなし。`application(_:open:)` が発火し plan B 不要。§5 に記録) |
| M3 | 走査 + RECENT リスト + フォルダ登録永続化 | 登録 → mtime 降順表示 / 再起動で保持 / node_modules 除外 / `swift test` 0 | ✅ 2026-06-15(Core テスト green。走査→ソートの受け入れ条件をテスト化)。2026-06-16 再レビュー反映: ignore case-insensitive 化・TCC 検知/案内・A-1 撤退基準(05 D9)を追加し Core 27 テスト green。GUI 手動検証は §5 チェックリストで担保 |
| M4 | WKWebView プレビュー + 起動時最新表示 + reveal + JS パネル | クリックでプレビュー / 起動直後に最新表示 / `alert()` fixture でダイアログ表示 | ✅ 2026-06-17(`NavigationPolicy` 5 テスト → 計 33 green、build/起動スモーク OK。レンダリング・JS ダイアログ・reveal は §5 手動チェックリストで担保) |
| M5 | 外部オープン完成(EXTERNAL ピン留め・一時監視) | M2.5 + 表示まで一気通貫 / Dock アイコン D&D でも開く | — |
| M6 | FileWatcher + live reload + スクロール維持 | 表示中ファイルへ追記 → 1 秒以内に再描画・位置維持 / 新規 .html がリスト出現 / `swift test` 0 | — |
| M7 | TREE タブ + 検索 + キーボード | 各キー仕様通り / 検索フォーカス中の j/k はテキスト入力 / 展開ポリシー UI 配線 / `swift test` 0 | ✅ 2026-06-24(`TreeBuilder`(`expansionSet` 含む)/`SearchProvider`/`SelectionLogic` 計 64 green、build/起動スモーク OK。セグメント・検索・DisclosureGroup 展開・キー操作の目視は §5)|
| M8 | hook + settings example | `scripts/test-hooks.sh` が 0 / 実セッションで Write → 自動表示 | — |
| M9 | デザイン仕上げ + .icns + README | モック比較の目視 / `make check` / README 言語確認 | — |

## 4. 検証実行の注意

- バンドル挙動(オープンイベント / TCC / UserDefaults)の検証は必ず `make install` 後のバンドル版で行う
- 検証用 HTML fixture は全て合成データ(`.claude/rules/security.md` 規約 3)

## 5. 手動検証チェックリスト

`swift test` が閉じられない GUI / TCC / バンドル境界は、ここで「実施した」記録を残して*完了の真正性*を担保する。実施は **必ず `make install` 後のバンドル版**で行い、合成データのみ使う。各 M 完了時に該当ブロックを埋める(チェック + 実施日)。

### M3: 走査 + RECENT リスト + フォルダ登録永続化(テンプレ)

| # | 項目 | 手順 | 期待 | 結果 |
|---|---|---|---|---|
| 1 | フォルダ登録 | サイドバー「＋」→ 合成 HTML を含むフォルダを選択 | RECENT に `.html` が mtime 降順で並ぶ | ⬜ |
| 2 | 複数フォルダ統合 | 2 つ目のフォルダを登録 | 両者が 1 つの RECENT に統合され重複なし | ⬜ |
| 3 | 再起動保持 | アプリ quit → 再起動 | 登録フォルダと RECENT が復元される | ⬜ |
| 4 | ignore 除外 | `node_modules` 配下に HTML を置く | 一覧に出ない | ⬜ |
| 5 | stale 表示 | 登録フォルダをリネーム / 外付けを unmount | 「見つかりません」表示・登録は維持 | ⬜ |
| 6 | TCC 検知/案内 | `tccutil reset SystemPolicyDocumentsFolder com.hayashi.htmlviewer` 後に `~/Documents` 配下を登録 | 「アクセス許可」導線が出る → クリックで設定が開く | ⬜ |
| 7 | 空状態 | `.html` 0 件のフォルダ(保護領域外)を登録 | クラッシュせず空のまま(案内は出ない) | ⬜ |

> 記録例: 各行の「結果」を `✅ 2026-06-NN` で置換し、特記事項があれば脚注を添える。

### M2.5: オープンイベント受信スモーク

実施: 2026-06-18(`make install` 後のバンドル版・合成 HTML)。

| # | 項目 | 手順 | 期待 | 結果 |
|---|---|---|---|---|
| 1 | コールド起動受信 | アプリ未起動で `open -b com.hayashi.htmlviewer <合成.html>` | 起動し受信パスがバナー表示(odoc は `didFinishLaunching` 前に到達 → バッファ→drain) | ✅ 2026-06-18 |
| 2 | 単一インスタンス | 起動中に再度 `open -b ... <合成.html>` | `pgrep -x HTMLViewer \| wc -l` が 1 | ✅ 2026-06-18 |
| 3 | 連続受信で二重なし | 続けて別 `.html` を open | `receivedPaths` が最新で置換(重複しない) | ✅ 2026-06-18 |
| 4 | 異常系 | 非 `.html` / 存在しないパスを open | クラッシュせず無視 | ✅ 2026-06-18 |
| 5 | Dock D&D | Dock アイコンへ `.html` をドロップ | 同経路で受信・バナー表示 | ⬜(GUI 手動) |

> 注: odoc 発火の確認は `NSLog` が `log show` で安定捕捉できず、一時センチネルファイル(検証後削除)で実施。`application(_:open:)` は SwiftUI ライフサイクルでも発火し plan B(`kAEOpenDocuments` / `.onOpenURL`)は不要だった。

### M7: TREE タブ + 検索 + キーボード

実施: 2026-06-23(`make install` 後のバンドル版・合成 HTML)。Core は `make test` で担保。

| # | 項目 | 手順 | 期待 | 結果 |
|---|---|---|---|---|
| 1 | セグメント切替 | 「最近」「ツリー」を切替 | RECENT(mtime 降順)/ TREE(階層)が切り替わる・選択維持 | ⬜(GUI 目視) |
| 2 | 検索 | 検索フィールドに入力 | 両タブが即時フィルタ・ヒット 0 件でも破綻しない | ⬜(GUI 目視) |
| 3 | `/` フォーカス | リストフォーカス時に `/` | 検索フィールドへフォーカス | ⬜(GUI 目視) |
| 4 | Esc クリア | 検索入力中に Esc | クエリクリア + リストへ復帰 | ⬜(GUI 目視) |
| 5 | j/k 移動 | リストで j/k | 選択が上下移動し即プレビュー(端クランプ) | ⬜(GUI 目視) |
| 6 | 検索中の透過 | 検索フォーカス中に j/k/r | テキスト入力として扱う(ビューア操作にならない) | ⬜(GUI 目視) |
| 7 | r / ⌘⇧R | リストで `r` / `⌘⇧R` | 再読込 / Finder 表示(未選択なら no-op) | ⬜(GUI 目視) |
| 8 | TREE 展開 | ツリータブで dir | DisclosureGroup で階層展開/折りたたみ・leaf 選択で即プレビュー | ⬜(GUI 目視) |
| 9 | 既定展開ポリシー | dir 総数 ≤ 40 / > 40 のフォルダで TREE 起動 | ≤40 は全展開・>40 は第一階層のみ展開 | ⬜(GUI 目視) |
| 10 | 親 dir 自動展開 | 折りたたみ dir 内の leaf を検索/選択で指す | 親 dir が自動展開され選択が可視化 | ⬜(GUI 目視) |
| 11 | 折りたたみ中の j/k | dir を折りたたんで j/k 移動 | 折りたたみ dir 配下の leaf は飛ばす(可視 leaf のみ移動) | ⬜(GUI 目視) |

> 注: Core(`TreeBuilder`/`SearchProvider`/`SelectionLogic`、展開合成 `expansionSet` 含む)は `make test` で閉じる。キーモニタ・@FocusState・DisclosureGroup 展開 UX の体感は GUI 手動。展開ポリシー(>40 第一階層のみ / 親 dir 自動展開 / 検索ヒット展開)は M7 brush-up(2026-06-24)で UI 配線済み(Core `expansionSet` + 再帰 `DisclosureGroup`)。
