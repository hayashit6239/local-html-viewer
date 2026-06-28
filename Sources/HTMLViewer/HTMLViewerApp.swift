import AppKit
import Carbon.HIToolbox  // kVK_* keyCode 定数(マジックナンバー回避 — round-4 #6)
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
/// WKWebView 内の `<input>`・`<textarea>`)は j/k/r/`/`/↑↓/Return を飲み込まずキー入力へ透過する。
/// (`.onKeyPress` はフォーカス取りこぼしがあるため monitor で受ける)。
@MainActor
private func installKeyMonitor(_ app: AppState) -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        // 検索入力(@FocusState ミラー)または WKWebView / フィールドエディタにフォーカスが
        // あるときはキーを横取りせず透過する。`isSearchFocused` だけでは WKWebView 内の
        // フォーム要素を取りこぼすため、firstResponder チェーンも見る(M7 review #1)。
        if app.isSearchFocused || keyEventShouldYieldToFocus() { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let optOrCtrl = flags.contains(.option) || flags.contains(.control)  // ⌥r='®' / ⌃r 等は横取りしない

        // 矢印キー / Return / Enter は `charactersIgnoringModifiers` が非 ASCII 制御文字を返すため
        // `keyCode` で判定する(#32)。j/k / ↑↓ は等価、Return / Enter(numpad)は activate(dir 展開)。
        // Carbon の `kVK_*` で名前付け(マジックナンバー回避・将来のキー追加時の typo 防止 — round-4 #6)。
        if !cmd && !optOrCtrl {
            switch Int(event.keyCode) {
            case kVK_DownArrow: app.moveSelection(.down); return nil
            case kVK_UpArrow:   app.moveSelection(.up);   return nil
            case kVK_Return, kVK_ANSI_KeypadEnter: app.activateSelection(); return nil
            default: break
            }
        }

        // Caps Lock 有効時 charactersIgnoringModifiers は 'r' を 'R' に変えるため、小文字へ正規化して
        // から判定する。reload と reveal は文字でなく修飾(cmd&&shift か否か)で振り分ける(M7 review #3)。
        // Shift+/ は '?' を返し "/" に一致しないため横取りされない('r' と対称)。
        let key = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch key {
        case "j" where !cmd && !optOrCtrl: app.moveSelection(.down); return nil
        case "k" where !cmd && !optOrCtrl: app.moveSelection(.up); return nil
        case "r" where !cmd && !shift && !optOrCtrl: app.reloadPreview(); return nil
        case "r" where cmd && shift && !optOrCtrl: app.revealSelectedInFinder(); return nil  // ⌘⇧R
        case "/" where !cmd && !shift && !optOrCtrl: app.requestSearchFocus(); return nil
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
    guard let keyWindow = NSApp.keyWindow else { return false }
    // モーダルパネル/シート(NSOpenPanel・NSSavePanel 等は NSPanel サブクラス)が key の
    // ときはビューアキーを横取りしない。ダイアログ背後で選択移動 / reload が走るのを防ぐ
    // (本アプリは単一 Window 設計のため、key が NSPanel = 補助ダイアログとみなせる — M7 review #10)。
    if keyWindow is NSPanel { return true }
    guard let responder = keyWindow.firstResponder else { return false }
    if responder is NSText { return true }  // フィールドエディタ(NSTextField 編集中)
    var view = responder as? NSView
    while let current = view {
        if current is WKWebView { return true }
        view = current.superview
    }
    return false
}
