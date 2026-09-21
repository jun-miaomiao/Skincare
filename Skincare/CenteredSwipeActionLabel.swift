import SwiftUI

/// 列表滑動按鈕：圖示＋文字垂直置中（避免貼齊頂端）。
struct CenteredSwipeActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
