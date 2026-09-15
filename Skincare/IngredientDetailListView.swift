import SwiftUI
import SwiftData

struct IngredientDetailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let ingredients: [String]
    let matchedAlerts: [String]
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let productName: String
    /// 掃描紀錄 ID；有值時編輯會寫回 SwiftData。
    var historyRecordID: String? = nil
    /// 最愛紀錄 ID；有值時編輯會寫回最愛。
    var favoriteRecordID: String? = nil
    /// 掃描當下已持久化的成分快照；有值時唯讀載入，不重跑字典比對。
    var storedSnapshots: [PersistedScannedIngredient] = []
    /// 辨識三態；`nil` 時依目前清單長度推斷。
    var recognitionTier: RecognitionTier? = nil
    var scanSource: ScanSource = .history

    @Query private var profileList: [UserProfile]
    @Query(sort: \FavoriteIngredientRecord.createdAt, order: .reverse)
    private var favoriteIngredientRecords: [FavoriteIngredientRecord]

    @State private var orderedItems: [ScannedIngredientItem] = []
    @State private var cachedAlertReport: IngredientAlertReport = .empty
    @State private var cachedBlockedItems: [ScannedIngredientItem] = []
    @State private var cachedRegularItems: [ScannedIngredientItem] = []
    @State private var cachedUnmatchedItems: [ScannedIngredientItem] = []
    @State private var unmatchedSectionExpanded = false
    @State private var didSetUnmatchedExpansion = false
    @State private var isPreparing = true

    @State private var editingItemID: UUID?
    @State private var searchDraft = ""
    @State private var activeSearchSheet: IngredientSearchPresentation?
    @State private var showManualPasteSheet = false
    @State private var showPaywall = false

    @State private var editableProductName: String = ""
    @State private var showRenameAlert = false
    @State private var renameDraft = ""

    private var profile: UserProfile? { profileList.first }

    private var favoritedIngredientKeys: Set<String> {
        FavoriteManager.favoritedIngredientKeys(from: favoriteIngredientRecords)
    }

    private var alertReport: IngredientAlertReport { cachedAlertReport }

    private var blockedItems: [ScannedIngredientItem] { cachedBlockedItems }

    private var regularItems: [ScannedIngredientItem] { cachedRegularItems }

    private var unmatchedItems: [ScannedIngredientItem] { cachedUnmatchedItems }

    /// 主標題只算字典命中；灰色未收錄另列，不灌進「已辨識」筆數。
    private var identifiedCount: Int {
        orderedItems.filter { $0.databaseItem != nil }.count
    }

    /// 弱辨識提示依「字典命中數」判斷；未命中原字串只是待修正的佔位，不算辨識成果。
    private var showsWeakRecognitionHint: Bool {
        if isPreparing || orderedItems.isEmpty {
            if let recognitionTier {
                return recognitionTier == .weak
            }
            let snapshotHits = storedSnapshots.filter { $0.databaseItem != nil }.count
            let fallback = storedSnapshots.isEmpty ? ingredients.count : snapshotHits
            return RecognitionTier(count: fallback) == .weak
        }
        return RecognitionTier(count: identifiedCount) == .weak
    }

    private var isStoredRecordView: Bool {
        historyRecordID != nil || favoriteRecordID != nil || !storedSnapshots.isEmpty
    }

    private var shouldShowPrimaryHint: Bool {
        cachedRegularItems.contains { $0.databaseItem != nil && $0.originalOrder <= 5 }
    }

    private var displayedProductName: String {
        let trimmed = editableProductName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? productName : trimmed
    }

    private var canPersistProductName: Bool {
        (historyRecordID?.isEmpty == false) || (favoriteRecordID?.isEmpty == false)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isPreparing {
                ProgressView("整理成分清單…")
                    .tint(Theme.accent)
            } else if orderedItems.isEmpty {
                emptyEditableState
            } else {
                ingredientList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                .accessibilityLabel("返回")
            }
            ToolbarItem(placement: .principal) {
                Button {
                    renameDraft = displayedProductName
                    showRenameAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Text(displayedProductName)
                            .font(.headline)
                            .foregroundColor(Theme.ink)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改商品名稱")
                .accessibilityHint("點擊以重新命名")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    beginAdd()
                } label: {
                    Label("新增成分", systemImage: "plus")
                }
                .accessibilityLabel("新增成分")
            }
        }
        .alert("修改商品名稱", isPresented: $showRenameAlert) {
            TextField("商品名稱", text: $renameDraft)
            Button("儲存") {
                commitProductNameEdit()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(canPersistProductName
                  ? "新名稱會儲存到此筆掃描紀錄。"
                  : "請輸入要顯示的商品名稱。")
        }
        .onAppear {
            if editableProductName.isEmpty {
                editableProductName = productName
            }
        }
        .onChange(of: productName) { _, newValue in
            if !showRenameAlert {
                editableProductName = newValue
            }
        }
        .sheet(item: $activeSearchSheet, onDismiss: {
            editingItemID = nil
        }) { presentation in
            IngredientSearchSheet(
                title: presentation.title,
                prompt: "成分名稱（英文或中文）",
                text: $searchDraft,
                onComplete: {
                    switch presentation {
                    case .edit:
                        return applyEdit()
                    case .add:
                        return applyAdd()
                    }
                },
                onSelect: { item in
                    switch presentation {
                    case .edit:
                        return applyEdit(selected: item)
                    case .add:
                        return applyAdd(selected: item)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showManualPasteSheet) {
            ManualInputView(
                source: scanSource,
                persistsToHistory: historyRecordID == nil && favoriteRecordID == nil
            ) { payload in
                applyReanalyzedPayload(payload)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: .favorites)
        }
        .task(id: contentIdentity) {
            didSetUnmatchedExpansion = false
            loadRowsForPresentation()
        }
    }

    private var contentIdentity: String {
        if !storedSnapshots.isEmpty {
            return "snap-\(storedSnapshots.count)-\(storedSnapshots.first?.name ?? "")-\(productName)"
        }
        return "names-\(ingredients.count)-\(ingredients.first ?? "")-\(productName)"
    }

    private var emptyEditableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.viewfinder")
                .font(.largeTitle)
                .foregroundColor(Theme.muted)
            Text("尚無成分資料")
                .font(.headline)
                .foregroundColor(Theme.ink)
            Text("拍照辨識不足時，可貼上官網或瓶身全成分，走同一套字典。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                showManualPasteSheet = true
            } label: {
                Label("貼上成分表", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Button {
                beginAdd()
            } label: {
                Label("新增單一成分", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }

    private var ingredientList: some View {
        List {
            if showsWeakRecognitionHint {
                Section {
                    WeakRecognitionHintCard(
                        count: identifiedCount,
                        onSearchAdd: { beginAdd() },
                        onPasteOfficial: { showManualPasteSheet = true }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 4, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .deleteDisabled(true)
                }
            }

            if !blockedItems.isEmpty {
                Section {
                    ingredientRows(
                        items: blockedItems,
                        displayMode: .warning,
                        onDelete: { deleteItems(from: blockedItems, at: $0) }
                    )
                } header: {
                    Label("優先留意", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.blush)
                        .font(.caption.weight(.semibold))
                }
            }

            if !regularItems.isEmpty {
                Section {
                    // 小標題獨立於可滑刪的 Row，避免左滑時連帶位移。
                    if shouldShowPrimaryHint {
                        Text("前排主成分（含量通常最高）")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.muted.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 34)
                            .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 0, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .deleteDisabled(true)
                    }

                    ingredientRows(
                        items: regularItems,
                        displayMode: .remaining,
                        onDelete: { deleteItems(from: regularItems, at: $0) }
                    )
                } header: {
                    Text(blockedItems.isEmpty ? "已辨識（\(identifiedCount)）" : "其餘成分（\(regularItems.count)）")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.muted)
                }
            }

            if !unmatchedItems.isEmpty {
                Section {
                    if unmatchedSectionExpanded {
                        ingredientRows(
                            items: unmatchedItems,
                            displayMode: .remaining,
                            onDelete: { deleteItems(from: unmatchedItems, at: $0) }
                        )
                    }
                } header: {
                    unmatchedSectionHeader
                }
            }

            Section {
                IngredientOrderNoteCard()
                    .listRowInsets(EdgeInsets(top: 12, leading: 18, bottom: 24, trailing: 18))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var unmatchedSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                unmatchedSectionExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("可能未辨識（\(unmatchedItems.count)）")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
                Spacer()
                Image(systemName: unmatchedSectionExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("可能未辨識 \(unmatchedItems.count) 項")
        .accessibilityHint(unmatchedSectionExpanded ? "點擊收合" : "點擊展開以修正")
    }

    @ViewBuilder
    private func ingredientRows(
        items: [ScannedIngredientItem],
        displayMode: IngredientRowDisplayMode,
        onDelete: @escaping (IndexSet) -> Void
    ) -> some View {
        ForEach(items) { item in
            detailRow(for: item, displayMode: displayMode)
        }
        .onDelete(perform: onDelete)
    }

    private func detailRow(
        for item: ScannedIngredientItem,
        displayMode: IngredientRowDisplayMode
    ) -> some View {
        IngredientDetailRow(
            item: item,
            displayMode: displayMode,
            alertTags: alertReport.annotation(forName: item.name, databaseItem: item.databaseItem)?.tags ?? [],
            skinReasons: alertReport.annotation(forName: item.name, databaseItem: item.databaseItem)?.skinReasons ?? [],
            onUnmatchedTap: item.databaseItem == nil
                ? { beginEdit(item) }
                : nil
        )
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                guard subscriptionStore.isPremium else {
                    showPaywall = true
                    return
                }
                addIngredientToFavorites(item)
            } label: {
                Label(
                    "最愛",
                    systemImage: subscriptionStore.isPremium ? "star.fill" : "lock.fill"
                )
            }
            .tint(.orange)
            .disabled(isIngredientAlreadyFavorited(item))
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func isIngredientAlreadyFavorited(_ item: ScannedIngredientItem) -> Bool {
        if let db = item.databaseItem {
            return FavoriteManager.isIngredientFavorited(db, favoritedKeys: favoritedIngredientKeys)
        }
        return FavoriteManager.isIngredientFavorited(
            ingredientID: item.name,
            englishName: item.name,
            favoritedKeys: favoritedIngredientKeys
        )
    }

    private func addIngredientToFavorites(_ item: ScannedIngredientItem) {
        if let db = item.databaseItem {
            _ = FavoriteManager.addIngredient(db, in: modelContext)
            return
        }
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = FavoriteManager.addIngredient(
            ingredientID: name.lowercased(with: Locale(identifier: "en_US_POSIX")),
            chineseName: name,
            englishName: name,
            in: modelContext
        )
    }

    // MARK: - Prepare

    /// 歷史／最愛：直接讀快照；警示比對一律背景計算後快取，避免 body 重複運算。
    @MainActor
    private func loadRowsForPresentation() {
        if !storedSnapshots.isEmpty {
            let items = storedSnapshots.map { snap in
                ScannedIngredientItem(
                    name: snap.name,
                    originalOrder: snap.originalOrder,
                    isBlocked: IngredientRiskEvaluator.isRiskWarning(
                        name: snap.name,
                        databaseItem: snap.databaseItem,
                        blockedTags: blockedTags,
                        customIngredients: customBlockedIngredients,
                        alerts: matchedAlerts
                    ),
                    databaseItem: snap.databaseItem
                )
            }
            applyItemsInstantly(items)
            return
        }

        if isStoredRecordView {
            Task {
                let names = ingredients
                let tags = blockedTags
                let custom = customBlockedIngredients
                let alerts = matchedAlerts
                let prepared = await Task.detached(priority: .userInitiated) { () -> [ScannedIngredientItem] in
                    IngredientDatabaseManager.shared.ensureLoaded()
                    return names.enumerated().map { index, name in
                        let hit = IngredientDatabaseManager.shared.lookup(ingredientName: name)
                        let display = hit?.englishName ?? name
                        return ScannedIngredientItem(
                            name: display,
                            originalOrder: index + 1,
                            isBlocked: IngredientRiskEvaluator.isRiskWarning(
                                name: display,
                                databaseItem: hit,
                                blockedTags: tags,
                                customIngredients: custom,
                                alerts: alerts
                            ),
                            databaseItem: hit
                        )
                    }
                }.value
                applyItemsInstantly(prepared)
            }
            return
        }

        Task {
            await prepareIngredientRowsLive()
        }
    }

    /// 先秒開清單（以 isBlocked 粗分區），再背景算完整警示快取。
    @MainActor
    private func applyItemsInstantly(_ items: [ScannedIngredientItem]) {
        orderedItems = items
        partitionUsingBlockedFlag(items)
        isPreparing = false
        Task {
            await rebuildAlertCache(for: items)
        }
    }

    @MainActor
    private func partitionUsingBlockedFlag(_ items: [ScannedIngredientItem]) {
        let blocked = items
            .filter(\.isBlocked)
            .sorted { $0.originalOrder < $1.originalOrder }
        let blockedIDs = Set(blocked.map(\.id))
        let matched = items
            .filter { !blockedIDs.contains($0.id) && $0.databaseItem != nil }
            .sorted { $0.originalOrder < $1.originalOrder }
        let unmatched = items
            .filter { !blockedIDs.contains($0.id) && $0.databaseItem == nil }
            .sorted { $0.originalOrder < $1.originalOrder }
        cachedBlockedItems = blocked
        cachedRegularItems = matched
        cachedUnmatchedItems = unmatched
        applyDefaultUnmatchedExpansionIfNeeded()
    }

    @MainActor
    private func rebuildAlertCache(for items: [ScannedIngredientItem]) async {
        let tags = blockedTags
        let custom = customBlockedIngredients
        let alerts = matchedAlerts
        let skinType = profile?.skinType ?? .combination
        let isSensitive = profile?.isSensitiveSkin ?? false
        let pairs = items.map { ($0.name, $0.databaseItem) }

        let report = await Task.detached(priority: .userInitiated) {
            IngredientAlertEngine.evaluate(
                items: pairs,
                blockedTags: tags,
                customBlockedIngredients: custom,
                matchedAlertMessages: alerts,
                skinType: skinType,
                isSensitiveSkin: isSensitive
            )
        }.value

        cachedAlertReport = report
        applyPartition(items: items, report: report)
    }

    @MainActor
    private func applyPartition(items: [ScannedIngredientItem], report: IngredientAlertReport) {
        let reconciled = items.map { item -> ScannedIngredientItem in
            var copy = item
            let fromToggleOrCustom = IngredientRiskEvaluator.isRiskWarning(
                name: item.name,
                databaseItem: item.databaseItem,
                blockedTags: blockedTags,
                customIngredients: customBlockedIngredients,
                alerts: []
            )
            let fromHighlight = report.annotation(forName: item.name, databaseItem: item.databaseItem)?.hasHighlightAlert == true
            copy.isBlocked = fromToggleOrCustom || fromHighlight
            return copy
        }
        orderedItems = reconciled
        let blocked = reconciled
            .filter(\.isBlocked)
            .sorted { lhs, rhs in
                let lp = report.annotation(forName: lhs.name, databaseItem: lhs.databaseItem)?.sortPriority ?? 8
                let rp = report.annotation(forName: rhs.name, databaseItem: rhs.databaseItem)?.sortPriority ?? 8
                if lp != rp { return lp < rp }
                return lhs.originalOrder < rhs.originalOrder
            }
        let blockedIDs = Set(blocked.map(\.id))
        let matched = reconciled
            .filter { !blockedIDs.contains($0.id) && $0.databaseItem != nil }
            .sorted { $0.originalOrder < $1.originalOrder }
        let unmatched = reconciled
            .filter { !blockedIDs.contains($0.id) && $0.databaseItem == nil }
            .sorted { $0.originalOrder < $1.originalOrder }
        cachedBlockedItems = blocked
        cachedRegularItems = matched
        cachedUnmatchedItems = unmatched
        applyDefaultUnmatchedExpansionIfNeeded()
    }

    @MainActor
    private func applyDefaultUnmatchedExpansionIfNeeded() {
        guard !didSetUnmatchedExpansion else { return }
        didSetUnmatchedExpansion = true
        unmatchedSectionExpanded = identifiedCount == 0 && !cachedUnmatchedItems.isEmpty
    }

    /// 僅用於尚無持久化快照的即時掃描預覽（非歷史開啟路徑）。
    @MainActor
    private func prepareIngredientRowsLive() async {
        isPreparing = true

        let rawIngredients = ingredients
        let alerts = matchedAlerts
        let tags = blockedTags
        let custom = customBlockedIngredients
        let skinType = profile?.skinType ?? .combination
        let isSensitive = profile?.isSensitiveSkin ?? false

        let bundle = await Task.detached(priority: .userInitiated) { () -> (items: [ScannedIngredientItem], report: IngredientAlertReport) in
            let prepared = PersistedScannedIngredient.buildSnapshots(
                ingredientNames: rawIngredients,
                matchedAlerts: alerts,
                blockedTags: tags,
                customBlockedIngredients: custom
            )
            let items = prepared.map {
                ScannedIngredientItem(
                    name: $0.name,
                    originalOrder: $0.originalOrder,
                    isBlocked: $0.isBlocked,
                    databaseItem: $0.databaseItem
                )
            }
            let report = IngredientAlertEngine.evaluate(
                items: items.map { ($0.name, $0.databaseItem) },
                blockedTags: tags,
                customBlockedIngredients: custom,
                matchedAlertMessages: alerts,
                skinType: skinType,
                isSensitiveSkin: isSensitive
            )
            return (items, report)
        }.value

        orderedItems = bundle.items
        cachedAlertReport = bundle.report
        applyPartition(items: bundle.items, report: bundle.report)
        isPreparing = false
    }

    // MARK: - Edit / Delete / Add

    private func beginEdit(_ item: ScannedIngredientItem) {
        editingItemID = item.id
        searchDraft = item.name
        activeSearchSheet = .edit(itemID: item.id)
    }

    private func beginAdd() {
        editingItemID = nil
        searchDraft = ""
        activeSearchSheet = .add
    }

    /// 弱辨識頁貼上官網文字重跑後，就地更新清單並寫回現有紀錄。
    @MainActor
    private func applyReanalyzedPayload(_ payload: ScanResultPayload) {
        guard !payload.ingredients.isEmpty else { return }

        let items: [ScannedIngredientItem]
        if !payload.resolvedIngredients.isEmpty {
            items = payload.resolvedIngredients.map { snap in
                ScannedIngredientItem(
                    name: snap.name,
                    originalOrder: snap.originalOrder,
                    isBlocked: snap.isBlocked,
                    databaseItem: snap.databaseItem
                )
            }
        } else {
            IngredientDatabaseManager.shared.ensureLoaded()
            items = payload.ingredients.enumerated().map { index, name in
                let hit = IngredientDatabaseManager.shared.lookup(ingredientName: name)
                let display = hit?.englishName ?? name
                return ScannedIngredientItem(
                    name: display,
                    originalOrder: index + 1,
                    isBlocked: IngredientRiskEvaluator.isRiskWarning(
                        name: display,
                        databaseItem: hit,
                        blockedTags: payload.blockedTags,
                        customIngredients: payload.customBlockedIngredients,
                        alerts: payload.matchedAlerts
                    ),
                    databaseItem: hit
                )
            }
        }
        applyItemsInstantly(items)
        persistCurrentList()
    }

    @discardableResult
    private func applyEdit(selected: IngredientItem? = nil) -> Bool {
        guard let editingItemID,
              let index = orderedItems.firstIndex(where: { $0.id == editingItemID }) else {
            return false
        }

        let resolved: IngredientItem?
        let displayName: String

        if let selected {
            resolved = selected
            displayName = selected.englishName
        } else {
            let trimmed = searchDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard trimmed.count >= 2 else { return false }

            IngredientDatabaseManager.shared.ensureLoaded()
            resolved = IngredientMatcher.matchToken(trimmed, logMiss: true)
            displayName = resolved?.englishName ?? trimmed
        }

        let isBlocked = IngredientRiskEvaluator.isRiskWarning(
            name: displayName,
            databaseItem: resolved,
            blockedTags: blockedTags,
            customIngredients: customBlockedIngredients,
            alerts: matchedAlerts
        )

        var updated = orderedItems[index]
        updated.name = displayName
        updated.databaseItem = resolved
        updated.isBlocked = isBlocked
        orderedItems[index] = updated
        self.editingItemID = nil
        activeSearchSheet = nil

        persistCurrentList()
        return true
    }

    private func deleteItems(from source: [ScannedIngredientItem], at offsets: IndexSet) {
        let ids = offsets.map { source[$0].id }
        orderedItems.removeAll { ids.contains($0.id) }
        renumberOrders()
        persistCurrentList()
    }

    @discardableResult
    private func applyAdd(selected: IngredientItem? = nil) -> Bool {
        let resolved: IngredientItem?
        let displayName: String

        if let selected {
            resolved = selected
            displayName = selected.englishName
        } else {
            let trimmed = searchDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard trimmed.count >= 2 else { return false }

            IngredientDatabaseManager.shared.ensureLoaded()
            resolved = IngredientMatcher.matchToken(trimmed, logMiss: true)
            displayName = resolved?.englishName ?? trimmed
        }

        let duplicateKey = displayName.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if orderedItems.contains(where: {
            ($0.databaseItem?.englishName ?? $0.name)
                .lowercased(with: Locale(identifier: "en_US_POSIX")) == duplicateKey
        }) {
            // 已在清單中：視為成功（關閉彈窗），不重複加入。
            activeSearchSheet = nil
            return true
        }

        let isBlocked = IngredientRiskEvaluator.isRiskWarning(
            name: displayName,
            databaseItem: resolved,
            blockedTags: blockedTags,
            customIngredients: customBlockedIngredients,
            alerts: matchedAlerts
        )
        let nextOrder = (orderedItems.map(\.originalOrder).max() ?? 0) + 1
        orderedItems.append(
            ScannedIngredientItem(
                name: displayName,
                originalOrder: nextOrder,
                isBlocked: isBlocked,
                databaseItem: resolved
            )
        )
        activeSearchSheet = nil
        persistCurrentList()
        return true
    }

    private func renumberOrders() {
        let sortedIDs = orderedItems
            .sorted { $0.originalOrder < $1.originalOrder }
            .map(\.id)
        for (index, id) in sortedIDs.enumerated() {
            guard let itemIndex = orderedItems.firstIndex(where: { $0.id == id }) else { continue }
            orderedItems[itemIndex].originalOrder = index + 1
        }
    }

    @MainActor
    private func commitProductNameEdit() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editableProductName = trimmed

        if let historyRecordID, !historyRecordID.isEmpty {
            ScanHistoryWriter.updateRecordTitle(
                recordID: historyRecordID,
                title: trimmed,
                in: modelContext
            )
            FavoriteManager.updateProductName(
                forScanRecordID: historyRecordID,
                name: trimmed,
                in: modelContext
            )
        }

        if let favoriteRecordID, !favoriteRecordID.isEmpty {
            FavoriteManager.updateProductName(
                recordID: favoriteRecordID,
                name: trimmed,
                in: modelContext
            )
        }
    }

    @MainActor
    private func persistCurrentList() {
        let names = orderedItems
            .sorted { $0.originalOrder < $1.originalOrder }
            .map { $0.databaseItem?.englishName ?? $0.name }

        let matched = IngredientMatcher.checkAlerts(
            detectedIngredients: names,
            blockedTags: blockedTags,
            customIngredients: customBlockedIngredients
        )

        for index in orderedItems.indices {
            let name = orderedItems[index].databaseItem?.englishName ?? orderedItems[index].name
            orderedItems[index].isBlocked = IngredientRiskEvaluator.isRiskWarning(
                name: name,
                databaseItem: orderedItems[index].databaseItem,
                blockedTags: blockedTags,
                customIngredients: customBlockedIngredients,
                alerts: matched
            )
        }

        let snapshots = orderedItems
            .sorted { $0.originalOrder < $1.originalOrder }
            .map {
                PersistedScannedIngredient(
                    name: $0.databaseItem?.englishName ?? $0.name,
                    originalOrder: $0.originalOrder,
                    isBlocked: $0.isBlocked,
                    databaseItem: $0.databaseItem
                )
            }

        if let historyRecordID, !historyRecordID.isEmpty {
            ScanHistoryWriter.updateRecognizedIngredients(
                recordID: historyRecordID,
                ingredients: names,
                matchedIngredients: matched,
                resolvedSnapshots: snapshots,
                in: modelContext
            )
        }

        if let favoriteRecordID, !favoriteRecordID.isEmpty {
            FavoriteManager.updateRecognizedIngredients(
                recordID: favoriteRecordID,
                ingredients: names,
                matchedIngredients: matched,
                resolvedSnapshots: snapshots,
                in: modelContext
            )
        }

        Task {
            await rebuildAlertCache(for: orderedItems)
        }
    }
}

/// 詳情列組裝工具：純字串處理，nonisolated 以免 Swift 6 在背景執行緒觸發 MainActor 警告。
private enum IngredientDetailRowBuilder {
    /// 保留既有 token；僅做空白正規化與去重，不重新切分。
    nonisolated static func normalizedDisplayTokens(from rawIngredients: [String]) -> [String] {
        var seen = Set<String>()
        var tokens: [String] = []

        for raw in rawIngredients {
            let trimmed = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard trimmed.count >= 2 else { continue }

            let key = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            tokens.append(trimmed)
        }
        return tokens
    }

    /// 風險警示區資格：與 `IngredientRiskEvaluator` 同一條規則。
    /// 未命中字典 → 永不進風險區；只跟避開開關與自訂清單走，不用字典 7–9 分自動上頂。
    nonisolated static func isRiskWarning(
        name: String,
        databaseItem: IngredientItem?,
        blockedTags: [String],
        customIngredients: [String],
        alerts: [String]
    ) -> Bool {
        IngredientRiskEvaluator.isRiskWarning(
            name: name,
            databaseItem: databaseItem,
            blockedTags: blockedTags,
            customIngredients: customIngredients,
            alerts: alerts
        )
    }

    nonisolated static func matchesAlert(name: String, alerts: [String]) -> Bool {
        IngredientRiskEvaluator.matchesAlert(name: name, alerts: alerts)
    }
}

/// 修正／新增共用搜尋 Sheet 的呈現模式。
private enum IngredientSearchPresentation: Identifiable, Equatable {
    case edit(itemID: UUID)
    case add

    var id: String {
        switch self {
        case .edit(let itemID):
            return "edit-\(itemID.uuidString)"
        case .add:
            return "add"
        }
    }

    var title: String {
        switch self {
        case .edit:
            return "修正成分"
        case .add:
            return "新增成分"
        }
    }
}

private struct ScannedIngredientItem: Identifiable, Sendable {
    let id: UUID
    var name: String
    var originalOrder: Int
    var isBlocked: Bool
    var databaseItem: IngredientItem?

    init(
        id: UUID = UUID(),
        name: String,
        originalOrder: Int,
        isBlocked: Bool,
        databaseItem: IngredientItem?
    ) {
        self.id = id
        self.name = name
        self.originalOrder = originalOrder
        self.isBlocked = isBlocked
        self.databaseItem = databaseItem
    }
}

private enum IngredientRowDisplayMode {
    case warning
    case remaining
}

private struct IngredientOrderNoteCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.muted)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("實體包裝排序說明")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.ink)

                Text("包裝上高於 1% 通常由高到低排；後面可能不按含量排。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum SafetyScoreStyle {
    static let badgeSize: CGFloat = 26
    static let scoreColumnWidth: CGFloat = 36
    static let orderColumnWidth: CGFloat = 28

    static func color(for score: Int?) -> Color {
        guard let score else {
            return Theme.muted.opacity(0.45)
        }
        switch score {
        case 1...2:
            return Theme.sage
        case 3...6:
            return Theme.gold
        case 7...9:
            return Theme.blush
        default:
            return Theme.muted.opacity(0.45)
        }
    }

    static func label(for score: Int?) -> String {
        guard let score else { return "-" }
        return "\(score)"
    }

    static func riskTitle(for score: Int?) -> String {
        guard let score else { return "暫無評級資料" }
        switch score {
        case 1...2:
            return "低風險"
        case 3...6:
            return "中度風險"
        case 7...9:
            return "高風險"
        default:
            return "暫無評級資料"
        }
    }

    static func riskSubtitle(for score: Int?) -> String {
        guard let score else { return "暫無評級資料" }
        switch score {
        case 1...2:
            return "刺激性低、致敏率低"
        case 3...6:
            return "視添加濃度與個人膚質耐受度而定"
        case 7...9:
            return "刺激性較高、易致敏或具爭議性成分"
        default:
            return "暫無評級資料"
        }
    }
}

private struct IngredientDetailRow: View {
    let item: ScannedIngredientItem
    let displayMode: IngredientRowDisplayMode
    var alertTags: [IngredientAlertTag] = []
    var skinReasons: [String] = []
    var onUnmatchedTap: (() -> Void)? = nil

    @State private var showSafetyExplanation = false

    private var score: Int? {
        item.databaseItem?.safetyScore
    }

    private var englishName: String {
        item.databaseItem?.englishName ?? item.name
    }

    private var chineseName: String? {
        guard let raw = item.databaseItem?.displayChineseName else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var functionTag: String? {
        item.databaseItem?.primaryFunctionTag
    }

    private var isUnmatched: Bool {
        item.databaseItem == nil
    }

    private var hasPersonalCustom: Bool {
        alertTags.contains { $0.kind == .personalCustom }
    }

    private var hasToggleRisk: Bool {
        alertTags.contains { $0.kind == .toggleRisk }
    }

    private var isHighlightAlert: Bool {
        hasPersonalCustom || hasToggleRisk || item.isBlocked
    }

    private var detailReasons: [String] {
        let alertReasons = alertTags.map(\.reason)
        return alertReasons.isEmpty ? skinReasons : alertReasons
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if displayMode == .remaining {
                Text("#\(item.originalOrder)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.muted.opacity(0.65))
                    .frame(width: SafetyScoreStyle.orderColumnWidth, alignment: .trailing)
            }

            Button {
                if isUnmatched, let onUnmatchedTap {
                    onUnmatchedTap()
                } else {
                    showSafetyExplanation = true
                }
            } label: {
                safetyBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isUnmatched ? "修正未命中成分" : "安心度說明")
            .frame(width: SafetyScoreStyle.scoreColumnWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(englishName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(isHighlightAlert ? Theme.blush : Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isHighlightAlert {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(hasPersonalCustom ? Theme.blush : Theme.gold)
                    }

                    if isUnmatched {
                        Text("點擊修正")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.accent.opacity(0.85))
                    }
                }

                if let chineseName, !chineseName.isEmpty {
                    Text(chineseName)
                        .font(.system(size: 15))
                        .foregroundColor(isHighlightAlert ? Theme.blush.opacity(0.85) : Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if isUnmatched {
                    Text("未收錄／辨識未中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.muted.opacity(0.85))
                        .lineLimit(1)
                }

                if !alertTags.isEmpty {
                    alertFlagTags
                }

                if displayMode == .warning {
                    concentrationHint
                }
            }
            .layoutPriority(0)
            .contentShape(Rectangle())
            .onTapGesture {
                if isUnmatched {
                    onUnmatchedTap?()
                } else if !detailReasons.isEmpty || item.databaseItem != nil {
                    showSafetyExplanation = true
                }
            }

            Spacer(minLength: 8)

            functionCapsule
                .layoutPriority(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            hasPersonalCustom
                ? Theme.blush.opacity(0.08)
                : (hasToggleRisk ? Theme.gold.opacity(0.08) : Color.clear),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    hasPersonalCustom
                        ? Theme.blush.opacity(0.55)
                        : (hasToggleRisk ? Theme.gold.opacity(0.50) : Color.clear),
                    lineWidth: (hasPersonalCustom || hasToggleRisk) ? 1.5 : 0
                )
        )
        .sheet(isPresented: $showSafetyExplanation) {
            SafetyScoreExplanationView(
                ingredientEnglishName: englishName,
                ingredientChineseName: chineseName,
                score: score,
                functionDescription: item.databaseItem?.fullFunctionDescription,
                skinReasons: detailReasons,
                aliases: item.databaseItem?.aliases ?? []
            )
            .presentationDetents([.fraction(detailReasons.isEmpty ? 0.61 : 0.72)])
            .presentationDragIndicator(.visible)
        }
    }

    private var alertFlagTags: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(alertTags) { tag in
                Text(tag.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color(for: tag.kind))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(background(for: tag.kind), in: Capsule())
                    .lineLimit(1)
            }
        }
    }

    private func color(for kind: IngredientAlertTag.Kind) -> Color {
        switch kind {
        case .personalCustom:
            return Theme.blush
        case .toggleRisk:
            return Theme.blush
        case .skinCaution:
            return Theme.gold
        case .skinFriendly:
            return Theme.sage
        case .traceNote:
            return Theme.muted.opacity(0.85)
        }
    }

    private func background(for kind: IngredientAlertTag.Kind) -> Color {
        switch kind {
        case .personalCustom:
            return Theme.blush.opacity(0.16)
        case .toggleRisk:
            return Theme.blush.opacity(0.14)
        case .skinCaution:
            return Theme.gold.opacity(0.16)
        case .skinFriendly:
            return Theme.sage.opacity(0.16)
        case .traceNote:
            return Theme.elevated.opacity(0.9)
        }
    }

    private var concentrationHint: some View {
        Group {
            if item.originalOrder <= 5 {
                Text("原包裝第 \(item.originalOrder) 項 · 主要成分區")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.gold)
            } else {
                Text("原包裝第 \(item.originalOrder) 項")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.muted)
            }
        }
        .lineLimit(1)
    }

    private var safetyBadge: some View {
        Text(SafetyScoreStyle.label(for: score))
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(score == nil ? Theme.muted : .white)
            .frame(width: SafetyScoreStyle.badgeSize, height: SafetyScoreStyle.badgeSize)
            .background(SafetyScoreStyle.color(for: score), in: Circle())
    }

    @ViewBuilder
    private var functionCapsule: some View {
        if isUnmatched {
            Text("未收錄")
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.cardStroke.opacity(0.95), in: Capsule())
        } else if let functionTag {
            Text(functionTag)
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.cardStroke.opacity(0.95), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("—")
                .font(.caption2)
                .foregroundColor(Theme.muted.opacity(0.55))
        }
    }
}

struct SafetyScoreExplanationView: View {
    let ingredientEnglishName: String
    let ingredientChineseName: String?
    let score: Int?
    /// 完整功能描述（未縮寫），例如「硬脂基氯化銨水輝石：增稠與懸浮穩定劑」。
    var functionDescription: String? = nil
    var skinReasons: [String] = []
    var aliases: [String] = []

    private var euHighlight: ModernEUSunscreenHighlight.Info? {
        ModernEUSunscreenHighlight.match(
            englishName: ingredientEnglishName,
            chineseName: ingredientChineseName,
            aliases: aliases
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sourceBanner
                        .padding(.top, 10)

                    currentRatingCard
                        .padding(.top, 12)

                    if let functionDescription, !functionDescription.isEmpty {
                        functionSection(functionDescription)
                            .padding(.top, 14)
                    }

                    if let euHighlight {
                        modernEUSunscreenCard(euHighlight)
                            .padding(.top, 14)
                    }

                    if !skinReasons.isEmpty {
                        skinCautionSection
                            .padding(.top, 14)
                    }

                    legendSection
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("此評級為公開資料與第三方指標彙整，供日常護膚辨識風險成分參考，非醫療診斷、治療建議或藥品規範標準。")
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 16) {
                            Link("EWG Skin Deep®", destination: LegalLinks.ewgSkinDeep)
                            Link("EU CosIng", destination: LegalLinks.euCosIng)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("安心度說明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func modernEUSunscreenCard(_ info: ModernEUSunscreenHighlight.Info) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(info.tradeLabel, systemImage: "sun.max.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.sage)

            Text("新型歐洲主流防曬成分")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.ink)

            Text(info.summary)
                .font(.caption)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sage.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.sage.opacity(0.22), lineWidth: 1)
        }
    }

    private func functionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("功能說明")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)

            Text(description)
                .font(.caption)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.elevated.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var skinCautionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("與您的膚質")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)

            ForEach(skinReasons, id: \.self) { reason in
                let isFriendly = isFriendlySkinReason(reason)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isFriendly ? "leaf.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(isFriendly ? Theme.sage : Theme.blush)
                        .padding(.top, 2)

                    Text(reason)
                        .font(.caption)
                        .foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isFriendly ? Theme.sage.opacity(0.10) : Theme.blush.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    private func isFriendlySkinReason(_ reason: String) -> Bool {
        if reason.contains("慎用") || reason.contains("注意") || reason.contains("致痘")
            || reason.contains("粉刺") || reason.contains("刺激") {
            return false
        }
        let markers = [
            "乾肌", "油肌", "敏弱", "友善", "推薦", "控油", "保濕", "修護", "屏障",
            "舒緩", "退紅", "抗老", "緊緻", "抗氧", "提亮", "胜肽", "滋潤", "皮脂", "淨化"
        ]
        return markers.contains { reason.contains($0) }
    }

    private var sourceBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("對照 EWG Skin Deep® 與國際化粧品成分資料", systemImage: "info.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.accent)

            HStack(spacing: 14) {
                Link("EWG Skin Deep®", destination: LegalLinks.ewgSkinDeep)
                Link("EU CosIng", destination: LegalLinks.euCosIng)
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var currentRatingCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(SafetyScoreStyle.label(for: score))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(score == nil ? Theme.muted : .white)
                .frame(width: 40, height: 40)
                .background(SafetyScoreStyle.color(for: score), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("當前成分評級")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)

                Text(ingredientEnglishName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)

                if let ingredientChineseName, !ingredientChineseName.isEmpty {
                    Text(ingredientChineseName)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }

                Text("\(SafetyScoreStyle.label(for: score)) · \(SafetyScoreStyle.riskTitle(for: score))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SafetyScoreStyle.color(for: score == nil ? nil : score))

                Text(SafetyScoreStyle.riskSubtitle(for: score))
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("燈號區間說明")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)

            legendRow(score: 1, title: "綠點 (1-2)", detail: "低風險（刺激性低、致敏率低）")
            legendRow(score: 4, title: "黃點 (3-6)", detail: "中度風險（視添加濃度與個人膚質耐受度而定）")
            legendRow(score: 8, title: "紅點 (7-9)", detail: "高風險（刺激性較高、易致敏或具爭議性成分）")
            legendRow(score: nil, title: "灰點 (-)", detail: "暫無評級資料")
        }
    }

    private func legendRow(score: Int?, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(SafetyScoreStyle.label(for: score))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(score == nil ? Theme.muted : .white)
                .frame(width: 24, height: 24)
                .background(SafetyScoreStyle.color(for: score), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct IngredientDetailListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            IngredientDetailListView(
                ingredients: [
                    "Water", "Glycerin", "Unknown OCR Fragment"
                ],
                matchedAlerts: [],
                blockedTags: ["denatured-alcohol", "artificial-fragrance"],
                customBlockedIngredients: [],
                productName: "未命名商品"
            )
        }
        .environmentObject(SubscriptionStore.shared)
    }
}
