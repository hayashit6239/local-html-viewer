import AppKit
import SwiftUI
import WebKit

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
                    app.startWatching()  // FSEvents で登録フォルダを監視(M6)
                }
                .onAppear { if keyMonitor == nil { keyMonitor = installKeyMonitor(app) } }
                .onDisappear {
                    if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
                }
        }
    }
}

/// ビューアキーの local key monitor を設置する。テキスト入力中(検索フィールド / プレビュー
/// WKWebView 内の `<input>`・`<textarea>`)は j/k/r/`/` を飲み込まずキー入力へ透過する。
/// (`.onKeyPress` はフォーカス取りこぼしがあるため monitor で受ける)。
@MainActor
private func installKeyMonitor(_ app: AppState) -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        // 検索入力(@FocusState ミラー)または WKWebView / フィールドエディタにフォーカスが
        // あるときはキーを横取りせず透過する。`isSearchFocused` だけでは WKWebView 内の
        // フォーム要素を取りこぼすため、firstResponder チェーンも見る(M7 review #1)。
        if app.isSearchFocused || keyEventShouldYieldToFocus() { return event }
        let chars = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        // option / control が乗ったキー(⌥r='®' / ⌃r 等)は横取りしない(M7 review #5)。
        // Shift+R は charactersIgnoringModifiers が "R" を返すため "r" ケースには落ちず、
        // ⌘⇧R(reveal)と別ハンドルされる。
        let optOrCtrl = flags.contains(.option) || flags.contains(.control)
        switch chars {
        case "j" where !cmd && !optOrCtrl: app.moveSelection(.down); return nil
        case "k" where !cmd && !optOrCtrl: app.moveSelection(.up); return nil
        case "r" where !cmd && !shift && !optOrCtrl: app.reloadPreview(); return nil
        case "R" where cmd && shift: app.revealSelectedInFinder(); return nil
        case "/" where !cmd && !optOrCtrl: app.requestSearchFocus(); return nil
        default: return event
        }
    }
}

/// キーウィンドウの first responder がテキスト編集文脈(フィールドエディタ)または
/// WKWebView 内にあるかを判定する。true ならビューアキーを横取りせず透過する。
/// WKWebView は内部の HTML input にフォーカスがあってもネイティブ側の first responder は
/// content view のため、responder チェーンを WKWebView までさかのぼって判定する(M7 review #1)。
@MainActor
private func keyEventShouldYieldToFocus() -> Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else { return false }
    if responder is NSText { return true }  // フィールドエディタ(NSTextField 編集中)
    var view = responder as? NSView
    while let current = view {
        if current is WKWebView { return true }
        view = current.superview
    }
    return false
}
