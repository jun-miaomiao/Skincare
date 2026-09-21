import Testing
@testable import Skincare

struct ScanAccuracySafeFixTests {
    private func ensureDatabase() {
        IngredientDatabaseManager.shared.ensureLoaded()
        IngredientMatcher.warmIngredientCache()
    }

    @Test func checkAlerts_customRiskOnlyWhenIngredientPresent() {
        ensureDatabase()

        let absent = IngredientMatcher.checkAlerts(
            detectedIngredients: ["Water", "Glycerin", "Niacinamide"],
            blockedTags: [],
            customIngredients: ["Retinol"]
        )
        #expect(!absent.contains(where: { $0.contains("自訂風險") }))

        let present = IngredientMatcher.checkAlerts(
            detectedIngredients: ["Water", "Glycerin", "Retinol"],
            blockedTags: [],
            customIngredients: ["Retinol"]
        )
        #expect(present.contains(where: { $0.contains("自訂風險") && $0.contains("Retinol") }))
    }

    @Test func exactSynonymMap_rescuesCommonOCRTyposWithoutFuzzy() {
        ensureDatabase()

        #expect(IngredientMatcher.applyINCISynonyms("glycern") == "glycerin")
        #expect(IngredientMatcher.applyINCISynonyms("niacinamid") == "niacinamide")
        #expect(IngredientMatcher.applyINCISynonyms("dimethcone") == "dimethicone")

        let glycerin = IngredientMatcher.matchToken("Glycern")
        #expect(glycerin?.englishName.uppercased().contains("GLYCERIN") == true)

        let niacinamide = IngredientMatcher.matchToken("Niacinamid")
        #expect(niacinamide?.englishName.uppercased().contains("NIACINAMIDE") == true)

        // 高風險錯字仍不得被精確別名誤救（維持既有契約）。
        let bannedTypo = IngredientResolver.resolveToken("Chloroacetamidf")
        #expect(bannedTypo == nil)
    }

    @Test func glyphFixes_unifyPipeAndDigitLookalikes() {
        #expect(IngredientParser.replaceCommonOCRCharacters(in: "Methy|propanediol") == "Methylpropanediol")
        #expect(IngredientParser.replaceCommonOCRCharacters(in: "Methy1propanediol") == "Methylpropanediol")
        #expect(IngredientMatcher.applyOCRGlyphFixes("Methy1propanediol") == "Methylpropanediol")
    }

    @Test func stripRedundantUnknowns_stillDropsPackagingNoise() {
        let cleaned = SequentialOverlapMerger.stripRedundantUnknowns([
            "Water",
            "Glycerin",
            "MOISTURIZE PM",
            "Distributed by Example"
        ])
        #expect(cleaned.contains("Water"))
        #expect(cleaned.contains("Glycerin"))
        #expect(!cleaned.contains(where: { $0.uppercased().contains("MOISTURIZE") }))
        #expect(!cleaned.contains(where: { $0.uppercased().contains("DISTRIBUTED") }))
    }
}
