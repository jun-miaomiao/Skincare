#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

enum CameraUnavailableReason: Equatable {
    case simulator
    case noDevice
    case permissionDenied
}

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var unavailableReason: CameraUnavailableReason?

    /// 所有 session 設定 / start / stop 必須在此佇列，禁止佔用主執行緒。
    private let sessionQueue = DispatchQueue(label: "com.skincare.cameraSessionQueue")

    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((Data?) -> Void)?
    /// 僅在 sessionQueue 上讀寫。
    private var hasConfiguredSession = false
    private var isConfiguring = false

    var isCameraUnavailable: Bool {
        unavailableReason != nil
    }

    var permissionDenied: Bool {
        unavailableReason == .permissionDenied
    }

    var isSimulatorEnvironment: Bool {
        unavailableReason == .simulator
    }

    func prepare() {
        #if targetEnvironment(simulator)
        markUnavailable(.simulator)
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async {
                        self.configureSessionIfNeeded()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.markUnavailable(.permissionDenied)
                    }
                }
            }
        default:
            markUnavailable(.permissionDenied)
        }
        #endif
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.startSessionOnQueue()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.stopSessionOnQueue()
        }
    }

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard self.hasConfiguredSession,
                  self.unavailableReason == nil,
                  self.session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.captureCompletion = completion
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Session queue only

    private func startSessionOnQueue() {
        guard hasConfiguredSession, !session.isRunning else { return }
        session.startRunning()
    }

    private func stopSessionOnQueue() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configureSessionIfNeeded() {
        if unavailableReason != nil { return }

        if hasConfiguredSession {
            startSessionOnQueue()
            return
        }

        if isConfiguring { return }
        isConfiguring = true
        defer { isConfiguring = false }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            publishUnavailable(.noDevice)
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            publishUnavailable(.noDevice)
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                publishUnavailable(.noDevice)
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            publishUnavailable(.noDevice)
            return
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            publishUnavailable(.noDevice)
            return
        }

        session.addOutput(photoOutput)
        session.commitConfiguration()

        hasConfiguredSession = true
        DispatchQueue.main.async { [weak self] in
            self?.isConfigured = true
        }

        startSessionOnQueue()
    }

    private func publishUnavailable(_ reason: CameraUnavailableReason) {
        DispatchQueue.main.async { [weak self] in
            self?.markUnavailable(reason)
        }
    }

    private func markUnavailable(_ reason: CameraUnavailableReason) {
        unavailableReason = reason
        isConfigured = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.hasConfiguredSession = false
            self.stopSessionOnQueue()
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completion = captureCompletion
        captureCompletion = nil

        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        // 相機 HDR／P3 → SDR JPEG，再交給 OCR／UI
        let flattened = OCRImageFlattening.flattenImageData(data) ?? data
        DispatchQueue.main.async { completion?(flattened) }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        // 預覽不攔截觸控，避免蓋住 TabBar / 控制列手勢。
        view.isUserInteractionEnabled = false
        if let previewLayer = view.previewLayer {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.isUserInteractionEnabled = false
        if let previewLayer = uiView.previewLayer {
            previewLayer.session = session
        }
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
#endif
