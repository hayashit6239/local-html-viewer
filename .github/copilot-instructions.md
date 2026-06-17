# Copilot 指示

Claude が生成する self-contained HTML を閲覧する macOS ネイティブアプリ。
SwiftUI + WKWebView、Xcode 非依存(SPM + Command Line Tools)。**公開リポジトリ**。

## レビューの振る舞い(最重要)

- **レビューはコメントのみで行う。コード修正のコミット・push をしない。**
  改善は suggestion ブロックまたは指摘コメントとして残し、適用するかは作者が判断する
- コメントは日本語で書く
- 修正や不具合を主張するときは、実際に問題が再現する具体条件を示す。
  検証していない場合は「未検証」と明記し、「〜で失敗し得る」という推測の断定を避ける

## 最優先の観点(セキュリティ — `.claude/rules/security.md`)

- 機密値(API キー / トークン / 秘密鍵 / パスワード)の混入
- `/Users` 始まりの実絶対パスの混入(`~` / `$HOME` で書くべき)
- 実在の個人生成 HTML・個人データの混入

## このプロジェクト固有の前提(指摘しないもの)

- Xcode 非依存(CLT のみ)は意図的な設計判断(`docs/05-decisions.md` D2)。
  Xcode 前提の改善提案・「Xcode を使えば」は不要
- マイルストーン単位の開発(`docs/04-verification.md`)。現在の PR スコープ外の
  未実装機能を「足りない」と指摘しない
- サードパーティ依存ゼロ方針。ライブラリ追加の提案は慎重に

## コード観点

- 判断ロジックは UI 非依存の `HTMLViewerCore` に置く(Humble Object)。
  `Sources/HTMLViewer`(SwiftUI / WKWebView 層)に判断ロジックが直書きされていたら
  `HTMLViewerCore` への分離を提案する
- Swift 6 strict concurrency / MainActor 隔離の前提を踏まえる
