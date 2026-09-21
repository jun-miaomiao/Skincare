import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 列表滑動：大圓形圖示＋下方文字。
/// 合成單張圖交給 swipeActions，避免矮列裁掉文字、也避免系統色塊填滿。
struct CircularSwipeActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    private let diameter: CGFloat = 56
    private let textBlockHeight: CGFloat = 16
    private let spacing: CGFloat = 4

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = renderedGlyph() {
                Image(uiImage: image)
                    .renderingMode(.original)
            } else {
                fallbackLabel
            }
            #else
            fallbackLabel
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var fallbackLabel: some View {
        VStack(spacing: spacing) {
            Image(systemName: "\(systemImage).circle.fill")
                .font(.system(size: diameter * 0.92))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }

    #if canImport(UIKit)
    private func renderedGlyph() -> UIImage? {
        let uiTint = UIColor(tint)
        let sizeConfig = UIImage.SymbolConfiguration(pointSize: diameter * 0.92, weight: .regular)
        let paletteConfig = sizeConfig.applying(
            UIImage.SymbolConfiguration(paletteColors: [.white, uiTint])
        )
        guard let symbol = UIImage(
            systemName: "\(systemImage).circle.fill",
            withConfiguration: paletteConfig
        ) else {
            return nil
        }

        let symbolSize = symbol.size
        let width = max(symbolSize.width + 8, 76)
        let height = symbolSize.height + spacing + textBlockHeight
        let canvas = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            let iconOrigin = CGPoint(
                x: (width - symbolSize.width) / 2,
                y: 0
            )
            symbol.draw(at: iconOrigin)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: uiTint,
                .paragraphStyle: paragraph
            ]
            let textRect = CGRect(
                x: 0,
                y: symbolSize.height + spacing,
                width: width,
                height: textBlockHeight
            )
            (title as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
    #endif
}
