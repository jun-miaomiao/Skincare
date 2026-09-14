import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject private var store = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss

    var reason: PaywallReason = .generic
    var onUnlocked: (() -> Void)? = nil

    @State private var selectedID: SubscriptionProductID = .yearly

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        benefitList
                        planList
                        purchaseButton
                        footerActions
                        if let message = store.lastErrorMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(Theme.blush)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                        .foregroundColor(Theme.muted)
                }
            }
            .task {
                await store.refresh()
                if store.product(for: .yearly) != nil {
                    selectedID = .yearly
                } else if let first = store.visibleProductIDs().first {
                    selectedID = first
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reason.title)
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.ink)
            if !reason.message.isEmpty {
                Text(reason.message)
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefitRow("無限相機／相簿掃描", systemImage: "camera.fill")
            benefitRow("加入最愛、完整紀錄節奏", systemImage: "star.fill")
            benefitRow("規劃中：韓日文辨識與字典翻譯完善", systemImage: "globe.asia.australia.fill")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private func benefitRow(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 20)
            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(store.visibleProductIDs()) { id in
                planCard(id)
            }
            if store.isLoadingProducts, store.products.isEmpty {
                ProgressView("載入方案中…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func planCard(_ id: SubscriptionProductID) -> some View {
        let product = store.product(for: id)
        let selected = selectedID == id
        return Button {
            selectedID = id
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(id.marketingTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.ink)
                        if id.isFeatured {
                            Text("推薦")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    if !id.marketingSubtitle.isEmpty {
                        Text(id.marketingSubtitle)
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
                Text(product?.displayPrice ?? id.fallbackPriceLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.ink)
            }
            .padding(14)
            .background(
                selected ? Theme.primaryLight : Theme.elevated.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Theme.accent : Theme.cardStroke, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInFlight)
    }

    private var purchaseButton: some View {
        Button {
            Task { await buySelected() }
        } label: {
            Group {
                if store.purchaseInFlight {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseTitle)
                        .font(.headline)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInFlight || store.product(for: selectedID) == nil)
    }

    private var purchaseTitle: String {
        if let product = store.product(for: selectedID) {
            return "以 \(product.displayPrice) 繼續"
        }
        return "選擇方案"
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button("恢復購買") {
                Task { await store.restorePurchases() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(Theme.accent)

            Text("貼上成分解析維持免費。付費只解鎖使用次數與最愛。")
                .font(.caption2)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Link("隱私權政策", destination: LegalLinks.privacyPolicy)
                Link("使用條款", destination: LegalLinks.termsOfUse)
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity)

            #if DEBUG
            Button(store.debugPremiumUnlocked ? "關閉開發解鎖" : "開發解鎖（略過 StoreKit）") {
                store.debugPremiumUnlocked.toggle()
                if store.isPremium {
                    onUnlocked?()
                    dismiss()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(Theme.muted)
            #endif
        }
        .padding(.top, 4)
    }

    private func buySelected() async {
        guard let product = store.product(for: selectedID) else {
            store.lastErrorMessage = "方案尚未載入，請稍後再試。"
            return
        }
        let ok = await store.purchase(product)
        if ok {
            onUnlocked?()
            dismiss()
        }
    }
}

enum PaywallReason: Equatable {
    case generic
    case weeklyScanLimit
    case favorites

    var title: String {
        switch self {
        case .generic:
            return "繼續完整使用"
        case .weeklyScanLimit:
            return "本週免費掃描已用完"
        case .favorites:
            return "最愛是訂閱功能"
        }
    }

    var message: String {
        switch self {
        case .generic:
            return ""
        case .weeklyScanLimit:
            return "免費每週 \(FreeScanQuota.weeklyCameraScanLimit) 次相機／相簿掃描。貼上成分解析不限次數。"
        case .favorites:
            return "掃完結果都能看。加入最愛、之後快速回看，需訂閱解鎖。"
        }
    }
}

/// 需要付費時顯示的輕量提示列。
struct PremiumGateBanner: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.ink)
                    Text(actionTitle)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
            }
            .padding(14)
            .background(Theme.primaryLight, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
