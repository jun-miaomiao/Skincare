#if canImport(UIKit)
import UIKit

enum AvatarImageProcessor {
    static func compressedJPEG(from data: Data, maxDimension: CGFloat = 512, quality: CGFloat = 0.75) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resize(image: image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    private static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
