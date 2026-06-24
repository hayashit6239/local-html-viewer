# HTMLViewer

Claude が生成する self-contained な HTML を、ディレクトリ単位でストレスなく閲覧・追従する **macOS ネイティブアプリ**。
SwiftUI + WKWebView、Xcode 非依存(SPM + Command Line Tools のみで `swift build` → `.app` バンドル手組み + ad-hoc 署名)。

- 主動線: Claude Code が `.html` を生成 → hook 経由でアプリが自動表示 → ライブリロードで追従
- ローカル完結: アプリ本体はネットワーク通信ゼロ(表示する HTML が外部リソースを参照するときのみ WKWebView が取得 = コンテンツ起因)
- 公開リポジトリ: 機密値・実パス・個人データを持ち込まない(`.claude/rules/security.md`)

リファレンスデザイン: [`docs/assets/design-mock-b.html`](docs/assets/design-mock-b.html)(案 B「アンバー × macOS ネイティブ・ハイブリッド」)

## セットアップ

前提: macOS 15+、Apple Silicon、Command Line Tools(`xcode-select --install`)。

```bash
git clone https://github.com/hayashit6239/local-html-viewer.git
cd local-html-viewer
make install   # build → ad-hoc 署名 → ~/Applications へ配置 → Launch Services 登録
open -a HTMLViewer
```

起動したら、サイドバー左上の **+** から登録したいフォルダ(例: `~/Codes/claude/`)を選択 → RECENT に `.html` が更新日時降順で並びます。

## Claude Code hook 連携(自動表示)

`hooks/settings.json.example` を **`~/.claude/settings.json` にマージ**(全置換ではなく既存に追記)します:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/Codes/local-html-viewer/hooks/open-html.sh"
          }
        ]
      }
    ]
  }
}
```

Claude Code を再起動すると、`.html` / `.htm` の Write/Edit/MultiEdit 直後に `open -g -b com.hayashi.htmlviewer <file>` がエディタのフォーカスを奪わずに呼ばれます。同一ファイルの 5 秒以内の連打は抑止します(`~/.cache/htmlviewer/last-open`)。

`open -b` で渡されたファイルが**登録フォルダ外**なら、RECENT 先頭に EXTERNAL バッジ付きでピン留めして即プレビューします(フォルダの自動登録はしません)。

## キー操作

サイドバーにフォーカスがあるとき:

| キー | 動作 |
|---|---|
| `↑` `↓` / `j` `k` | 選択移動(即プレビュー、端はクランプ) |
| `/` | 検索フィールドへフォーカス |
| `Esc` | 検索クリア・リストへフォーカス復帰 |
| `r` | 表示中ファイルを再読込 |
| `⌘⇧R` | Finder で表示 |

検索フィールドにフォーカスがある間は `j`/`k`/`r` はテキスト入力として扱われます(ビューア操作にしない)。

## 既知の制約

- **ローカル配布のみ**: 公証 / Sparkle 配布パッケージはスコープ外(`docs/05-decisions.md` D2)
- **Bash heredoc 経由の HTML 生成は hook 検知不可**: matcher は `Write|Edit|MultiEdit` のみ(誤発火増を避ける、`docs/02-specification.md` §4)
- **TCC のサイレント失効**: ad-hoc 再署名で CDHash が変わると `~/Documents` 等への許可が失効しうる。アプリ側で「在るのに 0 件 かつ TCC 保護領域」を検知して再許可導線を出すが、自動付与はできない(`docs/03-implementation.md` §4)
- **`file://` の `fetch`/XHR は CORS で失敗**: self-contained な HTML を前提とする
- **スクロール位置の復元はベストエフォート**: 重い JS レンダリングのページでは完全に戻らないことがある(`docs/02-specification.md` §5)

## 開発

```bash
make build         # swift build
make test          # Swift Testing(CLT 環境で動くよう -F/-rpath を固定)
make test-hooks    # hooks/open-html.sh の入力解析・スロットルを JSON fixture で検証
make check         # 実パス混入・.gitignore 機能の機械的検証(コミット前ゲート)
make run           # 直起動(オープンイベント / TCC / UserDefaults はバンドル版とドメインが異なるため検証用は make install)
make install       # 上記セットアップに同じ
make icon          # Support/icon/AppIcon.svg 編集後の .icns 再生成(.icns は checked-in binary)
```

詳細ドキュメント:

- [`docs/01-requirements.md`](docs/01-requirements.md) — 要件定義
- [`docs/02-specification.md`](docs/02-specification.md) — 仕様(挙動・キー・連携)
- [`docs/03-implementation.md`](docs/03-implementation.md) — 実装書(ターゲット構成・技術判断・マイルストーン記録)
- [`docs/04-verification.md`](docs/04-verification.md) — 検証計画・マイルストーン別検証ゴール・手動チェックリスト
- [`docs/05-decisions.md`](docs/05-decisions.md) — 設計判断記録(ADR ライト、D1〜D9)

開発プロセス(マイルストーン承諾制・TDD・進捗管理ルール)は [`CLAUDE.md`](CLAUDE.md) を参照。

## ライセンス

[MIT](LICENSE)
