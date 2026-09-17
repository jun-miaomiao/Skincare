import SwiftUI

/// 本 App「安心度」燈號區間（1–9 彙整分數），偏法規／長期風險彙整，非刺激性、亦非第三方商標評分。
enum ConcernBand: String, Hashable {
    case low = "較安心"
    case moderate = "需留意"
    case high = "需特別留意"

    var tint: Color {
        switch self {
        case .low: Theme.sage
        case .moderate: Theme.gold
        case .high: Theme.blush
        }
    }

    var icon: String {
        switch self {
        case .low: "checkmark.circle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .high: "xmark.octagon.fill"
        }
    }

    static func from(score: Int) -> ConcernBand {
        switch min(max(score, 1), 9) {
        case 1...2: return .low
        case 3...6: return .moderate
        default: return .high
        }
    }
}

/// 刺激／致敏風險（與安心度分數分開；「有人耐受」不代表不是刺激成分）。
enum IrritationRisk: String, Hashable {
    case low = "刺激偏低"
    case moderate = "刺激中度"
    case high = "刺激偏高"
    case unknown = "刺激未標"

    var tint: Color {
        switch self {
        case .low: Theme.sage
        case .moderate: Theme.gold
        case .high: Theme.blush
        case .unknown: Theme.muted
        }
    }

    var icon: String {
        switch self {
        case .low: "leaf.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .high: "flame.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var detail: String {
        switch self {
        case .low:
            return "一般使用刺激與致敏風險相對較低；仍請以產品標示與個人膚況為準。"
        case .moderate:
            return "可能引起刺癢、泛紅或致敏，視濃度與膚質而定；敏感肌建議降低頻率。"
        case .high:
            return "屬常見刺激／致敏或活性成分；「有人可用」不代表溫和，建議漸進或避開敏弱膚質。"
        case .unknown:
            return "資料不足，暫不以刺激軸評級；請參考產品標示與膚質提示。"
        }
    }
}

/// 依成分名稱／字典項推估刺激軸（規則彙整，非醫療診斷）。
enum IrritationRiskClassifier {
    static func evaluate(
        englishName: String,
        chineseName: String? = nil,
        databaseItem: IngredientItem? = nil
    ) -> IrritationRisk {
        let blob = normalize(
            [
                englishName,
                chineseName ?? "",
                databaseItem?.englishName ?? "",
                databaseItem?.chineseName ?? "",
                (databaseItem?.aliases ?? []).joined(separator: " ")
            ].joined(separator: " ")
        )

        if blob.isEmpty { return .unknown }

        if matches(blob, highKeywords) { return .high }
        if isSpicyEssentialOil(blob) { return .high }
        if matches(blob, moderateKeywords) { return .moderate }
        if isMildEssentialOil(blob) { return .moderate }
        if databaseItem?.forcesAllergenFunctionTag == true { return .high }
        if databaseItem?.displayChineseName == "香精" { return .high }

        return .low
    }

    // MARK: - Matching

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func matches(_ blob: String, _ keywords: [String]) -> Bool {
        keywords.contains { blob.contains($0) }
    }

    /// 精油／香薰油：排除常見基底油後，葉／花／皮／樹皮等精油預設高刺激。
    private static func isSpicyEssentialOil(_ blob: String) -> Bool {
        if blob.contains("精油") { return true }
        guard blob.contains(" oil") || blob.hasSuffix("oil") else { return false }
        if carrierOilMarkers.contains(where: { blob.contains($0) }) { return false }
        return spicyOilMarkers.contains { blob.contains($0) }
    }

    private static func isMildEssentialOil(_ blob: String) -> Bool {
        guard blob.contains(" oil") || blob.contains("精油") else { return false }
        if carrierOilMarkers.contains(where: { blob.contains($0) }) { return false }
        return mildOilMarkers.contains { blob.contains($0) }
    }

    // MARK: - Keyword tables

    private static let highKeywords: [String] = [
        // 維 A
        "retinol", "retinal", "retinaldehyde", "tretinoin", "retinoic acid",
        "adapalene", "視黃醇", "視黃醛", "維a酸", "維 a 酸",
        "hydroxypinacolone retinoate",
        // 香精本尊與常見過敏原單體
        "fragrance", "parfum", "perfume", "flavor", "flavour",
        "limonene", "linalool", "citral", "geraniol", "citronellol",
        "eugenol", "cinnamal", "coumarin", "farnesol", "isoeugenol",
        "hexyl cinnamal", "hydroxycitronellal", "benzyl alcohol",
        "benzyl benzoate", "benzyl salicylate", "alpha isomethyl ionone",
        "香精", "香料",
        // 強酸／去角質
        "glycolic acid", "salicylic acid", "lactic acid", "mandelic acid",
        "trichloroacetic", "benzoyl peroxide",
        "甘醇酸", "水楊酸", "乳酸", "杏仁酸", "過氧化苯甲醯",
        // 涼感／揮發酒精
        "menthol", "camphor", "alcohol denat", "alcohol denatured", "sd alcohol",
        "薄荷醇", "樟腦", "變性酒精",
        // 強精油標記字
        "tea tree", "melaleuca alternifolia leaf oil", "peppermint", "mentha piperita",
        "eucalyptus", "cinnamon", "cinnamomum", "clove", "eugenia caryophyllus",
        "thyme", "thymus", "oregano", "lemongrass", "cymbopogon",
        "茶樹精油", "胡椒薄荷", "尤加利", "肉桂", "丁香", "百里香"
    ]

    private static let moderateKeywords: [String] = [
        "retinyl", "視黃醇酯", "視黃醇棕櫚", "視黃醇乙酸",
        "azelaic acid", "杜鵑花酸", "壬二酸",
        "ascorbic acid", "抗壞血酸",
        "witch hazel", "hamamelis", "金縷梅",
        "urea", "尿素",
        "gluconolactone", "lactobionic", "葡糖酸內酯", "乳糖酸",
        "lavender", "lavandula", "薰衣草",
        "rosemary", "rosmarinus", "迷迭香",
        "citrus ", "檸檬", "甜橙", "佛手柑"
    ]

    private static let spicyOilMarkers: [String] = [
        "melaleuca", "mentha", "eucalyptus", "cinnamomum", "eugenia",
        "syzygium aromaticum", "thymus", "origanum", "cymbopogon",
        "citrus", "peel oil", "bark oil", "leaf oil", "flower oil",
        "needle oil", "wood oil", "root oil", "fruit oil",
        "茶樹", "薄荷", "迷迭香", "肉桂", "丁香", "百里香", "檸檬", "橙"
    ]

    private static let mildOilMarkers: [String] = [
        "lavandula", "lavender", "pelargonium", "geranium", "cananga",
        "ylang", "rosa damascena flower oil", "jasminum",
        "薰衣草", "天竺葵", "依蘭"
    ]

    private static let carrierOilMarkers: [String] = [
        "helianthus", "simmondsia", "prunus amygdalus", "olea europaea",
        "vitis vinifera", "caprylic", "capric triglyceride", "squalane",
        "butyrospermum", "mangifera", "persea", "glycine soja",
        "ricinus", "carthamus", "macadamia", "argania", "cocos nucifera",
        "elaeis", "oryza sativa", "sesamum", "cannabis sativa seed",
        "rosa canina seed", "linum", "isohexadecane", "paraffinum",
        "mineral oil", "petrolatum", "dimethicone",
        "葵花籽油", "荷荷芭", "甜杏仁油", "橄欖油", "葡萄籽油",
        "乳木果", "椰子油", "角鯊烷"
    ]
}
