import CoreGraphics
import SwiftUI

/// 相機取景框幾何：畫面框與拍照裁切共用，避免「框內是成分、OCR 卻吃整張圖」。
enum IngredientBandGeometry {
    static let widthRatio: CGFloat = 0.82
    static let maxFrameWidth: CGFloat = 340
    static let heightOverWidth: CGFloat = 0.62
    static let bottomPaddingRatio: CGFloat = 0.08
    static let minBottomPadding: CGFloat = 36
    /// OCR 裁切比白框更高更寬：視覺框只負責對焦，辨識要多吃上下密排成分。
    static let cropPaddingRatioX: CGFloat = 0.12
    static let cropPaddingRatioY: CGFloat = 0.42

    static func bottomPadding(forHeight height: CGFloat) -> CGFloat {
        max(height * bottomPaddingRatio, minBottomPadding)
    }

    /// 預覽上的成分帶（pt），與 `CameraScanGuideOverlay` 白框同一套計算。
    static func overlayRect(in viewSize: CGSize) -> CGRect {
        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)
        let bottom = bottomPadding(forHeight: height)
        let availableHeight = max(height - bottom, 1)
        let frameWidth = min(width * widthRatio, maxFrameWidth)
        let frameHeight = frameWidth * heightOverWidth
        let x = (width - frameWidth) / 2
        let y = (availableHeight - frameHeight) / 2
        return CGRect(x: x, y: y, width: frameWidth, height: frameHeight)
    }

    /// 預覽為 aspectFill 時，把白框對應回照片像素座標。
    static func imageCropRect(imageSize: CGSize, previewSize: CGSize) -> CGRect {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        guard imageSize.width > 8, imageSize.height > 8 else { return imageBounds }

        let overlay: CGRect
        if previewSize.width > 8, previewSize.height > 8 {
            overlay = overlayRect(in: previewSize)
        } else {
            return fallbackCenterBand(in: imageSize)
        }

        let scale = max(
            previewSize.width / imageSize.width,
            previewSize.height / imageSize.height
        )
        guard scale.isFinite, scale > 0 else { return fallbackCenterBand(in: imageSize) }

        let displayed = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let offset = CGPoint(
            x: (displayed.width - previewSize.width) / 2,
            y: (displayed.height - previewSize.height) / 2
        )

        let mapped = CGRect(
            x: (overlay.minX + offset.x) / scale,
            y: (overlay.minY + offset.y) / scale,
            width: overlay.width / scale,
            height: overlay.height / scale
        )
        let padded = mapped.insetBy(
            dx: -mapped.width * cropPaddingRatioX,
            dy: -mapped.height * cropPaddingRatioY
        )
        var clipped = padded.intersection(imageBounds)
        guard clipped.width >= imageSize.width * 0.2,
              clipped.height >= imageSize.height * 0.10 else {
            return fallbackCenterBand(in: imageSize)
        }
        // 預覽 16:9、照片 4:3 時對不準，至少給足夠高的橫帶，避免只吃到空白。
        let minHeight = imageSize.height * 0.58
        if clipped.height < minHeight {
            let extra = (minHeight - clipped.height) / 2
            clipped = CGRect(
                x: clipped.minX,
                y: max(0, clipped.minY - extra),
                width: clipped.width,
                height: min(minHeight, imageSize.height)
            ).intersection(imageBounds)
        }
        return clipped
    }

    /// 沒有預覽尺寸時：取照片中央橫帶（成分表通常在這個位置）。
    static func fallbackCenterBand(in imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let width = imageSize.width * 0.94
        let height = imageSize.height * 0.72
        let rect = CGRect(
            x: (imageSize.width - width) / 2,
            y: (imageSize.height - height) / 2,
            width: width,
            height: height
        )
        return rect.intersection(bounds)
    }
}

/// 相機預覽實際尺寸，供拍照後裁切成分帶。
enum CameraPreviewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}
