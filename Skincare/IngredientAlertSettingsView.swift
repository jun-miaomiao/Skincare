import SwiftData
import SwiftUI

struct IngredientAlertSettingsView: View {
    @Bindable var profile: UserProfile

    @State private var batchInputText = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introCard
                    avoidListSection
                    customBlockedSection
                    scanBehaviorNote
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("成分提醒")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("掃描即時警示", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundColor(Theme.ink)

            Text("勾選後，相機掃描辨識到對應成分時，會震動並在畫面中央顯示紅色警示。")
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var avoidListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("風險成分清單")
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(Theme.ink)

                Spacer(minLength: 8)

                Button(action: toggleAllAvoidOptions) {
                    Text(areAllAvoidOptionsEnabled ? "全部關閉" : "全部開啟")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(areAllAvoidOptionsEnabled ? "全部關閉風險成分提醒" : "全部開啟風險成分提醒")
            }

            VStack(spacing: 0) {
                ForEach(Array(AvoidIngredientOption.all.enumerated()), id: \.element.id) { index, option in
                    AvoidIngredientToggleRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        isOn: binding(for: option)
                    )

                    if index < AvoidIngredientOption.all.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
        }
    }

    private var areAllAvoidOptionsEnabled: Bool {
        AvoidIngredientOption.all.allSatisfy { profile.isAvoidEnabled(for: $0) }
    }

    private func toggleAllAvoidOptions() {
        let enable = !areAllAvoidOptionsEnabled
        for option in AvoidIngredientOption.all {
            profile.setAvoidEnabled(enable, for: option)
        }
    }

    private var customBlockedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自訂風險成分")
                .font(.system(.headline, design: .serif))
                .foregroundColor(Theme.ink)

            Text("可快捷加入常用敏感庫，或以逗號、頓號、換行批次貼上成分名稱。")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            quickAddSection
            batchInputSection
            customTagsSection
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用敏感庫快捷加入")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            FlowLayout(spacing: 8) {
                ForEach(SensitiveIngredientQuickPack.all) { pack in
                    QuickAddPackCapsule(
                        title: pack.title,
                        isFullyAdded: profile.isQuickPackFullyAdded(pack),
                        onAdd: { profile.addQuickPack(pack) }
                    )
                }
            }
        }
    }

    private var batchInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批次貼上 / 輸入")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            TextField("例：Niacinamide, 菸鹼醯胺、Salicylic Acid", text: $batchInputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.background.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                )
                .onSubmit { commitBatchInput() }

            HStack(spacing: 10) {
                Button(action: commitBatchInput) {
                    Text("批次新增")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(batchInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 8)

                Button(action: clearAllCustomBlocked) {
                    Text("全部取消")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.blush)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.blush.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Theme.blush.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(profile.customBlockedIngredients.isEmpty)
                .opacity(profile.customBlockedIngredients.isEmpty ? 0.45 : 1)
                .accessibilityLabel("全部取消自訂風險成分")
            }
        }
    }

    @ViewBuilder
    private var customTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已加入的自訂成分（\(profile.customBlockedIngredients.count)）")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            if profile.customBlockedIngredients.isEmpty {
                Text("尚未加入自訂成分")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(profile.customBlockedIngredients, id: \.self) { ingredient in
                        RemovableIngredientTag(name: ingredient) {
                            profile.removeCustomBlockedIngredient(ingredient)
                        }
                    }
                }
            }
        }
    }

    private var scanBehaviorNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(Theme.sage)
                .font(.title3)
            Text("設定即時保存在本機，掃描時自動以關鍵字比對成分表文字。")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.sage.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func binding(for option: AvoidIngredientOption) -> Binding<Bool> {
        Binding(
            get: { profile.isAvoidEnabled(for: option) },
            set: { profile.setAvoidEnabled($0, for: option) }
        )
    }

    private func commitBatchInput() {
        let parsed = IngredientMatcher.parseBatchInput(batchInputText)
        guard !parsed.isEmpty else { return }
        profile.addCustomBlockedIngredients(parsed)
        batchInputText = ""
    }

    private func clearAllCustomBlocked() {
        profile.customBlockedIngredients = []
    }
}

private struct AvoidIngredientToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }
        }
        .tint(Theme.blush)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct QuickAddPackCapsule: View {
    let title: String
    let isFullyAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Image(systemName: isFullyAdded ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
            }
            .foregroundColor(isFullyAdded ? Theme.sage : Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isFullyAdded ? Theme.sage.opacity(0.14) : Theme.accent.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isFullyAdded ? Theme.sage.opacity(0.35) : Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFullyAdded)
    }
}

private struct RemovableIngredientTag: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("取消 \(name)")
        .accessibilityHint("點一下即可從此清單移除")
    }
}

/// 簡易換行排版容器（膠囊標籤用）。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rawWidth = proposal.width ?? 0
        let width = Self.sanitizedWidth(rawWidth)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = Self.sanitizedSize(subview.sizeThatFits(.unspecified))
            if width > 0, x + size.width > width, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        maxRowWidth = max(maxRowWidth, max(0, x - spacing))

        let height = y + rowHeight
        let finalWidth = width > 0 ? width : maxRowWidth
        return CGSize(
            width: Self.sanitizedDimension(finalWidth),
            height: Self.sanitizedDimension(height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width.isFinite, bounds.height.isFinite,
              !bounds.width.isNaN, !bounds.height.isNaN else { return }

        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for subview in subviews {
            let size = Self.sanitizedSize(subview.sizeThatFits(.unspecified))
            if x + size.width > maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            let placeX = Self.sanitizedDimension(x)
            let placeY = Self.sanitizedDimension(y)
            subview.place(
                at: CGPoint(x: placeX, y: placeY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }

    private static func sanitizedWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, !value.isNaN, value > 0 else { return 0 }
        // 避免 infinity 進入 CoreGraphics
        if value > 10_000 { return 10_000 }
        return value
    }

    private static func sanitizedDimension(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, !value.isNaN else { return 0 }
        return max(0, value)
    }

    private static func sanitizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: sanitizedDimension(size.width),
            height: sanitizedDimension(size.height)
        )
    }
}

struct IngredientAlertSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CustomNavigationView {
            IngredientAlertSettingsView(profile: UserProfile())
        }
        .modelContainer(SkincareModelContainer.preview)
    }
}
