import AppKit
import HTMLViewerCore
import SwiftUI

/// 左サイドバー: 登録フォルダ管理 + 検索 + RECENT / TREE リスト。
struct SidebarView: View {
    @Environment(AppState.self) private var app
    @FocusState private var searchFocused: Bool

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

            // ── 検索 ──
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                TextField("検索(/)", text: $app.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onExitCommand { app.searchText = ""; searchFocused = false }  // Esc: クリア + リストへ
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .onChange(of: searchFocused) { _, focused in app.isSearchFocused = focused }
            .onChange(of: app.focusSearchRequest) { _, _ in searchFocused = true }  // `/` で要求

            // ── タブ ──
            Picker("", selection: $app.selectedTab) {
                Text("最近").tag(AppState.SidebarTab.recent)
                Text("ツリー").tag(AppState.SidebarTab.tree)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 6)

            // ── リスト(タブ別)──
            // List(selection:) は SidebarSelection? を受ける(#32: file/dir を同列に選択可能)。
            // 各行に `.onTapGesture` を当てて selection を SwiftUI 内で直接書き込み、同時に
            // `NSApp.keyWindow?.makeFirstResponder(nil)` で WKWebView から AppKit 層の first
            // responder を外す(#36: PR #33 の @FocusState 方式は AppKit makeFirstResponder に
            // 翻訳されず無効だったため、AppKit 直叩きで奪う)。
            // ScrollViewReader + .onChange で「選択が表示範囲外なら追従(範囲内なら no-op)」(#37)。
            ScrollViewReader { proxy in
                Group {
                    if app.selectedTab == .recent {
                        List(selection: $app.selection) {
                            ForEach(app.recentFiles) { file in
                                FileRowView(file: file, isSelected: app.selectedFile?.id == file.id)
                                    .tag(Optional(SidebarSelection.file(file)))
                                    .id(SidebarSelection.file(file))
                                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                                    .listRowBackground(Color.clear)
                                    .onTapGesture {
                                        app.selection = .file(file)
                                        yieldFirstResponderFromWebView()
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    } else {
                        // dir 行(DisclosureGroup ラベル)クリックで List(selection:) が nil を書き込んで
                        // 選択を失う macOS 挙動を防ぐため、nil 書込を無視する Binding を使う(M7 review #5)。
                        // ただし dir 行自体に SidebarSelection.dir tag を付与した今(#32)、ユーザーが dir 行を
                        // 明示クリックすれば setter には `.dir(...)` が入り、無視されず正しく書き込まれる。
                        List(selection: Binding(
                            get: { app.selection },
                            set: { if let v = $0 { app.selection = v } }
                        )) {
                            TreeRowsView(nodes: app.tree)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .onChange(of: app.selection) { _, new in
                    guard let new else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(new, anchor: nil)
                    }
                }
                .onChange(of: app.selectedTab) { _, _ in
                    guard let sel = app.selection else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(sel, anchor: nil)
                    }
                }
            }

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
        // 総在庫は allFiles.count を表示する。検索フィルタ後の件数を出すと、ヒット 0 で「0 ファイル」と
        // なりスキャン失敗/ファイル消失と誤解されるため、絞り込み中は「ヒット / 総数」表記にする(M7 review #9)。
        let total = app.allFiles.count
        var s: String
        if app.searchText.isEmpty {
            s = "\(total) ファイル"
        } else {
            s = "\(app.recentFiles.count) / \(total) ファイル(絞り込み中)"
        }
        if app.scanTruncated { s += " (上限到達)" }
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

    /// WKWebView(プレビュー)が key first responder を握ったままだと NSTableView の
    /// firstClickValid=false 挙動でクリック・矢印キーが selection 更新まで届かない macOS 挙動を救う。
    /// SwiftUI の `@FocusState` は AppKit 層の `makeFirstResponder` を呼ばないので、AppKit を
    /// 直接叩く(#36)。`makeFirstResponder(nil)` は window レベルへ first responder を戻す効果で、
    /// 結果として `installKeyMonitor` の `keyEventShouldYieldToFocus()` が false を返しキー操作が
    /// ビューアキーとして扱われるようになる。
    private func yieldFirstResponderFromWebView() {
        NSApp.keyWindow?.makeFirstResponder(nil)
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

/// TREE タブの再帰行。`DisclosureGroup(isExpanded:)` を `AppState.expandedDirs` にバインドし、
/// 展開ポリシー(既定展開閾値・検索/選択の親 dir 自動展開・手動トグル)を UI に反映する(M7 brush-up)。
/// `OutlineGroup` は展開状態を外部バインドできず常時全展開になるため、再帰 DisclosureGroup に置換した。
private struct TreeRowsView: View {
    @Environment(AppState.self) private var app
    let nodes: [TreeNode]

    var body: some View {
        ForEach(nodes) { node in
            if let file = node.file {
                FileRowView(file: file, isSelected: app.selectedFile?.id == file.id)
                    .tag(Optional(SidebarSelection.file(file)))
                    .id(SidebarSelection.file(file))
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowBackground(Color.clear)
                    .onTapGesture {
                        app.selection = .file(file)
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
            } else {
                // dir 行にも tag を付け、クリックで `.dir(id)` 選択になるようにする(#32)。
                // DisclosureGroup の chevron(disclosure indicator)クリックは従来通り個別開閉が走る。
                // label にだけ .onTapGesture を当てて selection を書き込む(DisclosureGroup の
                // chevron クリックは label 外なので独立して開閉が走り続ける — #36)。
                DisclosureGroup(isExpanded: expansion(of: node.id)) {
                    TreeRowsView(nodes: node.children ?? [])
                } label: {
                    Text(node.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isDirSelected(node.id) ? Theme.amber : Theme.textDim)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            app.selection = .dir(id: node.id)
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                }
                .tag(Optional(SidebarSelection.dir(id: node.id)))
                .id(SidebarSelection.dir(id: node.id))
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .listRowBackground(Color.clear)
            }
        }
    }

    private func isDirSelected(_ id: String) -> Bool {
        if case .dir(let i) = app.selection { return i == id }
        return false
    }

    /// `DisclosureGroup` の双方向バインディング(get=展開中か / set=ユーザートグル)。
    private func expansion(of dirID: String) -> Binding<Bool> {
        Binding(
            get: { app.isExpanded(dirID) },
            set: { app.setExpanded(dirID, $0) }
        )
    }
}
