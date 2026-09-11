import Foundation
import Testing
@testable import Skincare

struct DictionarySearchPresentationTests {

    @Test func searchReady_rejectsSingleLatinLetter() {
        #expect(!DictionaryView.isSearchReady(""))
        #expect(!DictionaryView.isSearchReady("a"))
        #expect(DictionaryView.isSearchReady("aq"))
        #expect(DictionaryView.isSearchReady("水"))
        #expect(DictionaryView.isSearchReady("甘油"))
    }

    @Test func search_emptyOrShortQueryReturnsNoRows() {
        let items = [
            IngredientItem(
                englishName: "Aqua",
                chineseName: "水",
                safetyRating: "1",
                function: "溶劑",
                aliases: ["Water"]
            )
        ]
        #expect(DictionaryView.search(in: items, query: "").isEmpty)
        #expect(DictionaryView.search(in: items, query: "a").isEmpty)
        #expect(!DictionaryView.search(in: items, query: "aq").isEmpty)
        #expect(!DictionaryView.search(in: items, query: "水").isEmpty)
    }
}
