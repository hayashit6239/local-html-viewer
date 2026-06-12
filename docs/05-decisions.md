# 05. 設計判断記録(ADR ライト)

追記式。1 判断 = 1 節。形式: 決定 / 理由 / 代替案と捨てた理由。

## D1: ネイティブ macOS アプリとして作る(2026-06-12)

- **決定**: SwiftUI + WKWebView のネイティブアプリ。
- **理由**: Dock 常駐・D&D・OS 統合(`open` 連携)の体験を重視するユーザー判断。実装コストがサーバー案の数倍になることを提示した上で選択された。
- **代替案**: ① Python ローカルサーバー + ブラウザ SPA(旧計画。最速・依存ゼロだがアプリ感なし)② Tauri / Electron(toolchain が重くオーバースペック)。

## D2: Xcode を使わず SPM + CLT + 手組み .app バンドル(2026-06-12)

- **決定**: `swift build` でビルドし、.app バンドルをスクリプトで組み立て、ad-hoc 署名する。
- **理由**: Xcode 未インストール環境(CLT のみ)で完結する。全工程がターミナルで完結するため AI エージェントによるビルド・検証の反復と相性が良い。
- **代替案**: Xcode インストール(約 12GB+。Previews 等は得られるが本規模には過剰)。
- **トレードオフ**: Previews / asset catalog / XCUITest 不可。E2E はバンドル版での手動検証ゴールで代替。

## D3: デザインは案 B「アンバー × macOS ネイティブ・ハイブリッド」(2026-06-12)

- **決定**: macOS の作法(vibrancy 風 sidebar / セグメント / 角丸 / SF Pro)に琥珀色アクセント。ファイル名のみモノスペース。リファレンス: `assets/design-mock-b.html`。
- **理由**: HTML モック 3 案(A: 全面ターミナル風 / B: ハイブリッド / C: CRT マキシマム)を比較し、ネイティブという形態選択との整合性と SwiftUI 実装コストの低さで B を選定。
- **代替案**: A は旧ブラウザ SPA 前提のデザインの引き継ぎ、C は日常の道具には装飾過多。

## D4: ファイル監視は FSEvents(2026-06-12)

- **決定**: `FSEventStreamCreate`(パス配列・再帰)1 本で全登録フォルダを監視。
- **理由**: 複数ルートの再帰監視を 1 ストリームで実現でき、エディタ / Claude のアトミック保存(temp 書き込み → rename)でも追跡が切れない。
- **代替案**: ① DispatchSource(fd 単位・非再帰で大量 fd が必要、rename に弱い)② ポーリング(遅延と無駄が大きい。最終フォールバックとしてのみ)。

## D5: 開発は t_wada 流 TDD + Humble Object(2026-06-12)

- **決定**: テストリスト → Red → Green → Refactor。判断ロジックは `HTMLViewerCore` に置き `swift test` で駆動。テスト不能な境界(SwiftUI / WKWebView / オープンイベント / TCC)は薄い殻に隔離。
- **理由**: ユーザー指定の開発方針。GUI アプリで「全部 TDD」は自己欺瞞になるため、テスト境界を明示する(`04-verification.md`)。

## D6: 公開リポジトリ統治を最優先で整備(2026-06-12)

- **決定**: M0 で CLAUDE.md / security rules / .gitignore / LICENSE(MIT)/ `make check` を実装の前に整備。コミット author は GitHub noreply。
- **理由**: git 履歴は不可逆。本プロジェクトは機密値を必要としない設計のため、現実的な漏洩経路(実パス / 個人 artifact / 実設定ファイル / コミットメタデータ)を構造(L3)+ 指示(L1)で塞ぐ。
- **補強**: public 化時に GitHub Secret scanning + Push protection を有効化。

## D7: hook は `open -g -b <bundle id>`(2026-06-12)

- **決定**: Claude Code の PostToolUse hook から `open -g -b com.hayashi.htmlviewer` で渡す。
- **理由**: `-b`(bundle id)はアプリ名衝突に強い(「HTMLViewer」は一般名詞)。`-g` はフォーカスを奪わず、生成のたびに前面に出る煩わしさを避ける。連打は hook 側 5 秒スロットル + アプリ側 no-op の二重で抑止。

## D8: 自然言語検索は将来送り、布石のみ(2026-06-12)

- **決定**: 初期はファイル名検索のみ。`SearchProvider` 抽象と監視イベントストリームの汎用化だけ入れる。
- **理由**: 段階的に FTS5 → embeddings → オンデバイス LLM リランクへ育てられる構造を確認済み(数千件規模ならベクトル DB 不要)。初回リリースを遅らせる価値がない。
