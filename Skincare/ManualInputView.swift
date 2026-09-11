import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// 貼上官網／瓶身全成分：全螢幕固定版面，略過 OCR，走與拍照相同的字典主引擎。
struct ManualInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profileList: [UserProfile]

    /// 寫入掃描紀錄時的來源標記。
    var source: ScanSource = .history
    /// 為 `false` 時只回傳分析結果，不另建歷史紀錄（例如弱辨識頁內貼上重跑）。
    var persistsToHistory: Bool = true
    var onAnalyzed: (ScanResultPayload) -> Void

    @State private var productName: String = ""
    @State private var ingredientsText: String = ""
    @State private var isAnalyzing = false
    @State private var analyzeError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case body
    }

    private var resolvedProductName: String {
        let value = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? ScanSummarySheet.defaultProductName() : value
    }

    private var trimmedBody: String {
        ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAnalyze: Bool {
        !trimmedBody.isEmpty && !isAnalyzing
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                nameField
                bodyEditor
                clipboardButton
                if let analyzeError {
                    Text(analyzeError)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(Theme.blush)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                hintRow
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture {
                if focusedField == .name {
                    focusedField = nil
                }
            }
            .navigationTitle("貼上成分表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isAnalyzing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAnalyzing ? "辨識中…" : "完成") {
                        focusedField = nil
                        Task { await analyze() }
                    }
                    .disabled(!canAnalyze)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                focusedField = .body
            }
            .interactiveDismissDisabled(true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("商品名稱（選填）")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            TextField(ScanSummarySheet.defaultProductName(), text: $productName)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .name)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                )
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("全成分")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            TextEditor(text: $ingredientsText)
                .focused($focusedField, equals: .body)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                )
                .font(.body)
                .foregroundColor(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: ingredientsText) { _, _ in
                    analyzeError = nil
                }
        }
    }

    private var clipboardButton: some View {
        Button {
            pasteFromClipboard()
        } label: {
            Label("從剪貼簿貼上", systemImage: "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Theme.primaryLight,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("從剪貼簿貼上成分表")
    }

    private var hintRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.gold)
            Text("從官網或瓶身複製全成分貼上。")
                .font(.footnote)
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        let pasted = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            analyzeError = "剪貼簿沒有文字。請先複製官網或瓶身全成分。"
            return
        }
        ingredientsText = pasted
        analyzeError = nil
        focusedField = .body
        #endif
    }

    @MainActor
    private func analyze() async {
        guard !trimmedBody.isEmpty, !isAnalyzing else { return }
        isAnalyzing = true
        analyzeError = nil
        focusedField = nil

        let profile = profileList.first
        let result = await ScanSessionProcessor.analyze(text: trimmedBody, profile: profile)

        guard result.dictionaryHitCount > 0 else {
            analyzeError = "這段文字對不上成分字典。請貼完整全成分（逗號、頓號或換行分隔）。"
            isAnalyzing = false
            return
        }

        let saved: ScanHistoryRecordEntity?
        if persistsToHistory {
            saved = ScanSessionProcessor.persist(
                result: result,
                imageData: nil,
                in: modelContext,
                title: resolvedProductName
            )
        } else {
            saved = nil
        }

        let snapshots = saved?.resolvedIngredients ?? PersistedScannedIngredient.buildSnapshots(
            ingredientNames: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients
        )

        let payload = ScanResultPayload(
            imageData: nil,
            ingredients: result.ingredients,
            matchedAlerts: result.matchedAlerts,
            blockedTags: result.blockedTags,
            customBlockedIngredients: result.customBlockedIngredients,
            scannedAt: saved?.scannedAt ?? Date(),
            historyRecordID: saved?.recordID,
            source: source,
            productName: resolvedProductName,
            resolvedIngredients: snapshots
        )

        isAnalyzing = false
        onAnalyzed(payload)
        dismiss()
    }
}
