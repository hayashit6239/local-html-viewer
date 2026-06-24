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

    /// 可視列に選択がある場合は通常の `next`。選択が**可視列に無い**(TREE で dir を折りたたんだ /
    /// タブ切替で隠れた)場合は、`fullOrder`(全 leaf の順序)での位置を基準に同方向の
    /// **最も近い可視 leaf** へ移す。これで「隠れた選択 → j/k が先頭へジャンプ」を防ぐ
    /// (選択の維持は呼び出し側の責務で、移動は j/k 操作時のみ起きる — M7 review #3/#4)。
    /// `current` が `fullOrder` にも無い(例: EXTERNAL ピンは tree に存在しない)場合は端から開始。
    public static func next(
        after current: HTMLFile?,
        in visible: [HTMLFile],
        fullOrder: [HTMLFile],
        direction: SelectionDirection
    ) -> HTMLFile? {
        guard !visible.isEmpty else { return nil }
        if current == nil || visible.contains(where: { $0.id == current!.id }) {
            return next(after: current, in: visible, direction: direction)  // 可視 → 通常移動
        }
        guard let idx = fullOrder.firstIndex(where: { $0.id == current!.id }) else {
            return next(after: nil, in: visible, direction: direction)  // 全順序にも無い → 端から
        }
        let visibleIDs = Set(visible.map(\.id))
        switch direction {
        case .down:
            if let hit = fullOrder[(idx + 1)...].first(where: { visibleIDs.contains($0.id) }) {
                return hit
            }
        case .up:
            if let hit = fullOrder[..<idx].last(where: { visibleIDs.contains($0.id) }) {
                return hit
            }
        }
        return next(after: nil, in: visible, direction: direction)  // 同方向に可視 leaf 無し → 端
    }
}
