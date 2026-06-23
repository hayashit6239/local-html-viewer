import HTMLViewerCore
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            if let unreadable = app.unreadableExternalPath {
                unreadableBanner(unreadable)
            }
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 300)
                Divider().overlay(Color.white.opacity(0.08))
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.background)
    }

    /// M5: 受信したが読めない(canonicalPath nil / TCC 等)外部ファイルの通知(ピンはしない)。
    private func unreadableBanner(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.amber)
            Text("読めない外部ファイル:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.amber.opacity(0.08))
        .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.08)) }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let file = app.selectedFile {
            VStack(spacing: 0) {
                // topbar(現在ファイル)
                HStack(spacing: 8) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if file.isExternal {
                        Text("EXTERNAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.amber.opacity(0.5)))
                    }
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                    Text(file.rootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    topbarButton("arrow.clockwise", help: "再読込") { app.reloadPreview() }
                    topbarButton("magnifyingglass", help: "Finder で表示") { app.revealInFinder(file) }
                    topbarButton("safari", help: "ブラウザで開く") { app.openInBrowser(file) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider().overlay(Color.white.opacity(0.08))

                // プレビュー本体(WKWebView)。背景白でコンテンツ忠実。
                WebViewContainer(file: file, reloadToken: app.reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        } else {
            VStack(spacing: 8) {
                Text("HTMLViewer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(app.folders.isEmpty ? "左上の + でフォルダを追加" : "ファイルを選択")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func topbarButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textDim)
        .help(help)
        .accessibilityLabel(help)  // アイコンのみ Button は help だけだと VoiceOver にラベルが伝わらない
    }
}
