import Foundation
import StoreKit

/// StoreKit 2 訂閱狀態。免費層不鎖準度；付費解鎖次數、最愛與完整使用節奏。
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInFlight = false
    @Published var lastErrorMessage: String?
    /// 開發用：略過 StoreKit，方便本機驗付費牆。
    @Published var debugPremiumUnlocked = false

    /// 終身早鳥下架後改 `false`，畫面上只留月／年。
    @Published var lifetimeEarlyBirdAvailable = true

    private var updatesTask: Task<Void, Never>?

    var isPremium: Bool {
        if debugPremiumUnlocked { return true }
        return !purchasedProductIDs.isEmpty
    }

    var activePlanLabel: String? {
        if debugPremiumUnlocked { return "開發解鎖" }
        if purchasedProductIDs.contains(SubscriptionProductID.lifetime.rawValue) {
            return "終身"
        }
        if purchasedProductIDs.contains(SubscriptionProductID.yearly.rawValue) {
            return "年費"
        }
        if purchasedProductIDs.contains(SubscriptionProductID.monthly.rawValue) {
            return "月費"
        }
        return nil
    }

    private init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let ids = Set(SubscriptionProductID.allCases.map(\.rawValue))
            let storeProducts = try await Product.products(for: ids)
            products = storeProducts.sorted { lhs, rhs in
                let left = SubscriptionProductID(rawValue: lhs.id)
                let right = SubscriptionProductID(rawValue: rhs.id)
                let leftRank = left.flatMap { SubscriptionProductID.storeDisplayOrder.firstIndex(of: $0) } ?? 99
                let rightRank = right.flatMap { SubscriptionProductID.storeDisplayOrder.firstIndex(of: $0) } ?? 99
                return leftRank < rightRank
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "無法載入方案，請稍後再試。"
            products = []
        }
    }

    func product(for id: SubscriptionProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func visibleProductIDs() -> [SubscriptionProductID] {
        SubscriptionProductID.storeDisplayOrder.filter { id in
            if id == .lifetime, !lifetimeEarlyBirdAvailable { return false }
            return true
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                lastErrorMessage = nil
                return true
            case .userCancelled:
                return false
            case .pending:
                lastErrorMessage = "購買待確認，完成後會自動解鎖。"
                return false
            @unknown default:
                return false
            }
        } catch {
            lastErrorMessage = "購買失敗，請稍後再試。"
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "無法還原購買，請確認 Apple ID。"
        }
    }

    private func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate != nil { continue }
            active.insert(transaction.productID)
        }
        purchasedProductIDs = active
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if let transaction = try? checkVerified(update) {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}

/// 免費層相機／相簿掃描額度（貼上成分不計）。
enum FreeScanQuota {
    static let weeklyCameraScanLimit = 7

    private static let countKey = "freeScan.weekCount"
    private static let weekKey = "freeScan.weekStart"

    static func remainingCameraScans(isPremium: Bool) -> Int? {
        if isPremium { return nil }
        return max(0, weeklyCameraScanLimit - usedCountThisWeek())
    }

    static func canStartCameraScan(isPremium: Bool) -> Bool {
        if isPremium { return true }
        return usedCountThisWeek() < weeklyCameraScanLimit
    }

    static func consumeCameraScan(isPremium: Bool) {
        guard !isPremium else { return }
        rollWeekIfNeeded()
        let defaults = UserDefaults.standard
        defaults.set(usedCountThisWeek() + 1, forKey: countKey)
    }

    static func usedCountThisWeek() -> Int {
        rollWeekIfNeeded()
        return UserDefaults.standard.integer(forKey: countKey)
    }

    private static func rollWeekIfNeeded() {
        let defaults = UserDefaults.standard
        let now = Date()
        let weekStart = calendarStartOfWeek(now)
        let stored = defaults.object(forKey: weekKey) as? Date
        if stored != weekStart {
            defaults.set(weekStart, forKey: weekKey)
            defaults.set(0, forKey: countKey)
        }
    }

    private static func calendarStartOfWeek(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }
}
