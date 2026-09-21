#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit
import Vision

enum CameraUnavailableReason: Equatable {
    case simulator
    case noDevice
    case permissionDenied
}

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isConfigured = false
    @Published private(set) var unavailableReason: CameraUnavailableReason?
    /// 預覽上偵測到的文字框（Vision 正規化座標，原點在左下）。只用於藍色標示。
    @Published private(set) var detectedTextBoxes: [CGRect] = []
    /// 文字框所屬的直立影像尺寸，用來對齊預覽。
    @Published private(set) var detectionImageSize: CGSize = .zero

    /// 所有 session 設定 / start / stop 必須在此佇列，禁止佔用主執行緒。
    private let sessionQueue = DispatchQueue(label: "com.skincare.cameraSessionQueue")

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionQueue = DispatchQueue(label: "com.skincare.cameraTextVision")
    private var captureCompletion: ((Data?) -> Void)?
    private var isDetectingText = false
    private var lastTextDetectTime: CFTimeInterval = 0
    /// 僅在 sessionQueue 上讀寫。
    private var hasConfiguredSession = false
    private var isConfiguring = false
    /// 僅在 sessionQueue 上讀寫。
    private var videoDevice: AVCaptureDevice?

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

    /// 點擊預覽對焦。`devicePoint` 為 capture device 座標（0...1）。
    func focus(atDevicePoint devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            self?.applyFocus(at: devicePoint, locked: true)
        }
    }

    /// 對成分框附近重新連續對焦（近距）。
    func refocusForIngredientBand() {
        sessionQueue.async { [weak self] in
            self?.applyFocus(at: CGPoint(x: 0.5, y: 0.42), locked: false)
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
        applyFocus(at: CGPoint(x: 0.5, y: 0.42), locked: false)
    }

    private func stopSessionOnQueue() {
        guard session.isRunning else { return }
        session.stopRunning()
        DispatchQueue.main.async { [weak self] in
            self?.detectedTextBoxes = []
            self?.detectionImageSize = .zero
        }
    }

    private func preferredBackCamera() -> AVCaptureDevice? {
        // Dual/triple virtual devices enable automatic macro switching on supported iPhones.
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: .back
        )
        for type in preferredTypes {
            if let device = discovery.devices.first(where: { $0.deviceType == type }) {
                return device
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    private func configureFocusDefaults(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.42)
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.42)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Keep session usable even if focus configuration fails.
        }
    }

    private func applyFocus(at devicePoint: CGPoint, locked: Bool) {
        guard let device = videoDevice else { return }
        let clamped = CGPoint(
            x: min(max(devicePoint.x, 0), 1),
            y: min(max(devicePoint.y, 0), 1)
        )
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = clamped
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = clamped
            }
            if locked, device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore transient focus errors.
        }
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

        guard let device = preferredBackCamera() else {
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
            videoDevice = device
            configureFocusDefaults(for: device)
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
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
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
            self.videoDevice = nil
            self.stopSessionOnQueue()
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = connection
        let now = CACurrentMediaTime()
        guard !isDetectingText, now - lastTextDetectTime > 0.4 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isDetectingText = true
        lastTextDetectTime = now

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let orientedSize = CGSize(width: height, height: width)

        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = false
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        defer { isDetectingText = false }
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.detectedTextBoxes = []
            }
            return
        }
        let boxes = (request.results ?? []).map(\.boundingBox).filter {
            $0.width > 0.02 && $0.height > 0.008
        }
        DispatchQueue.main.async { [weak self] in
            self?.detectionImageSize = orientedSize
            self?.detectedTextBoxes = boxes
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
    var textBoxes: [CGRect] = []
    var detectionImageSize: CGSize = .zero
    var onTapFocus: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapFocus: onTapFocus)
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.isUserInteractionEnabled = onTapFocus != nil
        if let previewLayer = view.previewLayer {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        context.coordinator.attach(to: view)
        view.updateTextHighlights(textBoxes, imageSize: detectionImageSize)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.onTapFocus = onTapFocus
        uiView.isUserInteractionEnabled = onTapFocus != nil
        if let previewLayer = uiView.previewLayer {
            previewLayer.session = session
        }
        uiView.updateTextHighlights(textBoxes, imageSize: detectionImageSize)
    }

    final class Coordinator: NSObject {
        var onTapFocus: ((CGPoint) -> Void)?
        private weak var previewView: CameraPreviewUIView?

        init(onTapFocus: ((CGPoint) -> Void)?) {
            self.onTapFocus = onTapFocus
        }

        func attach(to view: CameraPreviewUIView) {
            previewView = view
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = previewView,
                  let layer = view.previewLayer else { return }
            let viewPoint = gesture.location(in: view)
            let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onTapFocus?(devicePoint)
        }
    }
}

final class CameraPreviewUIView: UIView {
    private let textHighlightLayer = CAShapeLayer()
    private var textBoxes: [CGRect] = []
    private var detectionImageSize: CGSize = .zero

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        textHighlightLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.28).cgColor
        textHighlightLayer.strokeColor = UIColor.systemBlue.cgColor
        textHighlightLayer.lineWidth = 2
        textHighlightLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(textHighlightLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        textHighlightLayer.frame = bounds
        redrawTextHighlights()
    }

    func updateTextHighlights(_ boxes: [CGRect], imageSize: CGSize) {
        textBoxes = boxes
        detectionImageSize = imageSize
        redrawTextHighlights()
    }

    /// 把 Vision 左下原點的文字框畫成藍色，表示預覽裡已看到字。
    private func redrawTextHighlights() {
        guard bounds.width > 1, bounds.height > 1,
              detectionImageSize.width > 1, detectionImageSize.height > 1,
              !textBoxes.isEmpty else {
            textHighlightLayer.path = nil
            return
        }

        let scale = max(
            bounds.width / detectionImageSize.width,
            bounds.height / detectionImageSize.height
        )
        let displayed = CGSize(
            width: detectionImageSize.width * scale,
            height: detectionImageSize.height * scale
        )
        let offset = CGPoint(
            x: (displayed.width - bounds.width) / 2,
            y: (displayed.height - bounds.height) / 2
        )

        let path = CGMutablePath()
        for box in textBoxes {
            let rect = CGRect(
                x: box.minX * displayed.width - offset.x,
                y: (1 - box.maxY) * displayed.height - offset.y,
                width: box.width * displayed.width,
                height: box.height * displayed.height
            ).insetBy(dx: -2, dy: -1)
            guard rect.width > 4, rect.height > 4 else { continue }
            path.addRoundedRect(in: rect, cornerWidth: 4, cornerHeight: 4)
        }
        textHighlightLayer.path = path
    }
}
#endif
