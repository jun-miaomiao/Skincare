#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

/// 貼上頁的相機：拍一張後用系統原況文字選取。沒被辨識到的字不能選。
struct LiveTextCameraFlow: View {
    var onInsert: (String) -> Void
    var onCancel: () -> Void

    @StateObject private var camera = CameraController()
    @State private var capturedImage: UIImage?
    @State private var selectedText = ""
    @State private var recognizedText = ""
    @State private var isReading = false
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let capturedImage {
                selectionScreen(image: capturedImage)
            } else {
                captureScreen
            }
        }
        .onAppear {
            camera.prepare()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var captureScreen: some View {
        ZStack {
            if camera.isCameraUnavailable {
                VStack(spacing: 12) {
                    Text(unavailableTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(unavailableMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            } else {
                CameraPreviewView(session: camera.session) { point in
                    camera.focus(atDevicePoint: point)
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button("關閉") { onCancel() }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.42), in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.gold)
                    Text("密排小字相機可能會漏。想一次對完整份，請關閉後改複製貼上。")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Button(action: capture) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.95), lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!camera.isConfigured || isCapturing || camera.isCameraUnavailable)
                .opacity(camera.isConfigured && !isCapturing ? 1 : 0.45)
                .padding(.bottom, 28)
                .accessibilityLabel("拍攝")
            }
        }
    }

    private func selectionScreen(image: UIImage) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("關閉") { onCancel() }
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("重拍") {
                    capturedImage = nil
                    selectedText = ""
                    recognizedText = ""
                    camera.prepare()
                }
                .font(.caption.weight(.semibold))
            }
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Text("按住亮起來的字再拖曳。沒被辨識到的字選不到。")
                .font(.footnote)
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            LiveTextImageSelector(
                image: image,
                selectedText: $selectedText,
                recognizedText: $recognizedText,
                isReading: $isReading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .background(Color.black)

            if isReading {
                ProgressView("正在找出可選的字…")
                    .font(.footnote)
                    .padding(.top, 10)
            } else if recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("這張沒有辨識到可選的字。")
                    .font(.footnote)
                    .foregroundColor(Theme.blush)
                    .padding(.top, 10)
            }

            VStack(spacing: 8) {
                Button("帶入選取的文字") {
                    insert(selectedText)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("帶入這張辨識到的全部文字") {
                    insert(recognizedText)
                }
                .buttonStyle(.bordered)
                .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        camera.capturePhoto { data in
            isCapturing = false
            guard let data, let image = UIImage(data: data) else { return }
            camera.stop()
            capturedImage = image
        }
    }

    private func insert(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onInsert(text)
    }

    private var unavailableTitle: String {
        switch camera.unavailableReason {
        case .simulator: return "模擬器不支援相機"
        case .permissionDenied: return "需要相機權限"
        case .noDevice, .none: return "無法使用相機"
        }
    }

    private var unavailableMessage: String {
        switch camera.unavailableReason {
        case .simulator: return "請用 iPhone 實機拍攝。"
        case .permissionDenied: return "請到設定允許相機存取。"
        case .noDevice, .none: return "此裝置找不到可用相機。"
        }
    }
}

private struct LiveTextImageSelector: UIViewRepresentable {
    let image: UIImage
    @Binding var selectedText: String
    @Binding var recognizedText: String
    @Binding var isReading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText, recognizedText: $recognizedText, isReading: $isReading)
    }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.isUserInteractionEnabled = true
        view.image = image
        view.addInteraction(context.coordinator.interaction)
        context.coordinator.analyze(image)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image {
            uiView.image = image
            context.coordinator.analyze(image)
        }
    }

    final class Coordinator: NSObject, ImageAnalysisInteractionDelegate {
        let interaction = ImageAnalysisInteraction()
        private let analyzer = ImageAnalyzer()
        private var task: Task<Void, Never>?
        private var selectedText: Binding<String>
        private var recognizedText: Binding<String>
        private var isReading: Binding<Bool>

        init(
            selectedText: Binding<String>,
            recognizedText: Binding<String>,
            isReading: Binding<Bool>
        ) {
            self.selectedText = selectedText
            self.recognizedText = recognizedText
            self.isReading = isReading
            super.init()
            interaction.delegate = self
            interaction.preferredInteractionTypes = .textSelection
        }

        func analyze(_ image: UIImage) {
            task?.cancel()
            interaction.analysis = nil
            isReading.wrappedValue = true
            recognizedText.wrappedValue = ""
            selectedText.wrappedValue = ""
            task = Task { [analyzer, interaction] in
                var configuration = ImageAnalyzer.Configuration([.text])
                configuration.locales = ["en-US", "zh-Hant", "ja-JP", "ko-KR"]
                let analysis = try? await analyzer.analyze(image, configuration: configuration)
                if Task.isCancelled { return }
                await MainActor.run {
                    interaction.preferredInteractionTypes = .textSelection
                    interaction.analysis = analysis
                    self.recognizedText.wrappedValue = interaction.text
                    self.isReading.wrappedValue = false
                    DispatchQueue.main.async {
                        interaction.selectableItemsHighlighted = true
                    }
                }
            }
        }

        func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
            selectedText.wrappedValue = interaction.selectedText
        }
    }
}
#endif
