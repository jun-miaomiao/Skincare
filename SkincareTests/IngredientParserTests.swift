import Foundation
import Testing
@testable import Skincare

/// 字典主引擎、標題錨點裁切與清洗 helper 單元測試。
struct IngredientParserTests {

    private func ensureDatabase() {
        #expect(IngredientDatabaseManager.shared.ensureLoaded())
        DictionaryReverseAnalyzer.resetCandidateCache()
    }

    private func dictionaryParse(_ ocr: String) -> [String] {
        DictionaryReverseAnalyzer.matchIngredientItems(in: ocr).map(\.englishName)
    }

    private func resolved(_ name: String) -> IngredientItem? {
        IngredientMatcher.matchToken(name)
    }

    @Test func analyzeIngredientsByDictionary_isPrimaryEntry() {
        ensureDatabase()
        let result = IngredientParser.analyzeIngredientsByDictionary(
            rawText: "Water, Glycerin, Niacinamide, Seattle WA"
        )
        #expect(result.count >= 2)
        #expect(result.contains {
            $0.englishName.uppercased().contains("WATER")
                || $0.englishName.uppercased().contains("AQUA")
        })
        #expect(!result.contains { $0.englishName.uppercased().contains("SEATTLE") })
    }

    @Test func analyzeIngredientsByDictionary_hyaluronicTonerFullINCIPaste() {
        ensureDatabase()
        let raw = """
        全成分：WATER, DIPROPYLENE GLYCOL, PEG-40 HYDROGENATED CASTOR OIL, PEG-32, SODIUM HYALURONATE, CARBOMER, TRIETHANOLAMINE, HYDROXYETHYLCELLULOSE, DISODIUM EDTA, PEG/PPG-17/6 COPOLYMER, ALCOHOL, ALLANTOIN, PANTHENOL, ALOE BARBADENSIS LEAF WATER, BUTYLENE GLYCOL, MENTHA PIPERITA (PEPPERMINT) LEAF EXTRACT, FREESIA REFRACTA EXTRACT, ROSMARINUS OFFICINALIS (ROSEMARY) LEAF EXTRACT, CHAMOMILLA RECUTITA (MATRICARIA) FLOWER EXTRACT, LAVANDULA ANGUSTIFOLIA (LAVENDER) EXTRACT, MONARDA DIDYMA LEAF EXTRACT, CEREUS GRANDIFLORUS (CACTUS) EXTRACT, HYDROLYZED COLLAGEN, MALT EXTRACT, GLUCONOLACTONE, BAMBUSA VULGARIS LEAF/STEM EXTRACT, MELALEUCA ALTERNIFOLIA (TEA TREE) EXTRACT, PANAX GINSENG ROOT EXTRACT, DAUCUS CAROTA SATIVA (CARROT) ROOT EXTRACT, CUCURBITA PEPO (PUMPKIN) FRUIT EXTRACT, ETHYLHEXYLGLYCERIN, PHENOXYETHANOL, CHLORPHENESIN, FRAGRANCE
        """
        let result = IngredientParser.analyzeIngredientsByDictionary(rawText: raw)
        let names = result.map(\.englishName)
        // 標示共 34 項；貼上應接近全中，且從 Water 起頭（不是從 Allantoin）。
        #expect(result.count >= 28, "貼上全成分命中過少：\(result.count) → \(names)")
        #expect(result.count <= 36, "貼上不應明顯灌水：\(result.count) → \(names)")
        #expect(names.first.map {
            $0.uppercased().contains("WATER") || $0.uppercased().contains("AQUA")
        } == true)
        #expect(names.contains { $0.localizedCaseInsensitiveContains("Allantoin") })
        #expect(names.contains { $0.localizedCaseInsensitiveContains("Fragrance") || $0.localizedCaseInsensitiveContains("Parfum") })
    }

    @Test func analyzeIngredientsByDictionary_anchorDropsTitleIngredientWord() {
        ensureDatabase()
        let result = IngredientParser.analyzeIngredientsByDictionary(
            rawText: """
            Glow Water Mist
            INGREDIENTS: Glycerin, Niacinamide
            """
        )
        #expect(result.count >= 2)
        #expect(result.first.map {
            $0.englishName.uppercased().contains("GLYCERIN")
                || $0.englishName.uppercased().contains("GLYCEROL")
        } == true)
        #expect(!result.contains { item in
            let name = item.englishName.uppercased()
            return (name == "WATER" || name == "AQUA") && !name.contains("GLYCER")
        })
    }


    @Test func paulaBHA_dictionaryRecoversEightWithFuzzyOCR() {
        ensureDatabase()

        let ocr = """
        Water (Aqua), Methylpropanedi, Bitylene Glycol, Salicylic Acid,
        Polysorbate 20, Camellia Oleifera (Green Tea) Leaf Extract,
        Sodium Hydroide, Tetrasodium EDTA. [r5/il402v1]
        """
        let parsed = dictionaryParse(ocr)
        #expect(parsed.count == 8, "寶拉應為 8 項，實際 \(parsed.count)：\(parsed)")

        let expected = [
            "Water",
            "Methylpropanediol",
            "Butylene Glycol",
            "Salicylic Acid",
            "Polysorbate 20",
            "Camellia Oleifera Leaf Extract",
            "Sodium Hydroxide",
            "Tetrasodium EDTA",
        ]
        for name in expected {
            #expect(resolved(name) != nil, "應收錄：\(name)")
            #expect(parsed.contains {
                $0.uppercased().contains(name.uppercased().split(separator: " ").first.map(String.init) ?? name)
                    || resolved($0)?.englishName.uppercased() == name.uppercased()
                    || $0.uppercased() == name.uppercased()
            }, "清單應含 \(name)：\(parsed)")
        }
    }

    @Test func softymanSunscreen_dictionaryHitsFilters() {
        ensureDatabase()

        let ocr = """
        雪芙蘭 超水感防曬乳
        WATER, DIETHYLAMINO HYDROXYBENZOYL HEXYL BENZOATE(DHHB)(6.0%),
        ETHYLHEXYL SALICYLATE (4.5%), ETHYLHEXYL TRIAZONE(1.0%),
        METHYLENE BIS-BENZOTRIAZOLYL TETRAMETHYLBUTYLPHENOL(2.0%),
        DIETHYLHEXYL CARBONATE, MICROCRYSTALLINE CELLULOSE
        """
        let parsed = dictionaryParse(ocr)
        let joined = parsed.joined(separator: " | ").uppercased()
        #expect(joined.contains("DIETHYLAMINO") || joined.contains("HYDROXYBENZOYL"))
        #expect(joined.contains("ETHYLHEXYL SALICYLATE") || joined.contains("SALICYLATE"))
        #expect(parsed.count >= 4)
    }

    @Test func joinOCRLines_hyphenContinuation() {
        let joined = IngredientParser.joinOCRLines([
            "SODIUM POLYACRY-",
            "LOYLDIMETHYL TAURATE",
            "WATER"
        ])
        #expect(joined.uppercased().contains("SODIUM POLYACRYLOYLDIMETHYL TAURATE"))
        #expect(joined.contains("\n") || joined.uppercased().contains("WATER"))
    }

    @Test func suggestMatching_ammoAndNiacin() {
        ensureDatabase()

        let ammo = IngredientDatabaseManager.shared.suggest(matching: "ammo", limit: 8)
        #expect(!ammo.isEmpty)
        #expect(ammo.contains {
            $0.englishName.uppercased().contains("AMMONIUM ACRYLOYLDIMETHYLTAURATE")
        })

        let niacin = IngredientDatabaseManager.shared.suggest(matching: "niacin", limit: 8)
        #expect(niacin.contains {
            $0.englishName.uppercased().contains("NIACINAMIDE")
                || $0.chineseName.contains("菸鹼")
        })
    }
}
