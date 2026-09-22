import Foundation

/// App Store Connect 商品 ID。上架前請在後台建立同名訂閱／非消耗性商品。
enum SubscriptionProductID: String, CaseIterable, Identifiable {
    case monthly = "com.skincare.premium.monthly"
    case yearly = "com.skincare.premium.yearly"
    case lifetime = "com.skincare.premium.lifetime"

    var id: String { rawValue }

    /// 畫面只賣月費和終身。年費不再上架，識別碼留著以便還原購買。
    static var storeDisplayOrder: [SubscriptionProductID] {
        [.monthly, .lifetime]
    }

    var marketingTitle: String {
        switch self {
        case .monthly: return "月費"
        case .yearly: return "年費"
        case .lifetime: return "終身"
        }
    }

    var marketingSubtitle: String {
        switch self {
        case .monthly, .yearly, .lifetime: return ""
        }
    }

    /// 後備顯示價（StoreKit 尚未回傳時）。實際結帳以 App Store 為準。
    var fallbackPriceLabel: String {
        switch self {
        case .monthly: return "NT$60／月"
        case .yearly: return "NT$490／年"
        case .lifetime: return "NT$390"
        }
    }

    var isSubscription: Bool {
        self != .lifetime
    }

    var isFeatured: Bool {
        self == .lifetime
    }
}
