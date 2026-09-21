import SwiftUI

/// 手動修正／新增成分：底部 Sheet + 字典式防抖搜尋（背景執行，避免打字卡住）。
struct IngredientSearchSheet: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let onComplete: () -> Bool
    let onSelect: (IngredientItem) -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    @State private var suggestions: [IngredientItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                suggestionContent
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard onComplete() else { return }
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                IngredientDatabaseManager.shared.ensureLoaded()
                isFieldFocused = true
                scheduleSearch(text)
            }
            .onChange(of: text) { _, newValue in
                scheduleSearch(newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.muted)

            TextField(prompt, text: $text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    guard onComplete() else { return }
                    dismiss()
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !text.isEmpty {
                Button {
                    text = ""
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.muted.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if trimmed.isEmpty {
            VStack(spacing: 8) {
                Spacer(minLength: 24)
                Text("輸入英文或中文關鍵字以搜尋成分字典")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        } else if !isSearchReady(trimmed) {
            VStack(alignment: .leading, spacing: 8) {
                Text("請再輸入至少一個英文字母，或輸入中文關鍵字")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isSearching && suggestions.isEmpty {
            VStack {
                Spacer(minLength: 24)
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("資料庫無完全相符項目，可直接按下「完成」新增自訂成分")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            List {
                Section {
                    ForEach(suggestions) { item in
                        Button {
                            if onSelect(item) {
                                dismiss()
                            }
                        } label: {
                            IngredientSearchSuggestionRow(
                                item: item,
                                query: trimmed
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("建議（\(suggestions.count)）")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.muted)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearchReady(query) else {
            isSearching = false
            suggestions = []
            return
        }

        isSearching = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .userInitiated) {
                IngredientDatabaseManager.shared.suggest(matching: query, limit: 8)
            }.value

            guard !Task.isCancelled else { return }
            suggestions = results
            isSearching = false
        }
    }

    /// 與字典相同：拉丁至少 2 字、中日韓 1 字。
    private func isSearchReady(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        if query.contains(where: { character in
            character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        }) {
            return true
        }
        return query.count >= 2
    }
}

// MARK: - Suggestion row

private struct IngredientSearchSuggestionRow: View {
    let item: IngredientItem
    let query: String

    private var subtitleLine: String {
        let zh = item.displayChineseName
        let tag = item.primaryFunctionTag ?? ""
        // 中文名與功效標籤分開；勿把 function 當成中文名
        if zh.isEmpty || zh == item.englishName {
            return tag.isEmpty ? "" : tag
        }
        if tag.isEmpty { return zh }
        return "\(zh) · \(tag)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(SafetyScoreStyle.color(for: item.safetyScore))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                highlightedEnglishName
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitleLine.isEmpty {
                    Text(subtitleLine)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.englishName)，\(subtitleLine)")
    }

    private var highlightedEnglishName: Text {
        let name = item.englishName
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let range = name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.ink)
        }

        let before = String(name[..<range.lowerBound])
        let match = String(name[range])
        let after = String(name[range.upperBound...])

        return Text(before)
            .font(.subheadline.weight(.regular))
            .foregroundColor(Theme.ink)
            + Text(match)
            .font(.subheadline.weight(.bold))
            .foregroundColor(Theme.accent)
            + Text(after)
            .font(.subheadline.weight(.regular))
            .foregroundColor(Theme.ink)
    }
}
