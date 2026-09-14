import SwiftUI

struct IngredientDetailView: View {
    let ingredient: Ingredient

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            AmbientGlow()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let highlight = modernEUSunscreenHighlight {
                        modernEUSunscreenCard(highlight)
                    }
                    ewgSection
                    benefitsSection
                    skinAnalysisSection
                    warningsSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("成分詳情")
        .appDetailNavigationChrome()
    }

    private var modernEUSunscreenHighlight: ModernEUSunscreenHighlight.Info? {
        ModernEUSunscreenHighlight.match(
            englishName: ingredient.englishName,
            chineseName: ingredient.chineseName,
            aliases: ingredient.aliases ?? []
        )
    }

    private func modernEUSunscreenCard(_ info: ModernEUSunscreenHighlight.Info) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(info.tradeLabel, systemImage: "sun.max.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.sage)

            Text("新型歐洲主流防曬成分")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)

            Text(info.summary)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sage.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.sage.opacity(0.22), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Text(ingredient.symbol)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ingredient.accent)
                    .frame(width: 64, height: 64)
                    .background(ingredient.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.chineseName)
                        .font(.system(.largeTitle, design: .serif).weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(ingredient.englishName)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("學名")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
                Text(ingredient.scientificName)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            }
        }
    }

    private var ewgSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("EWG 安全等級")

            HStack(spacing: 14) {
                EWGBadge(band: ingredient.ewgBand)

                VStack(alignment: .leading, spacing: 2) {
                    Text("分數 \(ingredient.ewgScore) / 10")
                        .font(.system(.title3, design: .serif).weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text("分數越低，資料庫中的關注度通常越低。")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            }
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("主要功效")

            Text(ingredient.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            FlowChips(items: ingredient.benefits, tint: ingredient.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
    }

    private var skinAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("適合膚質分析")

            VStack(alignment: .leading, spacing: 8) {
                labelRow("較適合", systemImage: "checkmark.circle.fill", tint: Theme.sage)
                FlowChips(items: ingredient.suitableSkinTypes, tint: Theme.sage)
            }

            VStack(alignment: .leading, spacing: 8) {
                labelRow("需放慢節奏", systemImage: "hand.raised.fill", tint: Theme.gold)
                ForEach(ingredient.cautionSkinTypes, id: \.self) { note in
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("警語與使用限制")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(ingredient.warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.blush)
                            .padding(.top, 3)
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blush.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.blush.opacity(0.18), lineWidth: 1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .serif))
            .foregroundStyle(Theme.ink)
    }

    private func labelRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }
}

private struct FlowChips: View {
    let items: [String]
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AmbientGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 130, y: -160)
            Circle()
                .fill(Theme.sage.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -140, y: 220)
        }
        .allowsHitTesting(false)
    }
}

struct IngredientDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            IngredientDetailView(ingredient: Ingredient.samples[1])
        }
    }
}
