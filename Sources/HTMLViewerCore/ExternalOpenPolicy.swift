import Foundation

/// 登録フォルダ外の odoc 受信ファイル(M5: EXTERNAL ピン)の判断ロジック(UI 非依存)。
///
/// **不変条件**: ここで扱うパスは呼び出し側(AppState)が `.canonicalPathKey` で正規化済みの
/// 文字列であること。内外判定・dedup・ピン照合をすべて同じ正規形で行うことで
/// `/var`↔`/private/var` 非対称の再発を防ぐ。本 enum は FS に触れない(純ロジック)。
public enum ExternalOpenPolicy {
    /// 受信パス(正規化済)が登録ルート(正規化済)群の配下か。
    public static func isInside(_ path: String, registeredRoots roots: [String]) -> Bool {
        roots.contains { root in
            if path == root { return true }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            return path.hasPrefix(prefix)
        }
    }

    /// 登録フォルダ外ファイルの EXTERNAL `HTMLFile` を合成する。
    /// rootPath=親 dir(表示 / relativePath 用)、`isExternal=true`(read-access はファイル単体)。
    public static func makeExternalFile(path: String, mtime: Date) -> HTMLFile {
        let ns = path as NSString
        let name = ns.lastPathComponent
        return HTMLFile(
            path: path,
            name: name,
            mtime: mtime,
            rootPath: ns.deletingLastPathComponent,
            relativePath: name,
            isExternal: true
        )
    }

    /// RECENT に単一 EXTERNAL ピンを先頭合成する。
    /// pin path が recent に既出なら **omit**(二重解消はリスト構築時に declarative に行う)。
    public static func compose(recent: [HTMLFile], pinned: HTMLFile?) -> [HTMLFile] {
        guard let pinned else { return recent }
        if recent.contains(where: { $0.path == pinned.path }) { return recent }
        return [pinned] + recent
    }
}
