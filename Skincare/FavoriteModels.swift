import SwiftUI

struct FavoriteProduct: Identifiable, Hashable {
    let id: String
    let brand: String
    let name: String
    let category: String
    let highlight: String
    let note: String
    let accentRed: Double
    let accentGreen: Double
    let accentBlue: Double

    var accent: Color {
        Color.safeRGB(red: accentRed, green: accentGreen, blue: accentBlue)
    }
}

struct FavoriteIngredientItem: Identifiable, Hashable {
    let id: String
    let ingredient: Ingredient
}

enum FavoritesSegment: String, CaseIterable, Identifiable {
    case products = "保養品"
    case ingredients = "保養成分"

    var id: String { rawValue }
}

extension FavoriteProductRecord {
    var displayModel: FavoriteProduct {
        FavoriteProduct(
            id: recordID,
            brand: brand,
            name: name,
            category: category,
            highlight: highlight,
            note: note,
            accentRed: accentRed,
            accentGreen: accentGreen,
            accentBlue: accentBlue
        )
    }
}

extension FavoriteIngredientRecord {
    func displayItem(catalog: [Ingredient] = Ingredient.samples) -> FavoriteIngredientItem? {
        if let ingredient = catalog.first(where: { $0.id == ingredientID }) {
            return FavoriteIngredientItem(id: recordID, ingredient: ingredient)
        }

        IngredientDatabaseManager.shared.ensureLoaded()
        if let dbItem = IngredientDatabaseManager.shared.lookup(ingredientName: englishName)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: chineseName)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: ingredientID) {
            return FavoriteIngredientItem(id: recordID, ingredient: dbItem.asDetailIngredient())
        }

        let en = englishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !en.isEmpty || !zh.isEmpty else { return nil }

        let displayEN = en.isEmpty ? zh : en
        let displayZH = zh.isEmpty ? en : zh
        let symbolSource = displayEN
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .filter(\.isLetter)
        let symbol = String(symbolSource.prefix(2))

        return FavoriteIngredientItem(
            id: recordID,
            ingredient: Ingredient(
                id: ingredientID.isEmpty ? displayEN.lowercased() : ingredientID,
                chineseName: displayZH,
                englishName: displayEN,
                scientificName: displayEN,
                symbol: symbol.isEmpty ? "IN" : symbol,
                benefit: "收藏成分",
                benefits: ["收藏成分"],
                summary: "已加入我的最愛成分清單。",
                safetyNote: "此為自訂或字典外成分，請另參考產品標示。",
                suitableSkinTypes: ["一般膚質"],
                cautionSkinTypes: ["敏感肌請先局部測試"],
                warnings: [],
                ewgScore: 5,
                ewgBand: .moderate,
                risk: .moderate,
                accentRed: 0.55,
                accentGreen: 0.62,
                accentBlue: 0.54
            )
        )
    }
}
