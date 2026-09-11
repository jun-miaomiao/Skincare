import Foundation

/// 自訂風險成分比對：支援中英文精確／包含比對（不分大小寫）。
enum CustomRiskIngredientMatcher {
    /// 回傳命中的自訂名稱（保留使用者原始字串）。
    static func matchedCustoms(
        name: String,
        databaseItem: IngredientItem?,
        customList: [String]
    ) -> [String] {
        let customs = customList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !customs.isEmpty else { return [] }

        let haystacks = candidateKeys(name: name, databaseItem: databaseItem)
        guard !haystacks.isEmpty else { return [] }

        var hits: [String] = []
        for custom in customs {
            let needle = normalize(custom)
            guard needle.count >= 2 else { continue }
            if haystacks.contains(where: { matches(haystack: $0, needle: needle) }) {
                if !hits.contains(custom) {
                    hits.append(custom)
                }
            }
        }
        return hits
    }

    static func matchesAny(
        name: String,
        databaseItem: IngredientItem?,
        customList: [String]
    ) -> Bool {
        !matchedCustoms(name: name, databaseItem: databaseItem, customList: customList).isEmpty
    }

    private static func candidateKeys(name: String, databaseItem: IngredientItem?) -> [String] {
        var raw = [name]
        if let db = databaseItem {
            raw.append(db.englishName)
            raw.append(db.chineseName)
            raw.append(contentsOf: db.aliases ?? [])
        }
        return raw
            .map { normalize($0) }
            .filter { !$0.isEmpty }
    }

    private static func normalize(_ text: String) -> String {
        IngredientMatcher.normalizedForMatching(text)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "／", with: "")
    }

    /// 精確相等，或雙向包含（needle ≥ 3 字元才做包含，避免過短誤傷）。
    private static func matches(haystack: String, needle: String) -> Bool {
        if haystack == needle { return true }
        guard needle.count >= 3 else { return false }
        return haystack.contains(needle) || (haystack.count >= 3 && needle.contains(haystack))
    }
}

/// 單一成分上的警示／提醒標籤（三層 Hierarchy）。
struct IngredientAlertTag: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        /// 第一層：自訂風險成分（最高紅燈）
        case personalCustom
        /// 第二層：已開啟的風險開關（橘紅燈）
        case toggleRisk
        /// 第三層：膚質慎用（黃燈）
        case skinCaution
        /// 第三層：膚質友善（綠燈）
        case skinFriendly
        /// 1% 分界線後的概念性添加（灰底極淡）
        case traceNote
    }

    var id: String { "\(kind)|\(text)" }
    let kind: Kind
    let text: String
    let reason: String

    var isHighlightLayer: Bool {
        kind == .personalCustom || kind == .toggleRisk
    }
}

/// 單一成分的三層檢查結果。
struct IngredientAlertAnnotation: Hashable, Sendable {
    let ingredientKey: String
    let displayName: String
    let matchedCustomNames: [String]
    let toggleRiskTitles: [String]
    let skinFlags: [SkinSuitabilityFlag]
    let skinReasons: [String]
    let tags: [IngredientAlertTag]

    var hasPersonalCustom: Bool { !matchedCustomNames.isEmpty }
    var hasToggleRisk: Bool { !toggleRiskTitles.isEmpty }
    var hasHighlightAlert: Bool { hasPersonalCustom || hasToggleRisk }

    /// 排序權重：數字越小越靠前。
    var sortPriority: Int {
        if hasPersonalCustom { return 0 }
        if hasToggleRisk { return 1 }
        if skinFlags.contains(where: \.isCaution) { return 2 }
        if !skinFlags.isEmpty { return 3 }
        return 9
    }
}

enum IngredientAlertSummaryTone: Sendable {
    case personalCustom
    case toggleRisk
    case skinCaution
    case compatible
}

struct IngredientAlertReport: Sendable {
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let matchedAlertMessages: [String]
    let skinReport: SkinSuitabilityReport
    let annotations: [IngredientAlertAnnotation]
    /// O(1) 查詢用索引（進入詳情頁時避免重複掃 annotations）。
    let annotationByKey: [String: IngredientAlertAnnotation]

    init(
        blockedTags: [String],
        customBlockedIngredients: [String],
        matchedAlertMessages: [String],
        skinReport: SkinSuitabilityReport,
        annotations: [IngredientAlertAnnotation]
    ) {
        self.blockedTags = blockedTags
        self.customBlockedIngredients = customBlockedIngredients
        self.matchedAlertMessages = matchedAlertMessages
        self.skinReport = skinReport
        self.annotations = annotations
        var map: [String: IngredientAlertAnnotation] = [:]
        map.reserveCapacity(annotations.count)
        for ann in annotations {
            map[ann.ingredientKey] = ann
        }
        self.annotationByKey = map
    }

    var personalCustomCount: Int {
        annotations.filter(\.hasPersonalCustom).count
    }

    var toggleRiskCount: Int {
        annotations.filter(\.hasToggleRisk).count
    }

    var summaryTone: IngredientAlertSummaryTone {
        if personalCustomCount > 0 { return .personalCustom }

        let customOnlyMessages = matchedAlertMessages.filter { $0.contains("自訂") }
        let toggleMessages = matchedAlertMessages.filter { !$0.contains("自訂") }

        if personalCustomCount == 0, !customOnlyMessages.isEmpty, toggleRiskCount == 0, toggleMessages.isEmpty {
            return .personalCustom
        }
        if toggleRiskCount > 0 || !toggleMessages.isEmpty {
            return .toggleRisk
        }
        // 膚質警示：採位置加權後的摘要門檻；自訂／開關已於上方零容忍攔截
        if skinReport.shouldSurfaceSkinCautionInSummary { return .skinCaution }
        return .compatible
    }

    var summaryTitle: String {
        switch summaryTone {
        case .personalCustom:
            let count = max(personalCustomCount, matchedAlertMessages.filter { $0.contains("自訂") }.count, 1)
            return "偵測到 \(count) 項您個人設定避開的成分！"
        case .toggleRisk:
            return "含有 \(max(toggleRiskCount, matchedAlertMessages.filter { !$0.contains("自訂") }.count, 1)) 項您設定避開的成分"
        case .skinCaution:
            return skinReport.summaryTitle
        case .compatible:
            return skinReport.summaryTitle
        }
    }

    var summarySubtitle: String {
        switch summaryTone {
        case .personalCustom:
            let names = annotations
                .filter(\.hasPersonalCustom)
                .flatMap(\.matchedCustomNames)
            var unique: [String] = []
            for name in names where !unique.contains(name) {
                unique.append(name)
            }
            let preview = unique.prefix(3).joined(separator: "、")
            return preview.isEmpty
                ? "清單已以紅色【個人避開】標示，請優先確認。"
                : preview
        case .toggleRisk:
            var unique: [String] = []
            for title in annotations.filter(\.hasToggleRisk).flatMap(\.toggleRiskTitles) where !unique.contains(title) {
                unique.append(title)
            }
            if !unique.isEmpty {
                return unique.prefix(3).joined(separator: "、")
            }
            return matchedAlertMessages.filter { !$0.contains("自訂") }.prefix(3).joined(separator: "、")
        case .skinCaution:
            return skinReport.summarySubtitle
        case .compatible:
            let skin = skinReport.skinType.rawValue
            let sensitive = skinReport.isSensitiveSkin ? "・敏感肌" : ""
            return "未命中自訂避開與風險開關，且與目前膚質（\(skin)\(sensitive)）相符。"
        }
    }

    func annotation(forName name: String, databaseItem: IngredientItem?) -> IngredientAlertAnnotation? {
        let key = SkinSuitabilityEngine.matchKey(name: name, databaseItem: databaseItem)
        return annotationByKey[key]
    }

    static let empty = IngredientAlertReport(
        blockedTags: [],
        customBlockedIngredients: [],
        matchedAlertMessages: [],
        skinReport: SkinSuitabilityReport(skinType: .combination, isSensitiveSkin: false, hits: []),
        annotations: []
    )
}

/// 整合自訂風險、成分提醒 Toggle、膚質適配的三層掃描分析引擎。
enum IngredientAlertEngine {
    static func evaluate(
        ingredients: [String],
        databaseItems: [IngredientItem?] = [],
        blockedTags: [String],
        customBlockedIngredients: [String],
        matchedAlertMessages: [String] = [],
        skinType: SkinType,
        isSensitiveSkin: Bool
    ) -> IngredientAlertReport {
        IngredientDatabaseManager.shared.ensureLoaded()

        let enabledTags = Set(blockedTags)
        let skinReport = SkinSuitabilityEngine.evaluate(
            ingredients: ingredients,
            databaseItems: databaseItems,
            skinType: skinType,
            isSensitiveSkin: isSensitiveSkin,
            enabledAlertTags: enabledTags
        )

        var annotations: [IngredientAlertAnnotation] = []
        var seenKeys = Set<String>()

        for (index, raw) in ingredients.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let dbItem: IngredientItem? = {
                if index < databaseItems.count { return databaseItems[index] }
                return IngredientDatabaseManager.shared.lookup(ingredientName: trimmed)
                    ?? IngredientDatabaseManager.shared.resolve(trimmed, logMiss: false)
            }()

            let display = dbItem?.englishName ?? trimmed
            let key = SkinSuitabilityEngine.matchKey(name: display, databaseItem: dbItem)
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)

            // 第一層：自訂風險
            let customs = CustomRiskIngredientMatcher.matchedCustoms(
                name: display,
                databaseItem: dbItem,
                customList: customBlockedIngredients
            )

            // 第二層：風險開關（不含自訂清單）
            let toggleTitles = toggleRiskTitles(
                name: display,
                databaseItem: dbItem,
                blockedTags: blockedTags
            )

            let skinFlags = skinReport.flags(forName: display, databaseItem: dbItem)
            let skinReasons = skinReport.reasons(forName: display, databaseItem: dbItem)

            var tags: [IngredientAlertTag] = []

            if !customs.isEmpty {
                let joined = customs.joined(separator: "、")
                tags.append(
                    IngredientAlertTag(
                        kind: .personalCustom,
                        text: "🚨 個人避開成分",
                        reason: "您已將「\(joined)」加入自訂風險成分，掃描結果命中。"
                    )
                )
            }

            for title in toggleTitles {
                tags.append(
                    IngredientAlertTag(
                        kind: .toggleRisk,
                        text: "⚠️ 風險成分：\(title)",
                        reason: "您已在「成分提醒」開啟「\(title)」，掃描結果命中此成分。"
                    )
                )
            }

            let hasWarningLayer = !customs.isEmpty
                || !toggleTitles.isEmpty
                || skinFlags.contains(where: \.isCaution)

            for flag in skinFlags {
                // Safety First：已有警示時不並存推薦／微量標籤
                if (flag.isBeneficial || flag.isTraceNote), hasWarningLayer { continue }
                let reason = skinReasons.first { $0.hasPrefix(flag.rawValue) } ?? flag.rawValue
                let kind: IngredientAlertTag.Kind = {
                    if flag.isCaution { return .skinCaution }
                    if flag.isTraceNote { return .traceNote }
                    return .skinFriendly
                }()
                tags.append(
                    IngredientAlertTag(
                        kind: kind,
                        text: flag.rowLabel,
                        reason: reason
                    )
                )
            }

            guard !tags.isEmpty else { continue }

            annotations.append(
                IngredientAlertAnnotation(
                    ingredientKey: key,
                    displayName: display,
                    matchedCustomNames: customs,
                    toggleRiskTitles: toggleTitles,
                    skinFlags: skinFlags,
                    skinReasons: skinReasons,
                    tags: tags
                )
            )
        }

        return IngredientAlertReport(
            blockedTags: blockedTags,
            customBlockedIngredients: customBlockedIngredients,
            matchedAlertMessages: matchedAlertMessages,
            skinReport: skinReport,
            annotations: annotations
        )
    }

    static func evaluate(
        items: [(name: String, databaseItem: IngredientItem?)],
        blockedTags: [String],
        customBlockedIngredients: [String],
        matchedAlertMessages: [String] = [],
        skinType: SkinType,
        isSensitiveSkin: Bool
    ) -> IngredientAlertReport {
        evaluate(
            ingredients: items.map(\.name),
            databaseItems: items.map(\.databaseItem),
            blockedTags: blockedTags,
            customBlockedIngredients: customBlockedIngredients,
            matchedAlertMessages: matchedAlertMessages,
            skinType: skinType,
            isSensitiveSkin: isSensitiveSkin
        )
    }

    static func evaluate(
        from profile: UserProfile,
        ingredients: [String],
        databaseItems: [IngredientItem?] = [],
        matchedAlertMessages: [String] = []
    ) -> IngredientAlertReport {
        evaluate(
            ingredients: ingredients,
            databaseItems: databaseItems,
            blockedTags: profile.blockedTags,
            customBlockedIngredients: profile.customBlockedIngredients,
            matchedAlertMessages: matchedAlertMessages,
            skinType: profile.skinType,
            isSensitiveSkin: profile.isSensitiveSkin
        )
    }

    static func shouldTriggerScanAlert(matchedAlertMessages: [String]) -> Bool {
        !matchedAlertMessages.isEmpty
    }

    static func triggerScanWarningHapticIfNeeded(matchedAlertMessages: [String]) {
        guard shouldTriggerScanAlert(matchedAlertMessages: matchedAlertMessages) else { return }
        ScanAlertHaptics.triggerWarning()
    }

    private static func toggleRiskTitles(
        name: String,
        databaseItem: IngredientItem?,
        blockedTags: [String]
    ) -> [String] {
        var titles: [String] = []
        let candidates = [name, databaseItem?.englishName, databaseItem?.chineseName]
            .compactMap { $0 }
            + (databaseItem?.aliases ?? [])

        for candidate in candidates {
            // 僅 Toggle，不帶自訂清單
            for title in IngredientMatcher.matchedAvoidTitles(
                for: candidate,
                blockedTags: blockedTags,
                customIngredients: []
            ) {
                if !titles.contains(title) {
                    titles.append(title)
                }
            }
        }

        if blockedTags.contains("artificial-fragrance"),
           let db = databaseItem,
           (db.forcesAllergenFunctionTag || db.displayChineseName == "香精"),
           !titles.contains(where: { $0.contains("香精") }) {
            if let option = AvoidIngredientOption.all.first(where: { $0.id == "artificial-fragrance" }) {
                titles.insert(option.title, at: 0)
            }
        }

        return titles
    }
}
