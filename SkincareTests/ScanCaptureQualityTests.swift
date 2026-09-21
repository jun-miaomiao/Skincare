import CoreGraphics
import Foundation
import Testing
@testable import Skincare

struct ScanCaptureQualityTests {

    @Test func zeroHitsAlwaysNeedsRetake() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 0,
                tokenCount: 0,
                averageOCRConfidence: 0.9
            ) == .needsRetake
        )
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 0,
                tokenCount: 24,
                averageOCRConfidence: 0.85
            ) == .needsRetake
        )
    }

    @Test func strongHitsPassEvenWithModerateConfidence() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 12,
                tokenCount: 14,
                averageOCRConfidence: 0.45
            ) == .acceptable
        )
    }

    @Test func weakHitsWithLowConfidenceNeedRetake() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 3,
                tokenCount: 5,
                averageOCRConfidence: 0.22
            ) == .needsRetake
        )
    }

    @Test func weakHitsWithHighConfidenceAreAcceptable() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 3,
                tokenCount: 4,
                averageOCRConfidence: 0.72
            ) == .acceptable
        )
    }

    @Test func longListWithLowHitRateNeedsRetake() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 5,
                tokenCount: 40,
                averageOCRConfidence: 0.8
            ) == .needsRetake
        )
    }

    @Test func longListWithMostlyMatchedTokensPasses() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 38,
                tokenCount: 50,
                averageOCRConfidence: 0.55
            ) == .acceptable
        )
    }

    @Test func missingConfidenceDoesNotBlockHits() {
        #expect(
            ScanCaptureQuality.evaluate(
                dictionaryHitCount: 8,
                tokenCount: 10,
                averageOCRConfidence: nil
            ) == .acceptable
        )
    }
}

struct IngredientBandGeometryTests {

    @Test func overlayRectMatchesViewfinderAspectAndWidthCap() {
        let size = CGSize(width: 393, height: 700)
        let rect = IngredientBandGeometry.overlayRect(in: size)
        let expectedWidth = min(393 * 0.86, 370)
        #expect(abs(rect.width - expectedWidth) < 0.01)
        #expect(rect.height / rect.width <= 0.68 + 0.001)
        #expect(rect.minX > 0)
        #expect(rect.maxX < size.width)
        #expect(rect.minY >= 0)
        #expect(rect.maxY <= size.height)
    }

    @Test func imageCropRectIsCenteredBandInsidePhoto() {
        let imageSize = CGSize(width: 3024, height: 4032)
        let preview = CGSize(width: 393, height: 700)
        let crop = IngredientBandGeometry.imageCropRect(
            imageSize: imageSize,
            previewSize: preview
        )
        #expect(crop.width < imageSize.width)
        #expect(crop.height < imageSize.height)
        #expect(crop.minX >= 0)
        #expect(crop.minY >= 0)
        #expect(crop.maxX <= imageSize.width + 0.5)
        #expect(crop.maxY <= imageSize.height + 0.5)
        #expect(abs(crop.midX - imageSize.width / 2) < imageSize.width * 0.12)
    }

    @Test func firstShotPromptAsksToFrameIngredientList() {
        let prompt = MultiShotCaptureGuide.prompt(forCapturedCount: 0)
        #expect(prompt.contains("成分表"))
        #expect(prompt.contains("白框"))
    }

    @Test func fallbackBandIsUsedWhenPreviewSizeMissing() {
        let imageSize = CGSize(width: 1000, height: 2000)
        let crop = IngredientBandGeometry.imageCropRect(
            imageSize: imageSize,
            previewSize: .zero
        )
        #expect(abs(crop.width - 900) < 0.5)
        #expect(abs(crop.height - 1000) < 0.5)
        #expect(abs(crop.midY - imageSize.height / 2) < 0.5)
    }
}
