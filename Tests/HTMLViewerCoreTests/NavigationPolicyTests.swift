import Testing

@testable import HTMLViewerCore

// テストリスト(NavigationPolicy):
// [x] リンククリック + http/https は外部ブラウザへ
// [x] http/https の判定は大文字小文字を無視する
// [x] リンククリック + file: は WebView 内で許可(self-contained の内部遷移)
// [x] リンククリックでない遷移(初期ロード・リダイレクト・JS)は scheme によらず許可
// [x] scheme 不明(nil)のリンクは許可

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    @Test("リンククリック + http/https は外部ブラウザへ")
    func externalForWebLinks() {
        #expect(NavigationPolicy.decide(scheme: "http", isLinkActivation: true) == .openExternally)
        #expect(NavigationPolicy.decide(scheme: "https", isLinkActivation: true) == .openExternally)
    }

    @Test("scheme 判定は大文字小文字を無視")
    func schemeCaseInsensitive() {
        #expect(NavigationPolicy.decide(scheme: "HTTPS", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + file: は WebView 内で許可")
    func allowFileLinks() {
        #expect(NavigationPolicy.decide(scheme: "file", isLinkActivation: true) == .allowInWebView)
    }

    @Test("リンククリックでない遷移は scheme によらず許可")
    func allowNonLinkNavigation() {
        // 初期ロードやリダイレクトで http が来ても WebView 内で許可する
        #expect(NavigationPolicy.decide(scheme: "https", isLinkActivation: false) == .allowInWebView)
        #expect(NavigationPolicy.decide(scheme: "file", isLinkActivation: false) == .allowInWebView)
    }

    @Test("scheme 不明のリンクは許可")
    func allowUnknownScheme() {
        #expect(NavigationPolicy.decide(scheme: nil, isLinkActivation: true) == .allowInWebView)
    }
}
