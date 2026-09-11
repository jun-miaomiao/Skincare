import Foundation
import Testing
@testable import Skincare

/// 字典逆向主引擎基準：寶拉／蜜蜂爺爺等，以及 Matcher／清洗 helper。
struct IngredientPipelineBaselineTests {

    private func ensureDatabase() {
        #expect(IngredientDatabaseManager.shared.ensureLoaded())
        DictionaryReverseAnalyzer.resetCandidateCache()
    }

    private func dictionaryNames(from ocr: String) -> [String] {
        DictionaryReverseAnalyzer.matchIngredientItems(in: ocr).map(\.englishName)
    }

    private func resolved(_ name: String) -> IngredientItem? {
        IngredientMatcher.matchToken(name)
    }

    // MARK: - 寶拉

    @Test func baseline_paulaBHA_dictionaryEightItemsNoSeattleNoise() {
        ensureDatabase()

        let ocr = """
        PAULA'S CHOICE 2% BHA Liquid
        INGREDIENTS:
        Water (Aqua), Methy|propaneld, Butylene Glycol, Salicylic Acid,
        Polysorbate 20, Camellia Oleifera (Green Tea) Leaf Extract,
        Sodium Hydroxide, Tetrasodium EDTA. [r5/il402v1]
        4C. Seattle, WA 98101
        Distributed by Paula's Choice, LLC
        Directions: Apply once or twice daily.
        """

        let parsed = dictionaryNames(from: ocr)
        let joined = parsed.joined(separator: " | ").uppercased()

        #expect(parsed.count >= 7, "寶拉字典應 ≥7，實際 \(parsed.count)：\(parsed)")
        #expect(!joined.contains("SEATTLE"))
        #expect(!joined.contains("DISTRIBUTED"))
        #expect(!joined.contains("DIRECTIONS"))
        #expect(IngredientResolver.isNoiseToken("4C. Seattle"))
        #expect(IngredientParser.isAddressNoiseToken("WA 98101"))

        for name in ["WATER", "BUTYLENE", "SALICYLIC", "CAMELLIA", "EDTA"] {
            #expect(joined.contains(name), "應含 \(name)：\(parsed)")
        }
    }

    @Test func baseline_paulaBHA_curvedBottleManufacturedForKeepsList() {
        ensureDatabase()

        let ocr = """
        PAULA'S CHOICE 2% BHA Liquid
        Water (Aqua), Methylpropanedi, Manufactured for Paula's Choice
        Bitylene Glycol, Salicylic Acid,
        Polysorbate 20, Camellia Oleifera (Green Tea) Leaf Extract,
        Sodium Hydroide, Tetrasodium EDTA. [r5/il402v1]
        Manufactured for Paula's Choice, LLC
        4C. Seattle, WA 98101
        """

        let parsed = dictionaryNames(from: ocr)
        #expect(parsed.count >= 7, "圓弧瓶身寶拉應 ≥7，實際 \(parsed.count)：\(parsed)")
        let joined = parsed.joined(separator: " | ").uppercased()
        #expect(joined.contains("BUTYLENE"))
        #expect(joined.contains("SALICYLIC"))
        #expect(joined.contains("HYDROXIDE") || joined.contains("SODIUM"))
        #expect(!joined.contains("MANUFACTURED"))
        #expect(!joined.contains("SEATTLE"))
    }

    // MARK: - 蜜蜂爺爺

    @Test func baseline_burtsBees_dictionaryIgnoresMarketing() {
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

        let parsed = dictionaryNames(from: ocr)
        let joined = parsed.joined(separator: " | ").uppercased()
        #expect(parsed.count >= 12, "蜜蜂爺爺應 ≥12，實際 \(parsed.count)：\(parsed)")
        #expect(!joined.contains("PARABEN"))
        #expect(!joined.contains("PETROLATUM"))
        #expect(!joined.contains("ANIMAL"))
        #expect(!joined.contains("BURT"))
        #expect(joined.contains("BEESWAX") || joined.contains("CERA"))
        #expect(joined.contains("LANOLIN"))
        #expect(joined.contains("CANOLA"))
    }

    // MARK: - 清洗 helper

    @Test func cleanupHelpers_bracketPercentOCRPipe() {
        #expect(IngredientParser.removeBracketCodes(from: "Tetrasodium EDTA. [r5/il402v1]") == "Tetrasodium EDTA. ")
        #expect(IngredientParser.trimBoundaryNoise("  “Tetrasodium EDTA.”  ") == "Tetrasodium EDTA")
        #expect(IngredientParser.replaceCommonOCRCharacters(in: "Methy|propanediol") == "Methylpropanediol")
        #expect(
            IngredientParser.stripConcentrationAndAliasCodes(
                "DIETHYLAMINO HYDROXYBENZOYL HEXYL BENZOATE(DHHB)(6.0%)"
            ) == "DIETHYLAMINO HYDROXYBENZOYL HEXYL BENZOATE"
        )

        let joined = IngredientParser.joinBrokenLines("SODIUM POLYACRY-\nLOYLDIMETHYL TAURATE, SODIUM METABISUL- FITE")
        #expect(joined.uppercased().contains("SODIUM POLYACRYLOYLDIMETHYL TAURATE"))
        #expect(joined.uppercased().contains("SODIUM METABISULFITE"))

        #expect(IngredientParser.isNegativeClaimLine("Formulated without Parabens"))
        #expect(IngredientParser.isMarketingNoiseToken("NO ANIMAL TESTING"))
        #expect(IngredientParser.isFooterLedLine("Distributed by Paula's Choice, LLC"))
    }

    // MARK: - Matcher

    @Test func matcher_laneigeSlashAndBurtsBeesBotanicals() {
        ensureDatabase()

        #expect(IngredientMatcher.matchToken("MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA / CIRE MICROCRISTALLINE")?.chineseName.contains("微晶蠟") == true)
        #expect(IngredientMatcher.matchToken("WATER / AQUA / EAU")?.chineseName.contains("水") == true)
        #expect(IngredientMatcher.stripOrganicAsterisks("cannabis sativa seed oil*") == "cannabis sativa seed oil")
        #expect(IngredientMatcher.matchToken("cannabis sativa seed oil*")?.chineseName.contains("大麻") == true)
        #expect(IngredientMatcher.matchToken("beeswax")?.chineseName.contains("蜂蠟") == true)
        #expect(IngredientMatcher.matchToken("cocos nucifera (coconut) oil")?.chineseName.contains("椰子") == true)

        let pool = IngredientMatcher.buildCandidatePool(from: "helianthus annuus (sunflower) seed oil")
        #expect(pool.contains { IngredientMatcher.deepNormalize($0) == "helianthus annuus seed oil" })
        #expect(pool.contains { IngredientMatcher.deepNormalize($0) == "sunflower seed oil" })
    }

    @Test func matcher_threeLayerRecall_mustHitCataloguedIngredients() {
        ensureDatabase()

        #expect(IngredientMatcher.matchToken("Water ")?.chineseName.contains("水") == true
                || IngredientMatcher.matchToken("Water ")?.englishName.uppercased().contains("WATER") == true)
        #expect(IngredientMatcher.matchToken("WATER (AQUA)")?.chineseName.contains("水") == true)
        #expect(
            IngredientMatcher.matchToken("Methy|propanediol")?.englishName
                .uppercased()
                .contains("METHYLPROPANEDIOL") == true
        )
        #expect(IngredientMatcher.applyOCRGlyphFixes("Methy|propanediol") == "Methylpropanediol")

        let pool = IngredientMatcher.buildCandidatePool(from: "WATER (AQUA)")
        #expect(pool.contains { IngredientMatcher.deepNormalize($0) == "water" })
        #expect(pool.contains { IngredientMatcher.deepNormalize($0) == "aqua" })
    }

    @Test func matcher_cosIngSynonymsAndBotanicalAbbreviations() {
        ensureDatabase()

        #expect(
            IngredientMatcher.expandBotanicalAbbreviations("Camellia Sinensis Leaf Ext.")
                .lowercased()
                .contains("leaf extract")
        )
        #expect(
            IngredientMatcher.expandBotanicalAbbreviations("hamamelis virginiana dist.")
                .lowercased()
                .contains("distillate")
        )
        #expect(
            IngredientMatcher.expandBotanicalAbbreviations("aloe barbadensis fld. ext.")
                .lowercased()
                .contains("fluid extract")
        )
        #expect(
            IngredientMatcher.expandBotanicalAbbreviations("green tea leaf ext")
                .lowercased()
                .hasSuffix("extract")
        )

        #expect(IngredientMatcher.applyINCISynonyms("nicotinamide").lowercased() == "niacinamide")
        #expect(IngredientMatcher.applyINCISynonyms("Vitamin B3").lowercased() == "niacinamide")

        #expect(
            IngredientMatcher.matchToken("nicotinamide")?.englishName
                .uppercased()
                .contains("NIACINAMIDE") == true
        )
        #expect(
            IngredientMatcher.matchToken("vitamin b3")?.englishName
                .uppercased()
                .contains("NIACINAMIDE") == true
        )
        #expect(
            IngredientMatcher.matchToken("Salicylic Acid 2%")?.englishName
                .uppercased()
                .contains("SALICYLIC") == true
        )
        #expect(IngredientMatcher.matchToken("Camellia Oleifera Leaf Ext.") != nil)
    }

    @Test func matcher_tokenizeThenLookup_andLimitedFuzzy() {
        ensureDatabase()

        let tokens = IngredientMatcher.tokenizeCandidateList(
            "Water, nicotinamide, Salicylic Acid 2%, Camellia Sinensis Leaf Ext.\nGlycerin"
        )
        #expect(tokens.contains { $0.lowercased().contains("nicotinamide") })
        #expect(tokens.contains { $0.lowercased().contains("ext") || $0.lowercased().contains("extract") })

        let items = IngredientMatcher.matchIngredientItems(
            in: "Water, nicotinamide, Bitylene Glycol, Camellia Oleifera Leaf Ext."
        )
        let joined = items.map(\.englishName).joined(separator: " | ").uppercased()
        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("NIACINAMIDE"))
        #expect(joined.contains("BUTYLENE"))
        #expect(joined.contains("CAMELLIA"))
    }

    @Test func matcher_slidingWindow_gluedAndPunctuatedCoreSample() {
        ensureDatabase()

        let must = ["WATER", "BUTYLENE", "SALICYLIC", "CAMELLIA"]
        let samples = [
            "Water, Butylene Glycol, Salicylic Acid, Camellia Oleifera Leaf Extract",
            "Water Butylene Glycol Salicylic Acid Camellia Oleifera Leaf Extract",
            "Water\nButylene Glycol\nSalicylic Acid\nCamellia Oleifera Leaf Extract",
            "Water Glycerin Butylene Glycol Salicylic Acid Camellia Oleifera Leaf Extract",
        ]

        for sample in samples {
            let items = IngredientMatcher.matchIngredientItems(in: sample)
            let names = items.map { $0.englishName.uppercased() }
            let joined = names.joined(separator: " | ")
            for needle in must {
                #expect(joined.contains(needle), "樣本應命中 \(needle)：\(sample) → \(items.map(\.englishName))")
            }
            #expect(!names.contains("EXTRACT"), "不得以 Extract 短詞命中：\(names)")
            #expect(!names.contains("LEAF"), "不得以 Leaf 短詞命中：\(names)")
            #expect(!names.contains("ACID"), "不得以 Acid 短詞命中：\(names)")
            #expect(!names.contains("OIL"), "不得以 Oil 短詞命中：\(names)")
        }
    }

    @Test func matcher_preservesOCROrder_andKeepsSlashParenHyphenTokens() {
        ensureDatabase()

        let glued = "Water Glycerin Butylene Glycol Acrylates/C10-30 Alkyl Acrylate Crosspolymer"
        let gluedItems = IngredientMatcher.matchIngredientItems(in: glued)
        let gluedNames = gluedItems.map { $0.englishName.uppercased() }
        if let water = gluedNames.firstIndex(where: { $0.contains("WATER") || $0.contains("AQUA") }),
           let polymer = gluedNames.firstIndex(where: { $0.contains("ACRYLATE") && $0.contains("CROSSPOLYMER") }) {
            #expect(water < polymer, "Water 應排在增稠劑之前：\(gluedItems.map(\.englishName))")
        } else {
            #expect(Bool(false), "應同時命中 Water 與 Acrylates Crosspolymer：\(gluedItems.map(\.englishName))")
        }

        let tokens = IngredientMatcher.tokenizeCandidateList(
            "Water, 1,2-Hexanediol, Pyrus Malus (Apple) Fruit Extract, Acrylates/C10-30 Alkyl Acrylate Crosspolymer"
        )
        #expect(tokens.contains { $0.uppercased().contains("1,2-HEXANEDIOL") })
        #expect(tokens.contains { $0.uppercased().contains("APPLE") })
        #expect(tokens.contains { $0.uppercased().contains("ACRYLATES/C10-30") })

        let punctuated = IngredientMatcher.matchIngredientItems(
            in: "Water, 1,2-Hexanediol, Pyrus Malus (Apple) Fruit Extract, Acrylates/C10-30 Alkyl Acrylate Crosspolymer"
        )
        let joined = punctuated.map(\.englishName).joined(separator: " | ").uppercased()
        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("HEXANEDIOL"))
        #expect(joined.contains("PYRUS") || joined.contains("APPLE") || joined.contains("MALUS"))
        #expect(joined.contains("ACRYLATE") && joined.contains("CROSSPOLYMER"))
    }

    // MARK: - 第一階段：IngredientTokenizer

    @Test func tokenizer_keepsPhysicalOrderAndProtectsBrackets() {
        let raw = """
        INGREDIENTS: Water (Aqua, Eau), 1,2-Hexanediol; Pyrus Malus (Apple) Fruit Extract、
        Acrylates/C10-30 Alkyl Acrylate Crosspolymer, Camellia Sinensis Leaf Ext.
        """
        let tokens = IngredientTokenizer.tokenize(raw)
        let texts = tokens.map(\.text)

        // 1. 順序 = 物理順序，且 index 連續遞增。
        #expect(tokens.map(\.index) == Array(0..<tokens.count))
        #expect(texts.first?.uppercased().contains("WATER") == true)

        // 2. 括號內的逗號禁止切分。
        #expect(texts.contains { $0.uppercased().contains("AQUA") && $0.uppercased().contains("EAU") })

        // 3. 化學式編號逗號禁止切分。
        #expect(texts.contains { $0.uppercased().contains("1,2-HEXANEDIOL") })

        // 4. 分號、頓號是層級 0 的分隔符；換行在拉丁 INCI 續行時改當空白。
        #expect(texts.contains { $0.uppercased().contains("APPLE") })
        #expect(texts.contains { $0.uppercased().contains("ACRYLATES/C10-30") })
        #expect(texts.contains { $0.uppercased().contains("CAMELLIA") })

        // 5. 括號、斜線、連字號、化學式逗號一律保留。
        let joined = texts.joined(separator: " | ")
        #expect(joined.contains("("))
        #expect(joined.contains("/"))
        #expect(joined.contains("-"))
    }

    @Test func tokenizer_unclosedBracket_doesNotSwallowWholeList() {
        // OCR 漏掉右括號時，不得讓後面所有成分黏成單一 Token。
        let raw = """
        Water (Aqua, Glycerin, Butylene Glycol, Salicylic Acid, Niacinamide, \
        Panthenol, Allantoin, Tocopherol, Squalane, Phenoxyethanol, Carbomer
        """
        let texts = IngredientTokenizer.tokenizeToStrings(raw)
        #expect(texts.count >= 4, "未閉合括號應在防呆距離後恢復切分：\(texts)")
        #expect(texts.contains { $0.uppercased().contains("CARBOMER") })
    }

    @Test func tokenizer_wrappedINCI_joinsNewlineInsteadOfSplitting() {
        let ethyl = IngredientTokenizer.tokenizeToStrings("ETHYLHEXYL\nTRIAZONE")
        #expect(ethyl.count == 1, "折行不得切成兩 Token：\(ethyl)")
        #expect(ethyl[0].uppercased().replacingOccurrences(of: " ", with: "").contains("ETHYLHEXYLTRIAZONE")
            || ethyl[0].uppercased().contains("ETHYLHEXYL TRI"))

        let di = IngredientTokenizer.tokenizeToStrings("DIPROPYLENE\nGLYCOL")
        #expect(di.count == 1, "DIPROPYLENE GLYCOL 應為一筆：\(di)")
        #expect(di[0].uppercased().contains("DIPROPYLENE"))
        #expect(di[0].uppercased().contains("GLYCOL"))

        let rosa = IngredientTokenizer.tokenizeToStrings("ROSA\nROXBURGHII FRUIT EXTRACT")
        #expect(rosa.count == 1, "植萃折行應保持一筆：\(rosa)")
        #expect(rosa[0].uppercased().contains("ROSA"))
        #expect(rosa[0].uppercased().contains("ROXBURGHII"))
        #expect(!rosa.contains { $0.uppercased().trimmingCharacters(in: .whitespaces) == "ROSA" && !$0.uppercased().contains("ROXBURGHII") })
    }

    @Test func tokenizer_commaThenNewline_stillSplitsTwoIngredients() {
        let tokens = IngredientTokenizer.tokenizeToStrings("GLYCERIN,\nNIACINAMIDE")
        #expect(tokens.count == 2, "行尾逗號仍須切分：\(tokens)")
        #expect(tokens[0].uppercased().contains("GLYCERIN"))
        #expect(tokens[1].uppercased().contains("NIACINAMIDE"))
    }

    @Test func tokenizer_cjkThenLatin_newlineStillSplits() {
        let tokens = IngredientTokenizer.tokenizeToStrings("溫和配方適合每日使用\nWater, Glycerin")
        #expect(tokens.contains { $0.uppercased() == "WATER" || $0.uppercased().hasPrefix("WATER") })
        #expect(!tokens.contains { $0.contains("溫和") && $0.uppercased().contains("WATER") })
    }

    // MARK: - 第二階段：IngredientResolver

    @Test func resolver_stepwiseFallback_andKeepsUnknownTokens() {
        ensureDatabase()

        // Step 1 精準查表
        #expect(IngredientResolver.resolveToken("Glycerin") != nil)
        // Step 2 括號拆解（括號外 → 括號內）
        #expect(IngredientResolver.resolveToken("Water (Aqua/Eau)")?.chineseName.contains("水") == true)
        #expect(IngredientResolver.resolveToken("Cocos Nucifera (Coconut) Oil") != nil)
        // Step 3 植萃後綴展開
        #expect(IngredientResolver.resolveToken("Camellia Oleifera Leaf Ext.") != nil)
        // Step 4 模糊沙盒（Butylene Glycol 安心度 1）
        #expect(
            IngredientResolver.resolveToken("Bitylene Glycol")?.englishName
                .uppercased()
                .contains("BUTYLENE") == true
        )

        // 查無資料：像 INCI 的長拉丁名保留為未收錄；無母音亂碼降為雜訊。
        let entries = IngredientResolver.resolve("Water, Ziziphoid Marmelosa Leaf Hydrosol, Glycerin")
        #expect(entries.map(\.index) == Array(0..<entries.count))
        let displayable = entries.filter { !$0.isNoise }
        #expect(displayable.count == 3)
        #expect(displayable[1].isUnknown)
        #expect(displayable[1].rawToken.uppercased().contains("ZIZIPHOID"))
        #expect(displayable[0].databaseItem != nil)
        #expect(displayable[2].databaseItem != nil)

        let garbage = IngredientResolver.resolve("Water, Zzzqqx Wwvvbb Yyxxzz, Glycerin")
        #expect(garbage.contains { $0.isNoise && $0.rawToken.uppercased().contains("ZZZQQX") })
        #expect(garbage.filter { !$0.isNoise }.allSatisfy { $0.databaseItem != nil })
    }

    @Test func resolver_wrappedINCI_stitchesToSingleMatch() {
        ensureDatabase()

        func displayNames(_ raw: String) -> [String] {
            IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        }

        let ethyl = displayNames("ETHYLHEXYL\nTRIAZONE")
        #expect(ethyl.count == 1, "應合成一筆：\(ethyl)")
        #expect(ethyl[0].uppercased().contains("ETHYLHEXYL"))
        #expect(ethyl[0].uppercased().contains("TRIAZONE"))

        let splitByComma = displayNames("WATER, ETHYLHEXYL, TRIAZONE, GLYCERIN")
        let splitJoined = splitByComma.joined(separator: " | ").uppercased()
        #expect(splitJoined.contains("ETHYLHEXYL"))
        #expect(splitJoined.contains("TRIAZONE") || splitJoined.contains("ETHYLHEXYL TRIAZONE"))
        #expect(!splitByComma.contains { $0.uppercased().trimmingCharacters(in: .whitespaces) == "TRIAZONE" })
        #expect(!splitByComma.contains { $0.uppercased().trimmingCharacters(in: .whitespaces) == "ETHYLHEXYL" })

        let hyphenated = displayNames("WATER, ETHYLHEXYL-, TRIAZONE, GLYCERIN")
        #expect(!hyphenated.contains { $0.uppercased().trimmingCharacters(in: .whitespaces) == "TRIAZONE" })

        let di = displayNames("DIPROPYLENE\nGLYCOL")
        #expect(di.count == 1, "應合成一筆：\(di)")
        #expect(di[0].uppercased().contains("DIPROPYLENE"))
        #expect(di[0].uppercased().contains("GLYCOL"))

        let rosa = IngredientResolver.resolve("ROSA\nROXBURGHII FRUIT EXTRACT").filter { !$0.isNoise }
        let rosaNames = rosa.map(\.displayName)
        #expect(rosaNames.count == 1, "植萃應為一筆，不得讓 ROSA 落單：\(rosaNames)")
        #expect(!rosaNames.contains { $0.uppercased().trimmingCharacters(in: .whitespaces) == "ROSA" })
        if rosa[0].databaseItem != nil {
            #expect(rosa[0].displayName.uppercased().contains("ROSA"))
            #expect(rosa[0].displayName.uppercased().contains("ROXBURGHII")
                || rosa[0].displayName.uppercased().contains("EXTRACT"))
        } else {
            #expect(rosa[0].isUnknown)
            #expect(rosa[0].rawToken.uppercased().contains("ROXBURGHII"))
        }
    }

    @Test func resolver_commaNewline_keepsTwoIngredients() {
        ensureDatabase()
        let names = IngredientResolver.resolve("GLYCERIN,\nNIACINAMIDE")
            .filter { !$0.isNoise }
            .map(\.displayName)
        #expect(names.count == 2, "行尾逗號仍為兩筆：\(names)")
        #expect(names[0].uppercased().contains("GLYCERIN"))
        #expect(names[1].uppercased().contains("NIACINAMIDE"))
    }

    @Test func displayList_dropsGarbageCyrillicBarcodeAndStubs() {
        ensureDatabase()
        let raw = """
        Water, 9IEAHZRUE, МОЛОКО abc, 0123456789012, GLYCOL, TRIAZONE, \
        Ziziphoid Marmelosa Leaf Hydrosol, Glycerin
        """
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()

        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("GLYCERIN") || joined.contains("GLYCEROL"))
        #expect(joined.contains("ZIZIPHOID"), "合法長拉丁名應保留未收錄：\(display)")
        #expect(!joined.contains("9IEAHZRUE"))
        #expect(!joined.contains("МОЛОКО") && !display.contains { $0.contains("МОЛОКО") })
        #expect(!joined.contains("0123456789012"))
        #expect(!display.contains { $0.uppercased() == "GLYCOL" })
        #expect(!display.contains { $0.uppercased() == "TRIAZONE" })
        #expect(display.count == 3, "UI 筆數應等於顯示項：\(display)")
    }

    @Test func footer_companyAndAdminSuffixTokens_areDroppedAfterLastIngredient() {
        ensureDatabase()
        let raw = """
        全成分 WATER, GLYCERIN, SQUALANE, TOCOPHEROL, \
        ACME CORPORATION, SAMPLE-RO, SAMPLE-SI, SAMPLE-DO
        """
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(joined.contains("TOCOPHEROL") || joined.contains("SQUALANE"))
        #expect(!joined.contains("ACME"))
        #expect(!joined.contains("CORPORATION"))
        #expect(!joined.contains("SAMPLE-RO"))
        #expect(!joined.contains("SAMPLE-SI"))
        #expect(!joined.contains("SAMPLE-DO"))
        #expect(!display.contains { $0.uppercased().contains("CORPORATION") })
    }

    @Test func adjacentOCRFragment_ofMatchedNeighbor_isDropped() {
        ensureDatabase()
        let raw = "CAMELLIA SINE, Camellia Sinensis Leaf Extract, Glycerin"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(joined.contains("CAMELLIA"))
        #expect(joined.contains("EXTRACT") || joined.contains("SINENSIS"))
        #expect(!display.contains { $0.uppercased().replacingOccurrences(of: " ", with: "").contains("CAMELLIASINE") && !$0.uppercased().contains("SINENSIS") })
        #expect(display.filter { $0.uppercased().contains("CAMELLIA") }.count == 1, "半截碎片不得另列一筆：\(display)")
    }

    @Test func unregisteredFirstIngredient_afterHeader_isKeptAsUnknown() {
        ensureDatabase()
        let raw = "全成分 UNREGISTERED LONG POLYMER NAME, Squalane, Glycerin, Water"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        #expect(
            display.contains { $0.uppercased().contains("UNREGISTERED") && $0.uppercased().contains("POLYMER") },
            "字典尚未收錄的第一項不得當行銷刪掉：\(display)"
        )
        #expect(display.contains { $0.uppercased().contains("SQUALANE") })
        #expect(display.first?.uppercased().contains("UNREGISTERED") == true)
    }

    @Test func titledList_dropsRetailProductName_keepsHydrogenatedPolyisobutene() {
        ensureDatabase()
        let raw = "ACME LIP GLOWY BALM BERRY 用途：保濕 全成分 HYDROGENATED POLYISOBUTENE, Squalane, Glycerin"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(IngredientParser.hasIngredientListTitleAnchor(raw))
        #expect(!joined.contains("ACME"), "標題前品名不得進清單：\(display)")
        #expect(!joined.contains("GLOWY") && !joined.contains("BALM") && !joined.contains("BERRY"))
        #expect(
            joined.contains("POLYISOBUTENE"),
            "HYDROGENATED POLYISOBUTENE 必須在清單（命中或未收錄）：\(display)"
        )
        #expect(display.first?.uppercased().contains("POLYISOBUTENE") == true)
        #expect(display.contains { $0.uppercased().contains("SQUALANE") })
    }

    @Test func untitledList_dropsRetailProductName_keepsHydrogenatedPolyisobutene() {
        ensureDatabase()
        let raw = "ACME LIP GLOWY BALM BERRY, HYDROGENATED POLYISOBUTENE, Squalane, Glycerin"
        #expect(!IngredientParser.hasIngredientListTitleAnchor(raw))
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(!joined.contains("ACME") && !joined.contains("BALM") && !joined.contains("BERRY"))
        #expect(joined.contains("POLYISOBUTENE"), "無標題時聚合物仍須留下：\(display)")
        #expect(display.first?.uppercased().contains("POLYISOBUTENE") == true)
        #expect(display.contains { $0.uppercased().contains("SQUALANE") })
    }

    @Test func chemicalNames_areNotDroppedAsProductTitles() {
        ensureDatabase()
        let cases = [
            "Japan Wax, Squalane, Glycerin",
            "Camellia Sinensis Leaf Extract, Glycerin, Water",
            "Sucrose Tetrastearate Triacetate, Squalane, Glycerin"
        ]
        for raw in cases {
            let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
            let joined = display.joined(separator: " | ").uppercased()
            if raw.uppercased().contains("JAPAN WAX") {
                #expect(joined.contains("JAPAN") && joined.contains("WAX"), "Japan Wax 不得當品名刪掉：\(display)")
            } else if raw.uppercased().contains("CAMELLIA") {
                #expect(joined.contains("CAMELLIA"), "Camellia Sinensis Leaf Extract 不得當品名刪掉：\(display)")
            } else {
                #expect(
                    joined.contains("SUCROSE") && joined.contains("TETRASTEARATE"),
                    "Sucrose Tetrastearate Triacetate 不得當品名刪掉：\(display)"
                )
            }
        }
    }

    @Test func addressMorphology_doesNotKillJapanWaxChinaClayOrLaneINCI() {
        ensureDatabase()
        let raw = "WATER, GLYCERIN, JAPAN WAX, CHINA CLAY, SAMPLE LANE EXTRACT, SQUALANE"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(joined.contains("JAPAN") && joined.contains("WAX"), "Japan Wax 不得被地址規則刪掉：\(display)")
        #expect(joined.contains("CHINA") && joined.contains("CLAY"), "China Clay 不得被地址規則刪掉：\(display)")
        #expect(joined.contains("LANE"), "含 Lane 的 INCI 不得被地址規則刪掉：\(display)")
        #expect(joined.contains("SQUALANE"))
    }

    // MARK: - 起點偵測（資料庫命中驅動）

    /// 完全沒有標題關鍵字時，起點由「第一個精準命中且鄰近確實有成分」的 Token 決定。
    @Test func dataDrivenStart_dropsMarketingWithoutAnyHeader() {
        ensureDatabase()

        let raw = """
        ULTRA GLOW SERUM
        深層保濕、質地清爽、溫和不刺激
        Water, Glycerin, Niacinamide, Butylene Glycol, Phenoxyethanol
        """

        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }
        let names = display.map(\.displayName)
        let joined = names.joined(separator: " | ").uppercased()

        #expect(names.count == 5, "行銷文案不應進入清單：\(names)")
        #expect(names.first?.uppercased().contains("WATER") == true, "首項應為 Water：\(joined)")
        #expect(!joined.contains("SERUM"))
        #expect(!joined.contains("深層保濕"))
        #expect(!joined.contains("質地清爽"))
    }

    /// 密度防呆：行銷文案順口提到的單一成分不得被當成起點。
    @Test func dataDrivenStart_ignoresIsolatedIngredientMentionInMarketing() {
        ensureDatabase()

        let raw = "保濕成分、Glycerin、植物萃取、溫和配方、無添加香料"
            + "\nWater, Niacinamide, Panthenol, Allantoin, Phenoxyethanol"

        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }
        let names = display.map(\.displayName)

        #expect(names.count == 5, "起點應落在真正的成分表，而非行銷段的 Glycerin：\(names)")
        #expect(names.first?.uppercased().contains("WATER") == true)
        #expect(!names.joined(separator: " | ").contains("植物萃取"))

        // 行銷段的 Glycerin 被丟棄，最終清單不應出現重複的 Glycerin。
        #expect(!names.contains { $0.uppercased() == "GLYCERIN" })
    }

    /// 起點之前只丟棄「非精準命中」的 Token，夾在真成分間的 OCR 錯字不得害整段被砍掉。
    @Test func dataDrivenStart_keepsFirstIngredientDespiteFollowingOCRTypos() {
        ensureDatabase()

        let tokens = IngredientTokenizer.tokenize(
            """
            PAULA'S CHOICE 2% BHA Liquid
            Water (Aqua), Methylpropanedi, Manufactured for Paula's Choice
            Bitylene Glycol, Salicylic Acid, Polysorbate 20
            """
        )
        let start = IngredientResolver.firstHighConfidenceStart(in: tokens)

        #expect(start == 1, "起點應落在 Water 而非更後面：\(tokens.map(\.text))")
        #expect(tokens[start].text.uppercased().hasPrefix("WATER"))
    }

    /// 迴圈不得提早放棄：第 0 個 Token 就是精準命中但密度不足時，
    /// 必須繼續往下找下一個精準命中，而不是直接回傳 0。
    @Test func dataDrivenStart_continuesScanningAfterDensityCheckFails() {
        ensureDatabase()

        // 兩個孤立精準命中排在真正的成分表之前：若迴圈在第一次密度失敗就 return 0，
        // 後面的 Water 清單會整段被當成行銷雜訊留下來。
        let tokens = IngredientTokenizer.tokenize(
            "Glycerin、植物萃取、溫和配方、質地清爽、Niacinamide、無添加香料、不黏膩"
                + "\nWater, Butylene Glycol, Panthenol, Allantoin, Phenoxyethanol"
        )
        let start = IngredientResolver.firstHighConfidenceStart(in: tokens)
        let texts = tokens.map(\.text)

        #expect(start > 0, "開頭孤立的 Glycerin 不得讓掃描提早放棄：\(texts)")
        #expect(
            tokens[start].text.uppercased().hasPrefix("WATER"),
            "起點應落在真正的成分表，而非第一個精準命中：index \(start) = \(tokens[start].text)；tokens = \(texts)"
        )

        // Niacinamide 是第二個孤立精準命中，同樣必須被跳過。
        if let niacinamide = texts.firstIndex(where: { $0.uppercased().contains("NIACINAMIDE") }),
           let water = texts.firstIndex(where: { $0.uppercased().hasPrefix("WATER") }) {
            #expect(niacinamide < water)
            #expect(start != niacinamide, "第二個孤立命中也不得成為起點：\(texts)")
        }
    }

    /// 中文行銷句以句號結尾時，首項成分不得被黏在句尾一起丟掉。
    @Test func dataDrivenStart_chineseSentenceGluedToFirstIngredient() {
        ensureDatabase()

        let raw = "溫和配方適合每日使用。Water, Glycerin, Niacinamide, Panthenol"

        let tokens = IngredientTokenizer.tokenize(raw)
        #expect(tokens.count == 5, "句號應切開行銷句與首項成分：\(tokens.map(\.text))")

        let names = IngredientResolver.resolve(raw)
            .filter { !$0.isNoise }
            .map(\.displayName)
        #expect(names.count == 4, "行銷句不應留下，成分不應少一項：\(names)")
        #expect(names.first?.uppercased().contains("WATER") == true, "Water 必須保住：\(names)")
    }

    /// 找不到符合密度條件的起點時完全不裁，寧可多留也不砍掉真成分。
    @Test func dataDrivenStart_fallsBackToZeroWhenNoDenseHit() {
        ensureDatabase()

        let tokens = IngredientTokenizer.tokenize("Zzzqqx Wwvvbb, Yyxxzz Vvuutt, Qqppmm Nnllkk")
        #expect(IngredientResolver.firstHighConfidenceStart(in: tokens) == 0)
    }

    @Test func resolver_fuzzySandbox_neverRescuesHighRiskIngredients() {
        ensureDatabase()

        // 資料庫層不變式：安心度 ≥ 7 或禁用 → 強制 100% 精準，永遠不進模糊沙盒。
        for item in IngredientDatabaseManager.shared.allIngredients()
        where (item.safetyScore ?? 0) >= 7 {
            #expect(item.requiresExactMatchOnly, "高風險應強制精準：\(item.englishName)")
            #expect(
                !IngredientDatabaseManager.isFuzzySandboxEligible(item),
                "高風險不得進入模糊沙盒：\(item.englishName)"
            )
        }

        // 端到端：禁用成分打錯一個字元也不得被救回。
        #expect(IngredientMatcher.matchToken("Chloroacetamide") != nil)
        #expect(IngredientMatcher.matchToken("Chloroacetamidf") == nil)

        // 短詞不進沙盒（長度 < 6）。
        #expect(IngredientDatabaseManager.shared.sandboxFuzzyMatch(normalizedKey: "WATE") == nil)
    }

    @Test func resolver_localLevenshtein_rescuesOCRTyposAndKeepsUnknownOnMiss() {
        ensureDatabase()

        // 少字母／鄰近錯字 → 校正為標準 INCI，並帶上中文名與功效（不再是灰色未收錄）。
        let cases: [(typo: String, needle: String)] = [
            ("Glycern", "GLYCERIN"),
            ("Niacinamid", "NIACINAMIDE"),
            ("Dimethcone", "DIMETHICONE"),
            ("Phenoxyethanl", "PHENOXYETHANOL"),
            ("Methylpropanedi", "METHYLPROPANEDIOL"),
            ("Bitylene Glycol", "BUTYLENE"),
        ]
        for sample in cases {
            let item = IngredientResolver.resolveToken(sample.typo)
            #expect(item != nil, "應救援：\(sample.typo)")
            #expect(
                item?.englishName.uppercased().contains(sample.needle) == true,
                "\(sample.typo) 應校正為 \(sample.needle)，實際 \(item?.englishName ?? "nil")"
            )
            #expect(!(item?.chineseName ?? "").isEmpty, "救援後應有中文名：\(sample.typo)")
            #expect(!(item?.function ?? "").isEmpty, "救援後應有功效標籤：\(sample.typo)")
        }

        // 進入清單後顯示的是標準名，不是 OCR 錯字。
        let entries = IngredientResolver.resolve("Water, Glycern, Niacinamid")
            .filter { !$0.isNoise }
        let names = entries.map(\.displayName).joined(separator: " | ").uppercased()
        #expect(names.contains("GLYCERIN"))
        #expect(names.contains("NIACINAMIDE"))
        #expect(!names.contains("GLYCERN"))
        #expect(!names.contains("NIACINAMID"))
        #expect(entries.filter { $0.databaseItem != nil }.count == 3)

        // 候選池沒有達標者 → 像 INCI 的長名維持灰色未收錄；亂碼不進清單。
        let unknown = IngredientResolver.resolve("Water, Ziziphoid Marmelosa Leaf Hydrosol")
        #expect(unknown.contains { $0.isUnknown && $0.displayName.uppercased().contains("ZIZIPHOID") })
        let garbage = IngredientResolver.resolve("Water, Zzzqqx Wwvvbb Yyxxzz")
        #expect(garbage.filter { !$0.isNoise }.allSatisfy { $0.databaseItem != nil })

        // 絕對雜訊不得被救成成分。
        #expect(IngredientResolver.resolveToken("www.example.com") == nil)
        #expect(IngredientResolver.resolveToken("50ml") == nil)

        // 短詞與高風險仍不開放模糊。
        #expect(IngredientResolver.resolveToken("Urra") == nil)
        #expect(IngredientMatcher.matchToken("Chloroacetamidf") == nil)
    }

    @Test func localFuzzy_candidateFilter_neverScansBeyondLengthWindow() {
        #expect(IngredientDatabaseManager.localFuzzyMaxDistance(forLength: 4) == 0)
        #expect(IngredientDatabaseManager.localFuzzyMaxDistance(forLength: 6) == 1)
        #expect(IngredientDatabaseManager.localFuzzyMaxDistance(forLength: 10) == 2)
        #expect(IngredientDatabaseManager.localFuzzyMaxDistance(forLength: 16) == 3)
        #expect(IngredientDatabaseManager.localFuzzyLengthWindow == 3)

        #expect(IngredientDatabaseManager.boundedLevenshteinDistance("GLYCERN", "GLYCERIN", maxDistance: 1) == 1)
        #expect(IngredientDatabaseManager.boundedLevenshteinDistance("GLYCERN", "GLYCERIN", maxDistance: 0) == nil)
        #expect(IngredientDatabaseManager.boundedLevenshteinDistance("ABC", "XYZXYZ", maxDistance: 2) == nil)
    }

    // MARK: - 絕對雜訊過濾（第三道防線）

    @Test func absoluteNoise_rejectsUrlsUnitsAddressesAndMarketingSentences() {
        // 網址與電子郵件（含 OCR 把點吃掉的形式）
        #expect(IngredientParser.isWebNoiseToken("www.examplebeauty.com"))
        #expect(IngredientParser.isWebNoiseToken("https://example.com/faq"))
        #expect(IngredientParser.isWebNoiseToken("service@examplebeauty.com"))
        #expect(IngredientParser.isWebNoiseToken("PaulasChoice com"))
        #expect(IngredientParser.isWebNoiseToken("www paulaschoice com"))
        #expect(!IngredientParser.isWebNoiseToken("ALCOHOL DENAT.ORGANIC ALOE"))
        #expect(!IngredientParser.isWebNoiseToken("Camellia Oleifera Leaf Extract"))
        #expect(!IngredientParser.isWebNoiseToken("Silica Dimethyl Silylate"))

        // 容量與物理單位
        #expect(IngredientParser.isMeasurementNoiseToken("50ml"))
        #expect(IngredientParser.isMeasurementNoiseToken("1.7 fl. oz."))
        #expect(IngredientParser.isMeasurementNoiseToken("30 g"))
        #expect(!IngredientParser.isMeasurementNoiseToken("Polysorbate 20"))
        #expect(!IngredientParser.isMeasurementNoiseToken("C12-15 Alkyl Benzoate"))
        #expect(!IngredientParser.isMeasurementNoiseToken("PEG-40 Hydrogenated Castor Oil"))

        // 地址、國家聲明與公司據點城市
        #expect(IngredientParser.isGeographicNoiseToken("U.S. and Canada"))
        #expect(IngredientParser.isGeographicNoiseToken("(U S. and Canada)"), "括號包住的國別聲明")
        #expect(IngredientParser.isGeographicNoiseToken("UK"))
        #expect(IngredientParser.isGeographicNoiseToken("12 High Street"))
        #expect(IngredientParser.isGeographicNoiseToken("London"))
        #expect(IngredientParser.isGeographicNoiseToken("Amersfoort. NL."))
        #expect(IngredientParser.isGeographicNoiseToken("New York"))
        #expect(IngredientParser.isGeographicNoiseToken("4C. Seattle"))

        // 含地名但另有實質內容的合法成分不得誤殺
        #expect(!IngredientParser.isGeographicNoiseToken("China Clay"))
        #expect(!IngredientParser.isGeographicNoiseToken("Japan Wax"))
        #expect(!IngredientParser.isGeographicNoiseToken("Paris Polyphylla Rhizome Extract"))
        #expect(!IngredientParser.isGeographicNoiseToken("Avena Sativa Kernel Flour"))
        #expect(!IngredientParser.isGeographicNoiseToken("Water (Aqua/Eau)"))
        #expect(!IngredientParser.isGeographicNoiseToken("Ubiquinone"))

        // 公司法律後綴／行政道路後綴：形態規則，不得誤殺合法 INCI。
        #expect(IngredientParser.isCorporateLegalNameToken("ACME CORPORATION"))
        #expect(IngredientParser.isCorporateLegalNameToken("SAMPLE CO., LTD"))
        #expect(IngredientParser.isCorporateLegalNameToken("SAMPLE CO LTD"))
        #expect(IngredientParser.isCorporateLegalNameToken("SAMPLE PTE LTD"))
        #expect(IngredientParser.isCorporateLegalNameToken("SAMPLE INC."))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-SI"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-DO"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-RO"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-GU"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-GUN"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-DONG"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-CHO"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-MACHI"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-KU"))
        #expect(IngredientParser.isAdminRoadSuffixToken("SAMPLE-RI"))
        #expect(!IngredientParser.isAdminRoadSuffixToken("Japan Wax"))
        #expect(!IngredientParser.isAdminRoadSuffixToken("China Clay"))
        #expect(!IngredientParser.isAdminRoadSuffixToken("Methylsilanol"))
        #expect(!IngredientParser.isAdminRoadSuffixToken("Sample Lane Extract"))
        #expect(!IngredientParser.isGeographicNoiseToken("Sample Lane Extract"))
        #expect(!IngredientParser.isCorporateLegalNameToken("Acrylates Copolymer"))
        #expect(!IngredientParser.isCorporateLegalNameToken("Sample Lane Extract"))
        #expect(!IngredientParser.isGeographicNoiseToken("Methylsilanol"))
        #expect(!IngredientParser.hasAddressHouseNumber("Polysorbate 20"))
        #expect(!IngredientParser.hasAddressHouseNumber("C12-15 Alkyl Benzoate"))
        #expect(!IngredientParser.hasAddressHouseNumber("PEG-40 Hydrogenated Castor Oil"))

        #expect(IngredientParser.looksLikeChemicalName("Hydrogenated Polyisobutene"))
        #expect(IngredientParser.hasTwoOrMoreLongLatinWords("Hydrogenated Polyisobutene"))
        #expect(IngredientParser.looksLikeChemicalName("Japan Wax"))
        #expect(IngredientParser.looksLikeChemicalName("Camellia Sinensis Leaf Extract"))
        #expect(IngredientParser.looksLikeChemicalName("Sucrose Tetrastearate Triacetate"))
        #expect(IngredientParser.looksLikeChemicalName("UNREGISTERED LONG POLYMER NAME"))
        #expect(!IngredientParser.looksLikeChemicalName("ACME LIP GLOWY BALM BERRY"))
        #expect(IngredientParser.isRetailProductNameToken("ACME LIP GLOWY BALM BERRY"))
        #expect(IngredientParser.isRetailProductNameToken("ULTRA GLOW SERUM"))
        #expect(IngredientParser.isRetailProductNameToken("SAMPLE FACE GLOW OIL"))
        #expect(IngredientParser.isPackagingMarketingToken("EERPRO-COLLAGEN"))
        #expect(IngredientParser.isPackagingMarketingToken("PRO-COLLAGEN MULTI-PEPTIDE"))
        #expect(IngredientParser.isPackagingMarketingToken("DISTURIZEIPM"))
        #expect(IngredientParser.isPackagingMarketingToken("MOISTURIZE PM"))
        #expect(!IngredientParser.isPackagingMarketingToken("Hydrolyzed Collagen"))
        #expect(!IngredientParser.isRetailProductNameToken("Japan Wax"))
        #expect(!IngredientParser.isRetailProductNameToken("Camellia Sinensis Leaf Extract"))
        #expect(!IngredientParser.isRetailProductNameToken("Sucrose Tetrastearate Triacetate"))
        #expect(!IngredientParser.isRetailProductNameToken("Hydrogenated Polyisobutene"))
        #expect(!IngredientParser.isRetailProductNameToken("Cocos Nucifera Oil"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("EERPRO-COLLA"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("DISTURIZEIPM"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("MSTURILE A PF"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("REESABEIN"))
        #expect(IngredientParser.looksLikeStandaloneINCIWord("Allantoin"))
        #expect(IngredientParser.looksLikeStandaloneINCIWord("ECTOIN"))
        #expect(!IngredientParser.looksLikeStandaloneINCIWord("REESABEIN"))
        #expect(IngredientParser.looksLikeChemicalName("Cocos Nucifera Oil"))
        #expect(!IngredientParser.looksLikeChemicalName("SAMPLE FACE GLOW OIL"))

        // 整句中文行銷文案（> 40 字元且過半非拉丁字母）
        let marketing = "給乾燥肌的高效保濕乳霜質地清爽不黏膩適合每日早晚使用建議搭配化妝水一起使用效果更佳"
        #expect(marketing.count > 40)
        #expect(IngredientParser.isVerboseNonLatinToken(marketing))
        #expect(!IngredientParser.isVerboseNonLatinToken("聚二甲基矽氧烷"))
        #expect(!IngredientParser.isVerboseNonLatinToken("Camellia Oleifera (Green Tea) Leaf Extract"))
    }

    /// 端到端：整罐包裝的 OCR 全文只應留下成分本身，不得因行銷／地址／網址而暴增項數。
    @Test func fullLabel_noiseDoesNotInflateIngredientCount() {
        ensureDatabase()
        // 刻意混用「有換行」與「黏成一段」兩種 OCR 型態。
        let raw = """
        NEW! Ultra Hydrating Daily Moisturizer
        給乾燥肌的高效保濕乳霜，質地清爽不黏膩，適合每日早晚使用，建議搭配化妝水效果更佳。全成分WATER(AQUA/EAU), \
        GLYCERIN, DIMETHICONE, NIACINAMIDE, BUTYLENE GLYCOL,
        PHENOXYETHANOL, TOCOPHEROL, DISODIUM EDTA注意事項：本產品僅供外用，避免接觸眼睛，如有不適請停止使用。
        容量 50ml / 1.7 fl. oz.
        Distributed by Example Beauty Ltd., 12 High Street, London, UK
        PaulasChoice com | service@examplebeauty.com
        Made in (U S. and Canada)
        """

        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }
        let names = display.map(\.displayName)
        let joined = names.joined(separator: " | ").uppercased()

        #expect(names.count == 8, "外包裝雜訊不應撐大清單：\(names.count) 項 → \(joined)")
        #expect(display.filter { $0.databaseItem != nil }.count >= 7, "字典命中不足：\(joined)")
        #expect(names.first?.uppercased().hasPrefix("WATER") == true, "首項應為 WATER：\(joined)")

        for noise in [
            "MOISTURIZER", "保濕乳霜", "注意事項", "50ML", "FL. OZ",
            "LONDON", "PAULASCHOICE", "CANADA", "DISTRIBUTED"
        ] {
            #expect(!joined.contains(noise), "雜訊未濾除：\(noise) → \(joined)")
        }
    }

    @Test func database_expandedCoverage_withProductMustIncludes() {
        ensureDatabase()
        let count = IngredientDatabaseManager.shared.allIngredients().count
        #expect(count >= 3500, "本地庫應 ≥3500，實際 \(count)")

        let must: [(String, String)] = [
            ("CANNABIS SATIVA SEED OIL", "大麻籽油"),
            ("REBAUDIOSIDE A", "甜菊糖苷"),
            ("DIETHYLAMINO HYDROXYBENZOYL HEXYL BENZOATE", "二乙氨羥苯甲醯基苯甲酸己酯"),
            ("ARACHIDYL ALCOHOL", "花生醇"),
            ("LIMONENE", "香精"),
            ("LINALOOL", "香精"),
            ("FRAGRANCE", "香精"),
            ("FLAVOR", "香精"),
            ("HDI/TRIMETHYLOL HEXYLLACTONE CROSSPOLYMER", "交聯聚合物"),
            ("PEG/PPG-14/7 DIMETHYL ETHER", "二甲醚"),
            ("DISTEARYLDIMONIUM CHLORIDE", "二硬脂基"),
            ("PRUNUS SPECIOSA LEAF EXTRACT", "大島櫻"),
            ("ROSA CANINA FRUIT EXTRACT", "玫瑰果"),
            ("EUPHORBIA CERIFERA CERA", "小燭樹蠟"),
        ]
        for (en, zh) in must {
            let item = resolved(en)
            #expect(item != nil, "必備應命中：\(en)")
            #expect(item?.chineseName.contains(zh) == true || item?.chineseName == zh, "中文應對：\(en) → \(zh)，實際 \(item?.chineseName ?? "nil")")
        }
    }

    /// CosIng 歐盟植萃以精準 INCI 命中；屬名／部位／通名不得單獨撞庫。
    @Test func database_cosingEuBotanicalsExactMatchWithoutShortTokenHits() {
        ensureDatabase()
        let count = IngredientDatabaseManager.shared.allIngredients().count
        #expect(count >= 8000, "歐盟 CosIng 擴充後應遠高於原 3865，實際 \(count)")

        let botanicals = [
            "HIPPOPHAE RHAMNOIDES FRUIT EXTRACT",
            "CAMELLIA JAPONICA LEAF EXTRACT",
            "CENTELLA ASIATICA LEAF EXTRACT",
            "ROSA DAMASCENA FLOWER EXTRACT",
            "VITIS VINIFERA SEED EXTRACT",
            "GINKGO BILOBA LEAF EXTRACT",
            "PANAX GINSENG ROOT EXTRACT",
            "CUCUMIS SATIVUS FRUIT EXTRACT",
            "PUNICA GRANATUM FRUIT EXTRACT",
            "CAMELLIA SINENSIS LEAF WATER",
        ]
        for name in botanicals {
            #expect(resolved(name) != nil, "歐盟植萃應精準命中：\(name)")
        }
        #expect(resolved("PANAX GINSENG ROOT EXTRACT")?.chineseName.contains("人參") == true)
        #expect(resolved("GINKGO BILOBA LEAF EXTRACT")?.chineseName.contains("銀杏") == true)
        #expect(resolved("CAMELLIA SINENSIS LEAF EXTRACT")?.chineseName.contains("茶") == true)
        #expect(resolved("VITIS VINIFERA SEED EXTRACT")?.chineseName.contains("葡萄") == true)
        #expect(resolved("CUCUMIS SATIVUS FRUIT EXTRACT")?.chineseName.contains("黃瓜") == true)

        for token in ["Rosa", "Leaf", "Extract", "Oil", "Fruit", "Flower"] {
            let hit = IngredientMatcher.matchToken(token)
            #expect(hit == nil, "短詞不得單獨命中植萃：\(token) → \(hit?.englishName ?? "nil")")
        }
        #expect(IngredientMatcher.matchToken("Water") != nil, "Water 仍須精準命中")
    }

    /// 末項已是字典命中時，表尾地址過濾不得組成反轉 Range。
    @Test func resolve_doesNotCrashWhenListEndsOnMatchedIngredient() {
        ensureDatabase()
        let entries = IngredientResolver.resolve("Water, Glycerin, Phenoxyethanol")
        let names = entries.filter { !$0.isNoise }.map(\.displayName)
        #expect(!names.isEmpty)
        #expect(names.contains { $0.localizedCaseInsensitiveContains("Water") })
        #expect(names.contains { $0.localizedCaseInsensitiveContains("Phenoxyethanol") })
    }

    @Test func leadingOCRJunk_doesNotHideFirstHydrogenatedPolymer() {
        ensureDatabase()
        let raw = "全成分 EFUS HYDROGENATED POLYISOBUTENE, Squalane, Glycerin"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(!joined.contains("EFUS"), "OCR 短前綴不得留在清單：\(display)")
        #expect(joined.contains("POLYISOBUTENE") || joined.contains("HYDROGENATED"))
        #expect(display.first?.uppercased().contains("POLYISOBUTENE") == true
            || display.first?.uppercased().contains("HYDROGENATED") == true)
        let first = IngredientResolver.resolve(raw).filter { !$0.isNoise }.first
        #expect(first?.databaseItem != nil, "去掉短前綴後應命中字典：\(display)")
    }

    @Test func trailingNonChemicalUnknowns_afterLastMatch_areDropped() {
        ensureDatabase()
        let raw = "Water, Glycerin, Phenoxyethanol, FUER AMOREPACI, GETe 5"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(joined.contains("PHENOXYETHANOL"))
        #expect(!joined.contains("AMOREPACI"), "表尾公司殘句不得進清單：\(display)")
        #expect(!joined.contains("GETE"), "表尾亂碼不得進清單：\(display)")
    }

    @Test func barcodeLetterRun_afterLastIngredient_isDropped() {
        ensureDatabase()
        #expect(!IngredientResolver.looksLikeIngredientName("SRUETBRRRUVBR"))
        #expect(!IngredientParser.looksLikeChemicalName("SRUETBRRRUVBR"))
        #expect(IngredientParser.looksLikeChemicalName("ETHYLHEXYLMETHOXYCINNAMATE"))

        let raw = "WATER, GLYCERIN, SOLUBLE COLLAGEN, SRUETBRRRUVBR"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(joined.contains("COLLAGEN") || joined.contains("GLYCERIN"))
        #expect(!joined.contains("SRUE"))
        #expect(!joined.contains("BRRR"))
        #expect(!display.contains { $0.uppercased().contains("SRUET") })
    }

    @Test func unmatchedGray_dropsPackagingButKeepsUnlistedBotanical() {
        ensureDatabase()
        let raw = """
        Powercell Skinmunity Serum 5ML
        用途：保濕
        全成分 WATER, GLYCERIN, Ziziphoid Marmelosa Leaf Hydrosol, ECTOIN,
        原產地：法國 FRANCE, 台灣萊雅, LD8906 3, 40X105
        """
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()

        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("GLYCERIN"))
        #expect(joined.contains("ZIZIPHOID"), "未入庫植萃應留在可能未辨識：\(display)")
        #expect(
            IngredientResolver.resolve("Water, Glycerin, Phenoxyethanol, UNREGISTERED CAMELLIA FOO LEAF EXTRACT")
                .filter { !$0.isNoise }
                .map(\.displayName)
                .joined(separator: " | ")
                .uppercased()
                .contains("EXTRACT"),
            "未入庫植萃應保留"
        )
        #expect(!joined.contains("POWERCELL"), "品名不得進灰區：\(display)")
        #expect(!joined.contains("SKINMUNITY"), "品名不得進灰區：\(display)")
        #expect(!joined.contains("SERUM"), "品名不得進灰區：\(display)")
        #expect(!joined.contains("FRANCE"), "國名不得進灰區：\(display)")
        #expect(!joined.contains("LD8906"), "批號不得進灰區：\(display)")
        #expect(!joined.contains("40X105"), "標籤編號不得進灰區：\(display)")
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("HELENA RUBINSTEIN"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("FRANCE"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("MIST"))
        #expect(!IngredientResolver.shouldKeepAsUnmatchedUnknown("BOOSTER"))
        #expect(IngredientResolver.shouldKeepAsUnmatchedUnknown("Ziziphoid Marmelosa Leaf Hydrosol"))
        #expect(joined.contains("ECTOIN") || joined.contains("依克多因"), "依克多因應命中字典：\(display)")
        #expect(
            IngredientResolver.resolve("Water, Glycerin, ECTOIN, Phenoxyethanol")
                .filter { !$0.isNoise }
                .contains { $0.databaseItem != nil && $0.displayName.uppercased().contains("ECTOIN") },
            "ECTOIN 應字典命中，不再進灰區"
        )
    }

    @Test func droppingLeadingJunk_doesNotStealRedLakeColorant() {
        ensureDatabase()
        let raw = "Water, Glycerin, RED 7 LAKE (CI 15850), Phenoxyethanol"
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(
            joined.contains("RED") || joined.contains("LAKE") || joined.contains("15850") || joined.contains("CI"),
            "著色劑不得被短前綴規則拆掉：\(display)"
        )
    }

    /// 日韓台標常用中圓點、全形括號、中間換行，沒有逗號。
    @Test func bulletSeparatedPaste_doesNotCollapseToOnlyWater() {
        ensureDatabase()
        let raw = """
        WATER（AQUA）•ALCOHOL• DIISOPROPYL
        SEBACATE • DIMETHICONE • GLYCERIN • PHENOXYETHANOL • CAMELLIA SINENSIS LEAF EXTRACT •
        """
        let display = IngredientResolver.resolve(raw).filter { !$0.isNoise }.map(\.displayName)
        let joined = display.joined(separator: " | ").uppercased()
        #expect(display.count >= 6, "中圓點清單不應只剩 Water：\(display)")
        #expect(joined.contains("WATER") || joined.contains("AQUA"))
        #expect(joined.contains("ALCOHOL"))
        #expect(joined.contains("SEBACATE") || joined.contains("DIISOPROPYL"))
        #expect(joined.contains("DIMETHICONE"))
        #expect(joined.contains("GLYCERIN"))
        #expect(joined.contains("PHENOXYETHANOL"))
        #expect(joined.contains("CAMELLIA") || joined.contains("EXTRACT"))
    }

    @Test func matcher_hitsPropyleneGlycol() {
        ensureDatabase()
        let hit = IngredientMatcher.matchToken("PROPYLENE GLYCOL")
        #expect(hit != nil, "丙二醇本尊應在字典內")
        #expect(hit?.englishName.caseInsensitiveCompare("Propylene Glycol") == .orderedSame)
        #expect(IngredientMatcher.matchToken("丙二醇")?.englishName.caseInsensitiveCompare("Propylene Glycol") == .orderedSame)
    }

    @Test func matcher_hitsCommonCuratedParentsAndAliases() {
        ensureDatabase()
        let cases: [(query: String, mustContain: String)] = [
            ("ECTOIN", "ECTOIN"),
            ("依克多因", "ECTOIN"),
            ("INULIN", "INULIN"),
            ("POLYISOBUTENE", "POLYISOBUTENE"),
            ("XYLITYLGLUCOSIDE", "XYLITYL"),
            ("PYRIDOXINE HCL", "PYRIDOXINE"),
            ("ETHYL ASCORBIC ACID", "ASCORBIC"),
            ("RETINALDEHYDE", "RETINAL"),
            ("SH-OLIGOPEPTIDE-1", "OLIGOPEPTIDE")
        ]
        for item in cases {
            let hit = IngredientMatcher.matchToken(item.query)
            #expect(hit != nil, "應命中：\(item.query)")
            #expect(
                hit?.englishName.uppercased().contains(item.mustContain) == true,
                "\(item.query) → \(hit?.englishName ?? "nil")"
            )
        }
    }

    @Test func suggest_exactINCIBeatsLongerPrefixDerivatives() {
        ensureDatabase()
        let hits = IngredientDatabaseManager.shared.suggest(matching: "PROPYLENE GLYCOL", limit: 8)
        #expect(!hits.isEmpty)
        #expect(
            hits.first?.englishName.caseInsensitiveCompare("Propylene Glycol") == .orderedSame,
            "搜尋本尊時不應被酯類衍生物擠掉：\(hits.map(\.englishName))"
        )
    }
}