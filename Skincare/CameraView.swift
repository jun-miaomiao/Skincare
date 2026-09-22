import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct CameraView: View {
    /// 僅在相機真正顯示時為 true，用來啟動／暫停 session。
    var isActive: Bool = true
    /// 從貼上頁打開時不再放第二個貼上入口。
    var showsPasteButton: Bool = true
    /// 以全螢幕蓋上時顯示關閉，才能回到貼上頁。
    var allowsDismiss: Bool = false

    var body: some View {
        #if os(iOS)
        CameraViewIOS(
            isActive: isActive,
            showsPasteButton: showsPasteButton,
            allowsDismiss: allowsDismiss
        )
        #else
        CameraUnavailableView(
            title: "相機僅支援 iOS 裝置",
            message: "請在 iPhone 上使用相機掃描成分表。"
        )
        #endif
    }
}

#if os(iOS)
private struct CameraViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scanLaunch: ScanLaunchBridge
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query private var profileList: [UserProfile]

    var isActive: Bool
    var showsPasteButton: Bool
    var allowsDismiss: Bool

    @StateObject private var camera = CameraController()
    @State private var scannedImageData: Data?
    @State private var isScanning = false
    /// 多張相簿選取時顯示「正在分析多角度圖片...」
    @State private var scanningUsesMultiAngleCopy = false
    @State private var matchedAvoidItems: [String] = []
    @State private var showAvoidAlert = false
    @State private var showScanSummarySheet = false
    @State private var showPaywall = false
    @State private var paywallReason: PaywallReason = .weeklyScanLimit
    @State private var latestScanPayload: ScanResultPayload?
    @State private var showManualInput = false
    /// 貼上完成後先存結果，等全螢幕關閉再跳摘要，避免空白白畫面。
    @State private var pendingManualPastePayload: ScanResultPayload?
    @State private var showUnclearResult = false
    /// 保留首張結果，進入連續補拍模式。
    @State private var isFollowUpCaptureMode = false
    /// 圓瓶連拍暫存（上限 3 張）；每張先對框確認才入列。
    @State private var capturedImages: [UIImage] = []
    /// 對框後的裁切，辨識直接用這份，不再用實機預覽重裁。
    @State private var confirmedCrops: [Data] = []
    /// 剛拍下、等使用者拖進白框的那張。
    @State private var shotPendingAlign: UIImage?
    @State private var isCapturingShot = false
    @State private var isFinishingMultiShot = false
    @State private var cameraPreviewSize: CGSize = .zero
    @State private var focusIndicatorPoint: CGPoint?
    @State private var unclearPrompt: ScanUnclearPrompt = .noReadableText
    @State private var deferredLowQualityResult: ScanSessionResult?
    @State private var deferredLowQualityImage: Data?

    var body: some View {
        cameraBody
            .onAppear {
                DataBootstrap.seedIfNeeded(in: modelContext)
                if isActive {
                    camera.prepare()
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    camera.prepare()
                } else {
                    camera.stop()
                    resetCapturedImages()
                }
            }
            .onDisappear {
                camera.stop()
            }
    }

    private var cameraBody: some View {
        ZStack {
            if camera.isConfigured {
                CameraPreviewView(session: camera.session) { devicePoint in
                    camera.focus(atDevicePoint: devicePoint)
                }
                // 僅延伸上方，不可蓋過底部系統 TabBar。
                .ignoresSafeArea(edges: .top)
            } else {
                placeholderBackground
                    .allowsHitTesting(false)
            }

            if camera.isCameraUnavailable {
                CameraUnavailableView(
                    title: unavailableTitle,
                    message: unavailableMessage
                )
                .ignoresSafeArea(edges: .top)
            } else {
                CameraScanGuideOverlay(
                    capturedCount: capturedImages.count,
                    isFollowUpMode: isFollowUpCaptureMode
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            // 白框／提示層會擋住 UIView 點擊；用 SwiftUI 手勢承接對焦。
            if camera.isConfigured, !camera.isCameraUnavailable, !isScanning, !showUnclearResult, !showAvoidAlert {
                CameraTapFocusLayer(
                    onFocus: { camera.focus(atDevicePoint: $0) },
                    indicatorPoint: $focusIndicatorPoint
                )
                .ignoresSafeArea(edges: .top)
            }

            VStack(spacing: 0) {
                HStack {
                    if allowsDismiss {
                        Button("關閉") { dismiss() }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.42), in: Capsule())
                            .padding(.leading, 18)
                    }
                    Spacer(minLength: 0)
                    if showsPasteButton {
                    Button {
                        guard FreeScanQuota.canStartCameraScan(isPremium: subscriptionStore.isPremium) else {
                            paywallReason = .weeklyScanLimit
                            showPaywall = true
                            return
                        }
                        showManualInput = true
                    } label: {
                        Label("貼上成分", systemImage: "doc.on.clipboard")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.42), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("貼上成分表")
                    .padding(.trailing, 18)
                    }
                }
                .padding(.top, 10)

                if isFollowUpCaptureMode {
                    followUpCaptureBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                } else if !camera.isCameraUnavailable {
                    multiShotHintBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                captureControls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
            }
            .ignoresSafeArea(.keyboard)

            if isScanning {
                scanningOverlay
            }

            if showAvoidAlert {
                IngredientAvoidAlertOverlay(
                    matchedItems: matchedAvoidItems,
                    onViewDetails: openScanSummarySheet,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAvoidAlert = false
                        }
                        showScanSummarySheet = false
                        latestScanPayload = nil
                        isFollowUpCaptureMode = false
                        isScanning = false
                        resetCapturedImages()
                    }
                )
            }

            if showUnclearResult {
                ScanUnclearResultOverlay(
                    prompt: unclearPrompt,
                    onManualInput: {
                        showUnclearResult = false
                        clearDeferredLowQuality()
                        resetCapturedImages()
                        guard FreeScanQuota.canStartCameraScan(isPremium: subscriptionStore.isPremium) else {
                            paywallReason = .weeklyScanLimit
                            showPaywall = true
                            return
                        }
                        showManualInput = true
                    },
                    onRetake: {
                        showUnclearResult = false
                        clearDeferredLowQuality()
                        latestScanPayload = nil
                        resetCapturedImages()
                    },
                    onViewPartialResults: {
                        showUnclearResult = false
                        presentDeferredLowQualityResult()
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showUnclearResult = false
                        }
                        clearDeferredLowQuality()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(CameraPreviewSizeKey.self) { cameraPreviewSize = $0 }
        .animation(.easeOut(duration: 0.25), value: isFollowUpCaptureMode)
        .animation(.easeOut(duration: 0.22), value: capturedImages.count)
        .sheet(isPresented: $showScanSummarySheet, onDismiss: {
            if !isFollowUpCaptureMode {
                scanLaunch.resetToCameraTab()
            }
        }) {
            if let payload = latestScanPayload {
                ScanSummarySheet(
                    payload: payload,
                    onProductNameChanged: { updatedName in
                        latestScanPayload?.productName = updatedName
                    },
                    onCaptureNextAngle: {
                        beginFollowUpCaptureMode()
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showManualInput, onDismiss: {
            DeferredModalPresentation.afterCoverDismiss {
                presentPendingManualPasteResult()
            }
        }) {
            ManualInputView(source: .cameraTab) { payload in
                pendingManualPastePayload = payload
                latestScanPayload = payload
                matchedAvoidItems = payload.matchedAlerts
                isFollowUpCaptureMode = false
                resetCapturedImages()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: paywallReason)
        }
        .fullScreenCover(isPresented: Binding(
            get: { shotPendingAlign != nil },
            set: { if !$0 { shotPendingAlign = nil } }
        )) {
            if let pending = shotPendingAlign {
                PhotoLibraryFrameAlignView(
                    image: pending,
                    hint: isFollowUpCaptureMode
                        ? "補拍：把全成分拖進白框，再按確認這張"
                        : "第 \(confirmedCrops.count + 1) 張：把全成分拖進白框，再按確認這張",
                    confirmTitle: "確認這張",
                    onConfirm: { data in
                        acceptAlignedShot(data)
                    },
                    onCancel: {
                        shotPendingAlign = nil
                    }
                )
            }
        }
    }

    private var multiShotHintBanner: some View {
        Text(MultiShotCaptureGuide.prompt(forCapturedCount: capturedImages.count))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .accessibilityLabel(MultiShotCaptureGuide.prompt(forCapturedCount: capturedImages.count))
    }

    private var followUpCaptureBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text("連續補拍模式")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("請稍微向右轉動瓶身，重疊拍下右半部成分")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("取消") {
                    cancelFollowUpCaptureMode()
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var scanningOverlay: some View {
        ZStack {
            // 不延伸到底部 safe area，避免擋住 TabBar。
            Color.black.opacity(0.45)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text(
                    isFollowUpCaptureMode
                        ? "正在拼接補拍角度..."
                        : (scanningUsesMultiAngleCopy ? "正在拼接多張瓶身照片..." : "辨識成分中...")
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var placeholderBackground: some View {
        Color.black
            .ignoresSafeArea(edges: .top)
    }

    private var unavailableTitle: String {
        switch camera.unavailableReason {
        case .simulator:
            return "模擬器不支援相機預覽"
        case .permissionDenied:
            return "需要相機權限"
        case .noDevice:
            return "無法使用相機"
        case .none:
            return "無法使用相機"
        }
    }

    private var unavailableMessage: String {
        switch camera.unavailableReason {
        case .simulator:
            return "Xcode 模擬器與 Preview 沒有實體鏡頭，請使用 iPhone 實機測試。"
        case .permissionDenied:
            return "請到設定中允許相機存取，以便掃描成分表。"
        case .noDevice:
            return "此裝置找不到可用相機。"
        case .none:
            return "請使用 iPhone 實機拍攝成分表。"
        }
    }

    private var captureControls: some View {
        Group {
            if isFollowUpCaptureMode {
                HStack(alignment: .center) {
                    Color.clear
                        .frame(width: 76, height: 52)
                        .allowsHitTesting(false)
                    Spacer()
                    Button(action: capturePhoto) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.95), lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!camera.isConfigured || isScanning || isCapturingShot)
                    .opacity(camera.isConfigured && !isScanning && !isCapturingShot ? 1 : 0.45)
                    .accessibilityLabel("拍攝補拍角度")
                    Spacer()
                    Color.clear
                        .frame(width: 76, height: 52)
                        .allowsHitTesting(false)
                }
            } else {
                MultiShotCaptureBar(
                    capturedCount: capturedImages.count,
                    isConfigured: camera.isConfigured,
                    isBusy: isScanning || isCapturingShot || isFinishingMultiShot || shotPendingAlign != nil,
                    showsLibrary: false,
                    onLibrary: {},
                    onReset: resetCapturedImages,
                    onCapture: capturePhoto,
                    onFinish: {
                        Task { await finishMultiShotCapture() }
                    }
                )
            }
        }
    }

    private func capturePhoto() {
        guard camera.isConfigured, !isScanning, !isCapturingShot, shotPendingAlign == nil else { return }
        if !isFollowUpCaptureMode,
           capturedImages.count >= MultiShotCaptureGuide.maxShotCount {
            return
        }
        if !isFollowUpCaptureMode,
           capturedImages.isEmpty,
           !ensureCameraScanAllowed() {
            return
        }
        isCapturingShot = true
        camera.capturePhoto { data in
            isCapturingShot = false
            guard let data else { return }
            Task { @MainActor in
                guard let image = UIImage(data: data) else { return }
                shotPendingAlign = image.flattenedForOCR()
            }
        }
    }

    @MainActor
    private func acceptAlignedShot(_ data: Data) {
        shotPendingAlign = nil
        guard let image = UIImage(data: data) else { return }
        if isFollowUpCaptureMode {
            Task { await processFollowUpCapture(data: data) }
            return
        }
        guard confirmedCrops.count < MultiShotCaptureGuide.maxShotCount else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            confirmedCrops.append(data)
            capturedImages.append(image)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if confirmedCrops.count >= MultiShotCaptureGuide.maxShotCount {
            Task { await finishMultiShotCapture() }
        }
    }

    @MainActor
    private func finishMultiShotCapture() async {
        guard !isScanning, !isFinishingMultiShot, capturedImages.count >= 1 else { return }
        guard ensureCameraScanAllowed() else { return }
        isFinishingMultiShot = true
        defer { isFinishingMultiShot = false }
        let dataList = confirmedCrops
        guard !dataList.isEmpty else { return }
        await processImagesForAlerts(dataList: dataList, fromIngredientBand: true)
        if latestScanPayload != nil {
            resetCapturedImages()
        }
    }

    private func resetCapturedImages() {
        shotPendingAlign = nil
        guard !capturedImages.isEmpty || !confirmedCrops.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            capturedImages = []
            confirmedCrops = []
        }
    }

    /// 全螢幕貼上頁關乾淨後才跳摘要／避開警示，避免空白白 sheet。
    private func presentPendingManualPasteResult() {
        guard let payload = pendingManualPastePayload else { return }
        pendingManualPastePayload = nil

        switch payload.pasteResultPresentation {
        case .avoidAlert:
            ScanAlertHaptics.triggerWarning()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showAvoidAlert = true
            }
        case .summarySheet:
            showScanSummarySheet = true
        case nil:
            break
        }
    }

    private func ensureCameraScanAllowed() -> Bool {
        if FreeScanQuota.canStartCameraScan(isPremium: subscriptionStore.isPremium) {
            return true
        }
        paywallReason = .weeklyScanLimit
        showPaywall = true
        return false
    }

    private func beginFollowUpCaptureMode() {
        guard latestScanPayload != nil else { return }
        resetCapturedImages()
        showAvoidAlert = false
        showScanSummarySheet = false
        withAnimation(.easeOut(duration: 0.25)) {
            isFollowUpCaptureMode = true
        }
    }

    private func cancelFollowUpCaptureMode() {
        withAnimation(.easeOut(duration: 0.25)) {
            isFollowUpCaptureMode = false
        }
        if latestScanPayload != nil {
            showScanSummarySheet = true
        }
    }

    @MainActor
    private func processImageForAlerts(data: Data) async {
        await processImagesForAlerts(dataList: [data], fromIngredientBand: false)
    }

    @MainActor
    private func processFollowUpCapture(data: Data) async {
        guard let base = latestScanPayload else {
            isFollowUpCaptureMode = false
            await processImageForAlerts(data: data)
            return
        }

        isScanning = true
        showAvoidAlert = false
        showScanSummarySheet = false

        let profile: UserProfile? = profileList.first
        let result = await ScanSessionProcessor.mergeFollowUpCapture(
            existingIngredients: base.ingredients,
            followUpImageData: data,
            profile: profile,
            previousAverageConfidence: base.averageOCRConfidence,
            previousLineCount: base.ocrLineCount,
            previousImageCount: base.sourceImageCount
        )

        isScanning = false
        isFollowUpCaptureMode = false

        guard !result.ingredients.isEmpty else {
            // 補拍失敗：保留首張結果並回到摘要
            showScanSummarySheet = true
            return
        }

        let snapshots = PersistedScannedIngredient.buildSnapshots(
            ingredientNames: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients
        )

        if let recordID = base.historyRecordID {
            ScanHistoryWriter.updateRecognizedIngredients(
                recordID: recordID,
                ingredients: result.ingredients,
                matchedIngredients: result.matchedAlerts,
                resolvedSnapshots: snapshots,
                in: modelContext
            )
        }

        latestScanPayload = ScanResultPayload(
            imageData: base.imageData ?? data,
            ingredients: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            scannedAt: base.scannedAt,
            historyRecordID: base.historyRecordID,
            source: .cameraTab,
            productName: base.productName,
            resolvedIngredients: snapshots,
            averageOCRConfidence: result.averageOCRConfidence,
            ocrLineCount: result.ocrLineCount,
            sourceImageCount: result.sourceImageCount
        )

        matchedAvoidItems = result.matchedAlerts

        if !result.matchedAlerts.isEmpty {
            IngredientAlertEngine.triggerScanWarningHapticIfNeeded(matchedAlertMessages: result.matchedAlerts)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showAvoidAlert = true
            }
        } else {
            showScanSummarySheet = true
        }
    }

    @MainActor
    private func processImagesForAlerts(dataList: [Data], fromIngredientBand: Bool) async {
        guard let primary = dataList.first else { return }

        if isFollowUpCaptureMode {
            await processFollowUpCapture(data: primary)
            return
        }

        guard ensureCameraScanAllowed() else { return }

        scanningUsesMultiAngleCopy = dataList.count > 1
        isScanning = true
        showAvoidAlert = false
        showScanSummarySheet = false
        isFollowUpCaptureMode = false
        scannedImageData = primary

        let profile: UserProfile? = profileList.first
        let result = await ScanSessionProcessor.analyze(
            imageDataList: dataList,
            profile: profile,
            usesIngredientBandCrop: fromIngredientBand
        )

        isScanning = false
        scanningUsesMultiAngleCopy = false

        if result.needsCaptureRetake {
            presentUnclearCapture(result: result, primaryImageData: primary)
            return
        }

        commitSuccessfulScan(result: result, primaryImageData: primary)
    }

    @MainActor
    private func presentUnclearCapture(result: ScanSessionResult, primaryImageData: Data) {
        latestScanPayload = nil
        matchedAvoidItems = []
        if result.ingredients.isEmpty {
            unclearPrompt = .noReadableText
            clearDeferredLowQuality()
        } else {
            unclearPrompt = .lowCaptureQuality(identifiedCount: result.dictionaryHitCount)
            if result.dictionaryHitCount > 0 {
                deferredLowQualityResult = result
                deferredLowQualityImage = primaryImageData
            } else {
                clearDeferredLowQuality()
            }
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            showUnclearResult = true
        }
    }

    @MainActor
    private func presentDeferredLowQualityResult() {
        guard let result = deferredLowQualityResult,
              let image = deferredLowQualityImage else {
            clearDeferredLowQuality()
            return
        }
        clearDeferredLowQuality()
        resetCapturedImages()
        commitSuccessfulScan(result: result, primaryImageData: image)
    }

    private func clearDeferredLowQuality() {
        deferredLowQualityResult = nil
        deferredLowQualityImage = nil
    }

    @MainActor
    private func commitSuccessfulScan(result: ScanSessionResult, primaryImageData: Data) {
        FreeScanQuota.consumeCameraScan(isPremium: subscriptionStore.isPremium)

        let defaultTitle = ScanSummarySheet.defaultProductName()
        let savedRecord = ScanSessionProcessor.persist(
            result: result,
            imageData: primaryImageData,
            in: modelContext,
            title: defaultTitle
        )

        let snapshots = savedRecord?.resolvedIngredients.isEmpty == false
            ? (savedRecord?.resolvedIngredients ?? [])
            : PersistedScannedIngredient.buildSnapshots(
                ingredientNames: result.ingredients,
                matchedAlerts: result.matchedAlerts,
                blockedTags: result.blockedTags,
                customBlockedIngredients: result.customBlockedIngredients
            )

        latestScanPayload = ScanResultPayload(
            imageData: primaryImageData,
            ingredients: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            scannedAt: savedRecord?.scannedAt ?? Date(),
            historyRecordID: savedRecord?.recordID,
            source: .cameraTab,
            resolvedIngredients: snapshots,
            averageOCRConfidence: result.averageOCRConfidence,
            ocrLineCount: result.ocrLineCount,
            sourceImageCount: result.sourceImageCount
        )

        matchedAvoidItems = result.matchedAlerts

        if !result.matchedAlerts.isEmpty {
            IngredientAlertEngine.triggerScanWarningHapticIfNeeded(matchedAlertMessages: result.matchedAlerts)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showAvoidAlert = true
            }
        } else {
            showScanSummarySheet = true
        }
    }

    private func openScanSummarySheet() {
        showAvoidAlert = false
        showScanSummarySheet = true
    }
}

private struct CameraUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.9))
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .allowsHitTesting(false)
    }
}
#endif

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
            .environmentObject(ScanLaunchBridge())
    }
}
