import SwiftUI

/// 難標／低品質掃描引導（未命中或信心度不足時，不把灰字清單當成成功）。
enum ScanUnclearPrompt: Equatable, Sendable {
    case noReadableText
    case lowCaptureQuality(identifiedCount: Int)

    var title: String {
        switch self {
        case .noReadableText:
            return "未偵測到清晰成分文字"
        case .lowCaptureQuality:
            return "辨識品質不足"
        }
    }

    var message: String {
        "字太小、反光或只拍到一部份。重拍或是貼上成分即可辨識"
    }

    var showsPartialResults: Bool {
        if case .lowCaptureQuality(let count) = self { return count > 0 }
        return false
    }
}

/// 狀態 C：完全未命中或品質不足時的友善引導（取代冰冷「辨識失敗」Alert）。
struct ScanUnclearResultOverlay: View {
    var prompt: ScanUnclearPrompt = .noReadableText
    var onManualInput: (() -> Void)?
    var onRetake: (() -> Void)?
    var onViewPartialResults: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)

                Text(prompt.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(prompt.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let onManualInput {
                    Button(action: onManualInput) {
                        Text("貼上成分表")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let onRetake {
                    Button(action: onRetake) {
                        Text("重拍")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if prompt.showsPartialResults, let onViewPartialResults {
                    Button(action: onViewPartialResults) {
                        Text("仍查看已辨識結果")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDismiss) {
                    Text("關閉")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.22, green: 0.20, blue: 0.19).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}

/// 狀態 B：弱辨識（1～4 項）頂部暖色提示卡。
struct WeakRecognitionHintCard: View {
    let count: Int
    var onSearchAdd: () -> Void
    var onPasteOfficial: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.gold)

                Text("已為您辨識出 \(count) 項成分，瓶身反光或曲面可能導致部分遺漏。可貼上官網全成分一次補齊，與拍照走同一套字典。")
                    .font(.subheadline)
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onSearchAdd) {
                    Text("+ 手動搜尋補齊")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onPasteOfficial) {
                    Text("貼上官網成分")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            Theme.gold.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.gold.opacity(0.55), lineWidth: 1)
        )
    }
}
