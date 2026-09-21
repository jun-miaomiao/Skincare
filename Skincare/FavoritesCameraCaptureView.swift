import SwiftUI
import SwiftData
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

/// 我的最愛專用相機：fullScreenCover，不共用相機 Tab Session。
struct FavoritesCameraCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profileList: [UserProfile]

    let onCapturedPayload: (ScanResultPayload) -> Void
    let onCancel: () -> Void

    @StateObject private var camera = CameraController()
    @State private var isScanning = false
    @State private var showUnclearResult = false
    @State private var capturedImages: [UIImage] = []
    @State private var confirmedCrops: [Data] = []
    @State private var shotPendingAlign: UIImage?
    @State private var isCapturingShot = false
    @State private var isFinishingMultiShot = false
    @State private var cameraPreviewSize: CGSize = .zero
    @State private var focusIndicatorPoint: CGPoint?
    @State private var unclearPrompt: ScanUnclearPrompt = .noReadableText
    @State private var deferredLowQualityResult: ScanSessionResult?
    @State private var deferredLowQualityImage: Data?

    var body: some View {
        ZStack {
            #if os(iOS)
            if camera.isConfigured {
                CameraPreviewView(session: camera.session) { devicePoint in
                    camera.focus(atDevicePoint: devicePoint)
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if camera.isCameraUnavailable {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.9))
                    Text(unavailableTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(unavailableMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                CameraScanGuideOverlay(capturedCount: capturedImages.count)
                    .allowsHitTesting(false)
            }

            if camera.isConfigured, !camera.isCameraUnavailable, !isScanning {
                CameraTapFocusLayer(
                    onFocus: { camera.focus(atDevicePoint: $0) },
                    indicatorPoint: $focusIndicatorPoint
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button("取消") {
                        resetCapturedImages()
                        onCancel()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(16)
                    Spacer()
                }

                if !camera.isCameraUnavailable {
                    Text(MultiShotCaptureGuide.prompt(forCapturedCount: capturedImages.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            Color.black.opacity(0.58),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .allowsHitTesting(false)
                }

                Spacer()
                    .allowsHitTesting(false)

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
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
            .animation(.easeOut(duration: 0.22), value: capturedImages.count)

            if let pending = shotPendingAlign {
                PhotoLibraryFrameAlignView(
                    image: pending,
                    stepLabel: "\(confirmedCrops.count + 1)/\(MultiShotCaptureGuide.maxShotCount)",
                    confirmTitle: "確認這張",
                    onConfirm: { data in
                        acceptAlignedShot(data)
                    },
                    onCancel: {
                        shotPendingAlign = nil
                    }
                )
                .ignoresSafeArea()
                .zIndex(30)
            }

            if isScanning {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(capturedImages.count > 1 ? "正在拼接多張瓶身照片..." : "辨識成分中...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if showUnclearResult {
                ScanUnclearResultOverlay(
                    prompt: unclearPrompt,
                    onRetake: {
                        showUnclearResult = false
                        deferredLowQualityResult = nil
                        deferredLowQualityImage = nil
                        resetCapturedImages()
                    },
                    onViewPartialResults: {
                        showUnclearResult = false
                        commitDeferredLowQualityIfNeeded()
                    },
                    onDismiss: {
                        showUnclearResult = false
                        deferredLowQualityResult = nil
                        deferredLowQualityImage = nil
                        resetCapturedImages()
                        onCancel()
                    }
                )
            }
            #else
            Color.black.ignoresSafeArea()
            #endif
        }
        .onPreferenceChange(CameraPreviewSizeKey.self) { cameraPreviewSize = $0 }
        .onAppear { camera.prepare() }
        .onDisappear {
            camera.stop()
            resetCapturedImages()
        }
    }

    #if os(iOS)
    private var unavailableTitle: String {
        switch camera.unavailableReason {
        case .simulator: return "模擬器不支援相機"
        case .permissionDenied: return "需要相機權限"
        case .noDevice: return "無法使用相機"
        case .none: return "無法使用相機"
        }
    }

    private var unavailableMessage: String {
        switch camera.unavailableReason {
        case .simulator:
            return "請改從相簿選取，或使用 iPhone 實機測試。"
        case .permissionDenied:
            return "請到設定允許相機存取。"
        default:
            return "請改從相簿選取成分表照片。"
        }
    }

    private func capturePhoto() {
        guard camera.isConfigured, !isScanning, !isCapturingShot, shotPendingAlign == nil else { return }
        guard capturedImages.count < MultiShotCaptureGuide.maxShotCount else { return }
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
        guard confirmedCrops.count < MultiShotCaptureGuide.maxShotCount else { return }
        guard let image = UIImage(data: data) else { return }
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
        guard !isScanning, !isFinishingMultiShot, confirmedCrops.count >= 1 else { return }
        isFinishingMultiShot = true
        defer { isFinishingMultiShot = false }
        let dataList = confirmedCrops
        guard !dataList.isEmpty else { return }
        await process(dataList: dataList)
        if !showUnclearResult {
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

    @MainActor
    private func process(dataList: [Data]) async {
        guard let primary = dataList.first else { return }
        isScanning = true
        let profile = profileList.first
        let result = await ScanSessionProcessor.analyze(
            imageDataList: dataList,
            profile: profile,
            usesIngredientBandCrop: true
        )
        isScanning = false

        if result.needsCaptureRetake {
            unclearPrompt = result.ingredients.isEmpty
                ? .noReadableText
                : .lowCaptureQuality(identifiedCount: result.dictionaryHitCount)
            if result.dictionaryHitCount > 0 {
                deferredLowQualityResult = result
                deferredLowQualityImage = primary
            } else {
                deferredLowQualityResult = nil
                deferredLowQualityImage = nil
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showUnclearResult = true
            }
            return
        }

        commitSuccessfulScan(result: result, primaryImageData: primary)
    }

    @MainActor
    private func commitDeferredLowQualityIfNeeded() {
        guard let result = deferredLowQualityResult,
              let image = deferredLowQualityImage else { return }
        deferredLowQualityResult = nil
        deferredLowQualityImage = nil
        resetCapturedImages()
        commitSuccessfulScan(result: result, primaryImageData: image)
    }

    @MainActor
    private func commitSuccessfulScan(result: ScanSessionResult, primaryImageData: Data) {
        let title = ScanSummarySheet.defaultProductName()
        let saved = ScanSessionProcessor.persist(
            result: result,
            imageData: primaryImageData,
            in: modelContext,
            title: title
        )
        let payload = ScanResultPayload(
            imageData: primaryImageData,
            ingredients: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            scannedAt: saved?.scannedAt ?? Date(),
            historyRecordID: saved?.recordID,
            source: .favorites,
            resolvedIngredients: saved?.resolvedIngredients ?? [],
            averageOCRConfidence: result.averageOCRConfidence,
            ocrLineCount: result.ocrLineCount,
            sourceImageCount: result.sourceImageCount
        )
        onCapturedPayload(payload)
    }
    #endif
}
