import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// 掃描完成後推入成分資訊用的導航值（Hashable + 預先算好顯示參數）。
private struct FavoriteScanDetailRoute: Identifiable, Hashable {
    let id = UUID()
    let ingredients: [String]
    let matchedAlerts: [String]
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let productName: String
    let historyRecordID: String?
    let favoriteRecordID: String?
    let storedSnapshots: [PersistedScannedIngredient]
    var recognitionTier: RecognitionTier? = nil
}

/// 相簿辨識完成、尚未命名儲存的暫存結果。
private struct PendingFavoriteScan: Identifiable {
    let id = UUID()
    let imageData: Data
    let result: ScanSessionResult
    let scannedAt: Date

    var defaultName: String {
        ScanSummarySheet.defaultProductName(for: scannedAt)
    }
}

enum FavoritesSortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "由新到舊排序"
    case oldestFirst = "由舊到新排序"

    var id: String { rawValue }
}

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query private var profileList: [UserProfile]

    @State private var selectedSegment: FavoritesSegment = .products
    @State private var sortOrder: FavoritesSortOrder = .newestFirst
    @State private var showScanActions = false
    @State private var showManualInput = false
    @State private var pendingManualPayload: ScanResultPayload?
    @State private var showPaywall = false

    /// 獨立狀態：拍照 vs 相簿，互不共用、不相牽連。
    @State private var isCameraPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isLegacyPhotoLibraryPresented = false
    @State private var libraryAlignSession: PhotoLibraryAlignSession?
    @State private var retryLibraryImages: [UIImage] = []

    @State private var isScanning = false
    @State private var scanningUsesMultiAngleCopy = false
    @State private var showScanSummarySheet = false
    @State private var latestScanPayload: ScanResultPayload?
    @State private var showAvoidAlert = false
    @State private var matchedAvoidItems: [String] = []
    @State private var showUnclearResult = false
    @State private var unclearPrompt: ScanUnclearPrompt = .noReadableText

    @State private var pendingOpenIngredientDetail = false
    /// 掃描後推入成分資訊（item-based，避免 isPresented + 空 destination 卡死）。
    @State private var ingredientDetailRoute: FavoriteScanDetailRoute?
    /// 貼上成分表完成後直接推入成分清單。
    @State private var pendingManualDetailRoute: FavoriteScanDetailRoute?

    /// 相簿流程：辨識完直接命名儲存，不經中間結果確認。
    @State private var pendingFavoriteScan: PendingFavoriteScan?
    @State private var showNameSaveSheet = false
    @State private var nameDraft = ""

    /// 保養成分分頁：搜尋字典後加入最愛。
    @State private var showIngredientSearchSheet = false
    @State private var ingredientSearchDraft = ""

    /// 多選刪除（規格與商品紀錄一致）。
    @State private var isSelecting = false
    @State private var selectedRecordIDs: Set<String> = []
    @State private var showDeleteSelectedConfirmation = false

    @Query(sort: \FavoriteProductRecord.createdAt, order: .reverse)
    private var productRecords: [FavoriteProductRecord]

    @Query(sort: \FavoriteIngredientRecord.createdAt, order: .reverse)
    private var ingredientRecords: [FavoriteIngredientRecord]

    private var currentRecordsEmpty: Bool {
        selectedSegment == .products ? productRecords.isEmpty : ingredientRecords.isEmpty
    }

    private var displayedProductRecords: [FavoriteProductRecord] {
        switch sortOrder {
        case .newestFirst:
            return productRecords.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return productRecords.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var displayedIngredientRecords: [FavoriteIngredientRecord] {
        switch sortOrder {
        case .newestFirst:
            return ingredientRecords.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return ingredientRecords.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private var selectedCount: Int { selectedRecordIDs.count }

    var body: some View {
        // 僅此頁使用 NavigationStack；其餘 Tab 仍走 CustomNavigationView（NavigationView）。
        NavigationStack {
            rootContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("新增辨識", isPresented: $showScanActions, titleVisibility: .visible) {
                    Button("拍照辨識") {
                        guard ensurePremiumForFavorites() else { return }
                        isCameraPresented = true
                    }
                    Button("從相簿選取") {
                        guard ensurePremiumForFavorites() else { return }
                        presentPhotoPickerOnly()
                    }
                    Button("貼上成分表") {
                        showManualInput = true
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("拍照與相簿寫入最愛需訂閱；貼上成分表可先免費分析。")
                }
                .confirmationDialog(
                    "確定刪除所選的 \(selectedCount) 筆收藏？",
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
                            handleManualInputResult(payload)
                        }
                    }
                }) {
                    ManualInputView(source: .favorites) { payload in
                        pendingManualPayload = payload
                    }
                }
                .fullScreenCover(isPresented: $isCameraPresented) {
                    FavoritesCameraCaptureView(
                        onCapturedPayload: { payload in
                            isCameraPresented = false
                            presentScanResult(payload)
                        },
                        onCancel: {
                            isCameraPresented = false
                        }
                    )
                }
                .sheet(isPresented: $showScanSummarySheet, onDismiss: handleSummaryDismissed) {
                    if let payload = latestScanPayload {
                        ScanSummarySheet(
                            payload: payload,
                            onFinished: {
                                pendingOpenIngredientDetail = false
                            },
                            onProductNameChanged: { updatedName in
                                latestScanPayload?.productName = updatedName
                            },
                            onViewIngredients: {
                                pendingOpenIngredientDetail = true
                            }
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    }
                }
                .sheet(isPresented: $showNameSaveSheet, onDismiss: handleNameSaveDismissed) {
                    FavoriteNameSaveSheet(
                        name: $nameDraft,
                        ingredientCount: pendingFavoriteScan?.result.dictionaryHitCount ?? 0,
                        matchedCount: pendingFavoriteScan?.result.matchedAlerts.count ?? 0,
                        onConfirm: {
                            savePendingFavoriteFromAlbum()
                        },
                        onCancel: {
                            pendingFavoriteScan = nil
                            showNameSaveSheet = false
                        }
                    )
                    .presentationDetents([.fraction(0.38), .medium])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showIngredientSearchSheet, onDismiss: {
                    ingredientSearchDraft = ""
                }) {
                    IngredientSearchSheet(
                        title: "加入最愛成分",
                        prompt: "搜尋成分（中文或英文）",
                        text: $ingredientSearchDraft,
                        onComplete: {
                            addFavoriteIngredientFromDraft()
                        },
                        onSelect: { item in
                            _ = FavoriteManager.addIngredient(item, in: modelContext)
                            return true
                        }
                    )
                }
                .fullScreenCover(isPresented: $isLegacyPhotoLibraryPresented) {
                    #if os(iOS)
                    PhotoLibraryPickerView(
                        cropsToIngredientBand: false,
                        onCapture: { data in
                            isLegacyPhotoLibraryPresented = false
                            if let image = UIImage(data: data) {
                                libraryAlignSession = PhotoLibraryAlignSession(images: [image])
                            }
                        },
                        onCancel: {
                            isLegacyPhotoLibraryPresented = false
                        }
                    )
                    .ignoresSafeArea()
                    #endif
                }
                .fullScreenCover(item: $libraryAlignSession) { session in
                    #if os(iOS)
                    PhotoLibraryFrameAlignFlow(
                        images: session.images,
                        onComplete: { dataList in
                            retryLibraryImages = session.images
                            libraryAlignSession = nil
                            Task { await processImages(dataList, originals: session.images) }
                        },
                        onCancel: {
                            libraryAlignSession = nil
                        }
                    )
                    #endif
                }
                .onAppear {
                    DataBootstrap.seedIfNeeded(in: modelContext)
                }
                .sheet(isPresented: $showPaywall) {
                    PaywallView(reason: .favorites)
                }
                .modifier(
                    FavoritesPhotosPickerModifier(
                        isPresented: $isPhotoPickerPresented,
                        onPickedImages: { images in
                            libraryAlignSession = PhotoLibraryAlignSession(images: images)
                        }
                    )
                )
                .navigationDestination(item: $ingredientDetailRoute) { route in
                    IngredientDetailListView(
                        ingredients: route.ingredients,
                        matchedAlerts: route.matchedAlerts,
                        blockedTags: route.blockedTags,
                        customBlockedIngredients: route.customBlockedIngredients,
                        productName: route.productName,
                        historyRecordID: route.historyRecordID,
                        favoriteRecordID: route.favoriteRecordID,
                        storedSnapshots: route.storedSnapshots,
                        recognitionTier: route.recognitionTier,
                        scanSource: .favorites
                    )
                }
                .navigationDestination(item: $pendingManualDetailRoute) { route in
                    IngredientDetailListView(
                        ingredients: route.ingredients,
                        matchedAlerts: route.matchedAlerts,
                        blockedTags: route.blockedTags,
                        customBlockedIngredients: route.customBlockedIngredients,
                        productName: route.productName,
                        historyRecordID: route.historyRecordID,
                        favoriteRecordID: route.favoriteRecordID,
                        storedSnapshots: route.storedSnapshots,
                        recognitionTier: route.recognitionTier,
                        scanSource: .favorites
                    )
                }
                .onChange(of: selectedSegment) { _, _ in
                    exitSelectionMode()
                }
                .animation(.easeInOut(duration: 0.22), value: isSelecting)
        }
    }

    private var rootContent: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            FavoritesAmbientGlow()

            VStack(spacing: 0) {
                titleHeader
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                segmentPicker
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .disabled(isSelecting)
                    .opacity(isSelecting ? 0.55 : 1)

                Group {
                    if selectedSegment == .products {
                        FavoriteProductsPage(
                            records: displayedProductRecords,
                            isSelecting: isSelecting,
                            selectedRecordIDs: $selectedRecordIDs,
                            onDelete: deleteProducts
                        )
                    } else {
                        FavoriteIngredientsPage(
                            records: displayedIngredientRecords,
                            isSelecting: isSelecting,
                            selectedRecordIDs: $selectedRecordIDs,
                            onDelete: deleteIngredients
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 僅在真正顯示時掛上遮罩，避免透明層攔截手勢。
            if isScanning {
                scanningOverlay
            }

            if showAvoidAlert {
                IngredientAvoidAlertOverlay(
                    matchedItems: matchedAvoidItems,
                    onViewDetails: {
                        showAvoidAlert = false
                        showScanSummarySheet = true
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAvoidAlert = false
                        }
                        latestScanPayload = nil
                    }
                )
            }

            if showUnclearResult {
                ScanUnclearResultOverlay(
                    prompt: unclearPrompt,
                    onManualInput: {
                        showUnclearResult = false
                        pendingFavoriteScan = nil
                        showManualInput = true
                    },
                    onRetake: {
                        showUnclearResult = false
                        pendingFavoriteScan = nil
                        if let session = PhotoLibraryAlignSession(images: retryLibraryImages) {
                            libraryAlignSession = session
                        } else {
                            isPhotoPickerPresented = true
                        }
                    },
                    onViewPartialResults: {
                        showUnclearResult = false
                        if pendingFavoriteScan != nil {
                            nameDraft = pendingFavoriteScan?.defaultName ?? ""
                            showNameSaveSheet = true
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showUnclearResult = false
                        }
                        pendingFavoriteScan = nil
                    }
                )
            }

            if isSelecting, !currentRecordsEmpty {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        }
    }

    private var titleHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("我的最愛")
                .font(.largeTitle.bold())
                .foregroundColor(Theme.ink)

            sortOrderMenu

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
                .disabled(currentRecordsEmpty && !isSelecting)
                .opacity(currentRecordsEmpty && !isSelecting ? 0.45 : 1)
                .accessibilityLabel(isSelecting ? "完成選取" : "選取收藏項目")

                if !isSelecting {
                    Button {
                        handlePlusTapped()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundColor(Theme.ink)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedSegment == .products ? "新增保養品辨識" : "新增最愛成分")
                }
            }
        }
    }

    private var sortOrderMenu: some View {
        Menu {
            ForEach(FavoritesSortOrder.allCases) { option in
                Button {
                    sortOrder = option
                } label: {
                    if sortOrder == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("排序")
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Text(selectedCount == 0 ? "請勾選要刪除的收藏" : "已選 \(selectedCount) 項")
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

    private var segmentPicker: some View {
        Picker("收藏類型", selection: $selectedSegment) {
            ForEach(FavoritesSegment.allCases) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text(scanningUsesMultiAngleCopy ? "正在分析多角度圖片..." : "辨識成分中...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func presentPhotoPickerOnly() {
        // 僅開相簿，絕不啟動相機 Session / Cover
        isCameraPresented = false
        isPhotoPickerPresented = true
    }

    private func ensurePremiumForFavorites() -> Bool {
        if subscriptionStore.isPremium { return true }
        showPaywall = true
        return false
    }

    private func handlePlusTapped() {
        switch selectedSegment {
        case .products:
            showScanActions = true
        case .ingredients:
            guard ensurePremiumForFavorites() else { return }
            ingredientSearchDraft = ""
            showIngredientSearchSheet = true
        }
    }

    @discardableResult
    private func addFavoriteIngredientFromDraft() -> Bool {
        let trimmed = ingredientSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        IngredientDatabaseManager.shared.ensureLoaded()
        if let item = IngredientDatabaseManager.shared.lookup(ingredientName: trimmed) {
            _ = FavoriteManager.addIngredient(item, in: modelContext)
            return true
        }

        _ = FavoriteManager.addIngredient(
            ingredientID: trimmed.lowercased(),
            chineseName: trimmed,
            englishName: trimmed,
            in: modelContext
        )
        return true
    }

    private func handleSummaryDismissed() {
        isCameraPresented = false
        isPhotoPickerPresented = false
        showAvoidAlert = false

        if pendingOpenIngredientDetail, let payload = latestScanPayload {
            pendingOpenIngredientDetail = false
            ingredientDetailRoute = makeDetailRoute(from: payload)
        } else {
            pendingOpenIngredientDetail = false
            latestScanPayload = nil
            selectedSegment = .products
        }
    }

    private func makeDetailRoute(from payload: ScanResultPayload) -> FavoriteScanDetailRoute {
        FavoriteScanDetailRoute(
            ingredients: payload.ingredients,
            matchedAlerts: payload.matchedAlerts,
            blockedTags: payload.blockedTags,
            customBlockedIngredients: payload.customBlockedIngredients,
            productName: favoriteDisplayName(for: payload),
            historyRecordID: payload.historyRecordID,
            favoriteRecordID: FavoriteManager.favoriteRecordID(
                forScanRecordID: payload.historyRecordID,
                in: productRecords
            ),
            storedSnapshots: payload.resolvedIngredients,
            recognitionTier: payload.recognitionTier
        )
    }

    private func presentScanResult(_ payload: ScanResultPayload) {
        latestScanPayload = payload
        matchedAvoidItems = payload.matchedAlerts
        selectedSegment = .products

        if !payload.matchedAlerts.isEmpty {
            ScanAlertHaptics.triggerWarning()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showAvoidAlert = true
            }
        } else {
            showScanSummarySheet = true
        }
    }

    /// 手動貼上：寫入最愛後直接進入成分清單（與拍照相同的安全標示／字典）。
    private func handleManualInputResult(_ payload: ScanResultPayload) {
        selectedSegment = .products

        guard payload.identifiedIngredientCount > 0 else { return }

        // 貼上可免費看結果；寫入最愛需訂閱。
        if !subscriptionStore.isPremium {
            var freeView = payload
            freeView.source = .history
            presentScanResult(freeView)
            return
        }

        let resolvedName: String = {
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

        _ = FavoriteManager.addFromPayload(payload, productName: resolvedName, in: modelContext)
        let favoriteID = FavoriteManager.favoriteRecordID(
            forScanRecordID: payload.historyRecordID,
            in: modelContext
        )

        let route = FavoriteScanDetailRoute(
            ingredients: payload.ingredients,
            matchedAlerts: payload.matchedAlerts,
            blockedTags: payload.blockedTags,
            customBlockedIngredients: payload.customBlockedIngredients,
            productName: resolvedName,
            historyRecordID: payload.historyRecordID,
            favoriteRecordID: favoriteID,
            storedSnapshots: payload.resolvedIngredients,
            recognitionTier: payload.recognitionTier
        )

        if !payload.matchedAlerts.isEmpty {
            ScanAlertHaptics.triggerWarning()
        }

        pendingManualDetailRoute = route
    }

    private func favoriteDisplayName(for payload: ScanResultPayload) -> String {
        let fromPayload = payload.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromPayload.isEmpty {
            return fromPayload
        }
        return FavoriteManager.favoriteDisplayName(
            forScanRecordID: payload.historyRecordID,
            in: productRecords
        ) ?? payload.defaultProductName
    }

    @MainActor
    private func processImages(_ dataList: [Data], originals: [UIImage] = []) async {
        guard let primary = dataList.first else { return }
        // 相簿選擇器已關閉；略過中間結果／風險確認，辨識完直接命名。
        isPhotoPickerPresented = false
        isLegacyPhotoLibraryPresented = false
        scanningUsesMultiAngleCopy = dataList.count > 1
        isScanning = true
        showAvoidAlert = false
        showScanSummarySheet = false
        showNameSaveSheet = false
        pendingFavoriteScan = nil

        let profile = profileList.first
        let result: ScanSessionResult
        if originals.isEmpty {
            result = await ScanSessionProcessor.analyze(imageDataList: dataList, profile: profile)
        } else {
            result = await ScanSessionProcessor.analyzeAlignedLibraryPhotos(
                croppedJPEG: dataList,
                originalImages: originals,
                profile: profile
            )
        }

        isScanning = false
        scanningUsesMultiAngleCopy = false
        selectedSegment = .products

        guard !result.needsCaptureRetake else {
            pendingFavoriteScan = nil
            showNameSaveSheet = false
            if result.dictionaryHitCount > 0 {
                pendingFavoriteScan = PendingFavoriteScan(
                    imageData: primary,
                    result: result,
                    scannedAt: Date()
                )
                nameDraft = pendingFavoriteScan?.defaultName ?? ""
            }
            unclearPrompt = result.ingredients.isEmpty
                ? .noReadableText
                : .lowCaptureQuality(identifiedCount: result.dictionaryHitCount)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showUnclearResult = true
            }
            return
        }

        let pending = PendingFavoriteScan(
            imageData: primary,
            result: result,
            scannedAt: Date()
        )

        pendingFavoriteScan = pending
        nameDraft = pending.defaultName
        showNameSaveSheet = true
    }

    private func handleNameSaveDismissed() {
        // 若未儲存就關閉，丟棄暫存（不寫入 SwiftData）。
        if pendingFavoriteScan != nil {
            pendingFavoriteScan = nil
        }
        nameDraft = ""
    }

    private func savePendingFavoriteFromAlbum() {
        guard let pending = pendingFavoriteScan else { return }
        guard ensurePremiumForFavorites() else { return }

        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let productName = trimmed.isEmpty ? pending.defaultName : trimmed

        let saved = ScanSessionProcessor.persist(
            result: pending.result,
            imageData: pending.imageData,
            in: modelContext,
            title: productName
        )
        guard let saved else {
            pendingFavoriteScan = nil
            showNameSaveSheet = false
            nameDraft = ""
            return
        }

        let payload = ScanResultPayload(
            imageData: pending.imageData,
            ingredients: pending.result.ingredients,
            matchedAlerts: pending.result.matchedAlerts,
            blockedTags: pending.result.blockedTags,
            customBlockedIngredients: pending.result.customBlockedIngredients,
            scannedAt: saved.scannedAt,
            historyRecordID: saved.recordID,
            source: .favorites,
            resolvedIngredients: saved.resolvedIngredients,
            averageOCRConfidence: pending.result.averageOCRConfidence,
            ocrLineCount: pending.result.ocrLineCount,
            sourceImageCount: pending.result.sourceImageCount
        )

        _ = FavoriteManager.addFromPayload(payload, productName: productName, in: modelContext)

        pendingFavoriteScan = nil
        showNameSaveSheet = false
        selectedSegment = .products
        nameDraft = ""
    }

    private func deleteProducts(at offsets: IndexSet) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for index in offsets {
                modelContext.delete(productRecords[index])
            }
            try? modelContext.save()
        }
    }

    private func deleteIngredients(at offsets: IndexSet) {
        withAnimation(.easeInOut(duration: 0.25)) {
            for index in offsets {
                modelContext.delete(ingredientRecords[index])
            }
            try? modelContext.save()
        }
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

    private func deleteSelectedRecords() {
        let ids = selectedRecordIDs
        guard !ids.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.28)) {
            if selectedSegment == .products {
                for record in productRecords where ids.contains(record.recordID) {
                    modelContext.delete(record)
                }
            } else {
                for record in ingredientRecords where ids.contains(record.recordID) {
                    modelContext.delete(record)
                }
            }
            try? modelContext.save()
            exitSelectionMode()
        }
    }
}

// MARK: - 相簿辨識後命名儲存

private struct FavoriteNameSaveSheet: View {
    @Binding var name: String
    let ingredientCount: Int
    let matchedCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("產品名稱")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.muted)

                    TextField("輸入產品名稱", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.background.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.cardStroke, lineWidth: 1)
                        )
                }

                HStack(spacing: 8) {
                    Label("\(ingredientCount) 項成分", systemImage: "list.bullet")
                    if matchedCount > 0 {
                        Label("\(matchedCount) 項風險", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.blush)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

                Button {
                    onConfirm()
                } label: {
                    Text("確認儲存")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            canSave ? Theme.accent : Theme.muted.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("儲存至我的最愛")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Photos-only picker（不碰相機）

private struct FavoritesPhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPickedImages: ([UIImage]) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(
                ModernPhotosPickerModifier(
                    isPresented: $isPresented,
                    maxSelectionCount: ModernPhotoLoader.maxSelectionCount,
                    onPickedImages: onPickedImages
                )
            )
    }
}

private struct FavoriteProductsPage: View {
    let records: [FavoriteProductRecord]
    var isSelecting: Bool = false
    @Binding var selectedRecordIDs: Set<String>
    let onDelete: (IndexSet) -> Void

    @State private var routinePickerRecordID: String?

    var body: some View {
        Group {
            if records.isEmpty {
                FavoriteEmptyState(
                    systemImage: "shippingbox",
                    title: "尚無收藏保養品"
                )
            } else {
                List {
                    ForEach(records) { record in
                        Group {
                            if isSelecting {
                                Button {
                                    toggleSelection(record.recordID)
                                } label: {
                                    CompactFavoriteProductCard(
                                        record: record,
                                        isSelecting: true,
                                        isSelected: selectedRecordIDs.contains(record.recordID)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ZStack(alignment: .leading) {
                                    NavigationLink {
                                        FavoriteDetailView(record: record)
                                    } label: {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                    .accessibilityHidden(true)

                                    CompactFavoriteProductCard(record: record)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(Rectangle())
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    routinePickerRecordID = record.recordID
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteRecord(record)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 7, leading: 22, bottom: 7, trailing: 22))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .safeAreaInset(edge: .bottom) {
                    if isSelecting {
                        Color.clear.frame(height: 72)
                    }
                }
                .confirmationDialog(
                    "設定使用時段",
                    isPresented: routinePickerPresented,
                    titleVisibility: .visible
                ) {
                    Button("早上") {
                        setRoutineSlot("morning")
                    }
                    Button("晚上") {
                        setRoutineSlot("evening")
                    }
                    if let record = routinePickerRecord, record.routineSlotBadgeText != nil {
                        Button("清除時段", role: .destructive) {
                            setRoutineSlot("")
                        }
                    }
                    Button("取消", role: .cancel) {
                        routinePickerRecordID = nil
                    }
                } message: {
                    Text("標記此保養品用於早上或晚上保養")
                }
            }
        }
    }

    private var routinePickerPresented: Binding<Bool> {
        Binding(
            get: { routinePickerRecordID != nil },
            set: { if !$0 { routinePickerRecordID = nil } }
        )
    }

    private var routinePickerRecord: FavoriteProductRecord? {
        guard let id = routinePickerRecordID else { return nil }
        return records.first { $0.recordID == id }
    }

    private func setRoutineSlot(_ raw: String) {
        guard let record = routinePickerRecord else { return }
        record.routineSlotRaw = raw
        routinePickerRecordID = nil
    }

    private func toggleSelection(_ id: String) {
        if selectedRecordIDs.contains(id) {
            selectedRecordIDs.remove(id)
        } else {
            selectedRecordIDs.insert(id)
        }
    }

    private func deleteRecord(_ record: FavoriteProductRecord) {
        guard let index = records.firstIndex(where: { $0.recordID == record.recordID }) else { return }
        onDelete(IndexSet(integer: index))
    }
}

private struct FavoriteIngredientsPage: View {
    let records: [FavoriteIngredientRecord]
    var isSelecting: Bool = false
    @Binding var selectedRecordIDs: Set<String>
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Group {
            if records.isEmpty {
                FavoriteEmptyState(
                    systemImage: "star",
                    title: "尚無收藏成分"
                )
            } else {
                List {
                    ForEach(records) { record in
                        if let item = record.displayItem() {
                            Group {
                                if isSelecting {
                                    Button {
                                        toggleSelection(record.recordID)
                                    } label: {
                                        FavoriteIngredientSelectableRow(
                                            ingredient: item.ingredient,
                                            isSelected: selectedRecordIDs.contains(record.recordID)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    ZStack(alignment: .leading) {
                                        NavigationLink {
                                            IngredientDetailView(ingredient: item.ingredient)
                                        } label: {
                                            EmptyView()
                                        }
                                        .opacity(0)
                                        .accessibilityHidden(true)

                                        IngredientCard(ingredient: item.ingredient)
                                            .allowsHitTesting(false)
                                    }
                                    .contentShape(Rectangle())
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteRecord(record)
                                        } label: {
                                            Label("刪除", systemImage: "trash")
                                        }
                                        .tint(.red)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 7, leading: 22, bottom: 7, trailing: 22))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .safeAreaInset(edge: .bottom) {
                    if isSelecting {
                        Color.clear.frame(height: 72)
                    }
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedRecordIDs.contains(id) {
            selectedRecordIDs.remove(id)
        } else {
            selectedRecordIDs.insert(id)
        }
    }

    private func deleteRecord(_ record: FavoriteIngredientRecord) {
        guard let index = records.firstIndex(where: { $0.recordID == record.recordID }) else { return }
        onDelete(IndexSet(integer: index))
    }
}

private struct FavoriteIngredientSelectableRow: View {
    let ingredient: Ingredient
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.medium))
                .foregroundColor(isSelected ? Theme.accent : Theme.muted.opacity(0.7))
                .padding(.top, 18)
                .accessibilityLabel(isSelected ? "已選取" : "未選取")

            IngredientCard(ingredient: ingredient)
        }
    }
}

private struct CompactFavoriteProductCard: View {
    let record: FavoriteProductRecord
    var isSelecting: Bool = false
    var isSelected: Bool = false

    private var accent: Color {
        Color.safeRGB(red: record.accentRed, green: record.accentGreen, blue: record.accentBlue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.medium))
                    .foregroundColor(isSelected ? Theme.accent : Theme.muted.opacity(0.7))
                    .padding(.top, 12)
                    .accessibilityLabel(isSelected ? "已選取" : "未選取")
            }

            HStack(alignment: .top, spacing: 16) {
                leadingBadge

                VStack(alignment: .leading, spacing: 8) {
                    Text(record.name)
                        .font(.system(.title3, design: .serif).weight(.medium))
                        .foregroundColor(Theme.ink)
                        .lineLimit(2)

                    Text("\(record.formattedCreatedAt) · \(record.displayIngredientCount) 項成分")
                        .font(.caption)
                        .foregroundColor(Theme.muted)

                    if record.hasAvoidWarnings {
                        Label("含風險成分", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.blush, in: Capsule())
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        isSelecting && isSelected ? Theme.accent.opacity(0.45) : Theme.cardStroke,
                        lineWidth: isSelecting && isSelected ? 1.5 : 1
                    )
            )
            .shadow(color: accent.opacity(0.12), radius: 18, y: 10)
        }
    }

    /// 左側 48×48 方框保留；未設時段顯示星星／警示，已設則顯示「早」或「晚」。
    private var leadingBadge: some View {
        let warning = record.hasAvoidWarnings
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(warning ? Theme.blush : accent.opacity(0.16))

            if let slot = record.routineSlotBadgeText {
                Text(slot)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(warning ? .white : accent)
            } else {
                Image(systemName: warning ? "exclamationmark.triangle.fill" : "star.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(warning ? .white : accent)
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityLabel(leadingAccessibilityLabel)
    }

    private var leadingAccessibilityLabel: String {
        if let slot = record.routineSlotBadgeText {
            return slot == "早" ? "早上保養" : "晚上保養"
        }
        return record.hasAvoidWarnings ? "含風險成分" : "最愛保養品"
    }
}

private struct FavoriteEmptyState: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(Theme.gold)
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.ink)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 48)
    }
}

private struct FavoritesAmbientGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: -100, y: -160)
            Circle()
                .fill(Theme.sage.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 120, y: 100)
        }
        .allowsHitTesting(false)
    }
}

struct FavoritesView_Previews: PreviewProvider {
    static var previews: some View {
        FavoritesView()
            .modelContainer(SkincareModelContainer.preview)
    }
}
