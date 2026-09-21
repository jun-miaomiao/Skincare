import Testing
@testable import Skincare

struct DictionaryChineseAliasTests {
    private func ensureDatabase() {
        IngredientDatabaseManager.shared.ensureLoaded()
    }

    private func topEnglish(for query: String) -> String? {
        IngredientDatabaseManager.shared.suggest(matching: query, limit: 8)
            .first?
            .englishName
            .uppercased()
    }

    @Test func suggest_traditionalNicknamesHitCommonINCI() {
        ensureDatabase()

        #expect(topEnglish(for: "維他命B3")?.contains("NIACINAMIDE") == true)
        #expect(topEnglish(for: "A醇")?.contains("RETINOL") == true)
        #expect(topEnglish(for: "A醛")?.contains("RETINAL") == true)
        #expect(topEnglish(for: "維他命C")?.contains("ASCORBIC") == true)
        #expect(topEnglish(for: "雷公根")?.contains("CENTELLA") == true)
        #expect(topEnglish(for: "壬二酸")?.contains("AZELAIC") == true)
        #expect(topEnglish(for: "植物A醇")?.contains("BAKUCHIOL") == true)
        #expect(topEnglish(for: "乳木果脂")?.contains("BUTYROSPERMUM") == true
                || topEnglish(for: "乳木果脂")?.contains("PARKII") == true)
    }

    @Test func suggest_doesNotRequireSimplifiedChinese() {
        ensureDatabase()
        // 簡體不保證命中；繁中別名才是這輪目標。
        #expect(topEnglish(for: "菸鹼醯胺")?.contains("NIACINAMIDE") == true)
        #expect(topEnglish(for: "視黃醇")?.contains("RETINOL") == true)
    }

    @Test func suggest_ocrSynonymTyposMatchScanRescue() {
        ensureDatabase()

        #expect(topEnglish(for: "glycern")?.contains("GLYCERIN") == true)
        #expect(topEnglish(for: "niacinamid")?.contains("NIACINAMIDE") == true)
        #expect(topEnglish(for: "dimethcone")?.contains("DIMETHICONE") == true)
        #expect(topEnglish(for: "phenoxyethanl")?.contains("PHENOXYETHANOL") == true)
        #expect(topEnglish(for: "vit b3")?.contains("NIACINAMIDE") == true)
    }
}
