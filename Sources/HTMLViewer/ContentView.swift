import HTMLViewerCore
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 300)
            Divider().overlay(Color.white.opacity(0.08))
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.background)
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
                    Text("in")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                    Text(file.rootPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().overlay(Color.white.opacity(0.08))

                // プレビュー本体は M4(WKWebView)。M3 ではプレースホルダ。
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.textFaint)
                    Text(file.relativePath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Text("プレビューは M4 で実装")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
