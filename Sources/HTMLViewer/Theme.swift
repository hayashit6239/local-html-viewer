import SwiftUI

/// 案 B「アンバー × macOS ネイティブ・ハイブリッド」のパレット + 使用中の角丸定数。
/// リファレンス: `docs/assets/design-mock-b.html`。
enum Theme {
    // 色(swatch)
    static let background = Color(hex: 0x1D1B20)
    static let amber = Color(hex: 0xE8A13C)
    static let text = Color(hex: 0xE6E2D8)
    static let textDim = Color(hex: 0x98948B)
    static let textFaint = Color(hex: 0x5D5A54)
    static let live = Color(hex: 0x8FCE5A)

    enum Radius {
        static let badge: CGFloat = 3  // FileRowView / ContentView の既存 cornerRadius:3 と一致
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
