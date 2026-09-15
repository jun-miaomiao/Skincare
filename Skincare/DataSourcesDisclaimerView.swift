import SwiftUI

/// 評級／膚質提示的資料來源與非醫療免責（Guideline 1.4.1）。
struct DataSourcesDisclaimerView: View {
    var showsNavigationChrome: Bool = true

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationStack {
                    content
                        .navigationTitle("資料來源與免責")
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                disclaimerCard

                sourceSection

                legalSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("非醫療建議", systemImage: "stethoscope")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)

            Text("安心度評級、膚質適配與風險提示為日常護膚參考用的資訊彙整，並非醫療診斷、治療建議或藥品／化粧品法規判定。選購與使用請以產品標示為準；有皮膚疾患或不適請諮詢專業醫療人員。")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.gold.opacity(0.35), lineWidth: 1)
        )
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("公開資料來源")
                .font(.system(.headline, design: .serif))
                .foregroundColor(Theme.ink)

            Text("成分安心度對照下列公開資料庫與國際化粧品成分資訊；本 App 分數為彙整參考，不完全等同任一第三方原始評分。")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            sourceLinkRow(
                title: "EWG Skin Deep®",
                subtitle: "成分危害關注度公開資料",
                url: LegalLinks.ewgSkinDeep
            )
            sourceLinkRow(
                title: "EU CosIng",
                subtitle: "歐盟化粧品成分資料庫",
                url: LegalLinks.euCosIng
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("相關條款")
                .font(.system(.headline, design: .serif))
                .foregroundColor(Theme.ink)

            Link("隱私權政策", destination: LegalLinks.privacyPolicy)
            Link("使用條款", destination: LegalLinks.termsOfUse)
            Link("Apple 標準 EULA", destination: LegalLinks.appleStandardEULA)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(Theme.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private func sourceLinkRow(title: String, subtitle: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.muted)
            }
            .padding(.vertical, 6)
        }
    }
}

/// 掃描摘要等處的一行短免責＋開啟完整來源說明。
struct MedicalDisclaimerFooter: View {
    @State private var showSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("評級與膚質提示僅供日常護膚參考，非醫療建議。")
                .font(.caption2)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("查看資料來源") {
                showSources = true
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(Theme.accent)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showSources) {
            DataSourcesDisclaimerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
