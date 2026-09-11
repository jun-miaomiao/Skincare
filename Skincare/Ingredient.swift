import SwiftUI

enum HomeTab: String, CaseIterable, Identifiable {
    case popular = "熱門成分"
    case safety = "安全分析"

    var id: String { rawValue }
}

enum RiskLevel: String, CaseIterable, Hashable {
    case low = "低風險"
    case moderate = "中風險"
    case high = "高風險"

    var tint: Color {
        switch self {
        case .low: Theme.sage
        case .moderate: Theme.gold
        case .high: Theme.blush
        }
    }

    var icon: String {
        switch self {
        case .low: "checkmark.seal.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .high: "xmark.octagon.fill"
        }
    }

    var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }
}

enum EWGBand: String, Hashable {
    case safe = "綠色安全"
    case moderate = "黃色中度"
    case high = "紅色高風險"

    var tint: Color {
        switch self {
        case .safe: Theme.sage
        case .moderate: Theme.gold
        case .high: Theme.blush
        }
    }

    var icon: String {
        switch self {
        case .safe: "leaf.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .high: "xmark.octagon.fill"
        }
    }
}

struct Ingredient: Identifiable, Hashable {
    let id: String
    let chineseName: String
    let englishName: String
    let scientificName: String
    let symbol: String
    let benefit: String
    let benefits: [String]
    let summary: String
    let safetyNote: String
    let suitableSkinTypes: [String]
    let cautionSkinTypes: [String]
    let warnings: [String]
    let ewgScore: Int
    let ewgBand: EWGBand
    let risk: RiskLevel
    let accentRed: Double
    let accentGreen: Double
    let accentBlue: Double
    /// CosIng／INCI 別名；字典搜尋與詳情頁可選顯示。
    let aliases: [String]?

    var accent: Color {
        Color.safeRGB(red: accentRed, green: accentGreen, blue: accentBlue)
    }

    init(
        id: String,
        chineseName: String,
        englishName: String,
        scientificName: String,
        symbol: String,
        benefit: String,
        benefits: [String],
        summary: String,
        safetyNote: String,
        suitableSkinTypes: [String],
        cautionSkinTypes: [String],
        warnings: [String],
        ewgScore: Int,
        ewgBand: EWGBand,
        risk: RiskLevel,
        accentRed: Double,
        accentGreen: Double,
        accentBlue: Double,
        aliases: [String]? = nil
    ) {
        self.id = id
        self.chineseName = chineseName
        self.englishName = englishName
        self.scientificName = scientificName
        self.symbol = symbol
        self.benefit = benefit
        self.benefits = benefits
        self.summary = summary
        self.safetyNote = safetyNote
        self.suitableSkinTypes = suitableSkinTypes
        self.cautionSkinTypes = cautionSkinTypes
        self.warnings = warnings
        self.ewgScore = ewgScore
        self.ewgBand = ewgBand
        self.risk = risk
        self.accentRed = accentRed
        self.accentGreen = accentGreen
        self.accentBlue = accentBlue
        self.aliases = aliases
    }
}

extension Ingredient {
    static let samples: [Ingredient] = [
        Ingredient(
            id: "niacinamide",
            chineseName: "菸鹼醯胺",
            englishName: "Niacinamide",
            scientificName: "Niacinamide（Nicotinamide）",
            symbol: "N3",
            benefit: "控油 · 修護屏障",
            benefits: ["控油", "修護屏障", "亮白", "穩定膚況"],
            summary: "穩定膚況、淡化暗沉，適合日常保養。",
            safetyNote: "濃度 2–5% 普遍耐受，少數膚質可能初期泛紅。",
            suitableSkinTypes: ["油性", "混合性", "敏感性", "暗沉肌"],
            cautionSkinTypes: ["極乾燥肌初期可能緊繃，建議搭配保濕"],
            warnings: [
                "常見使用濃度約 2–5%，高濃度未必更有效。",
                "少數人初期可能出現泛紅或乾燥，可隔日使用再調整。"
            ],
            ewgScore: 1,
            ewgBand: .safe,
            risk: .low,
            accentRed: 0.62,
            accentGreen: 0.68,
            accentBlue: 0.58,
            aliases: ["Nicotinamide", "Vitamin B3", "Vit. B3"]
        ),
        Ingredient(
            id: "salicylic-acid",
            chineseName: "水楊酸",
            englishName: "Salicylic Acid",
            scientificName: "Salicylic Acid（2-Hydroxybenzoic acid）",
            symbol: "BHA",
            benefit: "疏通毛孔 · 抗痘",
            benefits: ["抗痘", "疏通毛孔", "去角質", "控油"],
            summary: "油溶性酸類，深入毛孔代謝老廢角質。",
            safetyNote: "避免高頻疊加酸類；敏感與乾燥膚質需降低頻率。",
            suitableSkinTypes: ["油性", "混合性", "痘痘肌", "粉刺肌"],
            cautionSkinTypes: ["乾燥、敏感肌需降低頻率與濃度"],
            warnings: [
                "孕婦與哺乳期建議避免使用，或先諮詢醫師。",
                "外用常見濃度約 0.5–2%，勿與高濃度酸類過度疊加。",
                "使用後加強保濕，白天務必防曬。"
            ],
            ewgScore: 4,
            ewgBand: .moderate,
            risk: .moderate,
            accentRed: 0.74,
            accentGreen: 0.58,
            accentBlue: 0.48
        ),
        Ingredient(
            id: "vitamin-c",
            chineseName: "維生素 C",
            englishName: "Vitamin C",
            scientificName: "Ascorbic Acid（L-Ascorbic Acid）",
            symbol: "C",
            benefit: "抗氧化 · 提亮",
            benefits: ["抗氧化", "亮白", "提亮均勻", "淡化暗沉"],
            summary: "對抗自由基、改善暗沉，讓膚色更均勻。",
            safetyNote: "酸性配方可能刺激；建議晨間使用並搭配防曬。",
            suitableSkinTypes: ["正常", "油性", "暗沉肌", "早老化肌"],
            cautionSkinTypes: ["敏感肌建議由低濃度或衍生物開始"],
            warnings: [
                "純 L-抗壞血酸偏酸，可能造成刺癢或泛紅。",
                "建議晨間使用，並搭配廣譜防曬以維持亮白效果。",
                "開封後注意氧化變色，效能會隨時間下降。"
            ],
            ewgScore: 2,
            ewgBand: .safe,
            risk: .low,
            accentRed: 0.80,
            accentGreen: 0.68,
            accentBlue: 0.42
        )
    ]
}
