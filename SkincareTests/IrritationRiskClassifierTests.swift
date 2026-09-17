import Testing
@testable import Skincare

struct IrritationRiskClassifierTests {
    @Test func retinolIsHighIrritation() {
        let risk = IrritationRiskClassifier.evaluate(englishName: "Retinol", chineseName: "視黃醇")
        #expect(risk == .high)
    }

    @Test func teaTreeOilIsHighIrritation() {
        let risk = IrritationRiskClassifier.evaluate(
            englishName: "Melaleuca Alternifolia Leaf Oil",
            chineseName: "茶樹精油"
        )
        #expect(risk == .high)
    }

    @Test func limoneneIsHighIrritation() {
        let risk = IrritationRiskClassifier.evaluate(englishName: "Limonene", chineseName: "香精")
        #expect(risk == .high)
    }

    @Test func glycerinIsLowIrritation() {
        let risk = IrritationRiskClassifier.evaluate(englishName: "Glycerin", chineseName: "甘油")
        #expect(risk == .low)
    }

    @Test func carrierSeedOilIsNotSpicyEssentialOil() {
        let risk = IrritationRiskClassifier.evaluate(
            englishName: "Helianthus Annuus Seed Oil",
            chineseName: "葵花籽油"
        )
        #expect(risk == .low)
    }

    @Test func concernBandMapsScores() {
        #expect(ConcernBand.from(score: 1) == .low)
        #expect(ConcernBand.from(score: 6) == .moderate)
        #expect(ConcernBand.from(score: 8) == .high)
    }
}
