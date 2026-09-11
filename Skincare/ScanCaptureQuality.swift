import Foundation

/// 難標掃描品質閘門：信心度低或幾乎沒對上字典時，不把一長串灰字當成成功結果。
enum ScanCaptureQuality: Equatable, Sendable {
    case acceptable
    case needsRetake

    /// Vision 平均信心度低於此值，且命中偏少時請重拍／貼上。
    static let minimumAverageConfidence: Float = 0.40
    /// 清單夠長時，字典命中佔比低於此值視為雜訊灌水。
    static let minimumHitRate: Double = 0.25
    static let hitRateTokenThreshold = 8
    /// 與 `RecognitionTier.weak` 上界一致：低信心時 1～4 項不裝成成功。
    static let weakHitCeiling = 4

    static func evaluate(
        dictionaryHitCount: Int,
        tokenCount: Int,
        averageOCRConfidence: Float?
    ) -> ScanCaptureQuality {
        if dictionaryHitCount <= 0 {
            return .needsRetake
        }

        if let confidence = averageOCRConfidence,
           confidence.isFinite,
           confidence < minimumAverageConfidence,
           dictionaryHitCount <= weakHitCeiling {
            return .needsRetake
        }

        if tokenCount >= hitRateTokenThreshold {
            let rate = Double(dictionaryHitCount) / Double(max(tokenCount, 1))
            if rate < minimumHitRate {
                return .needsRetake
            }
        }

        return .acceptable
    }
}

extension ScanSessionResult {
    /// 僅用於相機／相簿 OCR；手動貼上不要走這道閘（使用者已提供文字）。
    var needsCaptureRetake: Bool {
        ScanCaptureQuality.evaluate(
            dictionaryHitCount: dictionaryHitCount,
            tokenCount: ingredients.count,
            averageOCRConfidence: averageOCRConfidence
        ) == .needsRetake
    }
}
