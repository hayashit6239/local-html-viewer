import SwiftUI

@main
struct HTMLViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppState()

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
        }
    }
}
