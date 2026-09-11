import SwiftUI

enum Theme {
    static let background = Color.appBackground
    static let surface = Color.appCardBg
    static let cardStroke = Color.appBorder
    static let accent = Color.appPrimary
    static let primaryLight = Color.appPrimaryLight
    static let sage = Color.appSafetyGreen
    static let blush = Color.appWarningRed
    static let gold = Color.appModerateYellow
    static let ink = Color.appTextDark
    static let muted = Color.appTextMuted
}

extension Color {
    static let appBackground = Color(hex: "FAF6F0")
    static let appCardBg = Color(hex: "FFFFFF")
    static let appBorder = Color(hex: "EFE8DD")

    static let appPrimary = Color(hex: "FF6700")
    static let appPrimaryLight = Color(hex: "FFF0E6")

    static let appSafetyGreen = Color(hex: "48A9A6")
    static let appWarningRed = Color(hex: "E04B2A")
    static let appModerateYellow = Color(hex: "FF9F1C")

    static let appTextDark = Color(hex: "2B2520")
    static let appTextMuted = Color(hex: "8F877E")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// 避免 SwiftData／計算結果帶入 NaN 觸發 CoreGraphics 崩潰。
    static func safeRGB(red: Double, green: Double, blue: Double, opacity: Double = 1) -> Color {
        func clamp(_ value: Double) -> Double {
            guard value.isFinite, !value.isNaN else { return 0.5 }
            return min(1, max(0, value))
        }
        return Color(
            red: clamp(red),
            green: clamp(green),
            blue: clamp(blue),
            opacity: clamp(opacity)
        )
    }
}
