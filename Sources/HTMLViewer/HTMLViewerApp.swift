import SwiftUI

@main
struct HTMLViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // WindowGroup はオープンイベントや Dock 再クリックでウィンドウが増殖しうるため、
        // シングルウィンドウビューアとして Window シーンを使う(docs/03 判断 2)
        Window("HTML Viewer", id: "main") {
            ContentView()
        }
    }
}
