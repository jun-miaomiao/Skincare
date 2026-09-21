import SwiftUI
#if os(iOS)
import UIKit

/// 相簿選圖後：用與相機相同的白框對齊全成分，確認後才裁切送 OCR。
struct PhotoLibraryFrameAlignFlow: View {
    let images: [UIImage]
    let onComplete: ([Data]) -> Void
    let onCancel: () -> Void

    @State private var index = 0
    @State private var croppedResults: [Data] = []

    var body: some View {
        PhotoLibraryFrameAlignView(
            image: images[index],
            stepLabel: images.count > 1 ? "\(index + 1)/\(images.count)" : nil,
            onConfirm: { data in
                var next = croppedResults
                next.append(data)
                if index + 1 < images.count {
                    croppedResults = next
                    index += 1
                } else {
                    onComplete(next)
                }
            },
            onCancel: onCancel
        )
        .id(index)
    }
}

struct PhotoLibraryFrameAlignView: View {
    let image: UIImage
    var stepLabel: String? = nil
    let onConfirm: (Data) -> Void
    let onCancel: () -> Void

    @State private var previewSize: CGSize = .zero
    @StateObject private var cropper = FrameAlignCropController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FrameAlignScrollRepresentable(image: image, controller: cropper)
                .ignoresSafeArea()

            GeometryReader { geo in
                let rect = IngredientBandGeometry.overlayRect(in: geo.size)
                ZStack {
                    dimmedMask(in: geo.size, hole: rect)

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
                        .position(x: rect.midX, y: rect.maxY - 18)
                }
                .onAppear { previewSize = geo.size }
                .onChange(of: geo.size) { _, size in
                    previewSize = size
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("取消", action: onCancel)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(16)

                    Spacer()

                    if let stepLabel {
                        Text(stepLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }

                    Button("開始辨識") {
                        confirmCrop()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(16)
                }
                Spacer()
            }
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
        let size = previewSize
        guard size.width > 1, size.height > 1 else { return }
        let frame = IngredientBandGeometry.overlayRect(in: size)
        // 裁切略大於白框，與相機路徑一致。
        let padded = frame.insetBy(
            dx: -frame.width * IngredientBandGeometry.cropPaddingRatioX,
            dy: -frame.height * IngredientBandGeometry.cropPaddingRatioY
        )
        guard let data = cropper.jpegData(croppingTo: padded, in: size) else { return }
        onConfirm(data)
    }
}

// MARK: - Scroll zoom cropper

@MainActor
final class FrameAlignCropController: ObservableObject {
    weak var scrollView: UIScrollView?
    weak var imageView: UIImageView?
    var image: UIImage?

    func jpegData(croppingTo frameInView: CGRect, in viewSize: CGSize) -> Data? {
        guard let scrollView, let imageView, let image else { return nil }
        guard let cgImage = image.cgImage else {
            return image.jpegData(compressionQuality: 0.86)
        }

        // 白框座標與 scrollView.bounds 對齊（全螢幕）。
        let rectInImageView = scrollView.convert(frameInView, to: imageView)
        guard imageView.bounds.width > 1, imageView.bounds.height > 1 else {
            return IngredientBandPreprocessor.jpegDataForPhotoLibraryOCR(image)
        }

        let pixelScaleX = CGFloat(cgImage.width) / imageView.bounds.width
        let pixelScaleY = CGFloat(cgImage.height) / imageView.bounds.height
        var pixelRect = CGRect(
            x: (rectInImageView.minX * pixelScaleX).rounded(.down),
            y: (rectInImageView.minY * pixelScaleY).rounded(.down),
            width: (rectInImageView.width * pixelScaleX).rounded(.down),
            height: (rectInImageView.height * pixelScaleY).rounded(.down)
        )
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        pixelRect = pixelRect.intersection(bounds)
        guard pixelRect.width >= 32, pixelRect.height >= 32,
              let cut = cgImage.cropping(to: pixelRect) else {
            return IngredientBandPreprocessor.jpegDataForPhotoLibraryOCR(image)
        }

        let cropped = UIImage(cgImage: cut, scale: 1, orientation: .up)
            .flattenedForOCR()
        return cropped.jpegData(compressionQuality: 0.86)
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
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        controller.scrollView = scroll
        controller.imageView = imageView
        controller.image = image

        DispatchQueue.main.async {
            context.coordinator.layoutImageIfNeeded(in: scroll, image: image)
        }

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        controller.scrollView = scroll
        controller.imageView = context.coordinator.imageView
        controller.image = image
        context.coordinator.layoutImageIfNeeded(in: scroll, image: image)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        private var lastLayoutSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func layoutImageIfNeeded(in scroll: UIScrollView, image: UIImage) {
            let size = scroll.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let sizeChanged = abs(size.width - lastLayoutSize.width) > 0.5
                || abs(size.height - lastLayoutSize.height) > 0.5
            guard sizeChanged || imageView?.image == nil else { return }
            lastLayoutSize = size

            imageView?.image = image
            scroll.zoomScale = 1
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            // 以 aspectFill 塞滿，方便對白框。
            let fillScale = max(size.width / imageSize.width, size.height / imageSize.height)
            let fitted = CGSize(
                width: imageSize.width * fillScale,
                height: imageSize.height * fillScale
            )
            imageView?.frame = CGRect(origin: .zero, size: fitted)
            scroll.contentSize = fitted
            scroll.contentOffset = CGPoint(
                x: max((fitted.width - size.width) / 2, 0),
                y: max((fitted.height - size.height) / 2, 0)
            )
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 6
        }
    }
}
#endif
