import AppKit
import HTMLViewerCore
import SwiftUI

/// 左サイドバー: 登録フォルダ管理 + RECENT リスト。
struct SidebarView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(alignment: .leading, spacing: 0) {
            // ── フォルダ ──
            HStack {
                Text("フォルダ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button(action: pickFolder) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim)
                .help("フォルダを追加")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if app.folders.isEmpty {
                Text("フォルダを追加してください")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                ForEach(app.folders, id: \.path) { folder in
                    folderRow(folder)
                }
            }

            Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 8)

            // ── RECENT ──
            Text("最近")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            List(selection: $app.selectedFile) {
                ForEach(app.recentFiles) { file in
                    FileRowView(file: file, isSelected: app.selectedFile?.id == file.id)
                        .tag(Optional(file))
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // ── フッタ ──
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 6) {
                Circle().fill(Theme.live).frame(width: 6, height: 6)
                Text(footerText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(Theme.background)
    }

    private var footerText: String {
        var s = "\(app.recentFiles.count) ファイル"
        if app.scanTruncated { s += "(上限到達)" }
        return s
    }

    private func folderRow(_ folder: URL) -> some View {
        let status = app.status(of: folder)
        let dimmed = status == .unreachable
        return HStack(spacing: 7) {
            Image(systemName: icon(for: status))
                .font(.system(size: 10))
                .foregroundStyle(status == .unreachable ? Theme.textFaint : Theme.amber)
            Text(folder.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(dimmed ? Theme.textFaint : Theme.textDim)
                .lineLimit(1)
                .truncationMode(.middle)
            if status == .unreachable {
                Text("見つかりません")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textFaint)
            } else if status == .tccLikelyBlocked {
                // 「在るのに 0 件 かつ TCC 保護領域」= 再署名で許可が失効した疑い。
                // 人間が tccutil を思い出す運用に委ねず、再許可導線をその場に出す。
                Button(action: openFilesAndFoldersSettings) {
                    Text("アクセス許可")
                        .font(.system(size: 9.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.amber)
                .help(
                    "このフォルダは 0 件です。ad-hoc 再署名でフォルダアクセス許可が失効した可能性があります。"
                        + "クリックで「システム設定 > プライバシーとセキュリティ > ファイルとフォルダ」を開きます。"
                        + "改善しない場合はターミナルで "
                        + "`tccutil reset SystemPolicyDocumentsFolder com.hayashi.htmlviewer` を実行し、アプリを再起動してください。"
                )
            }
            Spacer(minLength: 4)
            Button {
                app.removeFolder(folder)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textFaint)
            .help("登録を解除")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .help(folder.path)
    }

    private func icon(for status: RootStatus) -> String {
        switch status {
        case .unreachable: return "folder.badge.questionmark"
        case .tccLikelyBlocked: return "exclamationmark.triangle.fill"
        case .ok, .empty: return "folder"
        }
    }

    /// システム設定の「プライバシーとセキュリティ > ファイルとフォルダ」を開く。
    /// ad-hoc アプリは TCC を自動付与できないため、できるのは再許可の導線提示まで。
    private func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "追加"
        panel.message = "HTML を閲覧するフォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            app.addFolder(url)
        }
    }
}
