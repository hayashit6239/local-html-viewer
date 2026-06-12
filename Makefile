# HTMLViewer — ビルド・検証タスク
# install(.app バンドル組み立て)は M2 で追加する

.PHONY: build test run check

# CLT 環境では swift test に Testing.framework の検索パスが自動で渡らないため明示する
# (素の `swift test` は "no such module 'Testing'" で失敗する — docs/03-implementation.md §5)
DEVELOPER_DIR_PATH := $(shell xcode-select -p 2>/dev/null)
TESTING_ROOT := $(if $(DEVELOPER_DIR_PATH),$(DEVELOPER_DIR_PATH),/Library/Developer/CommandLineTools)
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

# セキュリティ検査(.claude/rules/security.md の機械的検証)
# - 実パス([/]Users[/] — パターン自体が自己マッチしないよう文字クラスで表記)の混入検知
# - .gitignore が危険物を実際に無視しているかの検証
check:
	@matches=$$(grep -rEn '[/]Users[/]' . --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist || true); \
	if [ -n "$$matches" ]; then \
		echo "NG: 実パスが混入しています:"; echo "$$matches"; exit 1; \
	fi
	@for f in .env dist/x .DS_Store .build/x secret.pem; do \
		git check-ignore -q "$$f" || { echo "NG: $$f が .gitignore で無視されていません"; exit 1; }; \
	done
	@echo "check OK"
