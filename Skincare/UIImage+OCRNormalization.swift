import UIKit

extension UIImage {
    /// 強制重繪為標準 SDR／sRGB，剝離 HDR Headroom 與 Display P3 干擾（進 Vision／ImageIO 前必跑）。
    func flattenedForOCR() -> UIImage {
        let width = size.width
        let height = size.height
        guard width.isFinite, height.isFinite,
              !width.isNaN, !height.isNaN,
              width > 0, height > 0 else {
            return self
        }

        let drawSize = CGSize(width: width, height: height)

        // 先用 UIKit 重繪（正確處理 orientation），並強制 SDR 動態範圍。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.preferredRange = .standard
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: drawSize, format: format)
        let drawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: drawSize))
        }

        // 再 bake 進明確 sRGB 位圖，避免裝置預設 Display P3 觸發 CGImageSetHeadroom。
        guard let sourceCGImage = drawn.cgImage,
              let srgbImage = Self.redrawCGImageInSRGB(sourceCGImage) else {
            return drawn
        }
        return UIImage(cgImage: srgbImage, scale: 1.0, orientation: .up)
    }

    /// 相容舊名稱 → `flattenedForOCR()`。
    func normalizedForOCR() -> UIImage {
        flattenedForOCR()
    }

    /// 先 SDR 扁平化再輸出 JPEG，供相機／相簿寫入管線使用。
    func jpegDataFlattenedForOCR(compressionQuality: CGFloat = 0.86) -> Data? {
        flattenedForOCR().jpegData(compressionQuality: compressionQuality)
    }

    /// 將任意 CGImage 繪入 8-bit sRGB context，去除 P3／HDR headroom。
    static func redrawCGImageInSRGB(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

enum OCRImageFlattening {
    /// 將任意影像 Data（含 HDR HEIC／P3）解碼後扁平為 SDR JPEG。
    static func flattenImageData(_ data: Data, compressionQuality: CGFloat = 0.86) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegDataFlattenedForOCR(compressionQuality: compressionQuality)
    }

    /// 純記憶體 Data → UIImage → flattenedForOCR → SDR JPEG（無檔案系統）。
    static func flattenPickerData(_ data: Data, compressionQuality: CGFloat = 0.86) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let safeImage = uiImage.flattenedForOCR()
        return safeImage.jpegData(compressionQuality: compressionQuality)
    }
}
