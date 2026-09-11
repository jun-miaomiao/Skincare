import SwiftUI
import SwiftData

struct FavoriteDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var record: FavoriteProductRecord

    @State private var productName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            renameHeader
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 8)

            IngredientDetailListView(
                ingredients: record.recognizedIngredients,
                matchedAlerts: record.matchedIngredients,
                blockedTags: record.blockedTags,
                customBlockedIngredients: record.customBlockedIngredients,
                productName: trimmedName,
                favoriteRecordID: record.recordID,
                storedSnapshots: record.resolvedIngredients
            )
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if productName.isEmpty {
                productName = record.name
            }
        }
        .onChange(of: productName) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            record.name = trimmed
            try? modelContext.save()
        }
    }

    private var renameHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("產品名稱")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.muted)

            TextField("輸入產品名稱", text: $productName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.cardStroke, lineWidth: 1)
                )
        }
    }

    private var trimmedName: String {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? record.name : trimmed
    }
}

struct FavoriteDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FavoriteDetailView(record: FavoriteProductRecord(name: "掃描產品"))
        }
        .modelContainer(SkincareModelContainer.preview)
    }
}
