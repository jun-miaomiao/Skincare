import Foundation

/// App Store／付費牆使用的公開法務連結（GitHub Pages）與評級資料來源。
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://miaomiaokanapp.github.io/miaomiaokan-legal/privacy.html")!
    static let termsOfUse = URL(string: "https://miaomiaokanapp.github.io/miaomiaokan-legal/terms.html")!
    /// Apple 標準 EULA（訂閱審核常用）。
    static let appleStandardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// EWG Skin Deep®（成分危害關注度公開資料庫）。
    static let ewgSkinDeep = URL(string: "https://www.ewg.org/skindeep/")!
    /// 歐盟 CosIng 化妝品成分資料庫。
    static let euCosIng = URL(string: "https://ec.europa.eu/growth/tools-databases/cosing/")!
}
