import Foundation

/// App Store／付費牆使用的公開法務連結，以及可公開查閱的法規／成分資料來源。
enum LegalLinks {
    /// 與 App 同 repo 的 GitHub Pages（`main` → `/docs`）。
    static let privacyPolicy = URL(string: "https://jun-miaomiao.github.io/Skincare/privacy.html")!
    static let termsOfUse = URL(string: "https://jun-miaomiao.github.io/Skincare/terms.html")!
    /// Apple 標準 EULA（訂閱審核常用）。
    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 台灣：政府資料開放平臺・化粧品禁止使用成分（食藥署）。
    static let twCosmeticsBanned = URL(string: "https://data.gov.tw/dataset/173684")!
    /// 台灣：政府資料開放平臺・化粧品成分使用限制（食藥署）。
    static let twCosmeticsRestricted = URL(string: "https://data.gov.tw/dataset/173685")!
    /// 歐盟 CosIng 化粧品成分資料庫（公開查詢）。
    static let euCosIng = URL(string: "https://ec.europa.eu/growth/tools-databases/cosing/")!
}
