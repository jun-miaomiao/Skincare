import SwiftUI
import SwiftData

enum AppTab: Int, Hashable {
    case favorites = 0
    case scanHistory = 1
    case camera = 2
    case dictionary = 3
    case profile = 4
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .favorites
    @StateObject private var scanLaunch = ScanLaunchBridge()

    @Query(filter: #Predicate<ScanHistoryRecordEntity> { record in
        record.isRead == false
    })
    private var unreadHistoryRecords: [ScanHistoryRecordEntity]

    private var unreadCount: Int { unreadHistoryRecords.count }

    var body: some View {
        TabView(selection: $selectedTab) {
            FavoritesView()
                .tabItem {
                    Label("最愛", systemImage: "star.fill")
                }
                .tag(AppTab.favorites)

            ScanHistoryView()
                .tabItem {
                    Label("紀錄", systemImage: "clock.arrow.circlepath")
                }
                .badge(unreadCount)
                .tag(AppTab.scanHistory)

            LazyCameraTab(isSelected: selectedTab == .camera)
                .tabItem {
                    Label("相機", systemImage: "camera.fill")
                }
                .tag(AppTab.camera)

            DictionaryView()
                .tabItem {
                    Label("字典", systemImage: "book.fill")
                }
                .tag(AppTab.dictionary)

            ProfileView()
                .tabItem {
                    Label("檔案", systemImage: "person.fill")
                }
                .tag(AppTab.profile)
        }
        .accentColor(Theme.accent)
        .environmentObject(scanLaunch)
    }
}

/// 相機 Tab 按需載入：未選中前不建立 CameraController / AVCaptureSession。
private struct LazyCameraTab: View {
    let isSelected: Bool
    @State private var hasActivated = false

    var body: some View {
        Group {
            if hasActivated {
                CameraView(isActive: isSelected)
            } else {
                Color.black
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                hasActivated = true
            }
        }
        .onAppear {
            if isSelected {
                hasActivated = true
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
