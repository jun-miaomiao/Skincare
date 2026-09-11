import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IngredientAvoidAlertOverlay: View {
    let matchedItems: [String]
    let onViewDetails: () -> Void
    let onDismiss: () -> Void

    private var displayText: String {
        matchedItems.joined(separator: "、")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onViewDetails() }

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                Text("含有您標記的風險成分")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(displayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onViewDetails) {
                    Text("查看掃描結果")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.blush)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("關閉")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.blush,
                                Color(hex: "C43A1F")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
            )
            .shadow(color: Theme.blush.opacity(0.45), radius: 24, y: 10)
            .transition(.scale(scale: 0.88).combined(with: .opacity))
        }
    }
}

enum ScanAlertHaptics {
    static func triggerWarning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
}

struct IngredientAvoidAlertOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            IngredientAvoidAlertOverlay(
                matchedItems: ["變性酒精（Alcohol Denat）", "Paraben 類防腐劑（Methylparaben）"],
                onViewDetails: {},
                onDismiss: {}
            )
        }
    }
}
