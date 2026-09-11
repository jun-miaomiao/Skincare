import Foundation
import Testing
@testable import Skincare

/// 通用成分表起始錨點：不以特定產品或成分名稱當起點。
struct IngredientListAnchorTests {

    @Test func englishIngredientsAnchor_dropsPrefixCopy() {
        let raw = """
        Brightening Water Essence
        Marketing line about glow
        INGREDIENTS: Glycerin, Niacinamide, Panthenol
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        let lower = cropped.lowercased()
        #expect(lower.hasPrefix("glycerin"))
        #expect(!lower.hasPrefix("ingredient"))
        #expect(!cropped.contains("Brightening"))
        #expect(!cropped.contains("Marketing"))
    }

    @Test func englishContainsAnchor_supported() {
        let raw = """
        Product Title
        CONTAINS: Alpha-Glucan, Beta-Glucan
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("Alpha-Glucan"))
        #expect(!cropped.uppercased().contains("PRODUCT TITLE"))
    }

    @Test func chineseFullListAnchor_dropsProductName() {
        let raw = """
        美白精華水
        全成分：甘油, 菸鹼醯胺, 泛醇
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("甘油"))
        #expect(!cropped.contains("美白精華水"))
        #expect(!cropped.hasPrefix("全成分"))
        #expect(!cropped.hasPrefix("成分"))
    }

    @Test func chineseVariantChengFen_withColon() {
        let raw = """
        宣傳文案
        成份：丙二醇, 透明質酸
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("丙二醇"))
        #expect(!cropped.contains("宣傳文案"))
    }

    @Test func chineseChengFen_withSpacesAndColon() {
        let raw = "標題\n成 分 ： 水, 甘油"
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("水"))
        #expect(!cropped.contains("標題"))
    }

    @Test func prefersColonHeaderOverEarlierBareKeyword() {
        let raw = """
        INGREDIENTS FROM NATURE
        Formulated without synthetic dyes
        INGREDIENTS: Beeswax, Lanolin, Tocopherol
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        let upper = cropped.uppercased()
        #expect(upper.hasPrefix("BEESWAX"))
        #expect(!upper.hasPrefix("FROM NATURE"))
        #expect(!upper.contains("FORMULATED WITHOUT"))
    }

    @Test func chineseIngredientTableSuffix_isConsumed() {
        let raw = """
        宣傳標題
        成分表：甘油, 泛醇
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("甘油"))
        #expect(!cropped.hasPrefix("表"))
    }

    @Test func runningTextChengFen_isNotAHeader() {
        let raw = """
        含有活性成分與保濕因子
        甘油, 泛醇
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.contains("含有活性成分"))
        #expect(cropped.contains("甘油"))
    }

    @Test func noAnchor_keepsFullText() {
        let raw = "Glycerin, Niacinamide, Panthenol, Allantoin"
        #expect(IngredientParser.cropToIngredientListSection(raw) == raw)
    }

    // MARK: - 黏字 OCR（無換行、掉標點）

    /// 真實 OCR 常把整罐文字黏成一段：前句與標題相連、成分末項與頁尾相連。
    /// 錨點不得依賴行首或句號，否則裁切完全失效。
    @Test func gluedOCR_startAndEndAnchorsStillCrop() {
        let raw = "柔霧質地帶來持久的貼妝效果。全成分WATER(AQUA/EAU), GLYCERIN, DIMETHICONE,"
            + " PHENOXYETHANOL注意事項：本產品僅供外用，避免接觸眼睛。容量：50ml"
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("WATER"))
        #expect(cropped.hasSuffix("PHENOXYETHANOL"))
        #expect(!cropped.contains("貼妝效果"))
        #expect(!cropped.contains("注意事項"))
        #expect(!cropped.contains("50ml"))
    }

    @Test func gluedOCR_englishHeaderWithoutSpace() {
        let raw = "使用前請充分搖勻。Ingredients:Dimethicone, Cyclopentasiloxane, Silica批號 A2401"
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("Dimethicone"))
        #expect(cropped.hasSuffix("Silica"))
        #expect(!cropped.contains("搖勻"))
        #expect(!cropped.contains("批號"))
    }

    // MARK: - 結束錨點

    @Test func endAnchor_dropsEverythingAfterFooterSection() {
        let raw = """
        全成分：WATER, GLYCERIN, NIACINAMIDE, PHENOXYETHANOL
        注意事項：本產品僅供外用，避免接觸眼睛。
        容量 50ml
        Distributed by Example Beauty Ltd., 12 High Street, London, UK
        www.examplebeauty.com
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("WATER"))
        #expect(cropped.contains("PHENOXYETHANOL"))
        #expect(!cropped.contains("注意事項"))
        #expect(!cropped.contains("50ml"))
        #expect(!cropped.contains("London"))
        #expect(!cropped.contains("www"))
    }

    /// 關鍵防呆：夾在清單**中間**的製造商字樣不得截斷整份成分表。
    @Test func endAnchor_ignoresFooterKeywordInsideIngredientLine() {
        let raw = """
        Water (Aqua), Glycerin, Manufactured for Example Labs, Butylene Glycol,
        Niacinamide, Tocopherol
        Made in USA
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.contains("Butylene Glycol"))
        #expect(cropped.contains("Tocopherol"))
        #expect(!cropped.contains("Made in USA"))
    }

    @Test func endAnchor_softCorporationOnNewLine_doesNotCutMidListManufacturedFor() {
        let midList = """
        Water (Aqua), Glycerin, Manufactured for Sample Labs, Butylene Glycol,
        Niacinamide, Tocopherol
        """
        let croppedMid = IngredientParser.cropToIngredientListSection(midList)
        #expect(croppedMid.contains("Butylene Glycol"))
        #expect(croppedMid.contains("Tocopherol"))

        let afterList = """
        WATER, GLYCERIN, SQUALANE
        CORPORATION
        """
        let croppedEnd = IngredientParser.cropToIngredientListSection(afterList)
        #expect(croppedEnd.contains("SQUALANE"))
        #expect(!croppedEnd.uppercased().contains("CORPORATION"))
    }

    @Test func endAnchor_singleCountryName_isNotAHardCut() {
        let raw = "WATER, GLYCERIN, JAPAN WAX, SQUALANE"
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.uppercased().contains("JAPAN WAX"))
        #expect(cropped.uppercased().contains("SQUALANE"))
    }

    @Test func endAnchor_chineseManufacturerImporterAndNetWeight_afterList() {
        let chinese = """
        全成分：WATER, GLYCERIN, SQUALANE
        製造廠：SAMPLE FACTORY
        輸入業者：SAMPLE IMPORTER
        """
        let croppedChinese = IngredientParser.cropToIngredientListSection(chinese)
        #expect(croppedChinese.contains("SQUALANE"))
        #expect(!croppedChinese.contains("製造廠"))
        #expect(!croppedChinese.contains("輸入業者"))

        let western = """
        INGREDIENTS: Water, Glycerin, Squalane
        Made in France
        Net Wt 50ml
        """
        let croppedWestern = IngredientParser.cropToIngredientListSection(western)
        #expect(croppedWestern.uppercased().contains("SQUALANE"))
        #expect(!croppedWestern.uppercased().contains("MADE IN"))
        #expect(!croppedWestern.uppercased().contains("NET WT"))
    }

    /// 沒有起始錨點時，結束錨點仍須生效，且不得把整份文字砍空。
    @Test func endAnchor_worksWithoutStartAnchor() {
        let raw = """
        Glycerin, Niacinamide, Panthenol, Allantoin
        Directions: Apply twice daily.
        """
        let cropped = IngredientParser.cropToIngredientListSection(raw)
        #expect(cropped.hasPrefix("Glycerin"))
        #expect(cropped.contains("Allantoin"))
        #expect(!cropped.contains("Directions"))
    }

    // MARK: - 首項前綴清理

    @Test func headerPrefix_strippedWhenGluedToFirstIngredient() {
        #expect(IngredientParser.stripIngredientHeaderPrefix("全成分WATER(AQUA/EAU)") == "WATER(AQUA/EAU)")
        #expect(IngredientParser.stripIngredientHeaderPrefix("Ingredients:Dimethicone") == "Dimethicone")
        #expect(IngredientParser.stripIngredientHeaderPrefix("成份表：甘油") == "甘油")
        #expect(IngredientParser.stripIngredientHeaderPrefix("INCI: Aqua") == "Aqua")

        // 非標題開頭不得誤刪
        #expect(IngredientParser.stripIngredientHeaderPrefix("Water, Glycerin") == "Water, Glycerin")
        #expect(IngredientParser.stripIngredientHeaderPrefix("Cocos Nucifera Oil") == "Cocos Nucifera Oil")
    }

    @Test func gluedHeader_firstIngredientIsTokenizedIndependently() {
        let tokens = IngredientTokenizer.tokenizeToStrings("全成分WATER(AQUA/EAU), GLYCERIN")
        #expect(tokens.first?.uppercased().hasPrefix("WATER") == true)
        #expect(tokens.contains { $0.uppercased().contains("GLYCERIN") })
        #expect(!tokens.contains { $0.contains("全成分") })
    }

    @Test func preprocessAppliesAnchorBeforeOtherCleanup() {
        let raw = """
        Title With Extra Words
        Ingredients: Glycerin*, Niacinamide
        """
        let prepared = IngredientParser.preprocessIngredientListText(raw)
        #expect(prepared.lowercased().contains("glycerin"))
        #expect(!prepared.lowercased().contains("title with extra"))
        #expect(!prepared.contains("*"))
    }
}
