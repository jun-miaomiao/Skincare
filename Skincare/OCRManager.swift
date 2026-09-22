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
        guard prepared.cgImage != nil else {
            return OCRRecognitionResult(lines: [])
        }

        let whole = await recognizePrepared(prepared)
        // 白框是扁的。整框一起認時，密排小字佔整張圖太矮，中間會整段消失。
        // 切成較矮、上下重疊的橫帶後，每一行在那一條裡變高；行數變多才採用。
        guard prepared.size.width > prepared.size.height * 1.15 else {
            return whole
        }
        let sliced = await recognizeHorizontalBands(prepared)
        return sliced.lines.count > whole.lines.count ? sliced : whole
    }

    private func recognizeHorizontalBands(_ image: UIImage) async -> OCRRecognitionResult {
        // 每條約三分之一高，下一條往下移一半，避免一行被切在邊界上。
        let bandHeightRatio: CGFloat = 0.34
        let stepRatio: CGFloat = 0.17
        var lines: [OCRLineResult] = []
        var seen = Set<String>()

        var index = 0
        while index < 8 {
            let yRatio = stepRatio * CGFloat(index)
            if yRatio >= 0.995 { break }
            let heightRatio = min(bandHeightRatio, 1 - yRatio)
            if heightRatio < 0.12 { break }
            let y = image.size.height * yRatio
            let rect = CGRect(
                x: 0,
                y: y,
                width: image.size.width,
                height: image.size.height * heightRatio
            )
            index += 1
            guard let slice = Self.crop(image, to: rect) else { continue }
            let prepared = Self.prepareImageForOCR(slice, maxLongEdge: Self.ingredientBandLongEdge)
            let result = await recognizePrepared(prepared)
            for line in result.lines {
                let key = line.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(with: Locale(identifier: "en_US_POSIX"))
                guard key.count >= 2, seen.insert(key).inserted else { continue }
                lines.append(line)
            }
        }
        return OCRRecognitionResult(lines: lines)
    }

    private func recognizePrepared(_ image: UIImage) async -> OCRRecognitionResult {
        let edged = Self.insetSoEdgeLinesAreReadable(image)
        guard let cgImage = edged.cgImage else {
            return OCRRecognitionResult(lines: [])
        }
        let visionCGImage = UIImage.redrawCGImageInSRGB(cgImage) ?? cgImage

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "zh-Hant", "ja-JP", "ko-KR"]
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: visionCGImage, options: [:])
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

    /// Vision 會丟掉貼在圖片邊緣的字。只留一條細邊，避免把每一行墊矮。
    private static func insetSoEdgeLinesAreReadable(_ image: UIImage) -> UIImage {
        let padY = max(image.size.height * 0.012, 8)
        let padX = max(image.size.width * 0.012, 8)
        let canvas = CGSize(width: image.size.width + padX * 2, height: image.size.height + padY * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            image.draw(in: CGRect(x: padX, y: padY, width: image.size.width, height: image.size.height))
        }
    }

    private static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let pixel = rect.integral.intersection(bounds)
        guard pixel.width >= 32, pixel.height >= 32,
              let cut = cgImage.cropping(to: pixel) else {
            return nil
        }
        return UIImage(cgImage: cut, scale: 1, orientation: .up)
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
