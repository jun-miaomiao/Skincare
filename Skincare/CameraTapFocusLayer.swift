import SwiftUI

/// 蓋在相機預覽上的點擊對焦層（SwiftUI 手勢），避開 UIViewRepresentable 被上層擋住的問題。
struct CameraTapFocusLayer: View {
    let onFocus: (CGPoint) -> Void
    @Binding var indicatorPoint: CGPoint?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            let size = geo.size
                            guard size.width > 1, size.height > 1 else { return }
                            let location = event.location
                            let devicePoint = CGPoint(
                                x: min(max(location.x / size.width, 0), 1),
                                y: min(max(location.y / size.height, 0), 1)
                            )
                            onFocus(devicePoint)
                            showIndicator(at: location)
                        }
                )

            if let point = indicatorPoint {
                FocusReticle()
                    .position(point)
                    .transition(.opacity.combined(with: .scale(scale: 1.15)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func showIndicator(at point: CGPoint) {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            indicatorPoint = point
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                indicatorPoint = nil
            }
        }
    }
}

private struct FocusReticle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(Color.yellow.opacity(0.95), lineWidth: 2)
            .frame(width: 72, height: 72)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}
