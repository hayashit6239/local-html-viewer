# 01. 要件定義書

最終更新: 2026-06-12(要件定義セッションで確定)

## 1. ジョブ(誰が・何のために)

Claude Code を日常的に使う開発者が、**Claude が生成した self-contained な HTML 成果物(レポート / ダッシュボード / ツール等)を、生成された端から・ディレクトリ単位で・ストレスなく閲覧し続ける**ためのビューアが欲しい。

現状の代替手段(ブラウザで個別に `open`、VS Code のプレビュー等)には「最新の生成物にすぐ届く動線」「変更への自動追従」「複数ディレクトリの横断」がなく、生成 → 確認のループに摩擦がある。

## 2. 確定要件

| 論点 | 決定 |
|---|---|
| 形態 | macOS ネイティブアプリ(SwiftUI + WKWebView)。通常の Dock アプリ(メニューバー常駐なし) |
| ビルド環境 | Xcode 非依存。SPM + Command Line Tools(`swift build`)+ .app バンドル手組み + ad-hoc 署名 |
| 対象ファイル | `.html` / `.htm` のみ |
| ディレクトリ | UI(NSOpenPanel)からフォルダを随時追加。複数登録・永続化。FUSE 等の本当のマウントは不要 |
| 必須機能 | RECENT(更新日時降順)/ TREE の 2 タブ、ファイル名インクリメンタル検索、live reload、起動時最新ファイル自動表示、Finder reveal、キーボード操作(j/k 移動・`/` 検索・r リロード) |
| Claude Code 連携 | hook が `.html` 生成を検知し、フォーカスを奪わずにアプリへ自動表示(`open -g -b <bundle id>`)。hook も本リポジトリの成果物 |
| デザイン | アンバー × macOS ネイティブ・ハイブリッド(モック 3 案から選定。`docs/assets/design-mock-b.html`) |
| 配布 | ローカルビルド・ローカル利用のみ(公証 / 配布パッケージはスコープ外) |
| リポジトリ | 公開。セキュリティ規約は `.claude/rules/security.md` |

## 3. 非機能要件・制約

- **ローカル完結**: アプリ本体はネットワーク通信ゼロ。外部 API・テレメトリ・web フォントなし。依存はシステムフレームワークのみ(サードパーティライブラリゼロ)
- **走査の安全弁**: ignore ディレクトリ(`.git`, `node_modules`, `__pycache__`, `.venv`, `venv`, `.next`, `.cache`, `dist`, `build`, `.idea`, `.vscode`, 隠しディレクトリ)、最大ファイル数上限
- 環境前提: macOS 15+(開発環境は macOS 26)/ Apple Silicon / Swift 6.x toolchain(CLT)

## 4. スコープ外(明示的に作らないもの)

- Markdown / 画像 / PDF のレンダリング(HTML のみ)
- メニューバー常駐、LaunchAgent による常駐起動
- FUSE 的な仮想ファイルシステム
- 配布用パッケージング(公証・Sparkle 等)
- Bash ツール(heredoc 等)経由で生成された HTML の hook 検知

## 5. 将来拡張(布石のみ実装)

**自然言語検索**: 段階 1 = SQLite FTS5(trigram)全文検索 → 段階 2 = embeddings によるセマンティック検索(数千件規模なら総当たりコサインで十分)→ 段階 3 = オンデバイス LLM(Foundation Models)でのクエリ展開・リランク。初期実装に入れる布石は ①検索ロジックの `SearchProvider` 抽象化 ②ファイル監視イベントストリームを将来インデクサも購読できる形にする、の 2 点のみ。

## 6. 経緯

旧計画(別リポジトリの PLAN.md、Python ローカルサーバー + ブラウザ SPA 案)を要件定義で見直し、形態をネイティブアプリに変更して本リポジトリで新規開発する。主要な判断の記録は `05-decisions.md`。
