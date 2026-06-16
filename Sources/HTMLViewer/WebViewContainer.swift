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
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
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

        /// 同一ファイル & 同一トークンなら再ロードしない(updateNSView の再ロードループ防止)。
        /// リロードは reload() でなく loadFileURL 再実行(read-access 再付与が確実)。
        func load(file: HTMLFile, reloadToken: Int, into webView: WKWebView) {
            guard file.path != lastLoadedPath || reloadToken != lastReloadToken else { return }
            lastLoadedPath = file.path
            lastReloadToken = reloadToken
            let fileURL = URL(fileURLWithPath: file.path)
            // allowingReadAccessTo は所属ルート(同フォルダの相対 css/img を読むため)
            let root = URL(fileURLWithPath: file.rootPath)
            webView.loadFileURL(fileURL, allowingReadAccessTo: root)
        }

        // MARK: - WKNavigationDelegate

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
