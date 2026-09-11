import SwiftUI

struct HomeScreenContent<IngredientRow: View>: View {
    @Binding var query: String
    @Binding var selectedTab: HomeTab
    let filteredIngredients: [Ingredient]
    let onScanTapped: () -> Void
    @ViewBuilder let ingredientRow: (Ingredient) -> IngredientRow

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            HomeAmbientGlow()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    HStack(spacing: 10) {
                        SearchField(text: $query)
                        ScanCameraButton(action: onScanTapped)
                    }
                    TabSwitcher(selection: $selectedTab)

                    if selectedTab == .safety {
                        SafetyOverview(ingredients: filteredIngredients)
                    }

                    ingredientSection
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("成分智庫")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .tracking(3)
                .foregroundColor(Theme.muted)
                .textCase(.uppercase)

            Text("保養品成分查詢")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .foregroundColor(Theme.ink)

            Text("以清晰標示功效與風險，陪你做出更安心的選擇。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedTab == .popular ? "精選成分" : "風險一覽")
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(Theme.ink)
                Spacer()
                Text("\(filteredIngredients.count) 項")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }

            if filteredIngredients.isEmpty {
                EmptySearchState(query: query)
            } else {
                VStack(spacing: 14) {
                    ForEach(filteredIngredients) { ingredient in
                        ingredientRow(ingredient)
                    }
                }
            }
        }
    }
}

private struct HomeAmbientGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: -120, y: -180)
            Circle()
                .fill(Theme.sage.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 140, y: 80)
        }
        .allowsHitTesting(false)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundColor(Theme.muted)

            TextField("搜尋成分名稱或功效", text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(Theme.ink)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
        .shadow(color: Theme.ink.opacity(0.05), radius: 16, y: 8)
    }
}

private struct TabSwitcher: View {
    @Binding var selection: HomeTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundColor(selection == tab ? Color.white : Theme.accent)
                        .background(selectedBackground(for: tab))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Theme.surface, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func selectedBackground(for tab: HomeTab) -> some View {
        if selection == tab {
            Capsule(style: .continuous)
                .fill(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.28), radius: 10, y: 4)
        } else {
            Color.clear
        }
    }
}

private struct SafetyOverview: View {
    let ingredients: [Ingredient]

    private var lowCount: Int {
        ingredients.filter { $0.risk == .low }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            overviewTile(title: "低風險", value: "\(lowCount)", tint: Theme.sage)
            overviewTile(title: "需留意", value: "\(ingredients.filter { $0.risk != .low }.count)", tint: Theme.gold)
            overviewTile(title: "成分數", value: "\(ingredients.count)", tint: Theme.accent)
        }
    }

    private func overviewTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(.title2, design: .serif).weight(.medium))
                .foregroundColor(tint)
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

private struct EmptySearchState: View {
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.circle")
                .font(.largeTitle)
                .foregroundColor(Theme.sage)
            Text("找不到「\(query)」")
                .font(.headline)
                .foregroundColor(Theme.ink)
            Text("試試英文學名，或改搜尋功效關鍵字。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
