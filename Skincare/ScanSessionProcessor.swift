import Foundation
import SwiftData

struct ScanSessionResult: Sendable {
    let ingredients: [String]
    let matchedAlerts: [String]
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let fullText: String
    /// 字典逆向命中數（供 UI 三態分流）。
    /// `ingredients` 另含未命中原字串，所以此值可能小於 `ingredients.count`。
    let dictionaryHitCount: Int
    /// Vision OCR 平均信心度（0...1）；手動輸入為 `nil`。
    var averageOCRConfidence: Float? = nil
    /// Vision 辨識文字行數（多圖合計）；手動輸入為 `nil`。
    var ocrLineCount: Int? = nil
    /// 參與 OCR 的照片張數（多角度融合時 > 1）。
    var sourceImageCount: Int = 1

    /// 三態分流依「字典命中數」而非清單長度：未命中原字串不應讓辨識品質看起來比實際好。
    var recognitionTier: RecognitionTier {
        RecognitionTier(count: dictionaryHitCount)
    }
}

/// 辨識結果三態：正常／弱辨識／未命中。
enum RecognitionTier: Sendable, Equatable, Hashable {
    case strong
    case weak
    case none

    init(count: Int) {
        switch count {
        case 5...: self = .strong
        case 1...4: self = .weak
        default: self = .none
        }
    }
}

enum ScanSessionProcessor {
    /// 單張向下相容入口。
    static func analyze(imageData: Data, profile: UserProfile?) async -> ScanSessionResult {
        await analyze(imageDataList: [imageData], profile: profile)
    }

    /// 手動貼上／輸入成分文字：略過 OCR，走字典主引擎。
    static func analyze(text: String, profile: UserProfile?) async -> ScanSessionResult {
        let blockedTags = await MainActor.run { profile?.blockedTags ?? [] }
        let customIngredients = await MainActor.run { profile?.customBlockedIngredients ?? [] }
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return ScanSessionResult(
                ingredients: [],
                matchedAlerts: [],
                blockedTags: blockedTags,
                customBlockedIngredients: customIngredients,
                fullText: "",
                dictionaryHitCount: 0
            )
        }
        return await finalizeParsedResult(
            recognizedText: sourceText,
            blockedTags: blockedTags,
            customIngredients: customIngredients
        )
    }

    /// 多張（1～3）依選取順序 OCR → 循序重疊拼接成分 → 風險評估。
    static func analyze(
        imageDataList: [Data],
        profile: UserProfile?,
        usesIngredientBandCrop: Bool = false
    ) async -> ScanSessionResult {
        let blockedTags = await MainActor.run { profile?.blockedTags ?? [] }
        let customIngredients = await MainActor.run { profile?.customBlockedIngredients ?? [] }

        let images = Array(imageDataList.prefix(3))
        guard !images.isEmpty else {
            return ScanSessionResult(
                ingredients: [],
                matchedAlerts: [],
                blockedTags: blockedTags,
                customBlockedIngredients: customIngredients,
                fullText: "",
                dictionaryHitCount: 0,
                sourceImageCount: 0
            )
        }

        async let cacheReady: Bool = Task.detached(priority: .userInitiated) {
            IngredientMatcher.warmIngredientCache()
            return true
        }.value

        let mergedText: String
        let perImageTexts: [String]
        let averageConfidence: Float?
        let lineCount: Int?
        let sourceImageCount: Int
        #if canImport(UIKit)
        let longEdge = usesIngredientBandCrop
            ? OCRManager.ingredientBandLongEdge
            : 2000
        let merged = await OCRManager.shared.recognizeMerged(
            fromImageDataList: images,
            maxLongEdge: longEdge
        )
        mergedText = merged.text
        perImageTexts = merged.perImageTexts
        averageConfidence = merged.averageConfidence
        lineCount = merged.lineCount
        sourceImageCount = merged.sourceImageCount
        #else
        mergedText = ""
        perImageTexts = []
        averageConfidence = nil
        lineCount = nil
        sourceImageCount = images.count
        #endif

        _ = await cacheReady

        print("📝 多圖 OCR 張數: \(sourceImageCount)，各圖原文數: \(perImageTexts.count)")

        return await finalizeMultiImageResult(
            perImageTexts: perImageTexts,
            fallbackJoinedText: mergedText,
            blockedTags: blockedTags,
            customIngredients: customIngredients,
            averageOCRConfidence: averageConfidence,
            ocrLineCount: lineCount,
            sourceImageCount: sourceImageCount
        )
    }

    /// 各圖字典命中 → Sequential Overlap Merge → 風險比對。
    private static func finalizeMultiImageResult(
        perImageTexts: [String],
        fallbackJoinedText: String,
        blockedTags: [String],
        customIngredients: [String],
        averageOCRConfidence: Float?,
        ocrLineCount: Int?,
        sourceImageCount: Int
    ) async -> ScanSessionResult {
        await Task.detached(priority: .userInitiated) {
            IngredientDatabaseManager.shared.ensureLoaded()
            IngredientMatcher.warmIngredientCache()

            let perImageLists: [[String]] = perImageTexts.map { raw in
                SequentialOverlapMerger.orderPreservingUnique(displayList(from: raw))
            }

            for (index, list) in perImageLists.enumerated() {
                print("📦 Photo \(index + 1) 成分數: \(list.count)")
            }

            let ingredients: [String]
            let fullText: String
            if perImageLists.count > 1 {
                ingredients = SequentialOverlapMerger.mergeAll(perImageLists)
                fullText = ingredients.joined(separator: ", ")
                print("🔗 Sequential Overlap Merge 後成分數: \(ingredients.count)")
            } else if let only = perImageLists.first {
                ingredients = only
                fullText = IngredientParser.preprocessIngredientListText(
                    perImageTexts.first ?? fallbackJoinedText
                )
            } else {
                ingredients = SequentialOverlapMerger.orderPreservingUnique(
                    displayList(from: fallbackJoinedText)
                )
                fullText = IngredientParser.preprocessIngredientListText(fallbackJoinedText)
            }

            for (index, name) in ingredients.enumerated() {
                print("📦 [\(index)] \(name)")
            }

            return ScanSessionResult(
                ingredients: ingredients,
                matchedAlerts: alerts(
                    for: ingredients,
                    blockedTags: blockedTags,
                    customIngredients: customIngredients
                ),
                blockedTags: blockedTags,
                customBlockedIngredients: customIngredients,
                fullText: fullText,
                dictionaryHitCount: dictionaryHitCount(in: ingredients),
                averageOCRConfidence: averageOCRConfidence,
                ocrLineCount: ocrLineCount,
                sourceImageCount: max(1, sourceImageCount)
            )
        }.value
    }

    // MARK: - 兩階段管線 → 顯示清單

    /// OCR 文字 → 依物理順序排列的顯示名稱。
    ///
    /// 命中字典者用標準 INCI 名；看起來像成分但字典沒有的 `.unknown` 保留原字串
    /// （供點擊修正）。`.noise`（地址、亂碼、西里爾、半截詞、條碼）不進清單、不計入 N。
    private static func displayList(from rawText: String) -> [String] {
        IngredientResolver.resolve(rawText)
            .filter { !$0.isNoise }
            .map(\.displayName)
    }

    /// 清單中真正命中字典的名稱；未命中原字串不列入，辨識三態才不會虛胖。
    private static func dictionaryHits(in ingredients: [String]) -> [String] {
        ingredients.filter { IngredientMatcher.matchToken($0) != nil }
    }

    private static func dictionaryHitCount(in ingredients: [String]) -> Int {
        dictionaryHits(in: ingredients).count
    }

    /// 風險提醒只依字典命中項計算：未命中字串本來就不會進風險區（見 `IngredientRiskEvaluator`），
    /// 讓它參與關鍵字比對只會製造假警報。
    private static func alerts(
        for ingredients: [String],
        blockedTags: [String],
        customIngredients: [String]
    ) -> [String] {
        let matched = dictionaryHits(in: ingredients)
        guard !matched.isEmpty else { return [] }
        return IngredientMatcher.checkAlerts(
            detectedIngredients: matched,
            blockedTags: blockedTags,
            customIngredients: customIngredients
        )
    }

    /// 字典逆向主引擎：命中項用標準 INCI 名，未命中項保留原字串，兩者皆依物理順序。
    private static func finalizeParsedResult(
        recognizedText: String,
        blockedTags: [String],
        customIngredients: [String],
        averageOCRConfidence: Float? = nil,
        ocrLineCount: Int? = nil,
        sourceImageCount: Int = 1
    ) async -> ScanSessionResult {
        await Task.detached(priority: .userInitiated) {
            IngredientDatabaseManager.shared.ensureLoaded()
            IngredientMatcher.warmIngredientCache()

            let ingredients = SequentialOverlapMerger.stripRedundantUnknowns(
                SequentialOverlapMerger.orderPreservingUnique(
                    displayList(from: recognizedText)
                )
            )

            print("📦 ScanSession 成分數: \(ingredients.count)")
            for (index, name) in ingredients.enumerated() {
                print("📦 [\(index)] \(name)")
            }

            return ScanSessionResult(
                ingredients: ingredients,
                matchedAlerts: alerts(
                    for: ingredients,
                    blockedTags: blockedTags,
                    customIngredients: customIngredients
                ),
                blockedTags: blockedTags,
                customBlockedIngredients: customIngredients,
                fullText: recognizedText,
                dictionaryHitCount: dictionaryHitCount(in: ingredients),
                averageOCRConfidence: averageOCRConfidence,
                ocrLineCount: ocrLineCount,
                sourceImageCount: sourceImageCount
            )
        }.value
    }

    /// 相機連續補拍：將新圖成分以 Sequential Overlap Merge 併入既有清單並重算警示。
    static func mergeFollowUpCapture(
        existingIngredients: [String],
        followUpImageData: Data,
        profile: UserProfile?,
        previousAverageConfidence: Float?,
        previousLineCount: Int?,
        previousImageCount: Int
    ) async -> ScanSessionResult {
        let blockedTags = await MainActor.run { profile?.blockedTags ?? [] }
        let customIngredients = await MainActor.run { profile?.customBlockedIngredients ?? [] }

        let followUp = await analyze(
            imageDataList: [followUpImageData],
            profile: profile,
            usesIngredientBandCrop: true
        )
        let mergedIngredients = SequentialOverlapMerger.mergeIngredients(
            listA: existingIngredients,
            listB: followUp.ingredients
        )

        let merged = await Task.detached(priority: .userInitiated) {
            (
                alerts: alerts(
                    for: mergedIngredients,
                    blockedTags: blockedTags,
                    customIngredients: customIngredients
                ),
                hitCount: dictionaryHitCount(in: mergedIngredients)
            )
        }.value

        let combinedConfidence: Float? = {
            switch (previousAverageConfidence, followUp.averageOCRConfidence) {
            case let (a?, b?): return (a + b) / 2
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }()
        let combinedLines: Int? = {
            switch (previousLineCount, followUp.ocrLineCount) {
            case let (a?, b?): return a + b
            case let (a?, nil): return a
            case let (nil, b?): return b
            default: return nil
            }
        }()

        return ScanSessionResult(
            ingredients: mergedIngredients,
            matchedAlerts: merged.alerts,
            blockedTags: blockedTags,
            customBlockedIngredients: customIngredients,
            fullText: mergedIngredients.joined(separator: ", "),
            dictionaryHitCount: merged.hitCount,
            averageOCRConfidence: combinedConfidence,
            ocrLineCount: combinedLines,
            sourceImageCount: max(previousImageCount, 1) + 1
        )
    }

    /// 至少命中一項字典成分才寫入歷史。
    /// 只有未命中字串的掃描視為辨識失敗，不產生「整頁都是未收錄」的空殼紀錄。
    @MainActor
    @discardableResult
    static func persist(
        result: ScanSessionResult,
        imageData: Data?,
        in context: ModelContext,
        title: String? = nil
    ) -> ScanHistoryRecordEntity? {
        guard result.dictionaryHitCount > 0 else { return nil }

        let recordTitle = title ?? ScanSummarySheet.defaultProductName()
        let snapshots = PersistedScannedIngredient.buildSnapshots(
            ingredientNames: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients
        )
        return ScanHistoryWriter.saveScanRecord(
            in: context,
            imageData: imageData,
            ingredients: result.ingredients,
            matchedIngredients: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            title: recordTitle,
            resolvedSnapshots: snapshots
        )
    }
}
