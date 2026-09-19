import Foundation

/// App Store Connect 商品 ID。上架前請在後台建立同名訂閱／非消耗性商品。
enum SubscriptionProductID: String, CaseIterable, Identifiable {
    case monthly = "com.skincare.premium.monthly"
    case yearly = "com.skincare.premium.yearly"
    case lifetime = "com.skincare.premium.lifetime"

    var id: String { rawValue }

    /// 畫面排序：月費 → 年費（推薦）→ 終身早鳥。
    static var storeDisplayOrder: [SubscriptionProductID] {
        [.monthly, .yearly, .lifetime]
    }

    var marketingTitle: String {
        switch self {
        case .monthly: return "月費"
        case .yearly: return "年費"
        case .lifetime: return "終身早鳥"
        }
    }

    var marketingSubtitle: String {
        switch self {
        case .monthly: return ""
        case .yearly: return ""
        case .lifetime: return "限量 200 名"
        }
    }

    /// 後備顯示價（StoreKit 尚未回傳時）。實際結帳以 App Store 為準。
    var fallbackPriceLabel: String {
        switch self {
        case .monthly: return "NT$60／月"
        case .yearly: return "NT$490／年"
        case .lifetime: return "NT$690"
        }
    }

    var isSubscription: Bool {
        self != .lifetime
    }

    var isFeatured: Bool {
        self == .yearly
    }
}
