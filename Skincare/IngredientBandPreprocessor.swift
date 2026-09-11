#if canImport(UIKit)
import UIKit

/// 相機拍照後只把「成分帶」交給 Vision：裁切、提高對比，再輸出 JPEG。
enum IngredientBandPreprocessor {
    static func jpegDataForCameraOCR(
        _ image: UIImage,
        previewSize: CGSize,
        compressionQuality: CGFloat = 0.86
    ) -> Data? {
        let prepared = croppedAndFlattened(image, previewSize: previewSize)
        return prepared.jpegData(compressionQuality: compressionQuality)
    }

    static func jpegDataForCameraOCR(
        imageData: Data,
        previewSize: CGSize,
        compressionQuality: CGFloat = 0.86
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return jpegDataForCameraOCR(
            image,
            previewSize: previewSize,
            compressionQuality: compressionQuality
        )
    }

    /// 相簿沒有即時白框預覽時，退回中央成分帶裁切，避免整張圖亂掃。
    static func jpegDataForPhotoLibraryOCR(
        _ image: UIImage,
        compressionQuality: CGFloat = 0.86
    ) -> Data? {
        let prepared = croppedAndFlattenedPhotoLibraryImage(image)
        return prepared.jpegData(compressionQuality: compressionQuality)
    }

    static func jpegDataForPhotoLibraryOCR(
        imageData: Data,
        compressionQuality: CGFloat = 0.86
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        return jpegDataForPhotoLibraryOCR(
            image,
            compressionQuality: compressionQuality
        )
    }

    static func croppedAndFlattened(_ image: UIImage, previewSize: CGSize) -> UIImage {
        let flat = image.flattenedForOCR()
        let crop = IngredientBandGeometry.imageCropRect(
            imageSize: flat.size,
            previewSize: previewSize
        )
        return cropped(flat, to: crop) ?? flat
    }

    static func croppedAndFlattenedPhotoLibraryImage(_ image: UIImage) -> UIImage {
        let flat = image.flattenedForOCR()
        let crop = IngredientBandGeometry.fallbackCenterBand(in: flat.size)
        return cropped(flat, to: crop) ?? flat
    }

    static func cropped(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let scale = max(image.scale, 1)
        var pixelRect = CGRect(
            x: (rect.minX * scale).rounded(.down),
            y: (rect.minY * scale).rounded(.down),
            width: (rect.width * scale).rounded(.down),
            height: (rect.height * scale).rounded(.down)
        )
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        pixelRect = pixelRect.intersection(bounds)
        guard pixelRect.width >= 32, pixelRect.height >= 32,
              let cut = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        return UIImage(cgImage: cut, scale: 1, orientation: .up)
    }
}
#endif
