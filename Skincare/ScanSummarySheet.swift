import SwiftUI
import SwiftData

/// 掃描來源：影響摘要彈窗是否顯示「加入最愛」與是否自動收藏。
enum ScanSource: String, Hashable, Sendable {
    case cameraTab
    case favorites
    case history
}

/// 貼上成分表成功後，在全螢幕關閉完才呈現的下一層畫面。
enum ScanPasteResultPresentation: Equatable {
    case avoidAlert
    case summarySheet
}

enum DeferredModalPresentation {
    /// 下一個 run loop 再 present，避免 sheet 掛在正在消失的 fullScreenCover 上變成空白白畫面。
    @MainActor
    static func afterCoverDismiss(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }
}

struct ScanResultPayload: Identifiable {
    let id = UUID()
    let imageData: Data?
    let ingredients: [String]
    let matchedAlerts: [String]
    let blockedTags: [String]
    let customBlockedIngredients: [String]
    let scannedAt: Date
    var historyRecordID: String?
    var source: ScanSource = .cameraTab
    /// 使用者在貼上／摘要輸入的品名；空字串則顯示預設「未命名商品」。
    var productName: String = ""
    /// 掃描當下已解析快照；開啟詳情時直接顯示。
    var resolvedIngredients: [PersistedScannedIngredient] = []
    /// Vision OCR 平均信心度；手動輸入為 `nil`。
    var averageOCRConfidence: Float? = nil
    /// Vision 辨識文字行數；手動輸入為 `nil`。
    var ocrLineCount: Int? = nil
    /// 參與多角度 OCR 的照片張數；單圖／手動為 1。
    var sourceImageCount: Int = 1

    var defaultProductName: String {
        ScanSummarySheet.defaultProductName(for: scannedAt)
    }

    /// 摘要／紀錄用的品名：有輸入就用輸入，否則未命名。
    var resolvedProductName: String {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultProductName : trimmed
    }

    /// 從我的最愛觸發：自動收藏，且摘要不顯示加入最愛按鈕。
    var isFromFavorites: Bool { source == .favorites }

    /// 字典命中的成分名。清單中另含未命中原字串（UI 標示「未收錄」供手動修正），
    /// 但辨識品質判斷只能看真正命中的部分，否則警示會被雜訊灌水而消失。
    var dictionaryHitNames: [String] {
        guard !resolvedIngredients.isEmpty else { return ingredients }
        return resolvedIngredients
            .filter { $0.databaseItem != nil }
            .map(\.name)
    }

    /// 已對上字典的項數；摘要／詳情主標題只顯示這個數字。
    var identifiedIngredientCount: Int { dictionaryHitNames.count }

    /// 貼上成分、全螢幕關閉後要接的畫面。nil 表示不跳結果（0 命中應留在貼上頁）。
    var pasteResultPresentation: ScanPasteResultPresentation? {
        guard identifiedIngredientCount > 0 else { return nil }
        return matchedAlerts.isEmpty ? .summarySheet : .avoidAlert
    }

    /// 仍保留在清單、但尚未對上字典的項數（灰色待確認）。
    var pendingUnmatchedCount: Int {
        resolvedIngredients.filter { $0.databaseItem == nil }.count
    }

    /// 辨識三態（依字典命中數）。
    var recognitionTier: RecognitionTier {
        RecognitionTier(count: dictionaryHitNames.count)
    }

    var isWeakRecognition: Bool { recognitionTier == .weak }

    /// 多圖循序重疊拼接（≥ 2 張）。
    var isMultiImageMerge: Bool { sourceImageCount > 1 }

    /// 漏字／反光風險（行數不成比例／偏少且無常見結尾／低信心度）。
    var incompletenessAssessment: OCRCompletenessHint.Assessment {
        OCRCompletenessHint.assess(
            ingredients: dictionaryHitNames,
            averageOCRConfidence: averageOCRConfidence,
            ocrLineCount: ocrLineCount
        )
    }

    var showsCompletenessHint: Bool {
        incompletenessAssessment.isAtRisk
    }

    var recognitionHintBannerKind: OCRCompletenessHint.BannerKind {
        incompletenessAssessment.bannerKind
    }
}

struct ScanSummarySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let payload: ScanResultPayload
    /// 點「完成」或關閉流程時回呼（例如最愛來源關閉外層 cover）。
    var onFinished: (() -> Void)? = nil
    /// 商品名稱改動時，讓外層同步更新暫存 payload，避免離開摘要後又跳回舊名。
    var onProductNameChanged: ((String) -> Void)? = nil
    /// 最愛來源：點「查看完整成分」時先關閉彈窗，由外層再推入詳情。
    var onViewIngredients: (() -> Void)? = nil
    /// 相機連續補拍：保留本次結果，關閉彈窗進入下一張拍攝。
    var onCaptureNextAngle: (() -> Void)? = nil

    @Query(sort: \FavoriteProductRecord.createdAt, order: .reverse)
    private var favoriteProducts: [FavoriteProductRecord]

    @Query private var profileList: [UserProfile]

    @State private var customProductName: String = ""
    @State private var didFavorite = false
    @State private var showFavoriteToast = false
    @State private var resolvedFavoriteRecordID: String?
    @State private var cachedAlertReport: IngredientAlertReport = .empty
    @State private var showPaywall = false

    private var favoritedScanIDs: Set<String> {
        FavoriteManager.favoritedSourceScanIDs(from: favoriteProducts)
    }

    private var profile: UserProfile? { profileList.first }

    private var alertReport: IngredientAlertReport { cachedAlertReport }

    private var showsFavoriteButton: Bool { !payload.isFromFavorites }
    private var usesExternalIngredientNavigation: Bool {
        payload.isFromFavorites && onViewIngredients != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sheetHeader
                        unifiedAlertSummaryBanner
                        compactSummaryCard
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showFavoriteToast {
                    VStack {
                        favoriteToast
                            .padding(.top, 8)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: payload.id) {
                await refreshAlertReport()
            }
            .onAppear {
                if customProductName.isEmpty {
                    customProductName = initialProductName()
                }
                notifyProductNameChanged()
                refreshFavoriteStateFromCache()
                if payload.isFromFavorites, !didFavorite {
                    addToFavorites(silent: true)
                }
            }
            .onDisappear {
                syncHistoryTitle()
                syncFavoriteTitleIfNeeded()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: .favorites)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    /// 僅保留右側「完成」，不與狀態膠囊搶標題列。
    private var sheetHeader: some View {
        HStack {
            Spacer()
            Button("完成") {
                finishAndDismiss()
            }
            .font(.body.weight(.semibold))
            .foregroundColor(Theme.accent)
        }
        .padding(.top, 4)
    }

    @MainActor
    private func refreshAlertReport() async {
        let skinType = profile?.skinType ?? .combination
        let isSensitive = profile?.isSensitiveSkin ?? false
        let blocked = payload.blockedTags
        let custom = payload.customBlockedIngredients
        let alerts = payload.matchedAlerts
        let snaps = payload.resolvedIngredients
        let names = payload.ingredients

        cachedAlertReport = await Task.detached(priority: .userInitiated) {
            if !snaps.isEmpty {
                return IngredientAlertEngine.evaluate(
                    items: snaps.map { ($0.name, $0.databaseItem) },
                    blockedTags: blocked,
                    customBlockedIngredients: custom,
                    matchedAlertMessages: alerts,
                    skinType: skinType,
                    isSensitiveSkin: isSensitive
                )
            }
            return IngredientAlertEngine.evaluate(
                ingredients: names,
                blockedTags: blocked,
                customBlockedIngredients: custom,
                matchedAlertMessages: alerts,
                skinType: skinType,
                isSensitiveSkin: isSensitive
            )
        }.value
    }

    /// 第一層：精簡結果卡片（不含全成分列表；狀態膠囊已移出避免與標題重疊）。
    private var compactSummaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("產品名稱")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)

                TextField("輸入產品名稱", text: $customProductName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.background.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.cardStroke, lineWidth: 1)
                    )
                    .onChange(of: customProductName) { _, _ in
                        syncHistoryTitle()
                        syncFavoriteTitleIfNeeded()
                        notifyProductNameChanged()
                    }
            }

            if showsFavoriteButton {
                Button(action: { addToFavorites(silent: false) }) {
                    Label(
                        didFavorite ? "已加入我的最愛" : "加入我的最愛",
                        systemImage: didFavorite ? "star.fill" : (subscriptionStore.isPremium ? "star" : "lock.fill")
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(didFavorite ? Theme.gold : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        didFavorite ? Theme.gold.opacity(0.16) : Theme.accent,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(didFavorite)
            }

            if usesExternalIngredientNavigation {
                Button {
                    syncHistoryTitle()
                    syncFavoriteTitleIfNeeded()
                    onViewIngredients?()
                    dismiss()
                } label: {
                    ingredientListButtonLabel
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    IngredientDetailListView(
                        ingredients: payload.ingredients,
                        matchedAlerts: payload.matchedAlerts,
                        blockedTags: payload.blockedTags,
                        customBlockedIngredients: payload.customBlockedIngredients,
                        productName: trimmedProductName,
                        historyRecordID: payload.historyRecordID,
                        favoriteRecordID: payload.isFromFavorites ? resolvedFavoriteRecordID : nil,
                        storedSnapshots: payload.resolvedIngredients,
                        recognitionTier: payload.recognitionTier,
                        scanSource: payload.source
                    )
                    .onAppear {
                        syncHistoryTitle()
                        syncFavoriteTitleIfNeeded()
                    }
                } label: {
                    ingredientListButtonLabel
                }
                .buttonStyle(.plain)
            }

            recognitionHintBanner
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var unifiedAlertSummaryBanner: some View {
        let report = alertReport
        return alertSummaryBannerContent(report: report)
    }

    private func alertSummaryBannerContent(report: IngredientAlertReport) -> some View {
        let tone = report.summaryTone
        let usesWhiteText = (tone == .personalCustom || tone == .toggleRisk)

        return HStack(spacing: 12) {
            Image(systemName: tone == .compatible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(summaryIconColor(tone))

            Text(report.summaryTitle)
                .font(.headline)
                .foregroundColor(usesWhiteText ? .white : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(summaryBackground(tone), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(summaryStroke(tone), lineWidth: 1)
        )
    }

    private func summaryIconColor(_ tone: IngredientAlertSummaryTone) -> Color {
        switch tone {
        case .personalCustom, .toggleRisk:
            return .white
        case .skinCaution:
            return Theme.gold
        case .compatible:
            return Theme.sage
        }
    }

    private func summaryBackground(_ tone: IngredientAlertSummaryTone) -> Color {
        switch tone {
        case .personalCustom:
            return Theme.blush.opacity(0.92)
        case .toggleRisk:
            return Theme.blush.opacity(0.90)
        case .skinCaution:
            return Theme.gold.opacity(0.18)
        case .compatible:
            return Theme.sage.opacity(0.14)
        }
    }

    private func summaryStroke(_ tone: IngredientAlertSummaryTone) -> Color {
        switch tone {
        case .personalCustom:
            return Theme.blush.opacity(0.4)
        case .toggleRisk:
            return Theme.blush.opacity(0.35)
        case .skinCaution:
            return Theme.gold.opacity(0.45)
        case .compatible:
            return Theme.sage.opacity(0.25)
        }
    }

    @ViewBuilder
    private var recognitionHintBanner: some View {
        switch payload.recognitionHintBannerKind {
        case .normalReference:
            normalReferenceHintBanner
        case .incompleteWarning:
            incompletenessWarningBanner
        }
    }

    private var normalReferenceHintBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 1.5)
            Text("辨識結果僅供參考，建議核對實體瓶身全成分。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .accessibilityLabel("辨識結果僅供參考，建議核對實體瓶身全成分")
    }

    private var incompletenessWarningBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)

                Text("辨識可能未完全")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()
            }

            if onCaptureNextAngle != nil, payload.sourceImageCount < ModernPhotoLoader.maxSelectionCount {
                Button {
                    onCaptureNextAngle?()
                    dismiss()
                } label: {
                    Label(
                        payload.sourceImageCount <= 1 ? "旋轉瓶身補拍第二張" : "旋轉瓶身補拍下一張",
                        systemImage: "camera.fill"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Color.white.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.gold.opacity(0.55), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("旋轉瓶身補拍第二張")
            }
        }
        .padding()
        .background(Theme.gold.opacity(0.14))
        .cornerRadius(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("辨識可能未完全")
    }

    private var ingredientListButtonTitle: String {
        let hits = payload.identifiedIngredientCount
        let pending = payload.pendingUnmatchedCount
        if hits == 0 {
            return pending > 0
                ? "查看可能未辨識項目（\(pending)）"
                : "查看完整成分清單"
        }
        return "查看已辨識成分（\(hits) 項）"
    }

    private var ingredientListButtonLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ingredientListButtonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.accent)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.accent)
            }
            if payload.pendingUnmatchedCount > 0, payload.identifiedIngredientCount > 0 {
                Text("另有 \(payload.pendingUnmatchedCount) 項待確認")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.muted)
            }
            if payload.isMultiImageMerge {
                Text("已融合 \(payload.sourceImageCount) 張照片角度")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var favoriteToast: some View {
        Label("已加入我的最愛", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.78), in: Capsule())
    }

    private var trimmedProductName: String {
        let trimmed = customProductName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? payload.resolvedProductName : trimmed
    }

    private func initialProductName() -> String {
        let fromPayload = payload.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromPayload.isEmpty { return fromPayload }
        if let recordID = payload.historyRecordID {
            let descriptor = FetchDescriptor<ScanHistoryRecordEntity>(
                predicate: #Predicate { $0.recordID == recordID }
            )
            if let title = try? modelContext.fetch(descriptor).first?.title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return payload.defaultProductName
    }

    static func defaultProductName(for _: Date = Date()) -> String {
        "未命名商品"
    }

    private func finishAndDismiss() {
        syncHistoryTitle()
        syncFavoriteTitleIfNeeded()
        notifyProductNameChanged()
        onFinished?()
        dismiss()
    }

    private func syncHistoryTitle() {
        guard let recordID = payload.historyRecordID else { return }
        ScanHistoryWriter.updateRecordTitle(
            recordID: recordID,
            title: trimmedProductName,
            in: modelContext
        )
    }

    private func syncFavoriteTitleIfNeeded() {
        guard payload.isFromFavorites || didFavorite,
              let scanID = payload.historyRecordID else { return }
        FavoriteManager.updateProductName(
            forScanRecordID: scanID,
            name: trimmedProductName,
            in: modelContext
        )
    }

    private func refreshFavoriteStateFromCache() {
        guard let scanID = payload.historyRecordID else {
            resolvedFavoriteRecordID = nil
            return
        }
        didFavorite = FavoriteManager.isFavorited(scanID, favoritedScanIDs: favoritedScanIDs)
        resolvedFavoriteRecordID = FavoriteManager.favoriteRecordID(
            forScanRecordID: scanID,
            in: favoriteProducts
        )
    }

    private func addToFavorites(silent: Bool) {
        syncHistoryTitle()
        notifyProductNameChanged()

        if !subscriptionStore.isPremium, !silent {
            showPaywall = true
            return
        }

        guard FavoriteManager.addFromPayload(payload, productName: trimmedProductName, in: modelContext) else {
            refreshFavoriteStateFromCache()
            return
        }

        didFavorite = true
        refreshFavoriteStateFromCache()

        guard !silent else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showFavoriteToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showFavoriteToast = false }
        }
    }

    private func notifyProductNameChanged() {
        onProductNameChanged?(trimmedProductName)
    }
}

/// 向後相容：舊名稱指向同一精簡結果彈窗。
struct ScanResultSheet: View {
    let payload: ScanResultPayload

    var body: some View {
        ScanSummarySheet(payload: payload)
    }
}

struct ScanCompleteBanner: View {
    let ingredientCount: Int
    let matchedCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: matchedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(matchedCount > 0 ? Theme.blush : Theme.sage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(matchedCount > 0 ? "發現風險成分" : "辨識完成")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("點擊查看掃描摘要（已辨識 \(ingredientCount) 項）")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

struct ScanSummarySheet_Previews: PreviewProvider {
    static var previews: some View {
        ScanSummarySheet(
            payload: ScanResultPayload(
                imageData: nil,
                ingredients: ["Water", "Alcohol Denat.", "Fragrance"],
                matchedAlerts: ["變性酒精（alcohol denat）"],
                blockedTags: ["denatured-alcohol"],
                customBlockedIngredients: [],
                scannedAt: Date(),
                source: .cameraTab
            )
        )
        .environmentObject(SubscriptionStore.shared)
        .modelContainer(SkincareModelContainer.preview)
    }
}
