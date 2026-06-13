import SwiftUI

/// 案 B「アンバー × macOS ネイティブ・ハイブリッド」のパレット(docs/assets/design-mock-b.html)
enum Theme {
    static let background = Color(hex: 0x1D1B20)
    static let amber = Color(hex: 0xE8A13C)
    static let text = Color(hex: 0xE6E2D8)
    static let textDim = Color(hex: 0x98948B)
    static let textFaint = Color(hex: 0x5D5A54)
    static let live = Color(hex: 0x8FCE5A)
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
