import CoreImage
import Foundation
import UIKit
@preconcurrency import Vision

struct OCRLineResult: Sendable {
    let text: String
    let confidence: Float
}

struct OCRRecognitionResult: Sendable {
    let lines: [OCRLineResult]

    var texts: [String] { lines.map(\.text) }

    /// 有候選字時的平均信心度；無可讀結果時為 `nil`。
    var averageConfidence: Float? {
        let scores = lines.map(\.confidence).filter { $0.isFinite && $0 > 0 }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Float(scores.count)
    }
}

class OCRManager {
    static let shared = OCRManager()

    /// Vision 前處理：長邊上限（px），避免 4K/12MP 原圖拖慢辨識。
    private static let maxOCRLongEdge: CGFloat = 2000
    /// 相機已裁成分帶後，用較高解析度讀密排 INCI。
    static let ingredientBandLongEdge: CGFloat = 2200

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    struct MergedOCRText: Sendable {
        let text: String
        /// 各張照片 OCR 原文（已依選取順序排列），供循序成分合併。
        let perImageTexts: [String]
        let averageConfidence: Float?
        let lineCount: Int
        let sourceImageCount: Int
    }

    func recognizeText(from image: UIImage) async -> [String] {
        await recognize(from: image).texts
    }

    func recognize(from image: UIImage, maxLongEdge: CGFloat = OCRManager.maxOCRLongEdge) async -> OCRRecognitionResult {
        let prepared = Self.prepareImageForOCR(image, maxLongEdge: maxLongEdge)
        guard let cgImage = prepared.cgImage else {
            return OCRRecognitionResult(lines: [])
        }

        let visionCGImage = UIImage.redrawCGImageInSRGB(cgImage) ?? cgImage

        // Run Vision entirely inside a detached task (no completion-handler / queue captures).
        let cgImageForOCR = visionCGImage
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "zh-Hant", "ja-JP", "ko-KR"]
            // 密排 INCI 單行往往矮於預設 1/32，不降低會整行被丟掉。
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: cgImageForOCR, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return OCRRecognitionResult(lines: [])
            }

            let observations = (request.results ?? []).sorted { lhs, rhs in
                let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
                if abs(dy) > 0.012 { return dy > 0 }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let lines: [OCRLineResult] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLineResult(text: candidate.string, confidence: candidate.confidence)
            }
            return OCRRecognitionResult(lines: lines)
        }.value
    }

    static func prepareImageForOCR(_ image: UIImage, maxLongEdge: CGFloat = 2000) -> UIImage {
        let flattened = image.flattenedForOCR()
        let contrasted = enhanceContrastForOCR(flattened)
        return downsampleForOCR(contrasted, maxLongEdge: maxLongEdge)
    }

    /// 略提高對比，讓反光／淺灰印刷的密排字更接近 Vision 可讀範圍。不改幾何、不銳化到產生偽影。
    static func enhanceContrastForOCR(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1.16, forKey: kCIInputContrastKey)
        filter.setValue(0.03, forKey: kCIInputBrightnessKey)
        filter.setValue(0.92, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let rendered = ciContext.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: rendered, scale: 1, orientation: .up)
    }

    static func downsampleForOCR(_ image: UIImage, maxLongEdge: CGFloat = 2000) -> UIImage {
        let pixelWidth = max(image.size.width * image.scale, 1)
        let pixelHeight = max(image.size.height * image.scale, 1)
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              !pixelWidth.isNaN, !pixelHeight.isNaN else {
            return image.flattenedForOCR()
        }

        let longest = max(pixelWidth, pixelHeight)
        let targetSize: CGSize
        if longest > maxLongEdge {
            let ratio = maxLongEdge / longest
            guard ratio.isFinite, !ratio.isNaN, ratio > 0 else {
                return image.flattenedForOCR()
            }
            targetSize = CGSize(
                width: max(1, floor(pixelWidth * ratio)),
                height: max(1, floor(pixelHeight * ratio))
            )
        } else {
            targetSize = CGSize(width: floor(pixelWidth), height: floor(pixelHeight))
        }

        guard targetSize.width >= 1, targetSize.height >= 1,
              targetSize.width.isFinite, targetSize.height.isFinite else {
            return image.flattenedForOCR()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let cgImage = scaled.cgImage,
              let srgb = UIImage.redrawCGImageInSRGB(cgImage) else {
            return scaled.flattenedForOCR()
        }
        return UIImage(cgImage: srgb, scale: 1.0, orientation: .up)
    }

    func recognizeMergedText(from images: [UIImage]) async -> String {
        await recognizeMerged(from: images).text
    }

    func recognizeMerged(
        from images: [UIImage],
        maxLongEdge: CGFloat = OCRManager.maxOCRLongEdge
    ) async -> MergedOCRText {
        guard !images.isEmpty else {
            return MergedOCRText(
                text: "",
                perImageTexts: [],
                averageConfidence: nil,
                lineCount: 0,
                sourceImageCount: 0
            )
        }

        if images.count == 1 {
            let result = await recognize(from: images[0], maxLongEdge: maxLongEdge)
            let joined = IngredientParser.joinOCRLines(result.texts)
            return MergedOCRText(
                text: joined,
                perImageTexts: joined.isEmpty ? [] : [joined],
                averageConfidence: result.averageConfidence,
                lineCount: result.lines.count,
                sourceImageCount: 1
            )
        }

        // 平行 OCR，但以輸入索引回填，嚴格維持 Photo 1 → 2 → 3 順序。
        let orderedResults: [OCRRecognitionResult] = await withTaskGroup(
            of: (Int, OCRRecognitionResult).self
        ) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let result = await self.recognize(from: image, maxLongEdge: maxLongEdge)
                    return (index, result)
                }
            }
            var ordered = Array(repeating: OCRRecognitionResult(lines: []), count: images.count)
            for await (index, result) in group {
                ordered[index] = result
            }
            return ordered
        }

        let perImageTexts = orderedResults.map { IngredientParser.joinOCRLines($0.texts) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let nonEmptyTexts = perImageTexts.filter { !$0.isEmpty }
        let allLines = orderedResults.flatMap(\.lines)
        let confidences = allLines.map(\.confidence).filter { $0.isFinite && $0 > 0 }
        let average: Float? = confidences.isEmpty
            ? nil
            : confidences.reduce(0, +) / Float(confidences.count)

        return MergedOCRText(
            text: nonEmptyTexts.joined(separator: ", "),
            perImageTexts: perImageTexts,
            averageConfidence: average,
            lineCount: allLines.count,
            sourceImageCount: images.count
        )
    }

    func recognizeMergedText(from imageDataList: [Data]) async -> String {
        await recognizeMerged(fromImageDataList: imageDataList).text
    }

    func recognizeMerged(
        fromImageDataList imageDataList: [Data],
        maxLongEdge: CGFloat = OCRManager.maxOCRLongEdge
    ) async -> MergedOCRText {
        let images: [UIImage] = await Task.detached(priority: .userInitiated) {
            imageDataList.compactMap { UIImage(data: $0) }
        }.value
        return await recognizeMerged(from: images, maxLongEdge: maxLongEdge)
    }
}
