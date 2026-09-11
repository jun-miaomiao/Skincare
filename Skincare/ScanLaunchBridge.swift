import SwiftUI
import Combine

/// 相機 Tab 掃描來源旗標（我的最愛的相簿／相機改為頁內獨立狀態，不再經此 bridge 開相簿）。
final class ScanLaunchBridge: ObservableObject {
    @Published var source: ScanSource = .cameraTab

    func resetToCameraTab() {
        source = .cameraTab
    }
}
