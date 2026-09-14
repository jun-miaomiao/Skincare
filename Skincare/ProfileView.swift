import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profileList: [UserProfile]

    var body: some View {
        CustomNavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ProfileAmbientGlow()

                Group {
                    if let profile = profileList.first {
                        ScrollView {
                            ProfileFormContent(profile: profile)
                                .padding(.horizontal, 22)
                                .padding(.top, 12)
                                .padding(.bottom, 36)
                        }
                    } else {
                        ProgressView("載入設定中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("個人檔案")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                DataBootstrap.seedIfNeeded(in: modelContext)
            }
        }
    }
}

private struct ProfileFormContent: View {
    @Bindable var profile: UserProfile
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var showAvatarPicker = false
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileIntroSection
            subscriptionSection
            skinPreferenceSection
            alertSettingsSection
            systemDataSection
        }
    }

    private var profileIntroSection: some View {
        VStack(spacing: 8) {
            Button {
                showAvatarPicker = true
            } label: {
                ProfileAvatarView(data: profile.avatarData)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showAvatarPicker) {
                #if canImport(PhotosUI) && os(iOS)
                InMemoryPHPickerView(
                    maxSelectionCount: 1,
                    onPickedImages: { images in
                        showAvatarPicker = false
                        guard let image = images.first,
                              let data = ModernPhotoLoader.jpegData(from: image) else { return }
                        #if canImport(UIKit)
                        profile.avatarData = AvatarImageProcessor.compressedJPEG(from: data) ?? data
                        #else
                        profile.avatarData = data
                        #endif
                        profile.touchUpdatedAt()
                    },
                    onCancel: {
                        showAvatarPicker = false
                    }
                )
                .ignoresSafeArea()
                #endif
            }

            Text("編輯")
                .font(.caption)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("訂閱")

            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: subscriptionStore.isPremium ? "checkmark.seal.fill" : "sparkles")
                        .font(.title3)
                        .foregroundColor(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.elevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(subscriptionStore.isPremium ? "已解鎖完整使用" : "解鎖方案")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.ink)
                        if let plan = subscriptionStore.activePlanLabel {
                            Text("目前方案：\(plan)")
                                .font(.caption)
                                .foregroundColor(Theme.muted)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                .padding(14)
                .background(Theme.primaryLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            if !subscriptionStore.isPremium,
               let remaining = FreeScanQuota.remainingCameraScans(isPremium: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本週相機／相簿剩餘 \(remaining)／\(FreeScanQuota.weeklyCameraScanLimit) 次")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                    Text("貼上成分解析不限次數")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: .generic)
        }
    }

    private var skinPreferenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("膚質")

            Picker("膚質", selection: $profile.skinTypeRawValue) {
                ForEach(SkinType.allCases) { type in
                    Text(type.rawValue).tag(type.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: profile.skinTypeRawValue) { _, _ in
                profile.touchUpdatedAt()
            }

            Toggle(isOn: $profile.isSensitiveSkin) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("敏感肌 / 泛紅體質")
                        .font(.headline)
                        .foregroundColor(Theme.ink)
                    Text("供成分安全評級與篩選參考")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            .tint(Theme.blush)
            .onChange(of: profile.isSensitiveSkin) { _, _ in
                profile.touchUpdatedAt()
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var alertSettingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("通知與提醒")

            NavigationLink {
                IngredientAlertSettingsView(profile: profile)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title3)
                        .foregroundColor(Theme.blush)
                        .frame(width: 44, height: 44)
                        .background(Theme.blush.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("成分提醒")
                            .font(.headline)
                            .foregroundColor(Theme.ink)
                        Text("自訂風險成分與掃描警報")
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                    }

                    Spacer(minLength: 8)

                    if IngredientAlertMatcher.enabledCount(in: profile) > 0 {
                        Text("\(IngredientAlertMatcher.enabledCount(in: profile)) 項")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.blush)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.blush.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.muted)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }

    private var systemDataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("系統與資料")

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundColor(Theme.sage)
                    .frame(width: 44, height: 44)
                    .background(Theme.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("資料保存在本機與 iCloud")
                            .font(.headline)
                            .foregroundColor(Theme.ink)
                        Text("掃描紀錄、我的最愛與個人偏好保存在此裝置；登入 iCloud 時可自動同步。")
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 16) {
                        Link("隱私權政策", destination: LegalLinks.privacyPolicy)
                        Link("使用條款", destination: LegalLinks.termsOfUse)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(18)
        .background(Theme.sage.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.sage.opacity(0.18), lineWidth: 1)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .serif))
            .foregroundColor(Theme.ink)
    }
}

private struct ProfileAvatarView: View {
    let data: Data?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("ProfilePlaceholder")
                    .resizable()
                    .scaledToFill()
            }
            #else
            Image("ProfilePlaceholder")
                .resizable()
                .scaledToFill()
            #endif
        }
        .frame(width: 96, height: 96)
        .background(Theme.accent.opacity(0.10), in: Circle())
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
    }
}

private struct ProfileAmbientGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 130, y: -140)
            Circle()
                .fill(Theme.sage.opacity(0.10))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -120, y: 180)
        }
        .allowsHitTesting(false)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .modelContainer(SkincareModelContainer.preview)
            .onAppear {
                DataBootstrap.seedIfNeeded(in: SkincareModelContainer.preview.mainContext)
            }
    }
}
