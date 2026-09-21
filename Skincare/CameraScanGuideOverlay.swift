import SwiftUI

/// 圓瓶多張連拍的通用文案與上限（不綁定特定產品）。
enum MultiShotCaptureGuide {
    static let maxShotCount = 3

    static func prompt(forCapturedCount count: Int) -> String {
        switch count {
        case 0:
            return "請將成分表對準白框後拍第 1 張"
        case 1:
            return "已拍 1/3。圓瓶請向右微轉（保留約 1/3 重疊）拍第 2 張；平面標可點完成"
        case 2:
            return "已拍 2/3。請再微轉拍第 3 張，或點擊完成辨識"
        default:
            return "已拍 \(min(count, maxShotCount))/\(maxShotCount)"
        }
    }

    static func badgeText(forCapturedCount count: Int) -> String {
        "\(min(max(count, 0), maxShotCount))/\(maxShotCount)"
    }
}

/// 相機預覽上的對焦框與連拍引導提示。
struct CameraScanGuideOverlay: View {
    var capturedCount: Int = 0
    var isFollowUpMode: Bool = false

    var body: some View {
        GeometryReader { geo in
            let rect = IngredientBandGeometry.overlayRect(in: geo.size)

            ZStack {
                dimmedMask(in: geo.size, hole: rect)

                IngredientBandCornerFrame()
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .square))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)

            Text("請將成分表對準此框（可點螢幕對焦）")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.45), in: Capsule())
                .position(x: rect.midX, y: max(rect.minY - 22, 36))
            }
            .preference(key: CameraPreviewSizeKey.self, value: geo.size)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(promptText)
    }

    private func dimmedMask(in size: CGSize, hole: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.38))
            .frame(width: size.width, height: size.height)
            .mask(
                ZStack {
                    Rectangle().fill(Color.white)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
    }

    private var promptText: String {
        if isFollowUpMode {
            return "請稍微向右轉動瓶身，重疊拍下右半部成分"
        }
        return MultiShotCaptureGuide.prompt(forCapturedCount: capturedCount)
    }
}

/// 四角括號，強調「只框成分表那一塊」。
struct IngredientBandCornerFrame: Shape {
    var cornerLengthRatio: CGFloat = 0.18
    var cornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * cornerLengthRatio
        var path = Path()

        // 左上
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        // 右上
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        // 右下
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        // 左下
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

/// 連拍快門列：重設／相簿、快門＋張數徽章、完成辨識。
struct MultiShotCaptureBar: View {
    let capturedCount: Int
    let isConfigured: Bool
    let isBusy: Bool
    var showsLibrary: Bool = true
    let onLibrary: () -> Void
    let onReset: () -> Void
    let onCapture: () -> Void
    let onFinish: () -> Void

    private var canCapture: Bool {
        isConfigured && !isBusy && capturedCount < MultiShotCaptureGuide.maxShotCount
    }

    private var showsReset: Bool { capturedCount >= 1 }
    private var showsFinish: Bool { capturedCount >= 1 }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leftSlot
                .frame(width: 76)

            Spacer(minLength: 8)

            shutterButton

            shotChecks

            Spacer(minLength: 8)

            rightSlot
                .frame(width: 76)
        }
    }

    @ViewBuilder
    private var leftSlot: some View {
        if showsReset {
            sideButton(
                title: "重設",
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "重設連拍照片",
                action: onReset
            )
            .disabled(isBusy)
            .opacity(isBusy ? 0.45 : 1)
        } else if showsLibrary {
            Button(action: onLibrary) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("從相簿選擇（最多 3 張）")
        } else {
            Color.clear
                .frame(width: 52, height: 52)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var rightSlot: some View {
        if showsFinish {
            sideButton(
                title: "完成辨識",
                systemImage: "checkmark.circle.fill",
                accessibilityLabel: "完成辨識",
                emphasized: true,
                action: onFinish
            )
            .disabled(isBusy)
            .opacity(isBusy ? 0.45 : 1)
        } else {
            Color.clear
                .frame(width: 52, height: 52)
                .allowsHitTesting(false)
        }
    }

    private var shotChecks: some View {
        VStack(spacing: 8) {
            ForEach(0..<MultiShotCaptureGuide.maxShotCount, id: \.self) { index in
                Image(systemName: index < capturedCount ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(index < capturedCount ? .white : .white.opacity(0.35))
                    .accessibilityLabel(index < capturedCount ? "第 \(index + 1) 張已確認" : "第 \(index + 1) 張尚未拍攝")
            }
        }
        .frame(width: 28)
    }

    private var shutterButton: some View {
        Button(action: onCapture) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.95), lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                }
                Text(MultiShotCaptureGuide.badgeText(forCapturedCount: capturedCount))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Theme.inkOnLight)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .offset(x: 10, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canCapture)
        .opacity(canCapture ? 1 : 0.45)
        .accessibilityLabel("拍照")
        .accessibilityValue(MultiShotCaptureGuide.badgeText(forCapturedCount: capturedCount))
    }

    private func sideButton(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                (emphasized ? Color.white.opacity(0.28) : Color.black.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
