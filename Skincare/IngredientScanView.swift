import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ScanSourceAction {
    case camera
    case library
}

struct ScanCameraButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("相機掃描")
    }
}

struct ScanSourceSheet: View {
    var onSelect: (ScanSourceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("掃描成分表")
                    .font(.system(.title2, design: .serif).weight(.medium))
                    .foregroundColor(Theme.ink)
                Text("拍攝或選取保養品包裝上的全成分標示。")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            }

            VStack(spacing: 12) {
                ScanSourceRow(
                    title: "拍照掃描成分表",
                    subtitle: "對準標籤，自動進入辨識預覽",
                    systemImage: "camera.fill",
                    tint: Theme.accent,
                    iconBackground: Theme.primaryLight
                ) {
                    onSelect(.camera)
                }

                ScanSourceRow(
                    title: "從相簿選擇照片",
                    subtitle: "選取已拍攝的成分表照片",
                    systemImage: "photo.on.rectangle.angled",
                    tint: Theme.muted
                ) {
                    onSelect(.library)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }
}

private struct ScanSourceRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var iconBackground: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        iconBackground ?? tint.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct IngredientScanPreviewView: View {
    let imageData: Data
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.modelContext) private var modelContext
    @Query private var profileList: [UserProfile]

    @State private var isRecognizing = true
    @State private var recognizedText = ""
    @State private var matchedAvoidItems: [String] = []
    @State private var showAvoidAlert = false
    @State private var showScanSummarySheet = false
    @State private var latestScanPayload: ScanResultPayload?
    @State private var ingredientCount = 0
    @State private var showUnclearResult = false
    @State private var unclearPrompt: ScanUnclearPrompt = .noReadableText
    @State private var showManualInput = false
    @State private var pendingManualPastePayload: ScanResultPayload?
    @State private var deferredLowQualityResult: ScanSessionResult?

    init(imageData: Data) {
        self.imageData = imageData
    }

    var body: some View {
        CustomNavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 22) {
                    ScanImageView(data: imageData)
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Theme.cardStroke, lineWidth: 1)
                        )
                        .shadow(color: Theme.ink.opacity(0.08), radius: 18, y: 10)

                    VStack(spacing: 10) {
                        if isRecognizing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                            Text("辨識中...")
                                .font(.system(.title3, design: .serif).weight(.medium))
                                .foregroundColor(Theme.ink)
                            Text("正在讀取成分表並比對您的風險清單。")
                                .font(.subheadline)
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)
                        } else if recognizedText.isEmpty {
                            Image(systemName: "text.viewfinder")
                                .font(.title2)
                                .foregroundColor(Theme.sage)
                            Text("未辨識到文字")
                                .font(.system(.title3, design: .serif).weight(.medium))
                                .foregroundColor(Theme.ink)
                            Text("請確認照片清晰、成分表完整，或調整光線後重試。")
                                .font(.subheadline)
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)
                        } else {
                            Image(systemName: matchedAvoidItems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(matchedAvoidItems.isEmpty ? Theme.sage : Theme.blush)
                            Text(matchedAvoidItems.isEmpty ? "辨識完成" : "發現風險成分")
                                .font(.system(.title3, design: .serif).weight(.medium))
                                .foregroundColor(Theme.ink)
                            Text(
                                ingredientCount > 0
                                    ? "已辨識 \(ingredientCount) 項成分，點擊下方查看詳細結果。"
                                    : "尚未對上字典成分，點擊下方查看可能未辨識項目。"
                            )
                                .font(.subheadline)
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)

                            Button(action: openScanSummarySheet) {
                                Text("查看掃描摘要")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Theme.cardStroke, lineWidth: 1)
                    )

                    Spacer(minLength: 0)
                }
                .padding(22)

                if showAvoidAlert {
                    IngredientAvoidAlertOverlay(
                        matchedItems: matchedAvoidItems,
                        onViewDetails: openScanSummarySheet,
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                showAvoidAlert = false
                            }
                            // 僅關閉警告、重置掃描狀態，不開啟結果卡片
                            showScanSummarySheet = false
                            latestScanPayload = nil
                        }
                    )
                    .zIndex(10)
                }

                if showUnclearResult {
                    ScanUnclearResultOverlay(
                        prompt: unclearPrompt,
                        onManualInput: {
                            showUnclearResult = false
                            showManualInput = true
                        },
                        onRetake: {
                            showUnclearResult = false
                            presentationMode.wrappedValue.dismiss()
                        },
                        onViewPartialResults: {
                            showUnclearResult = false
                            commitDeferredLowQualityIfNeeded()
                        },
                        onDismiss: {
                            showUnclearResult = false
                            presentationMode.wrappedValue.dismiss()
                        }
                    )
                    .zIndex(11)
                }
            }
            .navigationTitle("成分掃描")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") {
                        presentationMode.wrappedValue.dismiss()
                    }
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
                    ingredientCount = payload.identifiedIngredientCount
                    recognizedText = payload.identifiedIngredientCount == 0
                        ? ""
                        : payload.ingredients.joined(separator: ", ")
                }
            }
            .sheet(isPresented: $showScanSummarySheet) {
                if let payload = latestScanPayload {
                    ScanSummarySheet(
                        payload: payload,
                        onProductNameChanged: { updatedName in
                            latestScanPayload?.productName = updatedName
                        }
                    )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .onAppear {
                Task { await runOCRAndMatchAvoidList() }
            }
        }
    }

    private func presentPendingManualPasteResult() {
        guard let payload = pendingManualPastePayload else { return }
        pendingManualPastePayload = nil

        switch payload.pasteResultPresentation {
        case .avoidAlert:
            ScanAlertHaptics.triggerWarning()
            showAvoidAlert = true
        case .summarySheet:
            showScanSummarySheet = true
        case nil:
            break
        }
    }

    @MainActor
    private func runOCRAndMatchAvoidList() async {
        #if canImport(UIKit)
        let profile: UserProfile? = profileList.first
        let result = await ScanSessionProcessor.analyze(imageData: imageData, profile: profile)

        recognizedText = result.fullText
        ingredientCount = result.dictionaryHitCount
        matchedAvoidItems = result.matchedAlerts
        isRecognizing = false

        if result.needsCaptureRetake {
            latestScanPayload = nil
            deferredLowQualityResult = result.dictionaryHitCount > 0 ? result : nil
            unclearPrompt = result.ingredients.isEmpty
                ? .noReadableText
                : .lowCaptureQuality(identifiedCount: result.dictionaryHitCount)
            if result.dictionaryHitCount == 0 {
                recognizedText = ""
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                showUnclearResult = true
            }
            return
        }

        commitSuccessfulScan(result: result)
        #else
        isRecognizing = false
        #endif
    }

    @MainActor
    private func commitDeferredLowQualityIfNeeded() {
        guard let result = deferredLowQualityResult else { return }
        deferredLowQualityResult = nil
        commitSuccessfulScan(result: result)
    }

    @MainActor
    private func commitSuccessfulScan(result: ScanSessionResult) {
        let defaultTitle = ScanSummarySheet.defaultProductName()
        let savedRecord = ScanSessionProcessor.persist(
            result: result,
            imageData: imageData,
            in: modelContext,
            title: defaultTitle
        )

        ingredientCount = result.dictionaryHitCount
        matchedAvoidItems = result.matchedAlerts
        recognizedText = result.fullText
        latestScanPayload = ScanResultPayload(
            imageData: imageData,
            ingredients: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            scannedAt: savedRecord?.scannedAt ?? Date(),
            historyRecordID: savedRecord?.recordID,
            resolvedIngredients: savedRecord?.resolvedIngredients ?? [],
            averageOCRConfidence: result.averageOCRConfidence,
            ocrLineCount: result.ocrLineCount,
            sourceImageCount: result.sourceImageCount
        )

        if !result.matchedAlerts.isEmpty {
            ScanAlertHaptics.triggerWarning()
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

struct ScanImageView: View {
    let data: Data

    var body: some View {
        Group {
            #if os(macOS)
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #else
            if let image = UIImage(data: data)?.flattenedForOCR() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #endif
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(Theme.muted)
            )
            .frame(height: 220)
    }
}

#if os(iOS)
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            if let data = image?.jpegDataFlattenedForOCR(compressionQuality: 0.86) {
                onCapture(data)
            } else {
                onCancel()
            }
        }
    }
}
#endif

struct IngredientScanPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        IngredientScanPreviewView(imageData: Data())
            .modelContainer(SkincareModelContainer.preview)
    }
}
