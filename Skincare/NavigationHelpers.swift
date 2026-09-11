import SwiftUI

struct CustomNavigationView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // 其餘 Tab 維持 NavigationView，避免 TabView 內多個 NavigationStack
        // 與 navigationDestination(isPresented:) 組合時主執行緒卡死。
        NavigationView {
            content
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

extension View {
    @ViewBuilder
    func appNavigationBarHidden(_ hidden: Bool) -> some View {
        navigationBarHidden(hidden)
    }

    @ViewBuilder
    func appDetailNavigationChrome() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func appSheetPresentationStyle() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
