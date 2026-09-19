import Foundation

/// 護膚明星有益成分規則：關鍵字比對、膚質適配標籤、敏感／致痘互斥。
/// 由 `SkinSuitabilityEngine` 呼叫；1% 分界降級與最終 Safety First 互斥仍由引擎統一處理。
enum BeneficialRuleEngine {

    struct Context {
        let displayName: String
        let key: String
        let databaseItem: IngredientItem?
        let listIndex: Int
        let skinType: SkinType
        let isSensitiveSkin: Bool
        let demoteIfTrace: Bool
    }

    static func collectHits(context: Context) -> [SkinSuitabilityHit] {
        var results: [SkinSuitabilityHit] = []

        appendAzelaic(context: context, into: &results)
        appendVitaminB6(context: context, into: &results)
        appendTeaTree(context: context, into: &results)
        appendEctoin(context: context, into: &results)
        appendOliveLeaf(context: context, into: &results)
        appendPurifiedCentella(context: context, into: &results)
        appendPhytosphingosine(context: context, into: &results)
        appendVitaminA(context: context, into: &results)
        appendVitaminC(context: context, into: &results)
        appendPeptides(context: context, into: &results)
        appendSheaButter(context: context, into: &results)

        return results
    }

    // MARK: - Oil / Combination T-zone

    private static func appendAzelaic(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: azelaicKeywords) else { return }

        if context.isSensitiveSkin {
            results.append(
                makeHit(
                    context,
                    flag: .sensitiveCaution,
                    reason: "杜鵑花酸／壬二酸具一定刺激性，敏感肌建議降低頻率或避開；已隱藏控油推薦標籤。"
                )
            )
            return
        }

        switch context.skinType {
        case .oily:
            results.append(contentsOf: beneficialPair(
                context,
                flags: [.oilyFriendly],
                reason: "含杜鵑花酸或其衍生物，有助油性肌控油與抗發炎淨膚。"
            ))
        case .combination:
            results.append(contentsOf: beneficialPair(
                context,
                flags: [.tZoneOilControl],
                reason: "含杜鵑花酸或其衍生物，有助混合肌 T 字控油與抗發炎調理。"
            ))
        case .dry, .normal:
            break
        }
    }

    private static func appendVitaminB6(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: vitaminB6Keywords) else { return }
        guard context.skinType == .oily || context.skinType == .combination else { return }
        guard !context.isSensitiveSkin else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.sebumBalance],
            reason: "含維生素 B6（Pyridoxine），有助調理皮脂分泌。"
        ))
    }

    private static func appendTeaTree(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: teaTreeKeywords) else { return }

        if context.isSensitiveSkin {
            results.append(
                makeHit(
                    context,
                    flag: .sensitiveNote,
                    reason: "茶樹精油／萃取可能刺激敏弱膚質，建議謹慎使用；已隱藏淨化控油推薦。"
                )
            )
            return
        }

        guard context.skinType == .oily || context.skinType == .combination else { return }
        results.append(contentsOf: beneficialPair(
            context,
            flags: [.purifyOilControl],
            reason: "含茶樹（Melaleuca）相關成分，有助淨化與控油。"
        ))
    }

    // MARK: - Sensitive / barrier

    private static func appendEctoin(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: ectoinKeywords) else { return }
        guard context.isSensitiveSkin || context.skinType == .dry || context.skinType == .normal else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.sensitiveRepair, .barrierStrengthen],
            reason: "含依克多因（Ectoin），有助敏弱修護與強化屏障。"
        ))
    }

    private static func appendOliveLeaf(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: oliveLeafKeywords) else { return }
        guard context.isSensitiveSkin || context.skinType == .dry || context.skinType == .normal else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.sootheRedness],
            reason: "含油橄欖葉萃取，有助舒緩退紅。"
        ))
    }

    private static func appendPurifiedCentella(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: purifiedCentellaKeywords) else { return }
        guard context.isSensitiveSkin || context.skinType == .dry || context.skinType == .normal else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.sootheRepair],
            reason: "含純化積雪草苷／酸，有助舒緩修護。"
        ))
    }

    private static func appendPhytosphingosine(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: phytosphingosineKeywords) else { return }
        guard context.isSensitiveSkin || context.skinType == .dry else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.barrierRepair],
            reason: "含植物鞘氨醇，有助屏障修護。"
        ))
    }

    // MARK: - Dry / anti-aging

    private static func appendVitaminA(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: vitaminAKeywords) else { return }

        // 孕哺慎用：視黃醇／維 A 酸家族一律標示（與膚質推薦並存，不取代刺激警示）。
        results.append(
            makeHit(
                context,
                flag: .pregnancyCaution,
                reason: "含維生素 A／視黃醇家族（含 A 醇、A 醛、視黃酸酯等）；孕婦與哺乳期建議避免使用或先諮詢醫師。"
            )
        )

        if context.isSensitiveSkin {
            results.append(
                makeHit(
                    context,
                    flag: .irritationCaution,
                    reason: "維生素 A 家族（視黃醇／視黃醛等）刺激性較高，敏感肌建議避開或極低頻率；已隱藏抗老推薦。"
                )
            )
            return
        }

        guard context.skinType == .dry || context.skinType == .normal else { return }
        results.append(contentsOf: beneficialPair(
            context,
            flags: [.dryAntiAging, .firmRepair],
            reason: "含維生素 A 家族活性，有助乾肌抗老與緊緻修護。"
        ))
    }

    private static func appendVitaminC(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: vitaminCKeywords) else { return }

        // 敏感肌＋前排（前 5）→ 敏弱慎用；其餘敏感情境不給搶眼推薦
        if context.isSensitiveSkin {
            if IngredientPositionWeight.isFrontCore(context.listIndex) {
                results.append(
                    makeHit(
                        context,
                        flag: .sensitiveCaution,
                        reason: "維生素 C 家族位於包裝前排，濃度相對較高，敏感肌建議慎用；已隱藏抗氧提亮推薦。"
                    )
                )
            }
            return
        }

        guard context.skinType == .dry || context.skinType == .normal else { return }
        results.append(contentsOf: beneficialPair(
            context,
            flags: [.antioxidantBrighten],
            reason: "含維生素 C 家族，有助抗氧提亮。"
        ))
    }

    private static func appendPeptides(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: peptideKeywords) else { return }
        // 乾性／中性肌為主；油性／混合肌不套用胜肽抗老背書
        guard context.skinType == .dry || context.skinType == .normal else { return }

        results.append(contentsOf: beneficialPair(
            context,
            flags: [.peptideFirming],
            reason: "含胜肽類成分，有助緊緻與修護訊號。"
        ))
    }

    private static func appendSheaButter(context: Context, into results: inout [SkinSuitabilityHit]) {
        guard matches(context, keywords: sheaButterKeywords) else { return }

        switch context.skinType {
        case .oily:
            results.append(
                makeHit(
                    context,
                    flag: .comedogenicRisk,
                    reason: "乳木果油／乳油木果脂質地偏厚重，油性肌較易致粉刺；已隱藏滋潤推薦。"
                )
            )
        case .combination:
            results.append(
                makeHit(
                    context,
                    flag: .tZoneComedogenic,
                    reason: "乳木果油／乳油木果脂於混合肌 T 字較易悶出粉刺，建議著重兩頰；已隱藏滋潤推薦。"
                )
            )
        case .dry:
            results.append(contentsOf: beneficialPair(
                context,
                flags: [.dryMoisturize],
                reason: "含乳木果油／乳油木果脂，有助乾肌滋潤鎖水。"
            ))
        case .normal:
            break
        }
    }

    // MARK: - Helpers

    private static func beneficialPair(
        _ context: Context,
        flags: [SkinSuitabilityFlag],
        reason: String
    ) -> [SkinSuitabilityHit] {
        return flags.map { makeHit(context, flag: $0, reason: reason) }
    }

    private static func makeHit(
        _ context: Context,
        flag: SkinSuitabilityFlag,
        reason: String
    ) -> SkinSuitabilityHit {
        SkinSuitabilityHit(
            ingredientKey: context.key,
            displayName: context.displayName,
            flag: flag,
            reason: reason,
            listIndex: context.listIndex
        )
    }

    private static func matches(_ context: Context, keywords: [String]) -> Bool {
        SkinSuitabilityEngine.matchesKeywords(
            displayName: context.displayName,
            databaseItem: context.databaseItem,
            keywords: keywords
        )
    }

    // MARK: - Keyword tables

    static let azelaicKeywords: [String] = [
        "azelaic acid", "potassium azeloyl diglycinate",
        "杜鵑花酸", "壬二酸"
    ]

    static let vitaminB6Keywords: [String] = [
        "pyridoxine", "pyridoxine hcl", "pyridoxine hydrochloride",
        "維生素b6", "維生素 b6", "维生素b6"
    ]

    static let teaTreeKeywords: [String] = [
        "melaleuca alternifolia", "tea tree",
        "茶樹精油", "茶樹葉", "茶樹"
    ]

    static let ectoinKeywords: [String] = [
        "ectoin", "ectoine",
        "四氫甲基嘧啶羧酸", "依克多因"
    ]

    static let oliveLeafKeywords: [String] = [
        "olea europaea leaf extract", "olive leaf extract",
        "油橄欖葉萃取", "橄欖葉萃取"
    ]

    static let purifiedCentellaKeywords: [String] = [
        "madecassoside", "asiaticoside", "asiatic acid", "madecassic acid",
        "羥基積雪草苷", "羟基積雪草苷", "積雪草苷", "積雪草酸"
    ]

    static let phytosphingosineKeywords: [String] = [
        "phytosphingosine", "植物鞘氨醇"
    ]

    static let vitaminAKeywords: [String] = [
        "retinol", "retinal", "retinaldehyde", "retinoic acid", "tretinoin", "adapalene",
        "hydroxypinacolone retinoate", "retinyl",
        "視黃醇", "視黃醛", "視黃酸", "維a酸", "維 a 酸", "維A酸",
        "A醇", "A醛", "A酸"
    ]

    static let vitaminCKeywords: [String] = [
        "ascorbic acid", "3-o-ethyl ascorbic acid", "ethyl ascorbic acid",
        "ascorbyl glucoside", "sodium ascorbyl phosphate",
        "左型c", "左旋c", "乙基維他命c", "乙基維生素c", "抗壞血酸"
    ]

    static let peptideKeywords: [String] = [
        "palmitoyl pentapeptide", "palmitoyl tripeptide",
        "acetyl hexapeptide", "copper tripeptide",
        "五胜肽", "六胜肽", "藍銅胜肽", "多肽", "胜肽"
    ]

    static let sheaButterKeywords: [String] = [
        "butyrospermum parkii", "shea butter",
        "乳油木果脂", "乳木果油", "乳木果脂", "乳油木果"
    ]
}
