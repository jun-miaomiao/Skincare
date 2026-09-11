import Foundation
import Testing
@testable import Skincare

struct ScanResultPresentationTests {

    @Test func payload_headlineCountIgnoresUnmatchedPlaceholders() {
        let water = IngredientItem(
            englishName: "Water",
            chineseName: "水",
            safetyRating: "1",
            function: "溶劑",
            aliases: nil
        )
        var payload = ScanResultPayload(
            imageData: nil,
            ingredients: ["Water", "OCRJUNKFRAGMENT", "Glycerin"],
            matchedAlerts: [],
            blockedTags: [],
            customBlockedIngredients: [],
            scannedAt: Date(),
            historyRecordID: nil,
            source: .cameraTab
        )
        payload.resolvedIngredients = [
            PersistedScannedIngredient(name: "Water", originalOrder: 1, isBlocked: false, databaseItem: water),
            PersistedScannedIngredient(name: "OCRJUNKFRAGMENT", originalOrder: 2, isBlocked: false, databaseItem: nil),
            PersistedScannedIngredient(
                name: "Glycerin",
                originalOrder: 3,
                isBlocked: false,
                databaseItem: IngredientItem(
                    englishName: "Glycerin",
                    chineseName: "甘油",
                    safetyRating: "1",
                    function: "保濕劑",
                    aliases: nil
                )
            )
        ]

        #expect(payload.identifiedIngredientCount == 2)
        #expect(payload.pendingUnmatchedCount == 1)
        #expect(payload.dictionaryHitNames == ["Water", "Glycerin"])
        #expect(payload.ingredients.count == 3)
    }

    @Test func payload_pendingCountIsZeroWithoutSnapshots() {
        let payload = ScanResultPayload(
            imageData: nil,
            ingredients: ["Water", "Glycerin"],
            matchedAlerts: [],
            blockedTags: [],
            customBlockedIngredients: [],
            scannedAt: Date()
        )
        #expect(payload.pendingUnmatchedCount == 0)
        #expect(payload.identifiedIngredientCount == 2)
    }

    @Test func payload_resolvedProductNamePrefersUserTitle() {
        var named = ScanResultPayload(
            imageData: nil,
            ingredients: ["Water"],
            matchedAlerts: [],
            blockedTags: [],
            customBlockedIngredients: [],
            scannedAt: Date(),
            productName: "寶拉 BHA"
        )
        #expect(named.resolvedProductName == "寶拉 BHA")

        named.productName = "   "
        #expect(named.resolvedProductName == ScanSummarySheet.defaultProductName())
    }

    @Test func pasteResult_showsSummaryWhenHitsAndNoAvoidList() {
        var payload = ScanResultPayload(
            imageData: nil,
            ingredients: ["Water"],
            matchedAlerts: [],
            blockedTags: [],
            customBlockedIngredients: [],
            scannedAt: Date()
        )
        payload.resolvedIngredients = [
            PersistedScannedIngredient(
                name: "Water",
                originalOrder: 1,
                isBlocked: false,
                databaseItem: IngredientItem(
                    englishName: "Water",
                    chineseName: "水",
                    safetyRating: "1",
                    function: "溶劑",
                    aliases: nil
                )
            )
        ]
        #expect(payload.pasteResultPresentation == .summarySheet)
    }

    @Test func pasteResult_showsAvoidAlertWhenHitsMatchAvoidList() {
        var payload = ScanResultPayload(
            imageData: nil,
            ingredients: ["Fragrance"],
            matchedAlerts: ["人工香精（Fragrance）"],
            blockedTags: ["artificial-fragrance"],
            customBlockedIngredients: [],
            scannedAt: Date()
        )
        payload.resolvedIngredients = [
            PersistedScannedIngredient(
                name: "Fragrance",
                originalOrder: 1,
                isBlocked: true,
                databaseItem: IngredientItem(
                    englishName: "Fragrance",
                    chineseName: "香精",
                    safetyRating: "8",
                    function: "香氛",
                    aliases: nil
                )
            )
        ]
        #expect(payload.pasteResultPresentation == .avoidAlert)
    }

    @Test func pasteResult_staysSilentWhenZeroDictionaryHits() {
        var payload = ScanResultPayload(
            imageData: nil,
            ingredients: ["OCRJUNK"],
            matchedAlerts: [],
            blockedTags: [],
            customBlockedIngredients: [],
            scannedAt: Date()
        )
        payload.resolvedIngredients = [
            PersistedScannedIngredient(
                name: "OCRJUNK",
                originalOrder: 1,
                isBlocked: false,
                databaseItem: nil
            )
        ]
        #expect(payload.pasteResultPresentation == nil)
    }

    @Test func riskWarning_alcoholToggleDoesNotPromoteFragranceByScore() {
        let fragrance = IngredientItem(
            englishName: "Fragrance",
            chineseName: "香精",
            safetyRating: "8",
            function: "香氛",
            aliases: nil
        )
        let alcohol = IngredientItem(
            englishName: "Alcohol Denat.",
            chineseName: "變性酒精",
            safetyRating: "7",
            function: "溶劑",
            aliases: nil
        )

        #expect(
            !IngredientRiskEvaluator.isRiskWarning(
                name: "Fragrance",
                databaseItem: fragrance,
                blockedTags: ["denatured-alcohol"],
                customIngredients: [],
                alerts: ["變性酒精（Alcohol）", "人工香精（Fragrance）"]
            )
        )
        #expect(
            IngredientRiskEvaluator.isRiskWarning(
                name: "Alcohol Denat.",
                databaseItem: alcohol,
                blockedTags: ["denatured-alcohol"],
                customIngredients: [],
                alerts: []
            )
        )
        #expect(
            IngredientRiskEvaluator.isRiskWarning(
                name: "Fragrance",
                databaseItem: fragrance,
                blockedTags: ["artificial-fragrance"],
                customIngredients: [],
                alerts: []
            )
        )
        #expect(
            !IngredientRiskEvaluator.isRiskWarning(
                name: "Fragrance",
                databaseItem: fragrance,
                blockedTags: [],
                customIngredients: [],
                alerts: []
            )
        )
    }

    @Test func allergenTag_ignoresCosIngFunctionFragranceNote() {
        let wax = IngredientItem(
            englishName: "Euphorbia Cerifera Cera",
            chineseName: "小燭樹蠟",
            safetyRating: "1",
            function: "Skin conditioning, fragrance",
            aliases: nil
        )
        let fragrance = IngredientItem(
            englishName: "Fragrance",
            chineseName: "香精",
            safetyRating: "8",
            function: "Perfuming",
            aliases: nil
        )

        #expect(!wax.forcesAllergenFunctionTag)
        #expect(fragrance.forcesAllergenFunctionTag)
        #expect(fragrance.primaryFunctionTag == "過敏原")

        let aloe = IngredientItem(
            englishName: "ALOE BARBADENSIS LEAF WATER",
            chineseName: "庫拉索蘆薈葉水",
            safetyRating: "1",
            function: "fragrance",
            aliases: nil
        )
        #expect(!aloe.forcesAllergenFunctionTag)
        #expect(aloe.primaryFunctionTag != "過敏原")
    }
}
