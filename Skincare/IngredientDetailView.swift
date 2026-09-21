import SwiftData
import SwiftUI

struct IngredientDetailView: View {
    let ingredient: Ingredient
    /// 字典／資料庫原文，供膚質引擎與掃描同一套規則比對。
    var databaseItem: IngredientItem? = nil

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query(sort: \FavoriteIngredientRecord.createdAt, order: .reverse)
    private var favoriteIngredientRecords: [FavoriteIngredientRecord]
    @Query private var profiles: [UserProfile]
    @State private var showPaywall = false

    private var profile: UserProfile? { profiles.first }

    private var favoritedIngredientKeys: Set<String> {
        FavoriteManager.favoritedIngredientKeys(from: favoriteIngredientRecords)
    }

    private var resolvedDatabaseItem: IngredientItem? {
        databaseItem
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: ingredient.englishName)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: ingredient.chineseName)
    }

    private var isFavorited: Bool {
        if let db = resolvedDatabaseItem {
            return FavoriteManager.isIngredientFavorited(db, favoritedKeys: favoritedIngredientKeys)
        }
        return FavoriteManager.isIngredientFavorited(
            ingredientID: ingredient.id,
            englishName: ingredient.englishName,
            favoritedKeys: favoritedIngredientKeys
        )
    }

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
                    riskAxesSection
                    benefitsSection
                    skinAnalysisSection
                    warningsSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("成分資訊")
        .appDetailNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: favoriteButtonSymbol)
                        .foregroundStyle(isFavorited ? Theme.gold : Theme.ink)
                }
                .accessibilityLabel(isFavorited ? "取消最愛" : "加入最愛")
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: .favorites)
        }
    }

    private var favoriteButtonSymbol: String {
        if !subscriptionStore.isPremium, !isFavorited {
            return "lock.fill"
        }
        return isFavorited ? "star.fill" : "star"
    }

    private func toggleFavorite() {
        guard subscriptionStore.isPremium else {
            showPaywall = true
            return
        }
        if let db = resolvedDatabaseItem {
            _ = FavoriteManager.toggleIngredientFavorite(
                db,
                favoritedKeys: favoritedIngredientKeys,
                in: modelContext
            )
            return
        }
        _ = FavoriteManager.toggleIngredientFavorite(
            ingredientID: ingredient.id,
            chineseName: ingredient.chineseName,
            englishName: ingredient.englishName,
            favoritedKeys: favoritedIngredientKeys,
            in: modelContext
        )
    }

    /// 與掃描結果相同引擎：依個人檔案膚質／敏感設定產生標籤。
    private var skinReport: SkinSuitabilityReport {
        let db = resolvedDatabaseItem
        return SkinSuitabilityEngine.evaluate(
            ingredients: [ingredient.englishName],
            databaseItems: [db],
            skinType: profile?.skinType ?? .combination,
            isSensitiveSkin: profile?.isSensitiveSkin ?? false,
            enabledAlertTags: Set(profile?.blockedTags ?? [])
        )
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

    /// 兩列徽章欄同寬，右側「安心度／刺激…」文案左緣對齊（膠囊本身靠左不動）。
    private static let riskBadgeColumnWidth: CGFloat = 118

    private var riskAxesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("安心度與刺激風險")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ConcernBadge(band: ingredient.concernBand)
                        .frame(width: Self.riskBadgeColumnWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("安心度 \(ingredient.concernScore) / 9")
                            .font(.system(.title3, design: .serif).weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text("分數越低通常越安心（偏法規／長期風險彙整）。屬本 App 整理，非第三方官網評分。")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                HStack(alignment: .top, spacing: 14) {
                    IrritationBadge(risk: ingredient.irritationRisk)
                        .frame(width: Self.riskBadgeColumnWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.irritationRisk.rawValue)
                            .font(.system(.title3, design: .serif).weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text(ingredient.irritationRisk.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                Text("公開來源可查：台灣食藥署開放資料（禁／限用）與歐盟 CosIng。分數與標籤為本 App 整理，不完全等同原始資料庫欄位。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link("台灣禁用品項", destination: LegalLinks.twCosmeticsBanned)
                    Link("台灣限用品項", destination: LegalLinks.twCosmeticsRestricted)
                    Link("EU CosIng", destination: LegalLinks.euCosIng)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
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
        let report = skinReport
        let suitable = report.beneficialHits
        let caution = report.cautionHits
        let profileLabel = "\(report.skinType.rawValue)\(report.isSensitiveSkin ? "・敏感肌" : "")"

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("適合膚質分析")

            Text("依您的膚質設定（\(profileLabel)），與掃描結果使用同一套規則。")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !suitable.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    labelRow("較適合／推薦", systemImage: "checkmark.circle.fill", tint: Theme.sage)
                    FlowChips(
                        items: Array(Set(suitable.map(\.flag.rawValue))).sorted(),
                        tint: Theme.sage
                    )
                    ForEach(suitable, id: \.id) { hit in
                        Text(hit.reason)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !caution.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    labelRow("需留意", systemImage: "hand.raised.fill", tint: Theme.gold)
                    FlowChips(
                        items: Array(Set(caution.map(\.flag.rawValue))).sorted(),
                        tint: Theme.gold
                    )
                    ForEach(caution, id: \.id) { hit in
                        Text(hit.reason)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if suitable.isEmpty && caution.isEmpty {
                Text("依目前膚質設定，此成分未觸發特別推薦或警示標籤。實際仍視產品濃度、配方位置與個人耐受而定。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("非醫療建議。可在「檔案」調整膚質與敏感肌設定。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
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
        .modelContainer(SkincareModelContainer.preview)
        .environmentObject(SubscriptionStore.shared)
    }
}
