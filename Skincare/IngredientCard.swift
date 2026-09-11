import SwiftUI

struct IngredientCard: View {
    let ingredient: Ingredient
    var emphasizesSafety: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(ingredient.symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ingredient.accent)
                .frame(width: 48, height: 48)
                .background(ingredient.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.chineseName)
                            .font(.system(.title3, design: .serif).weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text(ingredient.englishName)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    EWGBadge(band: ingredient.ewgBand, compact: true)
                }

                Text(ingredient.benefit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ingredient.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ingredient.accent.opacity(0.12), in: Capsule())

                Text(emphasizesSafety ? ingredient.safetyNote : ingredient.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
        .shadow(color: ingredient.accent.opacity(0.12), radius: 18, y: 10)
    }
}

struct EWGBadge: View {
    let band: EWGBand
    var compact: Bool = false

    var body: some View {
        Label(band.rawValue, systemImage: band.icon)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(band.tint)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(band.tint.opacity(0.14), in: Capsule())
    }
}
