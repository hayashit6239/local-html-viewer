# HTMLViewer — ビルド・検証タスク
# build / test / install / run は M1 / M2 で追加する

.PHONY: check

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
