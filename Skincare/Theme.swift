import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    /// 淺色卡片／輸入框底（深色模式下不再用死白）。
    static let elevated = Color.appElevated
}

extension Color {
    static let appBackground = Color(light: "FAF6F0", dark: "14110F")
    static let appCardBg = Color(light: "FFFFFF", dark: "1E1A17")
    static let appElevated = Color(light: "FFFFFF", dark: "2A2521")
    static let appBorder = Color(light: "EFE8DD", dark: "3A332D")

    static let appPrimary = Color(light: "FF6700", dark: "FF7A1F")
    static let appPrimaryLight = Color(light: "FFF0E6", dark: "3A2416")

    static let appSafetyGreen = Color(light: "48A9A6", dark: "5CBDBA")
    static let appWarningRed = Color(light: "E04B2A", dark: "F05A3A")
    static let appModerateYellow = Color(light: "FF9F1C", dark: "FFB040")

    /// 正文：淺色模式深字、深色模式淺字。
    static let appTextDark = Color(light: "2B2520", dark: "F3EEE7")
    /// 次要字：深色模式略亮，避免夜間幾乎看不見。
    static let appTextMuted = Color(light: "6F675F", dark: "B6ADA3")

    init(light lightHex: String, dark darkHex: String) {
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? darkHex : lightHex
                return UIColor(hex: hex)
            }
        )
        #else
        self.init(hex: lightHex)
        #endif
    }

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

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
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
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
#endif
