import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 受信ハンドラ(AppState 接続後に設定)。設定済みなら即呼び、未設定ならバッファする。
    private var onOpen: (([URL]) -> Void)?
    /// コールド起動でウィンドウ/ビュー構築より早く届いた odoc を取りこぼさないためのバッファ。
    private var pendingURLs: [URL] = []

    /// odoc(`open -b <file>` / Dock D&D)の受信口。
    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen {
            onOpen(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    /// AppState 側の受信ハンドラを接続する。
    /// **register(onOpen 設定)→ 同期 drain** の順を厳守し、間に await を挟まない。
    /// drain 先行だと「drain 後・register 前」に届いた odoc を取りこぼす(コールド起動レース対策)。
    func connect(_ handler: @escaping ([URL]) -> Void) {
        onOpen = handler
        guard !pendingURLs.isEmpty else { return }
        let buffered = pendingURLs
        pendingURLs = []
        handler(buffered)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
