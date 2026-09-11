import Foundation
import Testing
@testable import Skincare

struct DictionaryReverseAnalyzerTests {

    private func ensureDatabase() {
        #expect(IngredientDatabaseManager.shared.ensureLoaded())
        DictionaryReverseAnalyzer.resetCandidateCache()
    }

    @Test func longestMatchPrefersCamelliaOverExtractFragments() {
        ensureDatabase()

        let text = """
        Water, Camellia Oleifera (Green Tea) Leaf Extract, Glycerin
        """
        let items = DictionaryReverseAnalyzer.matchIngredientItems(in: text)
        let names = items.map { $0.englishName.uppercased() }

        #expect(names.contains(where: { $0.contains("CAMELLIA OLEIFERA") }))
        #expect(!names.contains("EXTRACT"))
        #expect(!names.contains("TEA"))
    }

    @Test func dictionaryTrack_paulaBHA_noAnchorRequired() {
        ensureDatabase()

        let ocr = """
        PAULA'S CHOICE 2% BHA Liquid
        Water (Aqua), Methy|propaneld, Butylene Glycol, Salicylic Acid,
        Polysorbate 20, Camellia Oleifera (Green Tea) Leaf Extract,
        Sodium Hydroxide, Tetrasodium EDTA. [r5/il402v1]
        4C. Seattle, WA 98101
        Distributed by Paula's Choice, LLC
        Manufactured for Paula's Choice
        """

        let newItems = DictionaryReverseAnalyzer.matchIngredientItems(in: ocr)
        let newNames = newItems.map(\.englishName)
        #expect(newNames.count >= 7, "字典逆向寶拉應 ≥7，實際 \(newNames.count)：\(newNames)")
        #expect(newNames.contains { $0.uppercased().contains("WATER") || $0.uppercased().contains("AQUA") })
        #expect(newNames.contains { $0.uppercased().contains("SALICYLIC") })
        #expect(newNames.contains { $0.uppercased().contains("BUTYLENE") })
        #expect(newNames.contains { $0.uppercased().contains("CAMELLIA") })
        #expect(newNames.contains { $0.uppercased().contains("EDTA") })
        #expect(!newNames.joined().uppercased().contains("SEATTLE"))
        #expect(!newNames.joined().uppercased().contains("DISTRIBUTED"))
    }

    /// OCR 輕微漏字／替換：編輯距離 ≤2 應撈回寶拉 8 項。
    @Test func dictionaryTrack_paulaBHA_fuzzyOCR_recoversEight() {
        ensureDatabase()

        let ocr = """
        Water (Aqua), Methylpropanedi, Bitylene Glycol, Salicylic Acid,
        Polysorbate 20, Camellia Oleifera (Green Tea) Leaf Extract,
        Sodium Hydroide, Tetrasodium EDTA
        4C. Seattle, WA 98104
        Distributed by Paula's Choice
        """

        let items = DictionaryReverseAnalyzer.matchIngredientItems(in: ocr)
        let names = items.map(\.englishName)
        let joined = names.joined(separator: " | ").uppercased()

        #expect(names.count == 8, "模糊容錯後寶拉應為 8 項，實際 \(names.count)：\(names)")
        #expect(joined.contains("METHYLPROPANEDIOL"))
        #expect(joined.contains("BUTYLENE"))
        #expect(joined.contains("SODIUM HYDROXIDE") || names.contains { $0.uppercased().contains("HYDROXIDE") })
        #expect(!joined.contains("SEATTLE"))
        #expect(!joined.contains("98104"))
        #expect(!joined.contains("DISTRIBUTED"))
        #expect(!names.contains { $0.contains("4C") || $0.uppercased().contains("WA ") })
    }

    /// 掃描清單保留未命中原字串供手動修正，但地址／頁尾等雜訊仍必須被擋掉，
    /// 且未命中項不得被算進字典命中數（辨識三態靠它分流）。
    @Test func scanSession_keepsUnknownTokens_butStillDropsAddressNoise() async {
        ensureDatabase()

        let ocr = """
        Water, Glycerin
        4C. Seattle, WA 98104
        -C.Seatte
        Distributed by Example Labs
        """
        let result = await ScanSessionProcessor.analyze(text: ocr, profile: nil)
        let joined = result.ingredients.joined(separator: " | ").uppercased()

        #expect(!joined.contains("SEATTLE"))
        #expect(!joined.contains("98104"))
        #expect(!joined.contains("DISTRIBUTED"))

        // 命中數只算字典命中，未命中原字串不計入。
        #expect(result.dictionaryHitCount >= 2)
        #expect(result.dictionaryHitCount <= result.ingredients.count)
        let hits = result.ingredients.filter { IngredientMatcher.matchToken($0) != nil }
        #expect(hits.count == result.dictionaryHitCount)
        #expect(hits.contains { $0.uppercased().contains("WATER") || $0.uppercased().contains("AQUA") })
        #expect(hits.contains { $0.uppercased().contains("GLYCER") })

        // OCR 碎片可以留在清單裡，但絕不能被當成字典命中。
        #expect(!hits.contains { $0.uppercased().contains("SEATTE") })
    }

    @Test func dictionaryTrack_burtsBees_ignoresMarketingNoise() {
        ensureDatabase()

        let ocr = """
        NO ANIMAL TESTING
        RECYCLABLE CARTON
        INGREDIENTS FROM NATURE
        Formulated without Parabens, Petrolatum or SLS
        INGREDIENTS: beeswax, cannabis sativa seed oil*, cocos nucifera (coconut) oil,
        helianthus annuus (sunflower) seed oil, lanolin, glycine soja (soybean) oil, canola oil,
        rosmarinus officinalis (rosemary) leaf extract, tocopherol, flavor**, rebaudioside A,
        mentha piperita (peppermint) oil, cera alba, butyrospermum parkii (shea) butter,
        theobroma cacao (cocoa) seed butter, ricinus communis (castor) seed oil
        Made in the USA. Dist. by BURT'S BEES
        """

        let newItems = DictionaryReverseAnalyzer.matchIngredientItems(in: ocr)
        let newNames = newItems.map(\.englishName)
        let joined = newNames.joined(separator: " | ").uppercased()

        #expect(newNames.count >= 12, "蜜蜂爺爺字典逆向應 ≥12，實際 \(newNames.count)：\(newNames)")
        #expect(joined.contains("BEESWAX") || newNames.contains { $0.uppercased().contains("CERA") })
        #expect(joined.contains("CANNABIS") || joined.contains("HEMP"))
        #expect(joined.contains("LANOLIN"))
        #expect(joined.contains("CANOLA"))
        #expect(!joined.contains("PARABEN"))
        #expect(!joined.contains("PETROLATUM"))
        #expect(!joined.contains("BURT"))
        #expect(!joined.contains("ANIMAL"))
        #expect(newNames.first.map { !$0.uppercased().contains("INGREDIENT") } == true)
    }

    @Test func analyzeIngredientsByDictionary_returnsIngredientModels() {
        ensureDatabase()
        let result = IngredientParser.analyzeIngredientsByDictionary(
            rawText: "Water, Glycerin, Niacinamide"
        )
        #expect(result.count >= 2)
        #expect(result.contains { $0.englishName.uppercased().contains("WATER")
            || $0.englishName.uppercased().contains("AQUA") })
    }

    @Test func recognitionTier_threeWaySplit() {
        #expect(RecognitionTier(count: 0) == .none)
        #expect(RecognitionTier(count: 1) == .weak)
        #expect(RecognitionTier(count: 4) == .weak)
        #expect(RecognitionTier(count: 5) == .strong)
        #expect(RecognitionTier(count: 12) == .strong)
    }

    @Test func shortNames_requireExactBoundary_noFuzzyFromGarbage() {
        ensureDatabase()

        // 亂碼內部夾短詞：不得命中 Serine / Urea
        let garbage = "XQSERINEZZ UREABCDE METHYLPROPANEDIOL"
        let garbageHits = DictionaryReverseAnalyzer.matchIngredientItems(in: garbage)
        let garbageNames = garbageHits.map { $0.englishName.uppercased() }
        #expect(!garbageNames.contains(where: { $0 == "SERINE" || $0.contains("SERINE") && $0.count <= 8 }))
        #expect(!garbageNames.contains(where: { $0 == "UREA" }))
        #expect(garbageNames.contains(where: { $0.contains("METHYLPROPANEDIOL") }))

        // 嚴格邊界下的精準短詞仍可命中
        let clean = "Water, Urea, Serine, Glycerin"
        let cleanHits = DictionaryReverseAnalyzer.matchIngredientItems(in: clean)
        let cleanNames = cleanHits.map { $0.englishName.uppercased() }
        #expect(cleanNames.contains(where: { $0.contains("WATER") || $0.contains("AQUA") }))
        #expect(cleanNames.contains(where: { $0 == "UREA" || $0.contains("UREA") }))
        #expect(cleanNames.contains(where: { $0.contains("SERINE") }))
    }

    @Test func fuzzy_onlyForLongNames_notShortTypos() {
        ensureDatabase()
        // 短詞錯拼不得 Fuzzy 撈回
        let shortTypo = "Urra, Seriene"
        let shortHits = DictionaryReverseAnalyzer.matchIngredientItems(in: shortTypo)
        #expect(!shortHits.contains { $0.englishName.uppercased() == "UREA" })
        #expect(!shortHits.contains { $0.englishName.uppercased().contains("SERINE") && $0.englishName.count <= 8 })

        // 長詞錯拼仍可
        let longTypo = "Sodium Hydroide, Bitylene Glycol"
        let longHits = DictionaryReverseAnalyzer.matchIngredientItems(in: longTypo)
        let joined = longHits.map(\.englishName).joined(separator: " | ").uppercased()
        #expect(joined.contains("HYDROXIDE"))
        #expect(joined.contains("BUTYLENE"))
    }

    @Test func consumedMask_preventsShortWordStealingLongHit() {
        ensureDatabase()
        let text = "Helianthus Annuus Seed Oil and fragrance"
        let items = DictionaryReverseAnalyzer.matchIngredientItems(in: text)
        let names = items.map { $0.englishName.uppercased() }
        #expect(names.contains(where: { $0.contains("HELIANTHUS") || $0.contains("SUNFLOWER") }))
        #expect(!names.contains("OIL"))
    }

    @Test func pastePath_usesDictionaryAndSkipsCaptureQualityGate() async {
        ensureDatabase()

        let result = await ScanSessionProcessor.analyze(
            text: "Water, Glycerin, Propylene Glycol, Phenoxyethanol",
            profile: nil
        )

        #expect(result.averageOCRConfidence == nil, "貼上不是 OCR，不該帶 Vision 信心度")
        #expect(!result.needsCaptureRetake, "貼上不走難標品質閘")
        #expect(result.dictionaryHitCount >= 3, "官網全成分應命中字典：\(result.ingredients)")
        let joined = result.ingredients.joined(separator: " | ").uppercased()
        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("GLYCERIN"))
        #expect(joined.contains("PROPYLENE"))
    }

    @Test func pastePath_unmatchedOnlyDoesNotCountAsSuccess() async {
        ensureDatabase()

        let result = await ScanSessionProcessor.analyze(
            text: "ZZZQQX WWVVBB, YYXXZZ VVUUTT",
            profile: nil
        )
        #expect(result.dictionaryHitCount == 0)
        #expect(result.averageOCRConfidence == nil)
    }
}
