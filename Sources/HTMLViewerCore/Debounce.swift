import Foundation

/// debounce(短時間の連続イベントを最後の 1 件に畳む)の**意味論**を決定論的に定義する純関数。
/// 実行時の debounce(`AppState` の Task cancel + `Task.sleep`)はこの意味論を実装する。
/// ここを単体テストで固定することで「N 連発 → 適用 1 回」を祈りでなく検証で担保する(暴走防止)。
public enum Debounce {
    /// `(発生時刻, 値)` の昇順列から、直前の確定値より `window` 以内に続く入力を畳み、
    /// 各バーストの **最後の値のみ**を発火させて返す。
    public static func coalesce<T>(_ events: [(at: Duration, value: T)], window: Duration) -> [T] {
        var fired: [T] = []
        var pending: (at: Duration, value: T)?
        for event in events {
            if let p = pending, event.at - p.at >= window {
                fired.append(p.value)  // 次が window 外 → 前のバーストを確定
            }
            pending = event
        }
        if let p = pending { fired.append(p.value) }
        return fired
    }
}
