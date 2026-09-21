import SwiftUI

struct IngredientCard: View {
    let ingredient: Ingredient
    var emphasizesSafety: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ingredient.symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ingredient.accent)
                .frame(width: 48, height: 48)
                .background(ingredient.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // 品名＋說明緊貼；功能膠囊留給掃描詳情，最愛列表不重複顯示。
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.chineseName)
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(ingredient.englishName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                Text(emphasizesSafety ? ingredient.safetyNote : ingredient.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 貼齊卡片右緣，寬度隨文案，不拉出右側空白。
            VStack(alignment: .trailing, spacing: 4) {
                ConcernBadge(band: ingredient.concernBand, compact: true)
                IrritationBadge(risk: ingredient.irritationRisk, compact: true)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
        .shadow(color: ingredient.accent.opacity(0.12), radius: 18, y: 10)
    }
}

struct ConcernBadge: View {
    let band: ConcernBand
    var compact: Bool = false

    var body: some View {
        RiskAxisBadge(
            title: band.rawValue,
            systemImage: band.icon,
            tint: band.tint,
            compact: compact
        )
    }
}

struct IrritationBadge: View {
    let risk: IrritationRisk
    var compact: Bool = false

    var body: some View {
        RiskAxisBadge(
            title: risk.rawValue,
            systemImage: risk.icon,
            tint: risk.tint,
            compact: compact
        )
    }
}

/// 安心度／刺激標籤共用排版：固定圖示欄寬，圖示貼近文字。
private struct RiskAxisBadge: View {
    let title: String
    let systemImage: String
    let tint: Color
    var compact: Bool = false

    private var iconSlot: CGFloat { compact ? 11 : 13 }
    private var iconFont: Font {
        compact ? .caption2.weight(.semibold) : .caption.weight(.semibold)
    }

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: systemImage)
                .font(iconFont)
                .frame(width: iconSlot, alignment: .center)
            Text(title)
                .font(iconFont)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.leading, compact ? 7 : 10)
        .padding(.trailing, compact ? 9 : 12)
        .padding(.vertical, compact ? 5 : 7)
        .background(tint.opacity(0.14), in: Capsule())
    }
}
