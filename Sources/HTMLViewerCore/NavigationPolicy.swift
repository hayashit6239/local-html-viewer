/// WKWebView 内のナビゲーションを「内部で許可」か「外部ブラウザへ」に振り分ける純粋ロジック。
/// UI 非依存(WebKit に依存しない)にして TDD で駆動する。
public enum NavigationDecision: Sendable, Equatable {
    /// WKWebView 内でそのまま遷移を許可する。
    case allowInWebView
    /// 既定ブラウザで開き、WebView 内の遷移はキャンセルする。
    case openExternally
}

public enum NavigationPolicy {
    /// リンククリック由来の http/https 遷移のみ外部ブラウザへ送る。
    /// 初期ロード・リダイレクト・JS 遷移・file: 内部遷移は WebView 内で許可する。
    public static func decide(scheme: String?, isLinkActivation: Bool) -> NavigationDecision {
        guard isLinkActivation else { return .allowInWebView }
        switch scheme?.lowercased() {
        case "http", "https":
            return .openExternally
        default:
            return .allowInWebView
        }
    }
}
