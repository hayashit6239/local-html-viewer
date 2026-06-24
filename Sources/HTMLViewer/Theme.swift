import SwiftUI

/// 案 B「アンバー × macOS ネイティブ・ハイブリッド」のパレット + spacing/radius 定数。
/// リファレンス: `docs/assets/design-mock-b.html`。
enum Theme {
    // 色(swatch)
    static let background = Color(hex: 0x1D1B20)
    static let amber = Color(hex: 0xE8A13C)
    static let text = Color(hex: 0xE6E2D8)
    static let textDim = Color(hex: 0x98948B)
    static let textFaint = Color(hex: 0x5D5A54)
    static let live = Color(hex: 0x8FCE5A)

    // 間隔・角丸(M9: 1 箇所に集約して画面間の一貫性を担保)。
    // 定数値は**既存の literal call site と一致**させる(配線は M7 マージ後にまとめて行うフォローアップ。
    // 値が既存と乖離していると「定数を編集したのに見た目が変わらない」罠になるため — M9 review #1)。
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum Radius {
        static let badge: CGFloat = 3  // FileRowView / ContentView の既存 cornerRadius:3 と一致
        static let button: CGFloat = 6
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
