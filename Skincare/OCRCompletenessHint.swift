import Foundation

/// 掃描結果底部辨識提示：常態溫馨提醒／異常漏抓警告。
/// - Note: 不將「缺少 Water／Aqua」視為漏字（護唇膏／油膏等無水配方為正常）。
enum OCRCompletenessHint {
    /// 達此數量以上視為清單夠完整 → 常態提醒。
    static let normalCountThreshold = 10
    /// 低於此數量且未見結尾成分 → 異常警告。
    static let warningCountThreshold = 10

    enum BannerKind: Sendable, Equatable {
        /// 常態溫馨提醒（辨識正常時顯示）。
        case normalReference
        /// 異常漏抓警告。
        case incompleteWarning
    }

    enum RiskFlag: String, Sendable, Hashable {
        case lowCountWithoutTypicalEnding
    }

    struct Assessment: Sendable {
        let flags: Set<RiskFlag>
        let bannerKind: BannerKind

        var isAtRisk: Bool { bannerKind == .incompleteWarning }
    }

    /// 判定底部提示狀態。
    static func assess(
        ingredients: [String],
        averageOCRConfidence: Float? = nil,
        ocrLineCount: Int? = nil
    ) -> Assessment {
        _ = averageOCRConfidence
        _ = ocrLineCount

        let tokens = ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 狀態 A：≥ 10 項，或末尾含常見配方結尾詞
        if tokens.count >= normalCountThreshold || hasTypicalEndingInTail(tokens) {
            return Assessment(flags: [], bannerKind: .normalReference)
        }

        // 狀態 B：< 10 項且末尾未命中結尾成分
        if tokens.count < warningCountThreshold {
            return Assessment(
                flags: [.lowCountWithoutTypicalEnding],
                bannerKind: .incompleteWarning
            )
        }

        return Assessment(flags: [], bannerKind: .normalReference)
    }

    static func bannerKind(
        ingredients: [String],
        averageOCRConfidence: Float? = nil,
        ocrLineCount: Int? = nil
    ) -> BannerKind {
        assess(
            ingredients: ingredients,
            averageOCRConfidence: averageOCRConfidence,
            ocrLineCount: ocrLineCount
        ).bannerKind
    }

    static func shouldShow(
        ingredients: [String],
        averageOCRConfidence: Float? = nil,
        ocrLineCount: Int? = nil
    ) -> Bool {
        assess(
            ingredients: ingredients,
            averageOCRConfidence: averageOCRConfidence,
            ocrLineCount: ocrLineCount
        ).isAtRisk
    }

    // MARK: - Early Termination（末尾 3 項）

    private static func hasTypicalEndingInTail(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let tail = tokens.suffix(3)
        return tail.contains { isTypicalEndingAgent($0) }
    }

    // MARK: - Match helpers

    private static func compact(_ text: String) -> String {
        IngredientMatcher.normalizedForMatching(text)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    /// 常見配方結尾：致敏香精單體、抗氧化／防腐劑等。
    private static func isTypicalEndingAgent(_ name: String) -> Bool {
        let key = compact(name)
        let endings = [
            "limonene", "linalool", "citronellol", "geraniol", "eugenol", "citral",
            "香茅醇", "香葉醇", "丁香酚",
            "tocopherol", "tocopherylacetate", "維生素e", "维生素e", "維他命e",
            "phenoxyethanol", "苯氧乙醇",
            "ethylhexylglycerin", "乙基己基甘油",
            "bht", "bha",
            "caprylylglycol", "hexanediol",
            "chlorphenesin", "sodiumbenzoate", "potassiumsorbate",
            "benzylalcohol", "dehydroaceticacid",
            "fragrance", "parfum", "perfume", "香精", "香料"
        ]
        return endings.contains { key.contains(compact($0)) || key == compact($0) }
    }
}
