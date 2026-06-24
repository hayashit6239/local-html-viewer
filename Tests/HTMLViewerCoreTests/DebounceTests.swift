import Foundation
import Testing

@testable import HTMLViewerCore

// テストリスト(Debounce.coalesce — debounce の意味論を決定論的に固定する純関数):
// [x] window 内の連続は最後の 1 件に畳む(N 連発 → 適用 1 回)
// [x] window を超えて離れた入力は別々に発火
// [x] 空入力は空
// AppState のランタイム debounce(Task cancel + sleep)はこの意味論を実装する。

@Suite("Debounce")
struct DebounceTests {
    @Test("window 内の連続は最後の 1 件に畳む")
    func coalesceBurst() {
        let events: [(at: Duration, value: Int)] = [
            (.zero, 1), (.milliseconds(50), 2), (.milliseconds(100), 3),
            (.milliseconds(150), 4), (.milliseconds(200), 5),
        ]
        #expect(Debounce.coalesce(events, window: .milliseconds(300)) == [5])
    }

    @Test("window を超えて離れた入力は別々に発火")
    func separateBeyondWindow() {
        let events: [(at: Duration, value: Int)] = [
            (.zero, 1), (.milliseconds(500), 2),
        ]
        #expect(Debounce.coalesce(events, window: .milliseconds(300)) == [1, 2])
    }

    @Test("空入力は空")
    func empty() {
        #expect(Debounce.coalesce([(at: Duration, value: Int)](), window: .milliseconds(300)).isEmpty)
    }
}
