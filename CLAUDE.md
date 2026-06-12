# local-html-viewer

Claude が生成する self-contained HTML を閲覧する macOS ネイティブアプリ「HTMLViewer」。SwiftUI + WKWebView。Xcode 非依存(SPM + CLT で `swift build` → .app バンドルをスクリプト手組み + ad-hoc 署名)。

## コマンド

- `make check` — セキュリティ検査(実パス混入 / .gitignore 検証)。**コミット前に必ず通す**。全マイルストーン共通ゲート
- `swift build` / `swift test` / `swift run` — ビルド・テスト・開発実行(M1 以降)
- `make install` — .app 組み立て → ad-hoc 署名 → `~/Applications` へ配置 → Launch Services 登録(M2 以降)

## 開発プロセス

- **マイルストーン(M0〜M9)ごとにユーザーの承諾を得る**。各 M の完了時に「実施内容・検証結果・次の予定」を報告し、承諾を得てから次へ進む。承諾なしに複数 M をまたがない
- **TDD(t_wada 流)**: 着手前にテストリストを書き、Red → Green → Refactor の小さなサイクル。判断ロジックは `HTMLViewerCore`(UI 非依存)に置いて `swift test` で駆動し、SwiftUI / WKWebView / odoc 境界は Humble Object として薄く保つ。コミットは Green ごとに小さく。詳細: `docs/04-verification.md`
- ドキュメント(`docs/01`〜`05`)は実装と並走して更新する。実装と乖離したらドキュメントを直す(実装が正)

## セキュリティ(公開リポジトリ — 違反は即インシデント)

要約(詳細と検知時手順: `.claude/rules/security.md`):

1. 機密値(API キー / トークン / 秘密鍵 / パスワード)をコード・docs・コミットメッセージ・ログ貼り付けに**絶対に含めない**。このプロジェクトに機密値は存在しないはずなので、現れたらそれ自体を異常として停止・報告する
2. `/Users` 始まりの実絶対パスを書かない → `~` / `$HOME` プレースホルダで書く(docs / example / コメント全て)
3. テスト fixture・スクリーンショット・README の例は**合成データのみ**。実在の個人生成 HTML を入れない
4. `~/.claude/settings.json` 等の実設定ファイルをコピーして example を作らない(example は最小手書き)
