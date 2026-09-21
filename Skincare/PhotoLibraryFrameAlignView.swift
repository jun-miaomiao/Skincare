import SwiftUI
#if os(iOS)
import UIKit

/// 相簿選圖後的對齊工作階段（用 item cover，避免空陣列進畫面當機）。
struct PhotoLibraryAlignSession: Identifiable {
    let id = UUID()
    let images: [UIImage]

    init?(images: [UIImage]) {
        let prepared = images.map { $0.flattenedForOCR() }.filter {
            $0.size.width > 8 && $0.size.height > 8
        }
        guard !prepared.isEmpty else { return nil }
        self.images = prepared
    }
}

/// 多張循序對齊：每張確認後裁切，全部完成再送 OCR。
struct PhotoLibraryFrameAlignFlow: View {
    let images: [UIImage]
    let onComplete: ([Data]) -> Void
    let onCancel: () -> Void

    @State private var index = 0
    @State private var croppedResults: [Data] = []

    var body: some View {
        Group {
            if images.isEmpty {
                Color.black
                    .ignoresSafeArea()
                    .onAppear(perform: onCancel)
            } else {
                let safeIndex = min(max(index, 0), images.count - 1)
                PhotoLibraryFrameAlignView(
                    image: images[safeIndex],
                    stepLabel: images.count > 1 ? "\(safeIndex + 1)/\(images.count)" : nil,
                    onConfirm: { data in
                        var next = croppedResults
                        next.append(data)
                        if safeIndex + 1 < images.count {
                            croppedResults = next
                            index = safeIndex + 1
                        } else {
                            onComplete(next)
                        }
                    },
                    onCancel: onCancel
                )
                .id(safeIndex)
            }
        }
    }
}

struct PhotoLibraryFrameAlignView: View {
    let image: UIImage
    var stepLabel: String? = nil
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void

    @State private var hostSize: CGSize = .zero
    @StateObject private var cropper = FrameAlignCropController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FrameAlignScrollRepresentable(image: image, controller: cropper)
                .ignoresSafeArea()

            GeometryReader { geo in
                let size = geo.size
                let rect = IngredientBandGeometry.overlayRect(in: size)
                ZStack {
                    dimmedMask(in: size, hole: rect)

                    IngredientBandCornerFrame()
                        .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .square))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Text("請將全成分對準白框（可雙指縮放、拖曳）")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        // 放在白框上方，避免蓋住成分字影響對焦判斷。
                        .position(x: rect.midX, y: max(rect.minY - 22, 28))
                }
                .onAppear { hostSize = size }
                .onChange(of: size) { _, newSize in
                    hostSize = newSize
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("取消", action: onCancel)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    if let stepLabel {
                        Text(stepLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.45), in: Capsule())
                            .padding(.trailing, 16)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Button {
                    confirmCrop()
                } label: {
                    Text("開始辨識")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .safeAreaPadding(.top, 4)
        }
    }

    private func dimmedMask(in size: CGSize, hole: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.38))
            .frame(width: size.width, height: size.height)
            .mask(
                ZStack {
                    Rectangle().fill(Color.white)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
    }

    private func confirmCrop() {
        let size = hostSize
        guard size.width > 1, size.height > 1 else { return }
        let frame = IngredientBandGeometry.overlayRect(in: size)
        let padded = frame.insetBy(
            dx: -frame.width * IngredientBandGeometry.cropPaddingRatioX,
            dy: -frame.height * IngredientBandGeometry.cropPaddingRatioY
        )
        if let data = cropper.jpegData(croppingTo: padded, in: size) {
            onConfirm(data)
            return
        }
        // 裁切失敗仍給可用 JPEG，避免卡死或當機。
        if let fallback = image.jpegData(compressionQuality: 0.86) {
            onConfirm(fallback)
        }
    }
}

// MARK: - Scroll zoom cropper

@MainActor
final class FrameAlignCropController: ObservableObject {
    weak var scrollView: UIScrollView?
    weak var imageView: UIImageView?
    var image: UIImage?

    func jpegData(croppingTo frameInHost: CGRect, in hostSize: CGSize) -> Data? {
        guard let scrollView, let imageView, let source = image else { return nil }
        let flat = source.flattenedForOCR()

        var frame = frameInHost
        if abs(scrollView.bounds.width - hostSize.width) > 1
            || abs(scrollView.bounds.height - hostSize.height) > 1 {
            let sx = scrollView.bounds.width / max(hostSize.width, 1)
            let sy = scrollView.bounds.height / max(hostSize.height, 1)
            frame = CGRect(
                x: frame.minX * sx,
                y: frame.minY * sy,
                width: frame.width * sx,
                height: frame.height * sy
            )
        }
        frame = frame.intersection(scrollView.bounds)
        guard frame.width >= 32, frame.height >= 32 else {
            return encodeForOCR(flat)
        }

        // 模擬器上 drawHierarchy＋zoom 常得到黑圖；改用 offset/zoom 對應原圖像素。
        if let cropped = cropUsingZoomMath(frameInScrollBounds: frame, flat: flat, scrollView: scrollView, imageView: imageView),
           !Self.isMostlyBlack(cropped) {
            return encodeForOCR(cropped)
        }

        if let cropped = cropUsingConvert(frameInScrollBounds: frame, flat: flat, scrollView: scrollView, imageView: imageView),
           !Self.isMostlyBlack(cropped) {
            return encodeForOCR(cropped)
        }

        // 最後才整張圖，總比黑圖／空裁切好。
        return encodeForOCR(flat)
    }

    private func cropUsingZoomMath(
        frameInScrollBounds frame: CGRect,
        flat: UIImage,
        scrollView: UIScrollView,
        imageView: UIImageView
    ) -> UIImage? {
        let zoom = max(scrollView.zoomScale, 0.0001)
        let offset = scrollView.contentOffset
        let ivFrame = imageView.frame

        var crop = CGRect(
            x: (offset.x + frame.minX - ivFrame.minX) / zoom,
            y: (offset.y + frame.minY - ivFrame.minY) / zoom,
            width: frame.width / zoom,
            height: frame.height / zoom
        )

        let bw = max(imageView.bounds.width, 1)
        let bh = max(imageView.bounds.height, 1)
        crop = CGRect(
            x: crop.minX / bw * flat.size.width,
            y: crop.minY / bh * flat.size.height,
            width: crop.width / bw * flat.size.width,
            height: crop.height / bh * flat.size.height
        )
        return renderCrop(crop, from: flat)
    }

    private func cropUsingConvert(
        frameInScrollBounds frame: CGRect,
        flat: UIImage,
        scrollView: UIScrollView,
        imageView: UIImageView
    ) -> UIImage? {
        let rectInImageView = scrollView.convert(frame, to: imageView)
        let bw = max(imageView.bounds.width, 1)
        let bh = max(imageView.bounds.height, 1)
        let crop = CGRect(
            x: rectInImageView.minX / bw * flat.size.width,
            y: rectInImageView.minY / bh * flat.size.height,
            width: rectInImageView.width / bw * flat.size.width,
            height: rectInImageView.height / bh * flat.size.height
        )
        return renderCrop(crop, from: flat)
    }

    private func renderCrop(_ crop: CGRect, from flat: UIImage) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: flat.size)
        let clipped = crop.integral.intersection(bounds)
        guard clipped.width >= 32, clipped.height >= 32 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: clipped.size, format: format)
        return renderer.image { _ in
            flat.draw(at: CGPoint(x: -clipped.origin.x, y: -clipped.origin.y))
        }
    }

    private func encodeForOCR(_ image: UIImage) -> Data? {
        let boosted = Self.upscaledIfNeeded(image, minLongEdge: 1600).flattenedForOCR()
        return boosted.jpegData(compressionQuality: 0.92)
    }

    private static func upscaledIfNeeded(_ image: UIImage, minLongEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0, longEdge < minLongEdge else { return image }
        let ratio = minLongEdge / longEdge
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 粗略判斷裁切是否幾乎全黑（模擬器 drawHierarchy／錯座標常見）。
    private static func isMostlyBlack(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return true }

        let sampleW = min(width, 48)
        let sampleH = min(height, 48)
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: sampleW * sampleH * bytesPerPixel)
        guard let ctx = CGContext(
            data: &data,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        var sum = 0
        let count = sampleW * sampleH
        for i in 0..<count {
            let o = i * bytesPerPixel
            sum += Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2])
        }
        let average = Double(sum) / Double(max(count * 3, 1))
        return average < 18
    }
}

struct FrameAlignScrollRepresentable: UIViewRepresentable {
    let image: UIImage
    let controller: FrameAlignCropController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.backgroundColor = .black
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        scroll.alwaysBounceHorizontal = true
        scroll.bouncesZoom = true
        scroll.isScrollEnabled = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = true
        scroll.minimumZoomScale = 0.2
        scroll.maximumZoomScale = 8
        scroll.pinchGestureRecognizer?.isEnabled = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = false
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        context.coordinator.configuredImageIdentity = ObjectIdentifier(image)
        controller.scrollView = scroll
        controller.imageView = imageView
        controller.image = image

        // 等 bounds 就緒後只排一次，之後不再重設 zoom。
        DispatchQueue.main.async {
            context.coordinator.layoutImageIfNeeded(in: scroll, image: image, force: true)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        controller.scrollView = scroll
        controller.imageView = context.coordinator.imageView
        controller.image = image

        let identity = ObjectIdentifier(image)
        if context.coordinator.configuredImageIdentity != identity {
            context.coordinator.configuredImageIdentity = identity
            context.coordinator.hasLaidOut = false
            context.coordinator.userAdjustedZoom = false
            context.coordinator.imageView?.image = image
            context.coordinator.layoutImageIfNeeded(in: scroll, image: image, force: true)
            return
        }

        // 已排版後只同步 inset；SwiftUI 重繪／小幅改尺寸不得重設 zoom。
        let size = scroll.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let rotated = abs(size.width - context.coordinator.lastLayoutSize.height) < 24
            && abs(size.height - context.coordinator.lastLayoutSize.width) < 24
            && abs(size.width - context.coordinator.lastLayoutSize.width) > 40
        if !context.coordinator.hasLaidOut {
            context.coordinator.layoutImageIfNeeded(in: scroll, image: image, force: true)
        } else if rotated {
            context.coordinator.layoutImageIfNeeded(in: scroll, image: image, force: true)
        } else {
            context.coordinator.applyAlignmentInsets(in: scroll)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var lastLayoutSize: CGSize = .zero
        var configuredImageIdentity: ObjectIdentifier?
        var hasLaidOut = false
        /// 使用者開始捏合後，禁止 layout 覆寫縮放。
        var userAdjustedZoom = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            userAdjustedZoom = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            applyAlignmentInsets(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            applyAlignmentInsets(in: scrollView)
        }

        func layoutImageIfNeeded(in scroll: UIScrollView, image: UIImage, force: Bool) {
            let size = scroll.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            // 使用者已縮放過：只更新尺寸記錄，不重設 zoom。
            if hasLaidOut, userAdjustedZoom, !force {
                applyAlignmentInsets(in: scroll)
                return
            }
            if hasLaidOut, !force,
               abs(size.width - lastLayoutSize.width) <= 12,
               abs(size.height - lastLayoutSize.height) <= 12 {
                applyAlignmentInsets(in: scroll)
                return
            }

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let previousZoom = scroll.zoomScale
            let previousMin = max(scroll.minimumZoomScale, 0.0001)
            let relativeZoom = hasLaidOut ? previousZoom / previousMin : 1

            imageView?.image = image
            imageView?.frame = CGRect(origin: .zero, size: imageSize)
            scroll.contentSize = imageSize

            let fitScale = min(size.width / imageSize.width, size.height / imageSize.height)
            let fillScale = max(size.width / imageSize.width, size.height / imageSize.height)
            // 最小縮放需能小於白框，最大可放很大方便對準密排文字。
            let minZoom = max(fitScale * 0.55, 0.04)
            let maxZoom = max(fillScale * 6, fitScale * 14, 5)

            scroll.minimumZoomScale = minZoom
            scroll.maximumZoomScale = maxZoom

            if hasLaidOut, userAdjustedZoom {
                let restored = min(max(minZoom * relativeZoom, minZoom), maxZoom)
                scroll.zoomScale = restored
            } else {
                scroll.zoomScale = fitScale
                userAdjustedZoom = false
            }

            lastLayoutSize = size
            hasLaidOut = true
            applyAlignmentInsets(in: scroll)
            centerImageInBand(in: scroll)
        }

        /// 以白框為「裁切窗」設 inset，圖片才能拖進框內（不只置中螢幕）。
        func applyAlignmentInsets(in scroll: UIScrollView) {
            let bounds = scroll.bounds
            guard bounds.width > 1, bounds.height > 1, let imageView else { return }

            let band = IngredientBandGeometry.overlayRect(in: bounds.size)
            var inset = UIEdgeInsets(
                top: max(band.minY, 0),
                left: max(band.minX, 0),
                bottom: max(bounds.height - band.maxY, 0),
                right: max(bounds.width - band.maxX, 0)
            )

            // 縮放後圖比白框小：再加餘裕，仍可在框內微移。
            let scaledWidth = imageView.frame.width
            let scaledHeight = imageView.frame.height
            if scaledWidth < band.width {
                let extra = (band.width - scaledWidth) * 0.5
                inset.left += extra
                inset.right += extra
            }
            if scaledHeight < band.height {
                let extra = (band.height - scaledHeight) * 0.5
                inset.top += extra
                inset.bottom += extra
            }

            scroll.contentInset = inset
            scroll.scrollIndicatorInsets = inset
        }

        private func centerImageInBand(in scroll: UIScrollView) {
            guard let imageView else { return }
            let bounds = scroll.bounds
            let band = IngredientBandGeometry.overlayRect(in: bounds.size)
            let scaledWidth = imageView.frame.width
            let scaledHeight = imageView.frame.height
            let inset = scroll.contentInset

            let offsetX = -inset.left + (scaledWidth - band.width) * 0.5
            let offsetY = -inset.top + (scaledHeight - band.height) * 0.5
            let maxX = max(scaledWidth - bounds.width + inset.right, -inset.left)
            let maxY = max(scaledHeight - bounds.height + inset.bottom, -inset.top)
            scroll.contentOffset = CGPoint(
                x: min(max(offsetX, -inset.left), maxX),
                y: min(max(offsetY, -inset.top), maxY)
            )
        }
    }
}
#endif
