import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

enum SkinType: String, CaseIterable, Identifiable, Codable {
    case oily = "油性肌"
    case dry = "乾性肌"
    case combination = "混合肌"
    case normal = "中性肌"

    var id: String { rawValue }
}

@Model
final class UserProfile {
    var nickname: String = ""
    var avatarData: Data? = nil
    var skinTypeRawValue: String = SkinType.combination.rawValue
    var isSensitiveSkin: Bool = false
    var avoidAlcohol: Bool = false
    var avoidFragrance: Bool = false
    var avoidPreservatives: Bool = false
    var avoidEssentialOils: Bool = false
    var avoidMineralOil: Bool = false
    var avoidComedogenic: Bool = false
    var avoidAcids: Bool = false
    var customBlockedIngredientsRaw: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        nickname: String = "",
        avatarData: Data? = nil,
        skinTypeRawValue: String = SkinType.combination.rawValue,
        isSensitiveSkin: Bool = false,
        avoidAlcohol: Bool = false,
        avoidFragrance: Bool = false,
        avoidPreservatives: Bool = false,
        avoidEssentialOils: Bool = false,
        avoidMineralOil: Bool = false,
        avoidComedogenic: Bool = false,
        avoidAcids: Bool = false,
        customBlockedIngredientsRaw: String = "[]"
    ) {
        self.nickname = nickname
        self.avatarData = avatarData
        self.skinTypeRawValue = skinTypeRawValue
        self.isSensitiveSkin = isSensitiveSkin
        self.avoidAlcohol = avoidAlcohol
        self.avoidFragrance = avoidFragrance
        self.avoidPreservatives = avoidPreservatives
        self.avoidEssentialOils = avoidEssentialOils
        self.avoidMineralOil = avoidMineralOil
        self.avoidComedogenic = avoidComedogenic
        self.avoidAcids = avoidAcids
        self.customBlockedIngredientsRaw = customBlockedIngredientsRaw
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var skinType: SkinType {
        get { SkinType(rawValue: skinTypeRawValue) ?? .combination }
        set { skinTypeRawValue = newValue.rawValue }
    }

    func touchUpdatedAt() {
        updatedAt = Date()
    }

    func isAvoidEnabled(for option: AvoidIngredientOption) -> Bool {
        switch option.id {
        case "denatured-alcohol": return avoidAlcohol
        case "artificial-fragrance": return avoidFragrance
        case "paraben": return avoidPreservatives
        case "mineral-oil": return avoidMineralOil
        case "comedogenic": return avoidComedogenic
        case "essential-oils": return avoidEssentialOils
        case "acids": return avoidAcids
        default: return false
        }
    }

    func setAvoidEnabled(_ enabled: Bool, for option: AvoidIngredientOption) {
        switch option.id {
        case "denatured-alcohol": avoidAlcohol = enabled
        case "artificial-fragrance": avoidFragrance = enabled
        case "paraben": avoidPreservatives = enabled
        case "mineral-oil": avoidMineralOil = enabled
        case "comedogenic": avoidComedogenic = enabled
        case "essential-oils": avoidEssentialOils = enabled
        case "acids": avoidAcids = enabled
        default: break
        }
        touchUpdatedAt()
    }

    var blockedTags: [String] {
        IngredientMatcher.blockedTags(from: self)
    }

    var customBlockedIngredients: [String] {
        get { ScanRecordCodec.decode(customBlockedIngredientsRaw) }
        set {
            customBlockedIngredientsRaw = ScanRecordCodec.encode(newValue)
            touchUpdatedAt()
        }
    }

    func addCustomBlockedIngredients(_ names: [String]) {
        var current = customBlockedIngredients
        var existingKeys = Set(current.map { IngredientMatcher.normalizedForMatching($0) })

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = IngredientMatcher.normalizedForMatching(trimmed)
            guard !existingKeys.contains(key) else { continue }
            existingKeys.insert(key)
            current.append(trimmed)
        }

        customBlockedIngredients = current
    }

    func removeCustomBlockedIngredient(_ name: String) {
        let key = IngredientMatcher.normalizedForMatching(name)
        customBlockedIngredients = customBlockedIngredients.filter {
            IngredientMatcher.normalizedForMatching($0) != key
        }
    }

    func addQuickPack(_ pack: SensitiveIngredientQuickPack) {
        addCustomBlockedIngredients(pack.ingredients)
    }

    func isQuickPackFullyAdded(_ pack: SensitiveIngredientQuickPack) -> Bool {
        let existing = Set(customBlockedIngredients.map { IngredientMatcher.normalizedForMatching($0) })
        return pack.ingredients.allSatisfy {
            existing.contains(IngredientMatcher.normalizedForMatching($0))
        }
    }
}

struct AvoidIngredientOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String

    var keywords: [String] {
        IngredientMatcher.keywords(for: id)
    }

    static let all: [AvoidIngredientOption] = [
        AvoidIngredientOption(
            id: "denatured-alcohol",
            title: "變性酒精",
            subtitle: "Alcohol Denat.、エタノール、에탄올 等"
        ),
        AvoidIngredientOption(
            id: "artificial-fragrance",
            title: "人工香精",
            subtitle: "Fragrance、香料、향료 等"
        ),
        AvoidIngredientOption(
            id: "paraben",
            title: "Paraben 類防腐劑",
            subtitle: "Paraben、パラベン、페녹시에탄올 等"
        ),
        AvoidIngredientOption(
            id: "acids",
            title: "刺激酸類",
            subtitle: "AHA / BHA、サリチル酸、살리실릭애씨드 等"
        ),
        AvoidIngredientOption(
            id: "mineral-oil",
            title: "礦物油",
            subtitle: "Mineral Oil、ミネラルオイル、미네랄오일 等"
        ),
        AvoidIngredientOption(
            id: "comedogenic",
            title: "高致痘成分",
            subtitle: "Isopropyl Myristate、ココナッツオイル 等"
        ),
        AvoidIngredientOption(
            id: "essential-oils",
            title: "精油",
            subtitle: "Essential Oil、エッセンシャルオイル、에센셜오일 等"
        )
    ]
}

struct SensitiveIngredientQuickPack: Identifiable {
    let id: String
    let title: String
    let ingredients: [String]

    static let all: [SensitiveIngredientQuickPack] = [
        SensitiveIngredientQuickPack(
            id: "comedogenic-oils",
            title: "致痘油脂類",
            ingredients: [
                "Isopropyl Myristate", "Myristyl Myristate", "Coconut Oil",
                "Cocos Nucifera", "Lanolin", "肉豆蔻酸異丙酯", "椰子油", "羊毛脂"
            ]
        ),
        SensitiveIngredientQuickPack(
            id: "chemical-sunscreen",
            title: "化學防曬劑",
            ingredients: [
                "Avobenzone", "Octinoxate", "Oxybenzone", "Homosalate",
                "Octocrylene", "Octisalate", "甲氧基肉桂酸酯", "二苯甲酮"
            ]
        ),
        SensitiveIngredientQuickPack(
            id: "sls-surfactant",
            title: "SLS 界面活性劑",
            ingredients: [
                "Sodium Lauryl Sulfate", "SLS", "Sodium Laureth Sulfate", "SLES",
                "Ammonium Lauryl Sulfate", "月桂基硫酸钠", "十二烷基硫酸钠"
            ]
        ),
        SensitiveIngredientQuickPack(
            id: "formaldehyde-releasers",
            title: "甲醛釋放劑",
            ingredients: [
                "DMDM Hydantoin", "Imidazolidinyl Urea", "Quaternium-15",
                "Diazolidinyl Urea", "甲醛釋放", "咪唑烷基脲"
            ]
        ),
        SensitiveIngredientQuickPack(
            id: "silicone-heavy",
            title: "高含量矽靈",
            ingredients: [
                "Dimethicone", "Cyclopentasiloxane", "Cyclohexasiloxane",
                "Dimethiconol", "聚二甲基矽氧烷", "環五聚二甲基矽氧烷"
            ]
        ),
        SensitiveIngredientQuickPack(
            id: "retinoid-family",
            title: "A酸／視黃醇系列",
            ingredients: [
                "Retinol", "Retinal", "Retinaldehyde", "Retinoic Acid",
                "Tretinoin", "Adapalene", "Hydroxypinacolone Retinoate",
                "Retinyl Palmitate", "Retinyl Acetate",
                "視黃醇", "視黃醛", "視黃酸", "A醇", "A醛", "A酸", "維A酸"
            ]
        )
    ]
}

@Model
final class FavoriteProductRecord {
    var recordID: String = UUID().uuidString
    var brand: String = ""
    var name: String = ""
    var category: String = ""
    var highlight: String = ""
    var note: String = ""
    var accentRed: Double = 0.62
    var accentGreen: Double = 0.68
    var accentBlue: Double = 0.58
    var sourceScanRecordID: String = ""
    var recognizedIngredientsRaw: String = "[]"
    var matchedIngredientsRaw: String = "[]"
    var blockedTagsRaw: String = "[]"
    var customBlockedIngredientsRaw: String = "[]"
    var resolvedIngredientsRaw: String = "[]"
    var ingredientCount: Int = 0
    /// 保養時段：`morning` / `evening`；空字串＝未設定（仍顯示星星）。
    var routineSlotRaw: String = ""
    /// 上次詳情比對時的風險開關與自訂清單。空字串代表還沒用這份設定算過。
    var alertEvaluationKey: String = ""
    var createdAt: Date = Date()

    init(
        recordID: String = UUID().uuidString,
        brand: String = "",
        name: String = "",
        category: String = "",
        highlight: String = "",
        note: String = "",
        accentRed: Double = 0.62,
        accentGreen: Double = 0.68,
        accentBlue: Double = 0.58,
        sourceScanRecordID: String = "",
        recognizedIngredientsRaw: String = "[]",
        matchedIngredientsRaw: String = "[]",
        blockedTagsRaw: String = "[]",
        customBlockedIngredientsRaw: String = "[]",
        resolvedIngredientsRaw: String = "[]",
        ingredientCount: Int = 0,
        routineSlotRaw: String = "",
        alertEvaluationKey: String = ""
    ) {
        self.recordID = recordID
        self.brand = brand
        self.name = name
        self.category = category
        self.highlight = highlight
        self.note = note
        self.accentRed = accentRed
        self.accentGreen = accentGreen
        self.accentBlue = accentBlue
        self.sourceScanRecordID = sourceScanRecordID
        self.recognizedIngredientsRaw = recognizedIngredientsRaw
        self.matchedIngredientsRaw = matchedIngredientsRaw
        self.blockedTagsRaw = blockedTagsRaw
        self.customBlockedIngredientsRaw = customBlockedIngredientsRaw
        self.resolvedIngredientsRaw = resolvedIngredientsRaw
        self.ingredientCount = ingredientCount
        self.routineSlotRaw = routineSlotRaw
        self.alertEvaluationKey = alertEvaluationKey
        self.createdAt = Date()
    }

    var recognizedIngredients: [String] {
        ScanRecordCodec.decode(recognizedIngredientsRaw)
    }

    var matchedIngredients: [String] {
        ScanRecordCodec.decode(matchedIngredientsRaw)
    }

    var blockedTags: [String] {
        ScanRecordCodec.decode(blockedTagsRaw)
    }

    var customBlockedIngredients: [String] {
        ScanRecordCodec.decode(customBlockedIngredientsRaw)
    }

    /// 掃描當下已解析的成分快照（開啟最愛詳情時直接讀取，不再重跑 Parser）。
    var resolvedIngredients: [PersistedScannedIngredient] {
        ScanRecordCodec.decodeSnapshots(resolvedIngredientsRaw)
    }

    var hasAvoidWarnings: Bool {
        !matchedIngredients.isEmpty
    }

    /// 最愛列表左側徽章：未設定時為星星；已設定顯示「早」或「晚」。
    var routineSlotBadgeText: String? {
        switch routineSlotRaw {
        case "morning": return "早"
        case "evening": return "晚"
        default: return nil
        }
    }

    var displayIngredientCount: Int {
        let snaps = resolvedIngredients
        if !snaps.isEmpty {
            return snaps.filter { $0.databaseItem != nil }.count
        }
        return ingredientCount > 0 ? ingredientCount : recognizedIngredients.count
    }

    var formattedCreatedAt: String {
        createdAt.formatted(date: .numeric, time: .shortened)
    }
}

enum FavoriteManager {
    /// 由已載入的 `@Query` 結果建立記憶體快取，供 List／ViewBuilder 以 O(1) 判斷。
    static func favoritedSourceScanIDs(from records: [FavoriteProductRecord]) -> Set<String> {
        var ids = Set<String>()
        ids.reserveCapacity(records.count)
        for record in records where !record.sourceScanRecordID.isEmpty {
            ids.insert(record.sourceScanRecordID)
        }
        return ids
    }

    static func isFavorited(_ scanRecordID: String, favoritedScanIDs: Set<String>) -> Bool {
        !scanRecordID.isEmpty && favoritedScanIDs.contains(scanRecordID)
    }

    /// 由已載入的 `@Query` 結果建立記憶體快取，供 List／ViewBuilder 以 O(1) 判斷成分最愛。
    static func favoritedIngredientKeys(from records: [FavoriteIngredientRecord]) -> Set<String> {
        var keys = Set<String>()
        keys.reserveCapacity(records.count * 2)
        for record in records {
            let idKey = normalizeIngredientKey(record.ingredientID)
            if !idKey.isEmpty { keys.insert(idKey) }
            let enKey = normalizeIngredientKey(record.englishName)
            if !enKey.isEmpty { keys.insert(enKey) }
        }
        return keys
    }

    static func isIngredientFavorited(
        ingredientID: String = "",
        englishName: String = "",
        favoritedKeys: Set<String>
    ) -> Bool {
        let idKey = normalizeIngredientKey(ingredientID)
        if !idKey.isEmpty, favoritedKeys.contains(idKey) { return true }
        let enKey = normalizeIngredientKey(englishName)
        return !enKey.isEmpty && favoritedKeys.contains(enKey)
    }

    static func isIngredientFavorited(
        _ item: IngredientItem,
        favoritedKeys: Set<String>
    ) -> Bool {
        isIngredientFavorited(
            ingredientID: item.id,
            englishName: item.englishName,
            favoritedKeys: favoritedKeys
        )
    }

    private static func normalizeIngredientKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func favoriteRecordID(
        forScanRecordID scanRecordID: String?,
        in records: [FavoriteProductRecord]
    ) -> String? {
        guard let scanRecordID, !scanRecordID.isEmpty else { return nil }
        return records.first(where: { $0.sourceScanRecordID == scanRecordID })?.recordID
    }

    static func favoriteDisplayName(
        forScanRecordID scanRecordID: String?,
        in records: [FavoriteProductRecord]
    ) -> String? {
        guard let scanRecordID, !scanRecordID.isEmpty else { return nil }
        let name = records.first(where: { $0.sourceScanRecordID == scanRecordID })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        return name
    }

    /// 僅供使用者操作（加入最愛等）一次性檢查；禁止在 List Row / body 呼叫。
    @MainActor
    static func isScanRecordFavorited(_ scanRecordID: String, in context: ModelContext) -> Bool {
        guard !scanRecordID.isEmpty else { return false }
        var descriptor = FetchDescriptor<FavoriteProductRecord>(
            predicate: #Predicate<FavoriteProductRecord> { record in
                record.sourceScanRecordID == scanRecordID
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.isEmpty == false
    }

    /// 僅供導航／寫入路徑一次性查詢；禁止在 List Row / body 呼叫。
    @MainActor
    static func favoriteRecordID(forScanRecordID scanRecordID: String?, in context: ModelContext) -> String? {
        guard let scanRecordID, !scanRecordID.isEmpty else { return nil }
        var descriptor = FetchDescriptor<FavoriteProductRecord>(
            predicate: #Predicate<FavoriteProductRecord> { record in
                record.sourceScanRecordID == scanRecordID
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.recordID
    }

    @MainActor
    static func updateProductName(forScanRecordID scanRecordID: String, name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scanRecordID.isEmpty, !trimmed.isEmpty else { return }
        var descriptor = FetchDescriptor<FavoriteProductRecord>(
            predicate: #Predicate<FavoriteProductRecord> { record in
                record.sourceScanRecordID == scanRecordID
            }
        )
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first else { return }
        entity.name = trimmed
        try? context.save()
    }

    @MainActor
    static func updateProductName(recordID: String, name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordID.isEmpty, !trimmed.isEmpty else { return }
        var descriptor = FetchDescriptor<FavoriteProductRecord>(
            predicate: #Predicate<FavoriteProductRecord> { record in
                record.recordID == recordID
            }
        )
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first else { return }
        entity.name = trimmed
        try? context.save()
    }

    @MainActor
    @discardableResult
    static func addFromScanHistory(_ entity: ScanHistoryRecordEntity, in context: ModelContext) -> Bool {
        guard !isScanRecordFavorited(entity.recordID, in: context) else { return false }

        let matched = entity.matchedIngredients
        let record = FavoriteProductRecord(
            name: entity.title,
            category: "掃描收藏",
            highlight: matched.isEmpty
                ? "共 \(entity.ingredientCount) 項成分"
                : "命中 \(matched.count) 項風險成分",
            note: "",
            accentRed: matched.isEmpty ? 0.55 : 0.78,
            accentGreen: matched.isEmpty ? 0.62 : 0.48,
            accentBlue: matched.isEmpty ? 0.54 : 0.42,
            sourceScanRecordID: entity.recordID,
            recognizedIngredientsRaw: entity.recognizedIngredientsRaw,
            matchedIngredientsRaw: entity.matchedIngredientsRaw,
            blockedTagsRaw: entity.blockedTagsRaw,
            resolvedIngredientsRaw: entity.resolvedIngredientsRaw,
            ingredientCount: entity.ingredientCount
        )
        context.insert(record)
        try? context.save()
        triggerFavoriteHaptic()
        return true
    }

    @MainActor
    @discardableResult
    static func addFromPayload(
        _ payload: ScanResultPayload,
        productName: String,
        in context: ModelContext
    ) -> Bool {
        if let scanID = payload.historyRecordID, isScanRecordFavorited(scanID, in: context) {
            return false
        }

        let matched = payload.matchedAlerts
        let snapshots = payload.resolvedIngredients.isEmpty
            ? PersistedScannedIngredient.buildSnapshots(
                ingredientNames: payload.ingredients,
                matchedAlerts: matched,
                blockedTags: payload.blockedTags,
                customBlockedIngredients: payload.customBlockedIngredients
            )
            : payload.resolvedIngredients

        let record = FavoriteProductRecord(
            name: productName,
            category: "掃描收藏",
            highlight: matched.isEmpty
                ? "共 \(payload.ingredients.count) 項成分"
                : "命中 \(matched.count) 項風險成分",
            note: "",
            accentRed: matched.isEmpty ? 0.55 : 0.78,
            accentGreen: matched.isEmpty ? 0.62 : 0.48,
            accentBlue: matched.isEmpty ? 0.54 : 0.42,
            sourceScanRecordID: payload.historyRecordID ?? "",
            recognizedIngredientsRaw: ScanRecordCodec.encode(payload.ingredients),
            matchedIngredientsRaw: ScanRecordCodec.encode(matched),
            blockedTagsRaw: ScanRecordCodec.encode(payload.blockedTags),
            customBlockedIngredientsRaw: ScanRecordCodec.encode(payload.customBlockedIngredients),
            resolvedIngredientsRaw: ScanRecordCodec.encodeSnapshots(snapshots),
            ingredientCount: payload.ingredients.count
        )
        context.insert(record)
        try? context.save()
        triggerFavoriteHaptic()
        return true
    }

    /// 最愛詳情頁手動編輯成分後寫回。
    @MainActor
    static func updateRecognizedIngredients(
        recordID: String,
        ingredients: [String],
        matchedIngredients: [String],
        resolvedSnapshots: [PersistedScannedIngredient],
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<FavoriteProductRecord>()
        guard let entities = try? context.fetch(descriptor),
              let entity = entities.first(where: { $0.recordID == recordID }) else {
            return
        }
        entity.recognizedIngredientsRaw = ScanRecordCodec.encode(ingredients)
        entity.matchedIngredientsRaw = ScanRecordCodec.encode(matchedIngredients)
        entity.resolvedIngredientsRaw = ScanRecordCodec.encodeSnapshots(resolvedSnapshots)
        entity.ingredientCount = ingredients.count
        entity.highlight = matchedIngredients.isEmpty
            ? "共 \(ingredients.count) 項成分"
            : "命中 \(matchedIngredients.count) 項風險成分"
        entity.alertEvaluationKey = ""
        try? context.save()
    }

    @MainActor
    @discardableResult
    static func addIngredient(
        _ item: IngredientItem,
        in context: ModelContext
    ) -> Bool {
        addIngredient(
            ingredientID: item.id,
            chineseName: item.chineseName,
            englishName: item.englishName,
            in: context
        )
    }

    @MainActor
    @discardableResult
    static func addIngredient(
        ingredientID: String,
        chineseName: String,
        englishName: String,
        in context: ModelContext
    ) -> Bool {
        let id = ingredientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty || !en.isEmpty || !zh.isEmpty else { return false }

        let resolvedID = id.isEmpty ? en.lowercased() : id
        guard !resolvedID.isEmpty else { return false }

        if let existing = try? context.fetch(FetchDescriptor<FavoriteIngredientRecord>()),
           existing.contains(where: {
               $0.ingredientID.caseInsensitiveCompare(resolvedID) == .orderedSame
                   || (!$0.englishName.isEmpty && $0.englishName.caseInsensitiveCompare(en) == .orderedSame && !en.isEmpty)
           }) {
            return false
        }

        context.insert(
            FavoriteIngredientRecord(
                ingredientID: resolvedID,
                chineseName: zh.isEmpty ? en : zh,
                englishName: en.isEmpty ? zh : en
            )
        )
        try? context.save()
        triggerFavoriteHaptic()
        return true
    }

    @MainActor
    @discardableResult
    static func removeIngredient(
        ingredientID: String = "",
        englishName: String = "",
        in context: ModelContext
    ) -> Bool {
        let idKey = normalizeIngredientKey(ingredientID)
        let enKey = normalizeIngredientKey(englishName)
        guard !idKey.isEmpty || !enKey.isEmpty else { return false }
        guard let all = try? context.fetch(FetchDescriptor<FavoriteIngredientRecord>()) else { return false }

        let matches = all.filter { record in
            let rid = normalizeIngredientKey(record.ingredientID)
            let ren = normalizeIngredientKey(record.englishName)
            if !idKey.isEmpty, rid == idKey { return true }
            if !enKey.isEmpty, (ren == enKey || rid == enKey) { return true }
            if !idKey.isEmpty, ren == idKey { return true }
            return false
        }
        guard !matches.isEmpty else { return false }
        for match in matches {
            context.delete(match)
        }
        try? context.save()
        return true
    }

    @MainActor
    @discardableResult
    static func removeIngredient(_ item: IngredientItem, in context: ModelContext) -> Bool {
        removeIngredient(ingredientID: item.id, englishName: item.englishName, in: context)
    }

    /// 回傳操作後是否為「已收藏」。
    @MainActor
    @discardableResult
    static func toggleIngredientFavorite(
        ingredientID: String,
        chineseName: String,
        englishName: String,
        favoritedKeys: Set<String>,
        in context: ModelContext
    ) -> Bool {
        if isIngredientFavorited(
            ingredientID: ingredientID,
            englishName: englishName,
            favoritedKeys: favoritedKeys
        ) {
            _ = removeIngredient(ingredientID: ingredientID, englishName: englishName, in: context)
            return false
        }
        _ = addIngredient(
            ingredientID: ingredientID,
            chineseName: chineseName,
            englishName: englishName,
            in: context
        )
        return true
    }

    @MainActor
    @discardableResult
    static func toggleIngredientFavorite(
        _ item: IngredientItem,
        favoritedKeys: Set<String>,
        in context: ModelContext
    ) -> Bool {
        toggleIngredientFavorite(
            ingredientID: item.id,
            chineseName: item.chineseName,
            englishName: item.englishName,
            favoritedKeys: favoritedKeys,
            in: context
        )
    }

    static func triggerFavoriteHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

@Model
final class FavoriteIngredientRecord {
    var recordID: String = UUID().uuidString
    var ingredientID: String = ""
    var chineseName: String = ""
    var englishName: String = ""
    var createdAt: Date = Date()

    init(
        recordID: String = UUID().uuidString,
        ingredientID: String = "",
        chineseName: String = "",
        englishName: String = ""
    ) {
        self.recordID = recordID
        self.ingredientID = ingredientID
        self.chineseName = chineseName
        self.englishName = englishName
        self.createdAt = Date()
    }
}

@Model
final class ScanHistoryRecordEntity {
    var recordID: String = UUID().uuidString
    var title: String = ""
    var scannedAt: Date = Date()
    var summary: String = ""
    var ingredientCount: Int = 0
    var statusRawValue: String = "已完成"
    var matchedIngredientsRaw: String = "[]"
    var recognizedIngredientsRaw: String = "[]"
    var blockedTagsRaw: String = "[]"
    /// 掃描當下已解析完成的成分快照 JSON（含燈號／中文／功效）。
    var resolvedIngredientsRaw: String = "[]"
    var imageCacheData: Data? = nil
    var isRead: Bool = false
    var createdAt: Date = Date()
    /// 上次詳情比對時的風險開關與自訂清單。空字串代表還沒用這份設定算過。
    var alertEvaluationKey: String = ""

    init(
        recordID: String = UUID().uuidString,
        title: String = "",
        scannedAt: Date = Date(),
        summary: String = "",
        ingredientCount: Int = 0,
        statusRawValue: String = ScanHistoryStatus.completed.rawValue,
        matchedIngredientsRaw: String = "[]",
        recognizedIngredientsRaw: String = "[]",
        blockedTagsRaw: String = "[]",
        resolvedIngredientsRaw: String = "[]",
        imageCacheData: Data? = nil,
        isRead: Bool = false,
        alertEvaluationKey: String = ""
    ) {
        self.recordID = recordID
        self.title = title
        self.scannedAt = scannedAt
        self.summary = summary
        self.ingredientCount = ingredientCount
        self.statusRawValue = statusRawValue
        self.matchedIngredientsRaw = matchedIngredientsRaw
        self.recognizedIngredientsRaw = recognizedIngredientsRaw
        self.blockedTagsRaw = blockedTagsRaw
        self.resolvedIngredientsRaw = resolvedIngredientsRaw
        self.imageCacheData = imageCacheData
        self.isRead = isRead
        self.createdAt = Date()
        self.alertEvaluationKey = alertEvaluationKey
    }

    var status: ScanHistoryStatus {
        ScanHistoryStatus(rawValue: statusRawValue) ?? .completed
    }

    var matchedIngredients: [String] {
        ScanRecordCodec.decode(matchedIngredientsRaw)
    }

    var recognizedIngredients: [String] {
        ScanRecordCodec.decode(recognizedIngredientsRaw)
    }

    var blockedTags: [String] {
        ScanRecordCodec.decode(blockedTagsRaw)
    }

    var resolvedIngredients: [PersistedScannedIngredient] {
        ScanRecordCodec.decodeSnapshots(resolvedIngredientsRaw)
    }
}

/// 掃描當下持久化的單一成分快照（開啟紀錄時直接顯示，不再重跑字典比對）。
struct PersistedScannedIngredient: Codable, Hashable, Sendable {
    var name: String
    var originalOrder: Int
    var isBlocked: Bool
    var databaseItem: IngredientItem?
    /// 詳情上次算完的標籤。舊快照沒有這個欄位。
    var storedAlertTags: [PersistedAlertTag] = []
    /// 優先留意排序。9 代表不在優先留意。
    var highlightRank: Int = 9

    init(
        name: String,
        originalOrder: Int,
        isBlocked: Bool,
        databaseItem: IngredientItem?,
        storedAlertTags: [PersistedAlertTag] = [],
        highlightRank: Int = 9
    ) {
        self.name = name
        self.originalOrder = originalOrder
        self.isBlocked = isBlocked
        self.databaseItem = databaseItem
        self.storedAlertTags = storedAlertTags
        self.highlightRank = highlightRank
    }

    enum CodingKeys: String, CodingKey {
        case name
        case originalOrder
        case isBlocked
        case databaseItem
        case storedAlertTags
        case highlightRank
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        originalOrder = try container.decode(Int.self, forKey: .originalOrder)
        isBlocked = try container.decode(Bool.self, forKey: .isBlocked)
        databaseItem = try container.decodeIfPresent(IngredientItem.self, forKey: .databaseItem)
        storedAlertTags = try container.decodeIfPresent([PersistedAlertTag].self, forKey: .storedAlertTags) ?? []
        highlightRank = try container.decodeIfPresent(Int.self, forKey: .highlightRank) ?? 9
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(originalOrder, forKey: .originalOrder)
        try container.encode(isBlocked, forKey: .isBlocked)
        try container.encodeIfPresent(databaseItem, forKey: .databaseItem)
        try container.encode(storedAlertTags, forKey: .storedAlertTags)
        try container.encode(highlightRank, forKey: .highlightRank)
    }

    /// 僅在「掃描／手動編輯當下」呼叫：對已切分好的名稱做一次字典解析。
    static func buildSnapshots(
        ingredientNames: [String],
        matchedAlerts: [String],
        blockedTags: [String],
        customBlockedIngredients: [String]
    ) -> [PersistedScannedIngredient] {
        IngredientDatabaseManager.shared.ensureLoaded()
        let cleaned = SequentialOverlapMerger.stripRedundantUnknowns(
            SequentialOverlapMerger.orderPreservingUnique(ingredientNames)
        )
        return cleaned.enumerated().map { index, name in
            // 與掃描管線走同一條兩階段路徑；未命中就保留原字串，不落入寬鬆前綴比對。
            let resolved = IngredientMatcher.matchToken(name)
            let displayName = resolved?.englishName ?? name
            let isBlocked = IngredientRiskEvaluator.isRiskWarning(
                name: displayName,
                databaseItem: resolved,
                blockedTags: blockedTags,
                customIngredients: customBlockedIngredients,
                alerts: matchedAlerts
            )
            return PersistedScannedIngredient(
                name: displayName,
                originalOrder: index + 1,
                isBlocked: isBlocked,
                databaseItem: resolved
            )
        }
    }
}

struct PersistedAlertTag: Codable, Hashable, Sendable {
    var kind: String
    var text: String
    var reason: String

    init(tag: IngredientAlertTag) {
        switch tag.kind {
        case .personalCustom: kind = "personalCustom"
        case .toggleRisk: kind = "toggleRisk"
        case .skinCaution: kind = "skinCaution"
        case .skinFriendly: kind = "skinFriendly"
        case .traceNote: kind = "traceNote"
        }
        text = tag.text
        reason = tag.reason
    }
}

extension IngredientAlertTag {
    init?(stored: PersistedAlertTag) {
        let resolvedKind: Kind
        switch stored.kind {
        case "personalCustom": resolvedKind = .personalCustom
        case "toggleRisk": resolvedKind = .toggleRisk
        case "skinCaution": resolvedKind = .skinCaution
        case "skinFriendly": resolvedKind = .skinFriendly
        case "traceNote": resolvedKind = .traceNote
        default: return nil
        }
        self.init(kind: resolvedKind, text: stored.text, reason: stored.reason)
    }
}

/// 風險判定（與詳情列共用），可供掃描持久化與 UI 使用。
enum IngredientRiskEvaluator {
    static func isRiskWarning(
        name: String,
        databaseItem: IngredientItem?,
        blockedTags: [String],
        customIngredients: [String],
        alerts: [String]
    ) -> Bool {
        // 未命中字典 → 永不進風險警示區。
        // 「優先留意」只跟使用者開啟的避開開關與自訂清單走，不用字典分數、也不用掃描摘要字串。
        guard let databaseItem else { return false }
        _ = alerts

        let checkName = databaseItem.englishName
        if IngredientMatcher.isIngredientBlocked(
            checkName,
            blockedTags: blockedTags,
            customIngredients: customIngredients
        ) {
            return true
        }
        return IngredientMatcher.isIngredientBlocked(
            name,
            blockedTags: blockedTags,
            customIngredients: customIngredients
        )
    }

    static func matchesAlert(name: String, alerts: [String]) -> Bool {
        let nameKey = IngredientMatcher.normalizedForMatching(name)
        guard nameKey.count >= 3 else { return false }
        guard nameKey.count <= 80 else { return false }
        return alerts.contains { alert in
            let alertKey = IngredientMatcher.normalizedForMatching(alert)
            return alertKey.contains(nameKey) || nameKey.contains(
                alertKey
                    .replacingOccurrences(of: "（", with: " ")
                    .replacingOccurrences(of: "）", with: " ")
            )
        }
    }
}

enum ScanRecordCodec {
    static func encode(_ strings: [String]) -> String {
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func encodeSnapshots(_ items: [PersistedScannedIngredient]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decodeSnapshots(_ raw: String) -> [PersistedScannedIngredient] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PersistedScannedIngredient].self, from: data) else {
            return []
        }
        return decoded
    }
}

/// 風險開關與自訂清單沒變時，詳情不再重算。
enum AlertEvaluationKey {
    static func make(
        blockedTags: [String],
        customBlockedIngredients: [String],
        skinType: SkinType,
        isSensitiveSkin: Bool
    ) -> String {
        let tags = blockedTags.sorted().joined(separator: "\u{1}")
        let custom = customBlockedIngredients
            .map { IngredientMatcher.normalizedForMatching($0) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\u{1}")
        return "\(tags)#\(custom)#\(skinType.rawValue)#\(isSensitiveSkin ? 1 : 0)#v2"
    }
}

/// 整瓶要浮上來的膚質提醒名稱，順序固定。
enum SkinCautionCapsule {
    static func labels(in report: SkinSuitabilityReport) -> [String] {
        guard report.shouldSurfaceSkinCautionInSummary else { return [] }
        let hit = Set(report.hits.filter(\.flag.isCaution).map(\.flag))
        return SkinSuitabilityFlag.allCases.filter { $0.isCaution && hit.contains($0) }.map(\.rawValue)
    }

    static func labels(ingredients: [String], profile: UserProfile) -> [String] {
        let report = SkinSuitabilityEngine.evaluate(
            ingredients: ingredients,
            skinType: profile.skinType,
            isSensitiveSkin: profile.isSensitiveSkin,
            enabledAlertTags: Set(profile.blockedTags)
        )
        return labels(in: report)
    }
}

/// 已存的最愛與紀錄，風險開關或自訂清單變了才重算。
enum SavedAlertSync {
    @MainActor
    static func refreshStoredAlerts(profile: UserProfile?, in context: ModelContext) {
        guard let profile else { return }
        IngredientDatabaseManager.shared.ensureLoaded()
        let tags = profile.blockedTags
        let custom = profile.customBlockedIngredients
        let tagsRaw = ScanRecordCodec.encode(tags)
        let customRaw = ScanRecordCodec.encode(custom)
        let evaluationKey = AlertEvaluationKey.make(
            blockedTags: tags,
            customBlockedIngredients: custom,
            skinType: profile.skinType,
            isSensitiveSkin: profile.isSensitiveSkin
        )
        var changed = false

        let favorites = (try? context.fetch(FetchDescriptor<FavoriteProductRecord>())) ?? []
        for record in favorites {
            if record.alertEvaluationKey == evaluationKey { continue }
            let names = record.recognizedIngredients
            guard !names.isEmpty else { continue }
            let matched = IngredientMatcher.checkAlerts(
                detectedIngredients: names,
                blockedTags: tags,
                customIngredients: custom
            ) + SkinCautionCapsule.labels(ingredients: names, profile: profile)
            let matchedRaw = ScanRecordCodec.encode(matched)
            if record.matchedIngredientsRaw == matchedRaw,
               record.blockedTagsRaw == tagsRaw,
               record.customBlockedIngredientsRaw == customRaw {
                continue
            }
            record.matchedIngredientsRaw = matchedRaw
            record.blockedTagsRaw = tagsRaw
            record.customBlockedIngredientsRaw = customRaw
            record.highlight = matched.isEmpty
                ? "共 \(names.count) 項成分"
                : "命中 \(matched.count) 項風險成分"
            record.accentRed = matched.isEmpty ? 0.55 : 0.78
            record.accentGreen = matched.isEmpty ? 0.62 : 0.48
            record.accentBlue = matched.isEmpty ? 0.54 : 0.42
            record.alertEvaluationKey = ""
            record.resolvedIngredientsRaw = ScanRecordCodec.encodeSnapshots(
                refreshedSnapshots(
                    existing: record.resolvedIngredients,
                    names: names,
                    matched: matched,
                    tags: tags,
                    custom: custom
                )
            )
            changed = true
        }

        let history = (try? context.fetch(FetchDescriptor<ScanHistoryRecordEntity>())) ?? []
        for entity in history {
            if entity.alertEvaluationKey == evaluationKey { continue }
            let names = entity.recognizedIngredients
            guard !names.isEmpty else { continue }
            let matched = IngredientMatcher.checkAlerts(
                detectedIngredients: names,
                blockedTags: tags,
                customIngredients: custom
            ) + SkinCautionCapsule.labels(ingredients: names, profile: profile)
            let matchedRaw = ScanRecordCodec.encode(matched)
            let summary = ScanHistoryWriter.makeSummary(
                ingredientCount: names.count,
                matchedCount: matched.count
            )
            if entity.matchedIngredientsRaw == matchedRaw,
               entity.blockedTagsRaw == tagsRaw,
               entity.summary == summary {
                continue
            }
            entity.matchedIngredientsRaw = matchedRaw
            entity.blockedTagsRaw = tagsRaw
            entity.summary = summary
            entity.alertEvaluationKey = ""
            entity.resolvedIngredientsRaw = ScanRecordCodec.encodeSnapshots(
                refreshedSnapshots(
                    existing: entity.resolvedIngredients,
                    names: names,
                    matched: matched,
                    tags: tags,
                    custom: custom
                )
            )
            changed = true
        }

        if changed {
            try? context.save()
        }
    }

    private static func refreshedSnapshots(
        existing: [PersistedScannedIngredient],
        names: [String],
        matched: [String],
        tags: [String],
        custom: [String]
    ) -> [PersistedScannedIngredient] {
        guard !existing.isEmpty else {
            return PersistedScannedIngredient.buildSnapshots(
                ingredientNames: names,
                matchedAlerts: matched,
                blockedTags: tags,
                customBlockedIngredients: custom
            )
        }
        return existing.map { snap in
            var copy = snap
            copy.isBlocked = IngredientRiskEvaluator.isRiskWarning(
                name: snap.name,
                databaseItem: snap.databaseItem,
                blockedTags: tags,
                customIngredients: custom,
                alerts: matched
            )
            return copy
        }
    }
}

enum ScanHistoryWriter {
    static func makeSummary(ingredientCount: Int, matchedCount: Int) -> String {
        if matchedCount == 0 {
            return ingredientCount == 0 ? "未辨識到成分文字" : "未命中風險清單"
        }
        return "命中 \(matchedCount) 項風險成分"
    }

    /// 舊紀錄曾帶「辨識到 X 項成分，」前綴；列表顯示時剝除。
    static func displaySummary(from stored: String) -> String {
        stored.replacingOccurrences(
            of: #"^辨識到 \d+ 項成分，"#,
            with: "",
            options: .regularExpression
        )
    }

    @MainActor
    @discardableResult
    static func saveScanRecord(
        in context: ModelContext,
        imageData: Data?,
        ingredients: [String],
        matchedIngredients: [String],
        blockedTags: [String] = [],
        customBlockedIngredients: [String] = [],
        title: String = "成分表掃描",
        resolvedSnapshots: [PersistedScannedIngredient]? = nil
    ) -> ScanHistoryRecordEntity {
        #if canImport(UIKit)
        let cachedImage = imageData.flatMap { AvatarImageProcessor.compressedJPEG(from: $0) ?? $0 }
        #else
        let cachedImage = imageData
        #endif

        let summary = makeSummary(
            ingredientCount: ingredients.count,
            matchedCount: matchedIngredients.count
        )

        let snapshots = resolvedSnapshots ?? PersistedScannedIngredient.buildSnapshots(
            ingredientNames: ingredients,
            matchedAlerts: matchedIngredients,
            blockedTags: blockedTags,
            customBlockedIngredients: customBlockedIngredients
        )

        let status: ScanHistoryStatus = ingredients.isEmpty ? .failed : .completed
        let entity = ScanHistoryRecordEntity(
            title: title,
            scannedAt: Date(),
            summary: summary,
            ingredientCount: ingredients.count,
            statusRawValue: status.rawValue,
            matchedIngredientsRaw: ScanRecordCodec.encode(matchedIngredients),
            recognizedIngredientsRaw: ScanRecordCodec.encode(ingredients),
            blockedTagsRaw: ScanRecordCodec.encode(blockedTags),
            resolvedIngredientsRaw: ScanRecordCodec.encodeSnapshots(snapshots),
            imageCacheData: cachedImage
        )
        context.insert(entity)
        try? context.save()
        return entity
    }

    @MainActor
    static func updateRecordTitle(recordID: String, title: String, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let descriptor = FetchDescriptor<ScanHistoryRecordEntity>()
        guard let entities = try? context.fetch(descriptor),
              let entity = entities.first(where: { $0.recordID == recordID }) else {
            return
        }
        entity.title = trimmed
        try? context.save()
    }

    /// 手動編輯／刪除／新增後同步成分清單、快照與摘要。
    @MainActor
    static func updateRecognizedIngredients(
        recordID: String,
        ingredients: [String],
        matchedIngredients: [String],
        resolvedSnapshots: [PersistedScannedIngredient],
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<ScanHistoryRecordEntity>()
        guard let entities = try? context.fetch(descriptor),
              let entity = entities.first(where: { $0.recordID == recordID }) else {
            return
        }

        entity.recognizedIngredientsRaw = ScanRecordCodec.encode(ingredients)
        entity.matchedIngredientsRaw = ScanRecordCodec.encode(matchedIngredients)
        entity.resolvedIngredientsRaw = ScanRecordCodec.encodeSnapshots(resolvedSnapshots)
        entity.ingredientCount = ingredients.count
        entity.alertEvaluationKey = ""
        entity.statusRawValue = (ingredients.isEmpty ? ScanHistoryStatus.failed : ScanHistoryStatus.completed).rawValue

        entity.summary = makeSummary(
            ingredientCount: ingredients.count,
            matchedCount: matchedIngredients.count
        )

        try? context.save()
    }

    @MainActor
    static func markAsRead(recordID: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<ScanHistoryRecordEntity>()
        guard let entities = try? context.fetch(descriptor),
              let entity = entities.first(where: { $0.recordID == recordID }),
              !entity.isRead else {
            return
        }
        entity.isRead = true
        try? context.save()
    }
}

enum SkincareModelContainer {
    /// 已啟用 SwiftData ↔ CloudKit 私有庫同步（需付費 Developer、iCloud 登入、容器 `iCloud.com.jun.Skincare`）。
    /// iCloud 未登入／空間滿時仍以本機庫運作；同步會暫緩，不應擋日常使用。
    static let usesCloudKitSync = true

    /// 啟用 CloudKit 時使用的容器 ID（需與 entitlements 一致）。
    static let cloudKitIdentifier = "iCloud.com.jun.Skincare"

    static let shared: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            FavoriteProductRecord.self,
            FavoriteIngredientRecord.self,
            ScanHistoryRecordEntity.self
        ])

        if usesCloudKitSync {
            do {
                let cloud = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(cloudKitIdentifier)
                )
                return try ModelContainer(for: schema, configurations: [cloud])
            } catch {
                // 容器／簽章／遷移失敗時退回本機，避免整 App 起不來。
                assertionFailure("CloudKit ModelContainer 失敗，改用本機：\(error.localizedDescription)")
            }
        }

        do {
            let local = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("無法建立 SwiftData ModelContainer: \(error.localizedDescription)")
        }
    }()

    static var preview: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            FavoriteProductRecord.self,
            FavoriteIngredientRecord.self,
            ScanHistoryRecordEntity.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()
}

enum DataBootstrap {
    /// 僅確保有一份空白 UserProfile；不注入任何最愛／商品紀錄示範資料。
    static func seedIfNeeded(in context: ModelContext) {
        seedUserProfileIfNeeded(in: context)
    }

    private static func seedUserProfileIfNeeded(in context: ModelContext) {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        guard (try? context.fetch(descriptor))?.isEmpty != false else { return }
        context.insert(UserProfile())
    }
}

extension Notification.Name {
    static let didClearScanHistory = Notification.Name("DidClearScanHistory")
}

enum LocalDataManager {
    /// 僅刪除掃描紀錄，保留我的最愛與 UserProfile 設定。
    @MainActor
    static func clearScanHistory(in context: ModelContext) {
        do {
            try context.delete(model: ScanHistoryRecordEntity.self)
            try context.save()
            NotificationCenter.default.post(name: .didClearScanHistory, object: nil)
        } catch {
            print("一鍵清除失敗: \(error.localizedDescription)")
            fallbackDeleteScanHistory(in: context)
        }
    }

    @MainActor
    private static func fallbackDeleteScanHistory(in context: ModelContext) {
        guard let items = try? context.fetch(FetchDescriptor<ScanHistoryRecordEntity>()) else { return }
        items.forEach { context.delete($0) }
        try? context.save()
        NotificationCenter.default.post(name: .didClearScanHistory, object: nil)
    }
}
