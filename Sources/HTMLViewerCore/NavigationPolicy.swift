/// WKWebView 内のナビゲーションを「内部で許可」か「外部ブラウザへ」に振り分ける純粋ロジック。
/// UI 非依存(WebKit に依存しない)にして TDD で駆動する。
public enum NavigationDecision: Sendable, Equatable {
    /// WKWebView 内でそのまま遷移を許可する。
    case allowInWebView
    /// 既定ブラウザ / OS ハンドラへ委譲し、WebView 内の遷移はキャンセルする。
    case openExternally
}

public enum NavigationPolicy {
    /// リンククリック由来の遷移をスキーム別に振り分ける(issue #11 決定の表どおり)。
    ///
    /// - `http` / `https` → 既定ブラウザ
    /// - `mailto` / `tel` / `facetime` / `sms` → OS の既定ハンドラ(`NSWorkspace` 経由)
    /// - `file` / `data` / `about` / `blob` → WebView 内で許可(self-contained の内部遷移)
    /// - 不明スキーム / nil → 安全側で WebView 内に委ねる(WebView 側で未対応なら自動で失敗)
    ///
    /// リンククリック以外(初期ロード・リダイレクト・JS 由来の navigation)は scheme を問わず許可する。
    public static func decide(scheme: String?, isLinkActivation: Bool) -> NavigationDecision {
        guard isLinkActivation else { return .allowInWebView }
        switch scheme?.lowercased() {
        case "http", "https",
             "mailto", "tel", "facetime", "sms":
            return .openExternally
        case "file", "data", "about", "blob":
            return .allowInWebView
        default:
            return .allowInWebView
        }
    }
}
