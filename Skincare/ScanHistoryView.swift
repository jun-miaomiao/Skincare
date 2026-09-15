import SwiftUI
import SwiftData

struct ScanHistoryRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let scannedAt: String
    let summary: String
    let ingredientCount: Int
    let status: ScanHistoryStatus
    let isRead: Bool
}

enum ScanHistoryStatus: String, Hashable {
    case completed = "已完成"
    case processing = "辨識中"
    case failed = "辨識失敗"

    var tint: Color {
        switch self {
        case .completed: Theme.sage
        case .processing: Theme.gold
        case .failed: Theme.blush
        }
    }

    var icon: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .processing: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

enum ScanHistorySortFilter: String, CaseIterable, Identifiable {
    case newestFirst = "由新到舊排序"
    case oldestFirst = "由舊到新排序"
    case unreadOnly = "僅看未讀紀錄"

    var id: String { rawValue }
}

/// 手動貼上成分後推入詳情用的導航值。
private struct ManualIngredientRoute: Identifiable, Hashable {
    let id = UUID()
    let ingredients: [String]
    let matchedAlerts: [String]
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let productName: String
    let historyRecordID: String?
    let storedSnapshots: [PersistedScannedIngredient]
}

extension ScanHistoryRecordEntity {
    /// 與詳情頁「已辨識」一致：有快照時只計字典命中，不含灰色未收錄。
    var displayIdentifiedCount: Int {
        let snaps = resolvedIngredients
        if !snaps.isEmpty {
            return snaps.filter { $0.databaseItem != nil }.count
        }
        return ingredientCount
    }

    var displayModel: ScanHistoryRecord {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return ScanHistoryRecord(
            id: recordID,
            title: title,
            scannedAt: formatter.string(from: scannedAt),
            summary: summary,
            ingredientCount: displayIdentifiedCount,
            status: status,
            isRead: isRead
        )
    }
}

struct ScanHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var showPaywall = false

    @Query(sort: \ScanHistoryRecordEntity.scannedAt, order: .reverse)
    private var recordEntities: [ScanHistoryRecordEntity]

    @Query(sort: \FavoriteProductRecord.createdAt, order: .reverse)
    private var favoriteProducts: [FavoriteProductRecord]

    @State private var sortFilter: ScanHistorySortFilter = .newestFirst
    @State private var historyRefreshToken = UUID()
    @State private var showManualInput = false
    @State private var pendingManualPayload: ScanResultPayload?
    @State private var pendingManualRoute: ManualIngredientRoute?

    @State private var isSelecting = false
    @State private var selectedRecordIDs: Set<String> = []
    @State private var showDeleteSelectedConfirmation = false

    init() {}

    /// 記憶體快取：List Row 用 contains，絕不在渲染時 fetch。
    private var favoritedScanIDs: Set<String> {
        FavoriteManager.favoritedSourceScanIDs(from: favoriteProducts)
    }

    private var displayedRecords: [ScanHistoryRecordEntity] {
        switch sortFilter {
        case .newestFirst:
            return recordEntities.sorted { $0.scannedAt > $1.scannedAt }
        case .oldestFirst:
            return recordEntities.sorted { $0.scannedAt < $1.scannedAt }
        case .unreadOnly:
            return recordEntities
                .filter { !$0.isRead }
                .sorted { $0.scannedAt > $1.scannedAt }
        }
    }

    private var selectedCount: Int { selectedRecordIDs.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.background.ignoresSafeArea()
                ScanHistoryAmbientGlow()

                VStack(spacing: 0) {
                    titleHeader
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)

                    Group {
                        if recordEntities.isEmpty {
                            emptyState
                        } else if displayedRecords.isEmpty {
                            filteredEmptyState
                        } else {
                            recordList
                        }
                    }
                }

                if isSelecting, !recordEntities.isEmpty {
                    selectionActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 18)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "確定刪除所選的 \(selectedCount) 筆掃描紀錄？",
                isPresented: $showDeleteSelectedConfirmation,
                titleVisibility: .visible
            ) {
                Button("刪除所選項 (\(selectedCount))", role: .destructive) {
                    deleteSelectedRecords()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此動作無法復原。")
            }
            .fullScreenCover(isPresented: $showManualInput, onDismiss: {
                DeferredModalPresentation.afterCoverDismiss {
                    if let payload = pendingManualPayload {
                        pendingManualPayload = nil
                        openManualResult(payload)
                    }
                }
            }) {
                ManualInputView(source: .history) { payload in
                    pendingManualPayload = payload
                }
            }
            .navigationDestination(item: $pendingManualRoute) { route in
                IngredientDetailListView(
                    ingredients: route.ingredients,
                    matchedAlerts: route.matchedAlerts,
                    blockedTags: route.blockedTags,
                    customBlockedIngredients: route.customBlockedIngredients,
                    productName: route.productName,
                    historyRecordID: route.historyRecordID,
                    storedSnapshots: route.storedSnapshots
                )
            }
            .id(historyRefreshToken)
            .onAppear {
                DataBootstrap.seedIfNeeded(in: modelContext)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: .favorites)
            }
            .onReceive(NotificationCenter.default.publisher(for: .didClearScanHistory)) { _ in
                historyRefreshToken = UUID()
                exitSelectionMode()
            }
            .animation(.easeInOut(duration: 0.22), value: isSelecting)
        }
    }

    private var recordList: some View {
        List {
            ForEach(displayedRecords) { entity in
                Group {
                    if isSelecting {
                        Button {
                            toggleSelection(for: entity.recordID)
                        } label: {
                            ScanHistoryRow(
                                record: entity.displayModel,
                                matchedCount: entity.matchedIngredients.count,
                                isSelecting: true,
                                isSelected: selectedRecordIDs.contains(entity.recordID)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        ZStack(alignment: .leading) {
                            NavigationLink {
                                IngredientDetailListView(
                                    ingredients: entity.recognizedIngredients,
                                    matchedAlerts: entity.matchedIngredients,
                                    blockedTags: entity.blockedTags,
                                    customBlockedIngredients: [],
                                    productName: entity.title,
                                    historyRecordID: entity.recordID,
                                    storedSnapshots: entity.resolvedIngredients
                                )
                                .onAppear {
                                    markAsRead(entity)
                                }
                            } label: {
                                Color.clear
                            }
                            .opacity(0)
                            .accessibilityHidden(true)

                            ScanHistoryRow(
                                record: entity.displayModel,
                                matchedCount: entity.matchedIngredients.count
                            )
                            .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                guard subscriptionStore.isPremium else {
                                    showPaywall = true
                                    return
                                }
                                _ = FavoriteManager.addFromScanHistory(entity, in: modelContext)
                            } label: {
                                Label("最愛", systemImage: subscriptionStore.isPremium ? "star.fill" : "lock.fill")
                            }
                            .tint(.orange)
                            .disabled(FavoriteManager.isFavorited(entity.recordID, favoritedScanIDs: favoritedScanIDs))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteRecord(entity)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .compositingGroup()
                .listRowInsets(EdgeInsets(top: 7, leading: 22, bottom: 7, trailing: 22))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                Color.clear.frame(height: 72)
            }
        }
    }

    private var titleHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("掃描紀錄")
                .font(.largeTitle.bold())
                .foregroundColor(Theme.ink)

            sortFilterMenu

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button {
                    toggleSelectionMode()
                } label: {
                    Text(isSelecting ? "完成" : "選取")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Theme.ink.opacity(isSelecting ? 0.10 : 0.06),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(Theme.cardStroke.opacity(0.9), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(recordEntities.isEmpty && !isSelecting)
                .opacity(recordEntities.isEmpty && !isSelecting ? 0.45 : 1)
                .accessibilityLabel(isSelecting ? "完成選取" : "選取掃描紀錄")

                if !isSelecting {
                    Button {
                        showManualInput = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundColor(Theme.ink)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("貼上成分表")
                }
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Text(selectedCount == 0 ? "請勾選要刪除的商品" : "已選 \(selectedCount) 項")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.92))

            Spacer(minLength: 8)

            Button {
                showDeleteSelectedConfirmation = true
            } label: {
                Label("刪除所選項 (\(selectedCount))", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selectedCount == 0 ? Color.white.opacity(0.22) : Color.red.opacity(0.92),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.82), in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private func openManualResult(_ payload: ScanResultPayload) {
        guard payload.identifiedIngredientCount > 0 else { return }

        let title: String = {
            let fromPayload = payload.productName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fromPayload.isEmpty {
                return fromPayload
            }
            if let id = payload.historyRecordID {
                let descriptor = FetchDescriptor<ScanHistoryRecordEntity>(
                    predicate: #Predicate { $0.recordID == id }
                )
                if let entity = try? modelContext.fetch(descriptor).first {
                    return entity.title
                }
            }
            return payload.resolvedProductName
        }()

        let route = ManualIngredientRoute(
            ingredients: payload.ingredients,
            matchedAlerts: payload.matchedAlerts,
            blockedTags: payload.blockedTags,
            customBlockedIngredients: payload.customBlockedIngredients,
            productName: title,
            historyRecordID: payload.historyRecordID,
            storedSnapshots: payload.resolvedIngredients
        )

        if !payload.matchedAlerts.isEmpty {
            ScanAlertHaptics.triggerWarning()
        }

        pendingManualRoute = route
    }

    private var sortFilterMenu: some View {
        Menu {
            ForEach(ScanHistorySortFilter.allCases) { option in
                Button {
                    sortFilter = option
                } label: {
                    if sortFilter == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("排序與篩選")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(Theme.sage)
            Text("尚無掃描紀錄")
                .font(.headline)
                .foregroundColor(Theme.ink)
            Text("使用相機掃描，或點右上角「＋」貼上成分表。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.largeTitle)
                .foregroundColor(Theme.gold)
            Text("目前沒有未讀紀錄")
                .font(.headline)
                .foregroundColor(Theme.ink)
            Text("切換排序選單即可查看全部掃描紀錄。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelectionMode() {
        if isSelecting {
            exitSelectionMode()
        } else {
            isSelecting = true
            selectedRecordIDs = []
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedRecordIDs = []
    }

    private func toggleSelection(for recordID: String) {
        if selectedRecordIDs.contains(recordID) {
            selectedRecordIDs.remove(recordID)
        } else {
            selectedRecordIDs.insert(recordID)
        }
    }

    private func markAsRead(_ entity: ScanHistoryRecordEntity) {
        guard !entity.isRead else { return }
        entity.isRead = true
        try? modelContext.save()
    }

    private func deleteRecord(_ entity: ScanHistoryRecordEntity) {
        modelContext.delete(entity)
        selectedRecordIDs.remove(entity.recordID)
        try? modelContext.save()
    }

    private func deleteSelectedRecords() {
        let targets = recordEntities.filter { selectedRecordIDs.contains($0.recordID) }
        for entity in targets {
            modelContext.delete(entity)
        }
        try? modelContext.save()
        exitSelectionMode()
        historyRefreshToken = UUID()
    }
}

private struct ScanHistoryRow: View {
    let record: ScanHistoryRecord
    var matchedCount: Int = 0
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.medium))
                    .foregroundColor(isSelected ? Theme.accent : Theme.muted.opacity(0.7))
                    .padding(.top, 10)
                    .accessibilityLabel(isSelected ? "已選取" : "未選取")
            }

            Image(systemName: "doc.text.magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.muted)
                .frame(width: 44, height: 44)
                .background(Theme.cardStroke.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(record.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Circle()
                        .fill(record.isRead ? Color.clear : Color.red)
                        .frame(width: 14, height: 14)
                        .padding(.top, 2)
                        .accessibilityLabel(record.isRead ? "" : "未讀")
                        .accessibilityHidden(record.isRead)
                }

                Text(record.scannedAt)
                    .font(.caption)
                    .foregroundColor(Theme.muted)

                Text(ScanHistoryWriter.displaySummary(from: record.summary))
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if record.ingredientCount > 0 {
                    HStack(spacing: 8) {
                        Text("\(record.ingredientCount) 項成分")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(record.status.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(record.status.tint.opacity(0.12), in: Capsule())

                        if matchedCount > 0 {
                            Text("\(matchedCount) 項成分命中")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.blush, in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        // 實心底 + compositingGroup：避免 List 左滑時 material 模糊抽到鄰列而瞬間變形。
        .background(Theme.surface)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isSelecting && isSelected ? Theme.accent.opacity(0.45) : Theme.cardStroke,
                    lineWidth: isSelecting && isSelected ? 1.5 : 1
                )
        )
    }
}

private struct ScanHistoryAmbientGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: -110, y: -150)
            Circle()
                .fill(Theme.sage.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 130, y: 120)
        }
        .allowsHitTesting(false)
    }
}

struct ScanHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        ScanHistoryView()
            .environmentObject(SubscriptionStore.shared)
    }
}
