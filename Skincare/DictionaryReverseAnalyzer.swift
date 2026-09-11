import Foundation

/// 成分清單比對入口（相容舊名稱）。
/// 實際流程為 `IngredientMatcher` 的先分詞後扁平索引 O(1) 查表，
/// 不再對整份資料庫做 regex／contains 掃描。
enum DictionaryReverseAnalyzer {

    /// 規格 API：回傳 UI 用 `Ingredient` 陣列（依原文出現順序）。
    static func analyzeIngredientsByDictionary(rawText: String) -> [Ingredient] {
        matchIngredientItems(in: rawText).map { $0.asDetailIngredient() }
    }

    /// 管線用：分詞 → 標準化 → lookupIndex O(1) → 有限模糊。
    static func matchIngredientItems(in rawText: String) -> [IngredientItem] {
        IngredientMatcher.matchIngredientItems(in: rawText)
    }

    /// 背景執行完整比對，完成後回傳（UI 更新請回到主線程）。
    static func matchIngredientItemsAsync(in rawText: String) async -> [IngredientItem] {
        await IngredientMatcher.matchIngredientItemsAsync(in: rawText)
    }

    /// 資料庫重載後可呼叫；扁平索引由 `IngredientDatabaseManager` 重建。
    static func resetCandidateCache() {}
}

extension IngredientParser {
    /// 正式主解析入口：先分詞後查表。
    static func analyzeIngredientsByDictionary(rawText: String) -> [Ingredient] {
        DictionaryReverseAnalyzer.analyzeIngredientsByDictionary(rawText: rawText)
    }
}
