import SwiftUI
import SwiftData

enum AppTab: Int, Hashable {
    case favorites = 0
    case scanHistory = 1
    case paste = 2
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

            PasteIngredientTab()
                .tabItem {
                    Label("貼上", systemImage: "doc.on.clipboard")
                }
                .tag(AppTab.paste)

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
        .tint(Theme.accent)
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environmentObject(scanLaunch)
    }
}

/// 中間分頁是貼上。相機在貼上頁裡，只帶回有辨識到的字。
private struct PasteIngredientTab: View {
    var body: some View {
        ManualInputView(
            source: .history,
            isTabRoot: true,
            onAnalyzed: { _ in }
        )
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
