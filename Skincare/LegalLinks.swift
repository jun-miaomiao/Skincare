import Foundation

/// App Store／付費牆使用的公開法務連結（GitHub Pages）。
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://miaomiaokanapp.github.io/miaomiaokan-legal/privacy.html")!
    static let termsOfUse = URL(string: "https://miaomiaokanapp.github.io/miaomiaokan-legal/terms.html")!
    /// Apple 標準 EULA（訂閱審核常用）。
    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
