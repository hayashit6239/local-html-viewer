# HTMLViewer — ビルド・検証タスク

.PHONY: build test run install check icon

# CLT 環境では swift test に Testing.framework の検索パスが自動で渡らないため明示する
# (素の `swift test` は "no such module 'Testing'" で失敗する — docs/03-implementation.md §5)
# フォールバック先は macOS 標準のシステムディレクトリであり、ユーザー実パスではない
TESTING_ROOT := $(shell dev="$$(xcode-select -p 2>/dev/null)"; \
	if [ -n "$$dev" ] && [ -d "$$dev/Library/Developer/Frameworks" ]; then \
		printf '%s' "$$dev"; \
	else \
		printf '%s' /Library/Developer/CommandLineTools; \
	fi)
TESTING_FW := $(TESTING_ROOT)/Library/Developer/Frameworks
TESTING_LIB := $(TESTING_ROOT)/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F$(TESTING_FW) \
	-Xlinker -F$(TESTING_FW) \
	-Xlinker -rpath -Xlinker $(TESTING_FW) \
	-Xlinker -rpath -Xlinker $(TESTING_LIB)

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# 開発用の直接実行。オープンイベント / TCC / UserDefaults の検証には使えない
# (バンドル版と挙動が異なる — docs/03-implementation.md §4)
run:
	swift run

# Support/icon/AppIcon.svg → .icns 再生成(SVG 編集後に実行。.icns は checked-in binary)
icon:
	bash scripts/build-icon.sh

# .app 組み立て → ad-hoc 署名 → ~/Applications へ配置 → Launch Services 登録
install:
	bash scripts/build.sh

# セキュリティ検査(.claude/rules/security.md の機械的検証)
# - 実パス([/]Users[/] — パターン自体が自己マッチしないよう文字クラスで表記)の混入検知
# - .gitignore が危険物を実際に無視しているかの検証
#
# 走査対象は git の追跡対象 + 未追跡(ただし .gitignore 除外後)= 「コミットされうるファイル」のみ。
# git ls-files --exclude-standard により、.claude/settings.local.json 等の gitignore 済みローカル設定
# (実パスを含むが決してコミットされない)を誤検知しない。-I はバイナリをスキップ。
check:
	@matches=$$(git ls-files --cached --others --exclude-standard -z \
		| xargs -0 grep -nEI '[/]Users[/]' 2>/dev/null || true); \
	if [ -n "$$matches" ]; then \
		echo "NG: 実パスが混入しています:"; echo "$$matches"; exit 1; \
	fi
	@for f in .env dist/x .DS_Store .build/x secret.pem; do \
		git check-ignore -q "$$f" || { echo "NG: $$f が .gitignore で無視されていません"; exit 1; }; \
	done
	@echo "check OK"
