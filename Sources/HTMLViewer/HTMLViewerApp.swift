import AppKit
import SwiftUI

@main
struct HTMLViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppState()
    /// ビューアキー(j/k/r/⌘⇧R//)の local monitor。Window 1 個に 1 個だけ設置(M7)。
    @State private var keyMonitor: Any?

    var body: some Scene {
        // WindowGroup はオープンイベントや Dock 再クリックでウィンドウが増殖しうるため、
        // シングルウィンドウビューアとして Window シーンを使う(docs/03 判断 2)
        Window("HTML Viewer", id: "main") {
            ContentView()
                .environment(app)
                .task {
                    app.rescan()  // 起動時に永続化済みフォルダを走査
                    // odoc 受信ハンドラを接続(register → 同期 drain。間に await を挟まない)。
                    // コールド起動でバッファされた odoc をここで取りこぼさず流す。
                    appDelegate.connect { app.handleOpenedURLs($0) }
                }
                .onAppear { if keyMonitor == nil { keyMonitor = installKeyMonitor(app) } }
                .onDisappear {
                    if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
                }
        }
    }
}

/// ビューアキーの local key monitor を設置する。検索フィールド入力中(`isSearchFocused`)は
/// j/k/r を飲み込まずテキスト入力へ透過する(`.onKeyPress` はフォーカス取りこぼしがあるため monitor で受ける)。
@MainActor
private func installKeyMonitor(_ app: AppState) -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if app.isSearchFocused { return event }  // 検索入力優先
        let chars = event.charactersIgnoringModifiers ?? ""
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch chars {
        case "j": app.moveSelection(.down); return nil
        case "k": app.moveSelection(.up); return nil
        case "r" where !cmd: app.reloadPreview(); return nil
        case "R" where cmd && shift: app.revealSelectedInFinder(); return nil
        case "/": app.requestSearchFocus(); return nil
        default: return event
        }
    }
}
