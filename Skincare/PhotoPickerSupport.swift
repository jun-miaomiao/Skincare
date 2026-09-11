import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

// MARK: - Legacy UIImagePicker（僅記憶體 UIImage，禁用 imageURL／檔案路徑）

#if os(iOS)
struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    var cropsToIngredientBand: Bool = false
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            cropsToIngredientBand: cropsToIngredientBand,
            onCapture: onCapture,
            onCancel: onCancel
        )
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let cropsToIngredientBand: Bool
        let onCapture: (Data) -> Void
        let onCancel: () -> Void

        init(
            cropsToIngredientBand: Bool,
            onCapture: @escaping (Data) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.cropsToIngredientBand = cropsToIngredientBand
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 嚴禁使用 .imageURL / .referenceURL（會觸發 FileProvider bookmark）。
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            let data = image.flatMap { selectedImage in
                if cropsToIngredientBand {
                    return IngredientBandPreprocessor.jpegDataForPhotoLibraryOCR(
                        selectedImage,
                        compressionQuality: 0.86
                    )
                }
                return selectedImage.jpegDataFlattenedForOCR(compressionQuality: 0.86)
            }
            if let data {
                onCapture(data)
            } else {
                onCancel()
            }
        }
    }
}
#endif

// MARK: - PHPicker 純記憶體選圖（loadObject UIImage，零 Bookmark／零外部 URL）

#if canImport(PhotosUI) && os(iOS)
/// 以 `PHPickerViewController` + `loadObject(ofClass: UIImage.self)` 載入，
/// 不呼叫 `loadDataRepresentation`、`bookmarkData`、`startAccessingSecurityScopedResource`。
struct InMemoryPHPickerView: UIViewControllerRepresentable {
    var maxSelectionCount: Int = ModernPhotoLoader.maxSelectionCount
    var onPickedImages: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPickedImages: onPickedImages, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = max(1, maxSelectionCount)
        // 嚴格依使用者點選順序回傳（Photo 1 → 2 → 3），供循序重疊拼接。
        configuration.selection = .ordered
        // 相容表示，降低 HDR／雲端檔案代理路徑
        configuration.preferredAssetRepresentationMode = .compatible

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPickedImages: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onPickedImages: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onPickedImages = onPickedImages
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else {
                onCancel()
                return
            }

            // `selection = .ordered` 時 results 即為點選順序；載入時逐項依序 append，不重排。
            let providers = results.map(\.itemProvider)
            Task {
                var images: [UIImage] = []
                images.reserveCapacity(providers.count)

                for provider in providers {
                    if let image = await Self.loadUIImageInMemory(from: provider) {
                        images.append(image.flattenedForOCR())
                    }
                }

                await MainActor.run {
                    if images.isEmpty {
                        onCancel()
                    } else {
                        onPickedImages(images)
                    }
                }
            }
        }

        /// 只走記憶體 UIImage；不讀檔案 URL、不建 Security Bookmark。
        private static func loadUIImageInMemory(from provider: NSItemProvider) async -> UIImage? {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}
#endif

// MARK: - 記憶體影像 → OCR 用 SDR JPEG

enum ModernPhotoLoader {
    static let maxSelectionCount = 3

    /// UIImage（已在記憶體）→ flattenedForOCR → JPEG Data。
    static func jpegData(
        from image: UIImage,
        compressionQuality: CGFloat = 0.86,
        cropsToIngredientBand: Bool = false
    ) -> Data? {
        if cropsToIngredientBand {
            return IngredientBandPreprocessor.jpegDataForPhotoLibraryOCR(
                image,
                compressionQuality: compressionQuality
            )
        }
        return image.flattenedForOCR().jpegData(compressionQuality: compressionQuality)
    }

    static func jpegDataList(
        from images: [UIImage],
        compressionQuality: CGFloat = 0.86,
        cropsToIngredientBand: Bool = false
    ) -> [Data] {
        images.compactMap {
            jpegData(
                from: $0,
                compressionQuality: compressionQuality,
                cropsToIngredientBand: cropsToIngredientBand
            )
        }
    }

    /// 純記憶體 Data → UIImage → SDR JPEG（無檔案系統）。
    static func flattenPickerData(_ data: Data, compressionQuality: CGFloat = 0.86) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpegData(from: image, compressionQuality: compressionQuality)
    }
}

// MARK: - Sheet 包裝：統一相簿入口

struct ModernPhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var maxSelectionCount: Int = ModernPhotoLoader.maxSelectionCount
    var cropsToIngredientBand: Bool = false
    var onPickedData: ([Data]) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                #if canImport(PhotosUI) && os(iOS)
                InMemoryPHPickerView(
                    maxSelectionCount: maxSelectionCount,
                    onPickedImages: { images in
                        let dataList = ModernPhotoLoader.jpegDataList(
                            from: images,
                            cropsToIngredientBand: cropsToIngredientBand
                        )
                        isPresented = false
                        if !dataList.isEmpty {
                            onPickedData(dataList)
                        }
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
                .ignoresSafeArea()
                #else
                Text("此平台不支援相簿選圖")
                    .padding()
                #endif
            }
    }
}
