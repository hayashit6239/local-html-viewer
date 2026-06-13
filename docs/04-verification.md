# 04. 検証計画書

最終更新: 2026-06-12(M0 結果を記録)

## 1. 開発・検証方針(TDD)

- **t_wada 流 TDD**: 着手前にテストリストを書き出し、Red(失敗するテストを先に書く)→ Green(仮実装で通す)→ Refactor の小さなサイクル。実装戦略は 仮実装 → 三角測量 → 明白な実装 を使い分ける。コミットは Green ごとに小さく
- **進行プロセス**: マイルストーンごとに検証ゴールを満たし、ユーザーの承諾を得てから次へ進む

## 2. テスト境界(何を自動テストし、何をしないか)

| 区分 | 対象 | 手段 |
|---|---|---|
| `swift test` でカバー | 走査・ignore 規則・ソート・検索・ツリー構築・選択移動・永続化コーデック・外部オープンポリシー | Swift Testing(単体) |
| 〃(統合) | FileWatcher(FSEvents) | temp dir に書き込み → イベント受信を timeout 付きで検証。flaky 時は 1 回リトライ |
| 自動テスト不能 | SwiftUI 描画 / オープンイベント配送 / TCC / WKWebView 表示・スクロール復元 | マイルストーンの手動検証ゴール(下表)で担保 |
| セキュリティ | 実パス混入 / .gitignore 機能 | `make check`(全 M 共通ゲート) |
| hook | open-html.sh の入力処理・スロットル | `scripts/test-hooks.sh`(JSON fixture を流す) |

## 3. マイルストーン別 検証ゴール

| M | 内容 | 検証ゴール | 結果 |
|---|---|---|---|
| M0 | リポジトリ統治 + docs 基盤 | `make check` が 0 / 初回コミットに統治・docs のみ | ✅ 2026-06-12 |
| M1 | SPM 3 ターゲット + 空ウィンドウ + ダミーテスト | `swift build && swift run` でウィンドウ表示 / `make test` が 0(Swift Testing の CLT 動作確認) | ✅ 2026-06-12(素の `swift test` は CLT で不動作 → `make test` にフラグ固定化。詳細: 03 §5 M1) |
| M2 | Info.plist + build.sh + Makefile 拡張 | `make install && open -a HTMLViewer` で起動 / `codesign -dv` が通る | — |
| M2.5 | オープンイベント受信スモーク(最大リスク前倒し) | 未起動で `open -b com.hayashi.htmlviewer /tmp/t.html` → 受信パスが表示される / 起動中再実行でプロセス数 1(`pgrep -x HTMLViewer \| wc -l`) | — |
| M3 | 走査 + RECENT リスト + フォルダ登録永続化 | 登録 → mtime 降順表示 / 再起動で保持 / node_modules 除外 / `swift test` 0 | — |
| M4 | WKWebView プレビュー + 起動時最新表示 + reveal + JS パネル | クリックでプレビュー / 起動直後に最新表示 / `alert()` fixture でダイアログ表示 | — |
| M5 | 外部オープン完成(EXTERNAL ピン留め・一時監視) | M2.5 + 表示まで一気通貫 / Dock アイコン D&D でも開く | — |
| M6 | FileWatcher + live reload + スクロール維持 | 表示中ファイルへ追記 → 1 秒以内に再描画・位置維持 / 新規 .html がリスト出現 / `swift test` 0 | — |
| M7 | TREE タブ + 検索 + キーボード | 各キー仕様通り / 検索フォーカス中の j/k はテキスト入力 / `swift test` 0 | — |
| M8 | hook + settings example | `scripts/test-hooks.sh` が 0 / 実セッションで Write → 自動表示 | — |
| M9 | デザイン仕上げ + .icns + README | モック比較の目視 / `make check` / README 言語確認 | — |

## 4. 検証実行の注意

- バンドル挙動(オープンイベント / TCC / UserDefaults)の検証は必ず `make install` 後のバンドル版で行う
- 検証用 HTML fixture は全て合成データ(`.claude/rules/security.md` 規約 3)
