import Foundation
import Security
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
            if products.isEmpty {
                lastErrorMessage = "尚未取得訂閱方案，請稍後重新載入。"
            } else {
                lastErrorMessage = nil
            }
        } catch {
            lastErrorMessage = "無法載入方案，請稍後再試。"
            products = []
        }
    }

    func product(for id: SubscriptionProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    func visibleProductIDs() -> [SubscriptionProductID] {
        SubscriptionProductID.storeDisplayOrder
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

/// 免費層掃描額度。拍照與貼上成分共用，重裝 App 也不重置。
/// 額度視窗為滾動 7 天（用滿須等滿 7 天）。
enum FreeScanQuota {
    static let weeklyCameraScanLimit = 7
    private static let windowDays = 7

    private static let defaultsCountKey = "freeScan.weekCount"
    private static let defaultsWeekKey = "freeScan.weekStart"
    private static let keychainService = "com.jun.Skincare.freeScanQuota"
    private static let keychainAccount = "quota.v2"

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
        var state = rolled(loadState(), now: Date())
        if state.periodStart == nil {
            state.periodStart = Date()
            state.count = 0
        }
        state.count += 1
        saveState(state)
    }

    static func usedCountThisWeek() -> Int {
        let loaded = loadState()
        let state = rolled(loaded, now: Date())
        if state != loaded {
            saveState(state)
        }
        return state.count
    }

    // MARK: - Window math

    struct State: Equatable {
        var periodStart: Date?
        var count: Int
    }

    /// 若已超過 `periodStart + 7 天`，歸零並清掉視窗起點。
    static func rolled(_ state: State, now: Date, windowDays: Int = FreeScanQuota.windowDays) -> State {
        guard let start = state.periodStart else {
            return State(periodStart: nil, count: 0)
        }
        let deadline = Calendar.current.date(byAdding: .day, value: windowDays, to: start) ?? start
        if now >= deadline {
            return State(periodStart: nil, count: 0)
        }
        return State(periodStart: start, count: max(0, state.count))
    }

    // MARK: - Persistence (Keychain survives reinstall)

    private static func loadState() -> State {
        if let data = KeychainStore.read(service: keychainService, account: keychainAccount),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            return State(periodStart: decoded.periodStart, count: decoded.count)
        }

        // 舊版 UserDefaults → 遷移一次到 Keychain（避免升級當下額度怪異歸零／翻倍）
        let defaults = UserDefaults.standard
        if let weekStart = defaults.object(forKey: defaultsWeekKey) as? Date {
            let migrated = State(
                periodStart: weekStart,
                count: max(0, defaults.integer(forKey: defaultsCountKey))
            )
            saveState(migrated)
            defaults.removeObject(forKey: defaultsCountKey)
            defaults.removeObject(forKey: defaultsWeekKey)
            return migrated
        }
        return State(periodStart: nil, count: 0)
    }

    private static func saveState(_ state: State) {
        let payload = Persisted(periodStart: state.periodStart, count: state.count)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        KeychainStore.write(data, service: keychainService, account: keychainAccount)
    }

    private struct Persisted: Codable {
        var periodStart: Date?
        var count: Int
    }
}

/// 極簡 Keychain 讀寫（`AfterFirstUnlockThisDeviceOnly`：同機重裝仍保留，不隨 iCloud 同步他機）。
private enum KeychainStore {
    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    static func write(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
            return
        }
        // 更新失敗時改刪再建，避免殘留損壞項目
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
