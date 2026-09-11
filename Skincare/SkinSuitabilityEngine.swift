import Foundation

/// 與個人檔案膚質聯動的成分適合度標記。
enum SkinSuitabilityFlag: String, Hashable, Sendable, CaseIterable {
    // MARK: Caution
    case sensitiveCaution = "敏感慎用"
    case sensitiveNote = "敏弱注意"
    case irritationCaution = "刺激慎用"
    case comedogenicRisk = "致痘風險"
    case tZoneComedogenic = "T字易致粉刺"

    // MARK: Beneficial（既有）
    case oilyFriendly = "油肌友善"
    case dryFriendly = "乾肌友善"
    case sensitiveFriendly = "敏弱肌友善"
    case cheekMoisturizing = "兩頰保濕友善"
    case tZoneOilControl = "T字控油調理"

    // MARK: Beneficial（明星成分細分）
    case sebumBalance = "調理皮脂"
    case purifyOilControl = "淨化控油"
    case sensitiveRepair = "敏弱修護"
    case barrierStrengthen = "強化屏障"
    case sootheRedness = "舒緩退紅"
    case sootheRepair = "舒緩修護"
    case barrierRepair = "屏障修護"
    case dryAntiAging = "乾肌抗老"
    case firmRepair = "緊緻修護"
    case antioxidantBrighten = "抗氧提亮"
    case peptideFirming = "胜肽緊緻"
    case dryMoisturize = "乾肌滋潤"

    /// 保留枚舉值以相容舊資料；新結果不再產生「微量添加」標籤。
    case traceAddition = "微量添加"

    var rowLabel: String {
        switch self {
        case .sensitiveCaution: return "⚠️ 敏弱慎用"
        case .sensitiveNote: return "⚠️ 敏弱注意"
        case .irritationCaution: return "⚠️ 刺激慎用"
        case .comedogenicRisk: return "⚠️ 易致粉刺"
        case .tZoneComedogenic: return "⚠️ T字易致粉刺"
        case .oilyFriendly: return "🌿 油肌推薦"
        case .dryFriendly: return "✨ 乾肌推薦"
        case .sensitiveFriendly: return "🌿 敏弱肌推薦"
        case .cheekMoisturizing: return "🌿 兩頰保濕友善"
        case .tZoneOilControl: return "🌿 T字控油調理"
        case .sebumBalance: return "🌿 調理皮脂"
        case .purifyOilControl: return "🌿 淨化控油"
        case .sensitiveRepair: return "🌿 敏弱修護"
        case .barrierStrengthen: return "🌿 強化屏障"
        case .sootheRedness: return "🌿 舒緩退紅"
        case .sootheRepair: return "🌿 舒緩修護"
        case .barrierRepair: return "🌿 屏障修護"
        case .dryAntiAging: return "✨ 乾肌抗老"
        case .firmRepair: return "✨ 緊緻修護"
        case .antioxidantBrighten: return "✨ 抗氧提亮"
        case .peptideFirming: return "✨ 胜肽緊緻"
        case .dryMoisturize: return "🌿 乾肌滋潤"
        case .traceAddition: return "微量添加"
        }
    }

    var isCaution: Bool {
        switch self {
        case .sensitiveCaution, .sensitiveNote, .irritationCaution, .comedogenicRisk, .tZoneComedogenic:
            return true
        default:
            return false
        }
    }

    var isBeneficial: Bool {
        switch self {
        case .oilyFriendly, .dryFriendly, .sensitiveFriendly, .cheekMoisturizing, .tZoneOilControl,
             .sebumBalance, .purifyOilControl, .sensitiveRepair, .barrierStrengthen,
             .sootheRedness, .sootheRepair, .barrierRepair, .dryAntiAging, .firmRepair,
             .antioxidantBrighten, .peptideFirming, .dryMoisturize:
            return true
        default:
            return false
        }
    }

    var isTraceNote: Bool { self == .traceAddition }
}

struct SkinSuitabilityHit: Hashable, Sendable, Identifiable {
    var id: String { "\(ingredientKey)|\(flag.rawValue)" }
    let ingredientKey: String
    let displayName: String
    let flag: SkinSuitabilityFlag
    let reason: String
    /// 包裝清單 0-based 位置（用於位置加權）。
    let listIndex: Int

    var positionWeight: Double {
        IngredientPositionWeight.multiplier(for: listIndex)
    }
}

/// 包裝清單位置加權（前排核心 / 中排有效 / 後排微量）。
enum IngredientPositionWeight {
    static func multiplier(for listIndex: Int) -> Double {
        switch listIndex {
        case 0..<5: return 3.0
        case 5..<10: return 1.5
        default: return 0.5
        }
    }

    static func isFrontCore(_ listIndex: Int) -> Bool { listIndex < 5 }
    static func isMidBand(_ listIndex: Int) -> Bool { (5..<10).contains(listIndex) }
    static func isTraceBand(_ listIndex: Int) -> Bool { listIndex >= 10 }
}

struct SkinSuitabilityReport: Sendable {
    let skinType: SkinType
    let isSensitiveSkin: Bool
    let hits: [SkinSuitabilityHit]

    var cautionHits: [SkinSuitabilityHit] {
        hits.filter(\.flag.isCaution)
    }

    var beneficialHits: [SkinSuitabilityHit] {
        hits.filter(\.flag.isBeneficial)
    }

    var beneficialIngredientCount: Int {
        Set(beneficialHits.map(\.ingredientKey)).count
    }

    var sensitiveCautionCount: Int {
        hits.filter {
            $0.flag == .sensitiveCaution || $0.flag == .sensitiveNote || $0.flag == .irritationCaution
        }.count
    }

    var comedogenicCount: Int {
        hits.filter { $0.flag == .comedogenicRisk || $0.flag == .tZoneComedogenic }.count
    }

    var cheekMoisturizingCount: Int {
        hits.filter { $0.flag == .cheekMoisturizing }.count
    }

    var hasCaution: Bool { !cautionHits.isEmpty }

    /// 位置加權適配分數：有益為正、警示為負；後排權重較低。
    var weightedSuitabilityScore: Double {
        hits.reduce(0) { partial, hit in
            let delta = hit.flag.isBeneficial ? 1.0 : (hit.flag.isCaution ? -2.0 : 0)
            return partial + delta * hit.positionWeight
        }
    }

    var hasFrontRowBeneficial: Bool {
        beneficialHits.contains { IngredientPositionWeight.isFrontCore($0.listIndex) }
    }

    var hasFrontRowCaution: Bool {
        cautionHits.contains { IngredientPositionWeight.isFrontCore($0.listIndex) }
    }

    /// 是否應在頂部摘要以膚質警示呈現（後排微量警示若分數仍為正可不主導摘要）。
    var shouldSurfaceSkinCautionInSummary: Bool {
        if hasFrontRowCaution { return true }
        if cautionHits.contains(where: { IngredientPositionWeight.isMidBand($0.listIndex) }) {
            return true
        }
        // 僅後排微量警示：分數明顯為負才拉高警示摘要
        if hasCaution, weightedSuitabilityScore < 0 {
            return true
        }
        return false
    }

    private var beneficialPhrase: String {
        switch skinType {
        case .oily:
            return isSensitiveSkin ? "膚質友善" : "油肌友善"
        case .combination:
            return "兩頰保濕"
        case .dry:
            return isSensitiveSkin ? "膚質友善" : "乾肌友善"
        case .normal:
            return isSensitiveSkin ? "敏弱肌友善" : "膚質友善"
        }
    }

    /// 摘要卡片主文案（不含前綴 emoji；圖示由 UI 系統符號提供）。
    var summaryTitle: String {
        // 前排核心有益，且無須在摘要拉高膚質警示
        if hasFrontRowBeneficial, !shouldSurfaceSkinCautionInSummary {
            return "前排主成分高度契合您的膚質"
        }

        if skinType == .combination {
            let hasTZoneRisk = comedogenicCount > 0 && shouldSurfaceSkinCautionInSummary
            let hasCheekCare = cheekMoisturizingCount > 0
            if hasTZoneRisk && hasCheekCare {
                return "混合肌分區建議：含 T 字需注意成分，建議著重兩頰使用"
            }
            if !shouldSurfaceSkinCautionInSummary && hasCheekCare {
                return "與混合肌適配良好（平衡兩頰保濕）"
            }
            if !shouldSurfaceSkinCautionInSummary && beneficialIngredientCount > 0 {
                return "與混合肌適配良好（含 \(beneficialIngredientCount) 項分區友善成分）"
            }
            if !shouldSurfaceSkinCautionInSummary {
                return "與混合肌適配良好"
            }
            if sensitiveCautionCount > 0 {
                return "含有 \(sensitiveCautionCount) 項敏弱肌需注意成分"
            }
            if comedogenicCount > 0 {
                return "混合肌分區建議：含 T 字需注意成分，建議著重兩頰使用"
            }
            return "部分成分需依膚質留意"
        }

        if !shouldSurfaceSkinCautionInSummary {
            if beneficialIngredientCount > 0 {
                return "與您的膚質高度契合（含 \(beneficialIngredientCount) 項\(beneficialPhrase)成分）"
            }
            return "與您的膚質高度契合"
        }
        if sensitiveCautionCount > 0 {
            return "含有 \(sensitiveCautionCount) 項敏弱肌需注意成分"
        }
        if comedogenicCount > 0 {
            return "含有 \(comedogenicCount) 項易致粉刺成分"
        }
        return "部分成分需依膚質留意"
    }

    var summarySubtitle: String {
        if !shouldSurfaceSkinCautionInSummary {
            return "依目前膚質設定（\(skinType.rawValue)\(isSensitiveSkin ? "・敏感肌" : "")），未偵測到需特別避開的成分。"
        }
        var parts: [String] = []
        if sensitiveCautionCount > 0 {
            parts.append("敏弱慎用 \(sensitiveCautionCount) 項")
        }
        if comedogenicCount > 0 {
            parts.append(skinType == .combination ? "T字致痘 \(comedogenicCount) 項" : "致痘風險 \(comedogenicCount) 項")
        }
        return parts.joined(separator: "・")
    }

    func flags(forName name: String, databaseItem: IngredientItem?) -> [SkinSuitabilityFlag] {
        let key = SkinSuitabilityEngine.matchKey(name: name, databaseItem: databaseItem)
        let ordered = SkinSuitabilityFlag.allCases.filter { flag in
            hits.contains { $0.ingredientKey == key && $0.flag == flag }
        }
        return ordered
    }

    func reasons(forName name: String, databaseItem: IngredientItem?) -> [String] {
        let key = SkinSuitabilityEngine.matchKey(name: name, databaseItem: databaseItem)
        return hits
            .filter { $0.ingredientKey == key }
            .map { "\($0.flag.rawValue)：\($0.reason)" }
    }
}

/// 混合肌：T 字控油防痘＋兩頰保濕雙向判定。
enum CombinationSkinMatcher {
    fileprivate static func collectHits(
        displayName: String,
        key: String,
        databaseItem: IngredientItem?,
        listIndex: Int,
        isSensitiveSkin: Bool,
        enabledAlertTags: Set<String>,
        demoteIfTrace: Bool,
        into hits: inout [SkinSuitabilityHit],
        seen: inout Set<String>
    ) {
        SkinSuitabilityEngine.applyCombinationRules(
            displayName: displayName,
            key: key,
            databaseItem: databaseItem,
            listIndex: listIndex,
            isSensitiveSkin: isSensitiveSkin,
            enabledAlertTags: enabledAlertTags,
            demoteIfTrace: demoteIfTrace,
            into: &hits,
            seen: &seen
        )
    }
}

/// 依 `UserProfile.skinType` / `isSensitiveSkin` 對成分清單做膚質聯動比對。
enum SkinSuitabilityEngine {
    static func evaluate(
        ingredients: [String],
        databaseItems: [IngredientItem?] = [],
        skinType: SkinType,
        isSensitiveSkin: Bool,
        enabledAlertTags: Set<String> = []
    ) -> SkinSuitabilityReport {
        IngredientDatabaseManager.shared.ensureLoaded()

        let resolvedItems: [IngredientItem?] = ingredients.enumerated().map { index, raw in
            if index < databaseItems.count, let provided = databaseItems[index] {
                return provided
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return IngredientDatabaseManager.shared.lookup(ingredientName: trimmed)
                ?? IngredientDatabaseManager.shared.resolve(trimmed, logMiss: false)
        }

        var hits: [SkinSuitabilityHit] = []
        var seen = Set<String>()

        for (index, raw) in ingredients.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let dbItem = index < resolvedItems.count ? resolvedItems[index] : nil
            let display = dbItem?.englishName ?? trimmed
            let key = matchKey(name: display, databaseItem: dbItem)

            if isSensitiveSkin {
                // 成分提醒已開 → 改由紅色警示；此處僅補橘色「額外」提醒
                let skipFragrance = enabledAlertTags.contains("artificial-fragrance")
                let skipAlcohol = enabledAlertTags.contains("denatured-alcohol")
                let skipAcids = enabledAlertTags.contains("acids")
                if let hit = sensitiveCautionHit(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    skipFragrance: skipFragrance,
                    skipAlcohol: skipAlcohol,
                    skipAcids: skipAcids
                ) {
                    appendUnique(hit, into: &hits, seen: &seen)
                }
            }

            switch skinType {
            case .oily:
                if !enabledAlertTags.contains("comedogenic"),
                   let hit = comedogenicHit(displayName: display, key: key, databaseItem: dbItem, listIndex: index) {
                    appendUnique(hit, into: &hits, seen: &seen)
                }
                if let hit = beneficialHit(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    flag: .oilyFriendly,
                    keywords: oilyBeneficialKeywords,
                    includeStrictSalicylicAcid: true,
                    demoteIfTrace: false,
                    reason: "含菸鹼醯胺、鋅類或綠茶等，有助油性肌控油淨膚。"
                ) {
                    appendUnique(hit, into: &hits, seen: &seen)
                }

            case .combination:
                CombinationSkinMatcher.collectHits(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    isSensitiveSkin: isSensitiveSkin,
                    enabledAlertTags: enabledAlertTags,
                    demoteIfTrace: false,
                    into: &hits,
                    seen: &seen
                )

            case .dry:
                if let hit = beneficialHit(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    flag: .dryFriendly,
                    keywords: dryBeneficialKeywords,
                    demoteIfTrace: false,
                    reason: "含神經醯胺、角鯊烷、玻尿酸或泛醇等，有助乾性肌鎖水修護。"
                ) {
                    appendUnique(hit, into: &hits, seen: &seen)
                }

            case .normal:
                break
            }

            if isSensitiveSkin {
                if let hit = beneficialHit(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    flag: .sensitiveFriendly,
                    keywords: sensitiveBeneficialKeywords,
                    demoteIfTrace: false,
                    reason: "含積雪草、紅沒藥醇或尿囊素等舒緩成分，較適合敏弱／泛紅膚質。"
                ) {
                    appendUnique(hit, into: &hits, seen: &seen)
                }
            }

            // 明星有益成分（含互斥警示）；最終仍走 Safety First
            for hit in BeneficialRuleEngine.collectHits(
                context: BeneficialRuleEngine.Context(
                    displayName: display,
                    key: key,
                    databaseItem: dbItem,
                    listIndex: index,
                    skinType: skinType,
                    isSensitiveSkin: isSensitiveSkin,
                    demoteIfTrace: false
                )
            ) {
                appendUnique(hit, into: &hits, seen: &seen)
            }
        }

        // Safety First：同一成分若已有警示，剔除推薦背書，避免矛盾標籤
        let cautionKeys = Set(hits.filter(\.flag.isCaution).map(\.ingredientKey))
        hits.removeAll { hit in
            (hit.flag.isBeneficial || hit.flag.isTraceNote) && cautionKeys.contains(hit.ingredientKey)
        }

        return SkinSuitabilityReport(
            skinType: skinType,
            isSensitiveSkin: isSensitiveSkin,
            hits: hits
        )
    }

    static func evaluate(
        items: [(name: String, databaseItem: IngredientItem?)],
        skinType: SkinType,
        isSensitiveSkin: Bool,
        enabledAlertTags: Set<String> = []
    ) -> SkinSuitabilityReport {
        evaluate(
            ingredients: items.map(\.name),
            databaseItems: items.map(\.databaseItem),
            skinType: skinType,
            isSensitiveSkin: isSensitiveSkin,
            enabledAlertTags: enabledAlertTags
        )
    }

    static func evaluate(
        from profile: UserProfile,
        ingredients: [String],
        databaseItems: [IngredientItem?] = []
    ) -> SkinSuitabilityReport {
        evaluate(
            ingredients: ingredients,
            databaseItems: databaseItems,
            skinType: profile.skinType,
            isSensitiveSkin: profile.isSensitiveSkin,
            enabledAlertTags: Set(profile.blockedTags)
        )
    }

    static func matchKey(name: String, databaseItem: IngredientItem?) -> String {
        let raw = databaseItem?.englishName ?? name
        return IngredientMatcher.normalizedForMatching(raw)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    // MARK: - Combination

    fileprivate static func applyCombinationRules(
        displayName: String,
        key: String,
        databaseItem: IngredientItem?,
        listIndex: Int,
        isSensitiveSkin: Bool,
        enabledAlertTags: Set<String>,
        demoteIfTrace: Bool,
        into hits: inout [SkinSuitabilityHit],
        seen: inout Set<String>
    ) {
        // T 字致痘防範（前排權重較高，後排仍標記但摘要權重較低）
        if !enabledAlertTags.contains("comedogenic"),
           let base = comedogenicHit(displayName: displayName, key: key, databaseItem: databaseItem, listIndex: listIndex) {
            let hit = SkinSuitabilityHit(
                ingredientKey: base.ingredientKey,
                displayName: base.displayName,
                flag: .tZoneComedogenic,
                reason: "高致粉刺油脂／酯類，混合肌 T 字部位較易悶出粉刺，建議慎用於臉中區域。",
                listIndex: listIndex
            )
            appendUnique(hit, into: &hits, seen: &seen)
        }

        // 兩頰保濕友善
        if let hit = beneficialHit(
            displayName: displayName,
            key: key,
            databaseItem: databaseItem,
            listIndex: listIndex,
            flag: .cheekMoisturizing,
            keywords: cheekMoisturizingKeywords,
            demoteIfTrace: demoteIfTrace,
            reason: "含神經醯胺、玻尿酸、角鯊烷或泛醇等，有助混合肌兩頰保濕修護。"
        ) {
            appendUnique(hit, into: &hits, seen: &seen)
        }

        // 控油角質代謝：敏感肌開啟時不給推薦；水楊酸酯類防曬劑不計入
        if !isSensitiveSkin,
           let hit = beneficialHit(
            displayName: displayName,
            key: key,
            databaseItem: databaseItem,
            listIndex: listIndex,
            flag: .tZoneOilControl,
            keywords: tZoneOilControlKeywords,
            includeStrictSalicylicAcid: true,
            demoteIfTrace: demoteIfTrace,
            reason: "含菸鹼醯胺或綠茶萃取等，有助混合肌 T 字控油調理。"
           ) {
            appendUnique(hit, into: &hits, seen: &seen)
        }
    }

    // MARK: - Sensitive

    private static func sensitiveCautionHit(
        displayName: String,
        key: String,
        databaseItem: IngredientItem?,
        listIndex: Int,
        skipFragrance: Bool = false,
        skipAlcohol: Bool = false,
        skipAcids: Bool = false
    ) -> SkinSuitabilityHit? {
        if !skipFragrance {
            if let db = databaseItem, db.forcesAllergenFunctionTag || db.displayChineseName == "香精" {
                return SkinSuitabilityHit(
                    ingredientKey: key,
                    displayName: displayName,
                    flag: .sensitiveCaution,
                    reason: "香精／過敏原相關成分，敏感或泛紅膚質建議慎用。",
                    listIndex: listIndex
                )
            }

            if matchesAnyKeyword(displayName: displayName, databaseItem: databaseItem, keywords: fragranceKeywords) {
                return SkinSuitabilityHit(
                    ingredientKey: key,
                    displayName: displayName,
                    flag: .sensitiveCaution,
                    reason: "含香精／香氛類成分（Fragrance／Parfum／Flavor），易刺激敏感肌。",
                    listIndex: listIndex
                )
            }
        }

        if !skipAlcohol, isDenaturedAlcohol(displayName: displayName, databaseItem: databaseItem) {
            return SkinSuitabilityHit(
                ingredientKey: key,
                displayName: displayName,
                flag: .sensitiveCaution,
                reason: "變性酒精／揮發性酒精可能使屏障乾燥、刺激泛紅膚質。",
                listIndex: listIndex
            )
        }

        if !skipAcids {
            let isStrongAcid = matchesTrueSalicylicAcid(displayName: displayName, databaseItem: databaseItem)
                || matchesAnyKeyword(
                    displayName: displayName,
                    databaseItem: databaseItem,
                    keywords: strongAcidKeywordsExcludingSalicylic
                )
            if isStrongAcid {
                return SkinSuitabilityHit(
                    ingredientKey: key,
                    displayName: displayName,
                    flag: .sensitiveCaution,
                    reason: "屬較強刺激酸類／去角質活性，敏感肌建議降低頻率或避開。",
                    listIndex: listIndex
                )
            }
        }

        return nil
    }

    // MARK: - Comedogenic (oily / combination)

    private static func comedogenicHit(
        displayName: String,
        key: String,
        databaseItem: IngredientItem?,
        listIndex: Int
    ) -> SkinSuitabilityHit? {
        guard let rating = comedogenicRating(displayName: displayName, databaseItem: databaseItem), rating >= 3 else {
            return nil
        }
        return SkinSuitabilityHit(
            ingredientKey: key,
            displayName: displayName,
            flag: .comedogenicRisk,
            reason: "高致粉刺指數（約 \(rating)/5），油性／混合肌較易悶出粉刺。",
            listIndex: listIndex
        )
    }

    // MARK: - Beneficial

    private static func beneficialHit(
        displayName: String,
        key: String,
        databaseItem: IngredientItem?,
        listIndex: Int,
        flag: SkinSuitabilityFlag,
        keywords: [String],
        includeStrictSalicylicAcid: Bool = false,
        demoteIfTrace: Bool = false,
        reason: String
    ) -> SkinSuitabilityHit? {
        let matched: Bool
        if includeStrictSalicylicAcid {
            matched = matchesTrueSalicylicAcid(displayName: displayName, databaseItem: databaseItem)
                || matchesAnyKeyword(displayName: displayName, databaseItem: databaseItem, keywords: keywords)
        } else {
            matched = matchesAnyKeyword(displayName: displayName, databaseItem: databaseItem, keywords: keywords)
        }
        guard matched else { return nil }

        return SkinSuitabilityHit(
            ingredientKey: key,
            displayName: displayName,
            flag: flag,
            reason: reason,
            listIndex: listIndex
        )
    }

    // MARK: - Matching helpers

    private static func appendUnique(
        _ hit: SkinSuitabilityHit,
        into hits: inout [SkinSuitabilityHit],
        seen: inout Set<String>
    ) {
        let token = hit.id
        if let existingIndex = hits.firstIndex(where: { $0.id == token }) {
            // 保留較靠前的位置權重
            if hit.listIndex < hits[existingIndex].listIndex {
                hits[existingIndex] = hit
            }
            return
        }
        seen.insert(token)
        hits.append(hit)
    }

    private static func matchesAnyKeyword(
        displayName: String,
        databaseItem: IngredientItem?,
        keywords: [String]
    ) -> Bool {
        let blob = matchingBlob(displayName: displayName, databaseItem: databaseItem)
        return keywords.contains { keyword in
            let needle = compactNormalized(keyword)
            let minLen = needle.unicodeScalars.contains(where: { $0.value > 0x7F }) ? 2 : 3
            guard needle.count >= minLen else { return false }
            return blob.contains(needle)
        }
    }

    /// 供 `BeneficialRuleEngine` 共用的關鍵字命中。
    static func matchesKeywords(
        displayName: String,
        databaseItem: IngredientItem?,
        keywords: [String]
    ) -> Bool {
        matchesAnyKeyword(displayName: displayName, databaseItem: databaseItem, keywords: keywords)
    }

    /// 僅「水楊酸本尊」；排除 Ethylhexyl Salicylate／Octisalate／Homosalate 等防曬酯類。
    private static func matchesTrueSalicylicAcid(
        displayName: String,
        databaseItem: IngredientItem?
    ) -> Bool {
        if isSalicylateSunscreenEster(displayName: displayName, databaseItem: databaseItem) {
            return false
        }
        return matchesAnyKeyword(
            displayName: displayName,
            databaseItem: databaseItem,
            keywords: trueSalicylicAcidKeywords
        )
    }

    private static func isSalicylateSunscreenEster(
        displayName: String,
        databaseItem: IngredientItem?
    ) -> Bool {
        matchesAnyKeyword(
            displayName: displayName,
            databaseItem: databaseItem,
            keywords: salicylateSunscreenEsterKeywords
        )
    }

    private static func matchingBlob(displayName: String, databaseItem: IngredientItem?) -> String {
        var haystacks: [String] = [compactNormalized(displayName)]
        if let db = databaseItem {
            haystacks.append(compactNormalized(db.englishName))
            haystacks.append(compactNormalized(db.chineseName))
            for alias in db.aliases ?? [] {
                haystacks.append(compactNormalized(alias))
            }
        }
        return haystacks.joined(separator: " ")
    }

    private static func compactNormalized(_ text: String) -> String {
        IngredientMatcher.normalizedForMatching(text)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "／", with: "")
    }

    private static func isDenaturedAlcohol(displayName: String, databaseItem: IngredientItem?) -> Bool {
        let candidates = [displayName, databaseItem?.englishName, databaseItem?.chineseName]
            .compactMap { $0 }
            + (databaseItem?.aliases ?? [])
        for raw in candidates {
            if denaturedAlcoholMatch(for: raw) != nil {
                return true
            }
        }
        return false
    }

    /// 與 `IngredientMatcher` 一致：僅揮發性酒精，排除脂肪醇。
    private static let fattyAlcoholCompactKeys: [String] = [
        "arachidylalcohol", "cetearylalcohol", "behenylalcohol",
        "cetylalcohol", "stearylalcohol", "myristylalcohol", "laurylalcohol"
    ]

    private static func denaturedAlcoholMatch(for raw: String) -> String? {
        let compact = raw
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard !compact.isEmpty else { return nil }

        for fatty in fattyAlcoholCompactKeys {
            if compact == fatty || compact.hasPrefix(fatty) {
                return nil
            }
        }

        let volatileKeys = [
            "alcoholdenat", "alcohol denat", "sdalcohol", "ethanoldenat",
            "變性酒精", "乙醇"
        ]
        let normalized = IngredientMatcher.normalizedForMatching(raw)
        if volatileKeys.contains(where: { normalized.contains(IngredientMatcher.normalizedForMatching($0)) }) {
            return raw
        }
        // 單獨 Alcohol / Ethanol（非某某 Alcohol 脂肪醇）
        if compact == "alcohol" || compact == "ethanol" || compact == "isopropylalcohol" {
            return raw
        }
        return nil
    }

    private static func comedogenicRating(displayName: String, databaseItem: IngredientItem?) -> Int? {
        let names = ([displayName, databaseItem?.englishName, databaseItem?.chineseName].compactMap { $0 }
            + (databaseItem?.aliases ?? []))
            .map { IngredientMatcher.normalizedForMatching($0) }

        var best: Int?
        for (keyword, rating) in comedogenicRatings where rating >= 3 {
            let needle = IngredientMatcher.normalizedForMatching(keyword)
            if names.contains(where: { $0.contains(needle) }) {
                best = max(best ?? 0, rating)
            }
        }
        return best
    }

    // MARK: - Keyword tables

    /// 水楊酸本尊（不含防曬用水楊酸酯）。
    private static let trueSalicylicAcidKeywords: [String] = [
        "salicylic acid", "bha", "beta hydroxy acid", "betahydroxyacid", "水楊酸"
    ]

    /// 水楊酸酯類 UV 防曬劑（不可當控油酸／強酸慎用）。
    private static let salicylateSunscreenEsterKeywords: [String] = [
        "ethylhexyl salicylate", "octisalate", "octyl salicylate",
        "homosalate", "butyloctyl salicylate",
        "水楊酸乙基己酯", "乙基己基水楊酸酯", "水楊酸辛酯",
        "胡莫柳酯", "荷莫柳酯", "水楊酸薄荷酯", "水楊酸高薄荷酯",
        "サリチル酸エチルヘキシル", "オクチサレート", "ホモサレート"
    ]

    private static let fragranceKeywords: [String] = [
        "fragrance", "parfum", "perfume", "flavor", "flavour", "aroma",
        "香精", "香料", "人工香精",
        "limonene", "linalool", "citronellol", "geraniol", "eugenol", "citral", "coumarin"
    ]

    /// 強酸／去角質（水楊酸本尊另以 `matchesTrueSalicylicAcid` 判定；維 A 改由明星規則標「刺激慎用」）。
    private static let strongAcidKeywordsExcludingSalicylic: [String] = [
        "glycolic acid", "lactic acid", "mandelic acid",
        "pyruvic acid", "trichloroacetic acid", "retinoic acid",
        "tretinoin", "adapalen",
        "果酸", "甘醇酸", "乳酸", "杏仁酸",
        "aha"
    ]

    private static let oilyBeneficialKeywords: [String] = [
        "niacinamide", "nicotinamide", "vitamin b3", "菸鹼醯胺", "烟酰胺", "菸碱酰胺",
        "zinc pca", "zinc gluconate", "zinc lactate", "zinc", "鋅",
        "camellia sinensis", "camellia oleifera", "green tea", "綠茶", "油茶"
        // 杜鵑花酸、茶樹改由 BeneficialRuleEngine 專責
    ]

    /// 混合肌兩頰保濕（神經醯胺、玻尿酸、角鯊烷、泛醇）。
    private static let cheekMoisturizingKeywords: [String] = [
        "ceramide", "ceramides", "神經醯胺", "神經酰胺",
        "squalane", "squalene", "角鯊烷", "角鯊烯",
        "hyaluronic acid", "sodium hyaluronate", "玻尿酸", "透明質酸",
        "panthenol", "dexpanthenol", "vitamin b5", "泛醇", "維生素b5"
    ]

    /// 混合肌 T 字控油（綠茶、菸鹼醯胺；水楊酸本尊另嚴格判定；杜鵑花酸／茶樹見明星規則）。
    private static let tZoneOilControlKeywords: [String] = [
        "niacinamide", "nicotinamide", "vitamin b3", "菸鹼醯胺", "烟酰胺",
        "camellia sinensis", "camellia oleifera", "green tea", "綠茶", "油茶"
    ]

    private static let dryBeneficialKeywords: [String] = [
        "ceramide", "ceramides", "神經醯胺", "神經酰胺",
        "squalane", "squalene", "角鯊烷", "角鯊烯",
        "hyaluronic acid", "sodium hyaluronate", "玻尿酸", "透明質酸",
        "panthenol", "dexpanthenol", "vitamin b5", "泛醇", "維生素b5"
        // 乳木果油改由 BeneficialRuleEngine（乾肌滋潤／油混致痘互斥）
    ]

    private static let sensitiveBeneficialKeywords: [String] = [
        "centella asiatica", "cica", "積雪草",
        "bisabolol", "紅沒藥醇", "没药醇",
        "allantoin", "尿囊素"
        // 純化積雪草苷／酸、依克多因等改由 BeneficialRuleEngine
    ]

    /// 常見高致粉刺指數（≥3）成份。
    private static let comedogenicRatings: [(String, Int)] = [
        ("isopropyl myristate", 5),
        ("myristyl myristate", 5),
        ("isopropyl palmitate", 4),
        ("ethylhexyl palmitate", 4),
        ("octyl palmitate", 4),
        ("coconut oil", 4),
        ("cocos nucifera", 4),
        ("cocoa butter", 4),
        ("theobroma cacao", 4),
        ("lauric acid", 4),
        ("wheat germ oil", 5),
        ("triticum vulgare germ oil", 5),
        ("lanolin", 3),
        ("oleic acid", 3),
        ("stearic acid", 3),
        ("butyl stearate", 3),
        ("octyl stearate", 5),
        ("glyceryl stearate se", 3),
        ("algae extract", 5),
        ("肉豆蔻酸異丙酯", 5),
        ("椰子油", 4),
        ("可可脂", 4),
        ("羊毛脂", 3)
    ]
}
