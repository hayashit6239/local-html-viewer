import Foundation

public enum SelectionDirection: Sendable { case up, down }

/// 可視 leaf 列(`[HTMLFile]`)に対する選択計算(j/k 移動・フィルタ後の保持)。UI 非依存。
/// 照合は `id`(絶対パス)で行う(reload で mtime が変わっても同一視するため)。
public enum SelectionLogic {
    /// j(down)/k(up)の次選択。端はクランプ(回り込みなし)。未選択時は端から開始。
    public static func next(
        after current: HTMLFile?,
        in list: [HTMLFile],
        direction: SelectionDirection
    ) -> HTMLFile? {
        guard !list.isEmpty else { return nil }
        guard let current, let idx = list.firstIndex(where: { $0.id == current.id }) else {
            return direction == .down ? list.first : list.last
        }
        let target = direction == .down ? idx + 1 : idx - 1
        guard list.indices.contains(target) else { return current }  // クランプ
        return list[target]
    }

    /// フィルタ/再走査後の選択保持: 残存していれば維持、消えていれば先頭(空なら nil)。
    public static func reconcile(previous: HTMLFile?, in list: [HTMLFile]) -> HTMLFile? {
        guard let previous else { return list.first }
        if let kept = list.first(where: { $0.id == previous.id }) { return kept }
        return list.first
    }
}
