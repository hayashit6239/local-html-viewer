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

## 進捗管理

各ステップ(マイルストーン M0〜M9、および CI / chore 等の付随ステップ)は **issue による仕様固め**フェーズと **PR による実装**フェーズを持つ。進捗のスナップショットは Claude のプロジェクトメモリに `plan-progress.json`(JSON)として保持し、issue / PR の状況が変わるたびに更新する。

各フェーズのステータスは、`plan-progress.json` 上では JSON の `null`(未着手) または以下の文字列(enum) **のみ**を取る:

- **issue(仕様固め)** — 8 段階(`completed review` 後に `ready for implementation` / `starting review work` へ分岐、review work 完了後は `waiting for review` に戻して再レビュー):
  `null` → `created issue` → `starting review` → `completed review` → (`ready for implementation` → `closed issue`(終端) | `starting review work` → `waiting for review` → `starting review` …)
- **PR(実装)** — 9 段階(`completed review` 後に `ready for merge` / `starting review work` へ分岐、review work 完了後は `waiting for review` に戻して再レビュー):
  `null` → [`implementation-ready`(任意の前段)] → `created pr` → `starting review` → `completed review` → (`ready for merge` → `merged pr`(終端) | `starting review work` → `waiting for review` → `starting review` …)

> 紛らわしいので注意: issue 側 `ready for implementation` は `completed review` 後の分岐点(必須)、PR 側 `implementation-ready` は `created pr` 前の任意の前段。役割が違う。

運用ルール:

- `null` = そのフェーズ未着手(対応する issue / PR が未作成)
- GitHub 上で **closed** の issue は review / brush-up の有無に関わらず `closed issue`(終端)、**merged** の PR は `merged pr`(終端)
- **issue を仕様の正**とし、PR 着手前に最新の issue を再読する(レビュー反映で仕様が更新されている場合があるため)
- レビューは AI エージェントに**コメントとして残させ、修正は当てさせない**。指摘は作者が検証してから採否を決める(誇張は正確に評価し直す)。詳細: `.github/copilot-instructions.md`
- **wrapper による status 自動進行**: `reviewing-untriaged-issues-for-loop`(issue 側、`reviewing-github-issues` skill)と `reviewing-untriaged-pr-for-loop`(PR 側、組み込み `/code-review` skill)は、レビュー対象を選別 → `starting review` に進めてからレビュー実行 → 判定で **`ready for implementation`(issue、has_blocker false)/ `ready for merge`(PR、findings 0 件)** or `completed review`(blocker / findings あり)に**自動進行**する。PR 側はマージ承認の可視化として GitHub の `merge ready` ラベルも同期付与/除去する(issue 側はラベルを使わない — 意図的な非対称)。`doer ≠ judge` 原則を破る代わりに作者の手動 status 進行を省ける(誤判定時は作者が `waiting for review` に巻き戻して再レビューさせる)。review work(旧 brush-up)後の再レビューは作者が `completed review` → `starting review work` → `waiting for review` と進めるだけで次回 loop が拾う(`lastReviewedStatus` の手動リセットは不要)

## セキュリティ(公開リポジトリ — 違反は即インシデント)

要約(詳細と検知時手順: `.claude/rules/security.md`):

1. 機密値(API キー / トークン / 秘密鍵 / パスワード)をコード・docs・コミットメッセージ・ログ貼り付けに**絶対に含めない**。このプロジェクトに機密値は存在しないはずなので、現れたらそれ自体を異常として停止・報告する
2. `/Users` 始まりの実絶対パスを書かない → `~` / `$HOME` プレースホルダで書く(docs / example / コメント全て)
3. テスト fixture・スクリーンショット・README の例は**合成データのみ**。実在の個人生成 HTML を入れない
4. `~/.claude/settings.json` 等の実設定ファイルをコピーして example を作らない(example は最小手書き)
