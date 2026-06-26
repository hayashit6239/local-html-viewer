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

    // MARK: - 行ベース(#32: SidebarSelection / TreeRow)

    /// 可視行列(dir + file の混在)に対する↑↓選択。端はクランプ。未選択時は端から
    /// (down=先頭、up=末尾)。`current` が可視行に無い(折りたたみで dir が消えた等)
    /// 場合も同様に端から開始する。leaf 版の `fullOrder` 補正は行版では持たない:
    /// dir/file の混在順序を一意に決める「全行順」が `visibleRows(expanded=全 dir)` 以外に
    /// 存在せず、利用側(M7 で隠れた選択を救う狙い)に対するゲインも小さいため、最小化する。
    public static func nextRow(
        after current: SidebarSelection?,
        in visible: [TreeRow],
        direction: SelectionDirection
    ) -> SidebarSelection? {
        guard !visible.isEmpty else { return nil }
        guard let current, let idx = visible.firstIndex(where: { matches($0, current) }) else {
            return direction == .down ? selection(of: visible.first!) : selection(of: visible.last!)
        }
        let target = direction == .down ? idx + 1 : idx - 1
        guard visible.indices.contains(target) else { return current }  // クランプ
        return selection(of: visible[target])
    }

    /// フィルタ/再走査後の行ベース選択保持: 残存(file 同 id / dir 同 id)維持、
    /// 消えたら先頭行、空なら nil。leaf 版と同じセマンティクスで dir も扱う。
    public static func reconcile(
        previous: SidebarSelection?,
        in visible: [TreeRow]
    ) -> SidebarSelection? {
        guard let previous else { return visible.first.map(selection(of:)) }
        if let kept = visible.first(where: { matches($0, previous) }) {
            return selection(of: kept)
        }
        return visible.first.map(selection(of:))
    }

    private static func selection(of row: TreeRow) -> SidebarSelection {
        switch row {
        case .file(let file): return .file(file)
        case .dir(let id, _): return .dir(id: id)
        }
    }

    /// `TreeRow` と `SidebarSelection` の同一判定。可視列 membership 検査(reconcile / nextRow /
    /// AppState 側の rescan 後 reconcile 等)で共通に使うため public。`SidebarSelection` に case を
    /// 追加したときに分岐の同期漏れを発生させないよう、判定ロジックは本関数 1 箇所に集約する。
    public static func matches(_ row: TreeRow, _ selection: SidebarSelection) -> Bool {
        switch (row, selection) {
        case (.file(let f), .file(let g)): return f.id == g.id
        case (.dir(let i, _), .dir(let j)): return i == j
        default: return false
        }
    }
}
