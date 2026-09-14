import SwiftUI
import SwiftData

/// 成分字典：搜尋為主。空白時只顯示最近掃描／常用查詢，不一次攤開全部收錄。
struct DictionaryView: View {
    private static let maxDisplayedResults = 80
    /// 常用 INCI 查詢捷徑（查庫才顯示，不是品牌／品名名單）。
    private static let commonQueries = [
        "Water", "Glycerin", "Butylene Glycol", "Niacinamide",
        "Dimethicone", "Squalane", "Phenoxyethanol", "Tocopherol",
        "Panthenol", "Sodium Hyaluronate"
    ]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @Query(sort: \ScanHistoryRecordEntity.scannedAt, order: .reverse)
    private var historyRecords: [ScanHistoryRecordEntity]

    @Query(sort: \FavoriteIngredientRecord.createdAt, order: .reverse)
    private var favoriteIngredientRecords: [FavoriteIngredientRecord]

    @State private var allItems: [IngredientItem] = []
    @State private var commonItems: [IngredientItem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showPaywall = false

    private var favoritedIngredientKeys: Set<String> {
        FavoriteManager.favoritedIngredientKeys(from: favoriteIngredientRecords)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !query.isEmpty }

    private var searchResults: [IngredientItem] {
        guard Self.isSearchReady(query) else { return [] }
        return Array(Self.search(in: allItems, query: query).prefix(Self.maxDisplayedResults))
    }

    private var recentItems: [IngredientItem] {
        var seen = Set<String>()
        var result: [IngredientItem] = []
        for record in historyRecords.prefix(10) {
            for snap in record.resolvedIngredients {
                guard let item = snap.databaseItem else { continue }
                let key = item.englishName.lowercased(with: Locale(identifier: "en_US_POSIX"))
                guard seen.insert(key).inserted else { continue }
                result.append(item)
                if result.count >= 12 { return result }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView("載入成分字典…")
                        .tint(Theme.accent)
                } else {
                    List {
                        Section {
                            dictionaryHeader
                                .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 12, trailing: 22))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        if isSearching {
                            searchContent
                        } else {
                            idleContent
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("成分字典")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "請搜尋成分名稱"
            )
            .task {
                await loadDictionary()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: .favorites)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if !Self.isSearchReady(query) {
            Section {
                searchHint("請再輸入一個字，以免一次列出過多結果。")
                    .listRowInsets(EdgeInsets(top: 24, leading: 22, bottom: 24, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } else if searchResults.isEmpty {
            Section {
                emptySearchState
                    .listRowInsets(EdgeInsets(top: 24, leading: 22, bottom: 24, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(searchResults) { item in
                    dictionaryLink(item)
                }
            } header: {
                Text("搜尋結果（\(searchResults.count)\(searchResults.count == Self.maxDisplayedResults ? "+" : "")）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if !recentItems.isEmpty {
            Section {
                ForEach(recentItems) { item in
                    dictionaryLink(item)
                }
            } header: {
                Text("最近掃描")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
                    .textCase(nil)
            }
        }

        if !commonItems.isEmpty {
            let recentKeys = Set(recentItems.map { $0.englishName.lowercased(with: Locale(identifier: "en_US_POSIX")) })
            let extras = commonItems.filter {
                !recentKeys.contains($0.englishName.lowercased(with: Locale(identifier: "en_US_POSIX")))
            }
            if !extras.isEmpty {
                Section {
                    ForEach(extras) { item in
                        dictionaryLink(item)
                    }
                } header: {
                    Text("常用查詢")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.muted)
                        .textCase(nil)
                }
            }
        }
    }

    private func dictionaryLink(_ item: IngredientItem) -> some View {
        NavigationLink {
            IngredientDetailView(ingredient: item.asDetailIngredient())
        } label: {
            DictionaryIngredientRow(item: item)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                guard subscriptionStore.isPremium else {
                    showPaywall = true
                    return
                }
                _ = FavoriteManager.addIngredient(item, in: modelContext)
            } label: {
                Label(
                    "最愛",
                    systemImage: subscriptionStore.isPremium ? "star.fill" : "lock.fill"
                )
            }
            .tint(.orange)
            .disabled(FavoriteManager.isIngredientFavorited(item, favoritedKeys: favoritedIngredientKeys))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 6, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func searchHint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.muted)
                .padding(.top, 1)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var dictionaryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("成分字典")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .foregroundColor(Theme.ink)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(allItems.count) 筆")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.ink)
                    Text("已收錄，請用搜尋查找")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.databaseVersionLabel)
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.ink)
                    Text("資料庫版本")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.elevated)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var emptySearchState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(Theme.muted)
            Text("找不到「\(searchText)」")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)
            Text("試試英文 INCI、中文名或常見別名。")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @MainActor
    private func loadDictionary() async {
        isLoading = true
        let queries = Self.commonQueries
        let loaded = await Task.detached(priority: .userInitiated) {
            _ = IngredientDatabaseManager.shared.ensureLoaded()
            let all = IngredientDatabaseManager.shared.allIngredients()
            let common = queries.compactMap { name in
                IngredientDatabaseManager.shared.lookup(ingredientName: name)
            }
            return (all, common)
        }.value
        allItems = loaded.0
        commonItems = loaded.1
        isLoading = false
    }

    static var databaseVersionLabel: String {
        "v\(IngredientDatabaseManager.bundledDatabaseVersion).0"
    }

    /// 拉丁至少 2 字、中日韓 1 字，避免單字母把近三萬筆灌進畫面。
    static func isSearchReady(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains(where: { character in
            character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }) {
            return true
        }
        return trimmed.count >= 2
    }

    /// 搜尋：原文包含 + 去標點緊湊包含；查詢端套用植萃縮寫與 CosIng 同義詞。
    static func search(in items: [IngredientItem], query: String) -> [IngredientItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchReady(trimmed) else { return [] }

        let expanded = IngredientMatcher.expandBotanicalAbbreviations(trimmed)
        let normalized = IngredientMatcher.deepNormalize(expanded)
        var needles: [String] = [
            trimmed.lowercased(with: Locale(identifier: "en_US_POSIX")),
            expanded.lowercased(with: Locale(identifier: "en_US_POSIX")),
            normalized,
        ]
        let compactNeedles = needles.map(compactSearchKey).filter { $0.count >= 2 }
        needles = Array(Set(needles.filter { !$0.isEmpty }))

        return items.filter { item in
            item.allMatchNames.contains { name in
                let lower = name.lowercased(with: Locale(identifier: "en_US_POSIX"))
                if needles.contains(where: { lower.contains($0) }) { return true }
                let compact = compactSearchKey(lower)
                return compactNeedles.contains { compact.contains($0) }
            }
        }
    }

    private static func compactSearchKey(_ text: String) -> String {
        text.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { Character($0) }
            .reduce(into: "") { $0.append($1) }
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

private struct DictionaryIngredientRow: View {
    let item: IngredientItem

    private var score: Int? { item.safetyScore }

    var body: some View {
        HStack(spacing: 12) {
            Text(SafetyScoreStyle.label(for: score))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(score == nil ? Theme.muted : .white)
                .frame(width: 28, height: 28)
                .background(SafetyScoreStyle.color(for: score), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.englishName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)

                Text(item.displayChineseName)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let tag = item.primaryFunctionTag {
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cardStroke.opacity(0.9), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

extension IngredientItem {
    /// 將字典項目轉成 `IngredientDetailView` 可用的詳情模型。
    func asDetailIngredient() -> Ingredient {
        let score = safetyScore ?? 5
        let clamped = min(max(score, 1), 9)
        let band: EWGBand
        let risk: RiskLevel
        switch clamped {
        case 1...2:
            band = .safe
            risk = .low
        case 3...6:
            band = .moderate
            risk = .moderate
        default:
            band = .high
            risk = .high
        }

        let functionTags = function
            .components(separatedBy: CharacterSet(charactersIn: "、，,/／|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let aliasWarnings: [String] = {
            guard let aliases, !aliases.isEmpty else {
                return ["此為本地成分字典摘要；完整臨床評估請另參考產品標示與醫師建議。"]
            }
            let joined = aliases.prefix(4).joined(separator: "、")
            return [
                "常見別名：\(joined)",
                "此為本地成分字典摘要；完整臨床評估請另參考產品標示與醫師建議。"
            ]
        }()

        let symbolSource = englishName
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter }
        let symbol = String(symbolSource.prefix(2))
        let displaySymbol = symbol.isEmpty ? "IN" : symbol

        return Ingredient(
            id: id,
            chineseName: chineseName.isEmpty ? englishName : chineseName,
            englishName: englishName,
            scientificName: englishName,
            symbol: displaySymbol,
            benefit: firstFunctionSegment ?? function,
            benefits: functionTags.isEmpty ? [function] : Array(functionTags.prefix(4)),
            summary: function.isEmpty ? "一般保養成份" : function,
            safetyNote: "安心度評級 \(safetyRating.isEmpty ? "—" : safetyRating)（1–9，分數越低通常關注度越低）。",
            suitableSkinTypes: ["一般膚質", "依產品配方與濃度而定"],
            cautionSkinTypes: ["敏感肌請先局部測試；實際耐受度因人而異"],
            warnings: aliasWarnings,
            ewgScore: clamped,
            ewgBand: band,
            risk: risk,
            accentRed: 0.55,
            accentGreen: 0.58,
            accentBlue: 0.52,
            aliases: aliases
        )
    }
}

struct DictionaryView_Previews: PreviewProvider {
    static var previews: some View {
        DictionaryView()
            .environmentObject(SubscriptionStore.shared)
    }
}
