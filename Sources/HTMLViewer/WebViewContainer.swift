import AppKit
import HTMLViewerCore
import SwiftUI
import WebKit

/// 選択ファイルを WKWebView で表示する薄いラッパー(Humble Object)。
/// 判断は Core の `NavigationPolicy` に委ね、ここは WebKit との結線に徹する。
struct WebViewContainer: NSViewRepresentable {
    let file: HTMLFile
    /// 明示リロード要求トークン(変化で loadFileURL を再実行)。
    let reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isInspectable = true  // 右クリック → 要素の詳細(デバッグ用)
        webView.underPageBackgroundColor = .white  // ロード前後の白フラッシュ防止
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(file: file, reloadToken: reloadToken, into: webView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // completion handler は SDK で WK_SWIFT_UI_ACTOR(= @MainActor)宣言のため、
    // 各 closure に @MainActor を付けて要件と一致させる(無いと「nearly matches」=実行時に呼ばれない)。
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var lastLoadedPath: String?
        private var lastReloadToken = Int.min
        /// リロード(同一ファイル再読込)時に復元するスクロール位置。ファイル切替時は nil。
        private var pendingScroll: (x: Double, y: Double)?

        /// 同一ファイル & 同一トークンなら再ロードしない(updateNSView の再ロードループ防止)。
        /// リロードは reload() でなく loadFileURL 再実行(read-access 再付与が確実)。
        /// 同一ファイルの reload はスクロール位置をベストエフォートで維持する(M6)。
        func load(file: HTMLFile, reloadToken: Int, into webView: WKWebView) {
            let samePath = file.path == lastLoadedPath
            guard !samePath || reloadToken != lastReloadToken else { return }
            let isReload = samePath  // 同一ファイルの再読込(トークン変化)
            lastLoadedPath = file.path
            lastReloadToken = reloadToken

            if isReload {
                // リロード前に現在のスクロール位置を退避(JS は非同期なので退避完了後にロード)
                webView.evaluateJavaScript("[window.scrollX, window.scrollY]") { [weak self] result, _ in
                    if let a = result as? [Double], a.count == 2 { self?.pendingScroll = (a[0], a[1]) }
                    self?.performLoad(file, into: webView)
                }
            } else {
                pendingScroll = nil  // ファイル切替は復元しない
                performLoad(file, into: webView)
            }
        }

        private func performLoad(_ file: HTMLFile, into webView: WKWebView) {
            let fileURL = URL(fileURLWithPath: file.path, isDirectory: false)
            // 内部ファイル: allowingReadAccessTo は所属ルート dir(同フォルダの相対 css/img を読むため。
            //   isDirectory: true を明示しないと hasDirectoryPath が FS stat 依存になり読み取りが縮退する)。
            // 外部ファイル(M5 EXTERNAL): ファイル単体スコープに切替(登録外の周囲フォルダを晒さない)。
            let readScope = file.isExternal
                ? fileURL
                : URL(fileURLWithPath: file.rootPath, isDirectory: true)
            webView.loadFileURL(fileURL, allowingReadAccessTo: readScope)
        }

        // MARK: - WKNavigationDelegate

        /// ロード完了時にスクロール位置を復元(ベストエフォート)。レンダリング遅延に備え 200ms 後に再試行。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let scroll = pendingScroll else { return }
            pendingScroll = nil
            let js = "window.scrollTo(\(scroll.x), \(scroll.y))"
            webView.evaluateJavaScript(js)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                webView.evaluateJavaScript(js)  // = didFinish 後のレンダリング完了 lag への二段復元
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isLink = navigationAction.navigationType == .linkActivated
            switch NavigationPolicy.decide(scheme: url?.scheme, isLinkActivation: isLink) {
            case .openExternally:
                if let url { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            case .allowInWebView:
                decisionHandler(.allow)
            }
        }

        // MARK: - WKUIDelegate

        /// target=_blank 等の新規ウィンドウ要求。新規ウィンドウは作らず、外部リンクなら同ポリシーで処理。
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
                NavigationPolicy.decide(scheme: url.scheme, isLinkActivation: true) == .openExternally {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor () -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "キャンセル")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (String?) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = prompt
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "キャンセル")
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}
