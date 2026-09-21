import CoreGraphics
import SwiftUI

/// 相機取景框幾何：畫面框與拍照裁切共用，避免「框內是成分、OCR 卻吃整張圖」。
enum IngredientBandGeometry {
    /// 框太大會把字縮小、雜訊變多；略大於舊版即可。
    static let widthRatio: CGFloat = 0.86
    static let maxFrameWidth: CGFloat = 370
    static let heightOverWidth: CGFloat = 0.68
    static let bottomPaddingRatio: CGFloat = 0.08
    static let minBottomPadding: CGFloat = 36
    /// 裁切比白框略大，避免貼邊的密排 INCI 被切字。
    static let cropPaddingRatioX: CGFloat = 0.06
    static let cropPaddingRatioY: CGFloat = 0.08

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
        let frameHeight = min(frameWidth * heightOverWidth, availableHeight * 0.82)
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
        let clipped = padded.intersection(imageBounds)
        guard clipped.width >= imageSize.width * 0.2,
              clipped.height >= imageSize.height * 0.12 else {
            return fallbackCenterBand(in: imageSize)
        }
        return clipped
    }

    /// 相簿／無預覽：中央橫帶（勿開太大，否則背景雜訊會蓋過密排 INCI）。
    static func fallbackCenterBand(in imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let width = imageSize.width * 0.90
        let height = imageSize.height * 0.50
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
