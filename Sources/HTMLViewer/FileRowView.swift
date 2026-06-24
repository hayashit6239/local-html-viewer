import HTMLViewerCore
import SwiftUI

/// RECENT リストの 1 行。ファイル名 + 所属サブパス + 相対更新時刻。
struct FileRowView: View {
    let file: HTMLFile
    let isSelected: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var directory: String {
        let dir = (file.relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("◆")
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Theme.amber : Theme.textFaint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(file.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(isSelected ? Theme.amber : Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if file.isExternal {
                        Text("EXTERNAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 4).padding(.vertical, 0.5)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.amber.opacity(0.5)))
                    }
                }
                if !directory.isEmpty {
                    Text(directory)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(Self.relativeFormatter.localizedString(for: file.mtime, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
