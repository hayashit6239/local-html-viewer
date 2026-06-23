import Testing

@testable import HTMLViewerCore

// テストリスト(NavigationPolicy / issue #11 スキーム分類 DoD):
// [x] リンククリック + http / https は外部ブラウザへ
// [x] リンククリック + mailto / tel / facetime / sms は OS ハンドラへ(外部)
// [x] リンククリック + file / data / about / blob は WebView 内で許可
// [x] スキーム判定は大文字小文字を無視する
// [x] リンククリックでない遷移(初期ロード・リダイレクト・JS)は scheme によらず許可
// [x] scheme 不明(nil)のリンクは安全側で WebView 内に委ねる
// [x] 未知スキーム(例: chrome / weird)は安全側で WebView 内に委ねる(WebView 側で未対応なら自動失敗)

@Suite("NavigationPolicy")
struct NavigationPolicyTests {
    @Test("リンククリック + http/https は外部ブラウザへ")
    func externalForWebLinks() {
        #expect(NavigationPolicy.decide(scheme: "http", isLinkActivation: true) == .openExternally)
        #expect(NavigationPolicy.decide(scheme: "https", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + mailto は外部(OS ハンドラ)へ")
    func externalForMailto() {
        #expect(NavigationPolicy.decide(scheme: "mailto", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + tel は外部(OS ハンドラ)へ")
    func externalForTel() {
        #expect(NavigationPolicy.decide(scheme: "tel", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + facetime は外部(OS ハンドラ)へ")
    func externalForFacetime() {
        #expect(NavigationPolicy.decide(scheme: "facetime", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + sms は外部(OS ハンドラ)へ")
    func externalForSms() {
        #expect(NavigationPolicy.decide(scheme: "sms", isLinkActivation: true) == .openExternally)
    }

    @Test("リンククリック + file は WebView 内で許可")
    func allowFileLinks() {
        #expect(NavigationPolicy.decide(scheme: "file", isLinkActivation: true) == .allowInWebView)
    }

    @Test("リンククリック + data は WebView 内で許可")
    func allowDataLinks() {
        #expect(NavigationPolicy.decide(scheme: "data", isLinkActivation: true) == .allowInWebView)
    }

    @Test("リンククリック + about は WebView 内で許可")
    func allowAboutLinks() {
        #expect(NavigationPolicy.decide(scheme: "about", isLinkActivation: true) == .allowInWebView)
    }

    @Test("リンククリック + blob は WebView 内で許可")
    func allowBlobLinks() {
        #expect(NavigationPolicy.decide(scheme: "blob", isLinkActivation: true) == .allowInWebView)
    }

    @Test("scheme 判定は大文字小文字を無視")
    func schemeCaseInsensitive() {
        #expect(NavigationPolicy.decide(scheme: "HTTPS", isLinkActivation: true) == .openExternally)
        #expect(NavigationPolicy.decide(scheme: "MailTo", isLinkActivation: true) == .openExternally)
        #expect(NavigationPolicy.decide(scheme: "FILE", isLinkActivation: true) == .allowInWebView)
    }

    @Test("リンククリックでない遷移は scheme によらず許可")
    func allowNonLinkNavigation() {
        // 初期ロード・リダイレクト・JS 由来は scheme 不問で許可(prevent な誤誘導を避ける)
        #expect(NavigationPolicy.decide(scheme: "https", isLinkActivation: false) == .allowInWebView)
        #expect(NavigationPolicy.decide(scheme: "mailto", isLinkActivation: false) == .allowInWebView)
        #expect(NavigationPolicy.decide(scheme: "file", isLinkActivation: false) == .allowInWebView)
    }

    @Test("scheme 不明(nil)のリンクは安全側で WebView 内に委ねる")
    func allowNilScheme() {
        #expect(NavigationPolicy.decide(scheme: nil, isLinkActivation: true) == .allowInWebView)
    }

    @Test("未知スキームは安全側で WebView 内に委ねる(WebView 側で未対応なら自動失敗)")
    func allowUnknownScheme() {
        #expect(NavigationPolicy.decide(scheme: "weird", isLinkActivation: true) == .allowInWebView)
    }
}
