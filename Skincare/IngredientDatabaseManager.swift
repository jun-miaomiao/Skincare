import CryptoKit
import Foundation

struct IngredientItem: Codable, Hashable, Identifiable, Sendable {
    var id: String { englishName.lowercased() }

    let englishName: String
    let chineseName: String
    let safetyRating: String
    let function: String
    let aliases: [String]?

    private enum CodingKeys: String, CodingKey {
        case englishName, chineseName, safetyRating, function, aliases
        case name, category
    }

    init(englishName: String, chineseName: String, safetyRating: String, function: String, aliases: [String]?) {
        self.englishName = englishName
        self.chineseName = chineseName
        self.safetyRating = safetyRating
        self.function = function
        self.aliases = aliases
    }

    /// 合併搜尋用別名（去重、保留原順序）。
    func mergingAliases(_ extras: [String]) -> IngredientItem {
        var seen = Set((aliases ?? []).map { $0.lowercased(with: Locale(identifier: "en_US_POSIX")) })
        let zhKey = chineseName.lowercased(with: Locale(identifier: "en_US_POSIX"))
        seen.insert(zhKey)
        var merged = aliases ?? []
        for raw in extras {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
            guard !seen.contains(key) else { continue }
            // 已完整寫在中文主名裡的不再重複掛別名。
            if zhKey.contains(key) { continue }
            seen.insert(key)
            merged.append(trimmed)
        }
        return IngredientItem(
            englishName: englishName,
            chineseName: chineseName,
            safetyRating: safetyRating,
            function: function,
            aliases: merged.isEmpty ? aliases : merged
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        englishName = try c.decodeIfPresent(String.self, forKey: .englishName)
            ?? c.decode(String.self, forKey: .name)
        chineseName = try c.decode(String.self, forKey: .chineseName)
        safetyRating = try c.decodeIfPresent(String.self, forKey: .safetyRating) ?? ""
        function = try c.decodeIfPresent(String.self, forKey: .function)
            ?? c.decodeIfPresent(String.self, forKey: .category)
            ?? "一般成分"
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(englishName, forKey: .englishName)
        try c.encode(englishName, forKey: .name)
        try c.encode(chineseName, forKey: .chineseName)
        try c.encode(safetyRating, forKey: .safetyRating)
        try c.encode(function, forKey: .function)
        try c.encode(function, forKey: .category)
        try c.encodeIfPresent(aliases, forKey: .aliases)
    }

    /// 安心度分數 1–9；無法對應時回傳 `nil`。
    var safetyScore: Int? {
        let trimmed = safetyRating.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), (1...9).contains(value) {
            return value
        }
        switch trimmed {
        case "低風險":
            return 1
        case "中風險":
            return 4
        case "高風險":
            return 8
        default:
            return nil
        }
    }

    /// 高風險／禁用：禁止模糊與短詞 contains，僅允許 100% 精確命中。
    var requiresExactMatchOnly: Bool {
        if let score = safetyScore, score >= 7 { return true }
        let blob = "\(safetyRating)\(function)\(chineseName)"
        return blob.contains("禁用") || blob.contains("不得使用")
    }

    /// 右側功能膠囊文字（列表用短標籤，約 2～4 字）。
    /// 香精／香氛相關成分一律顯示「過敏原」，取代「香氛」「調味香氛」等零散標籤。
    var primaryFunctionTag: String? {
        if forcesAllergenFunctionTag {
            return "過敏原"
        }
        return Self.sanitizedFunctionBadge(
            functionText: function,
            englishName: englishName,
            chineseName: chineseName,
            aliases: aliases ?? []
        )
    }

    /// 詳情頁完整功能描述（中文名＋清洗後可讀功能；避免「特定用途」法規代稱）。
    var fullFunctionDescription: String? {
        let readable = Self.readableFunctionDescription(
            functionText: function,
            englishName: englishName,
            chineseName: chineseName,
            aliases: aliases ?? []
        )
        guard let readable, !readable.isEmpty else { return nil }
        let name = displayChineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == readable {
            return readable
        }
        return "\(name)：\(readable)"
    }

    /// 字典／資料庫原始功能字串的第一段（未縮寫）。
    var firstFunctionSegment: String? {
        function
            .components(separatedBy: CharacterSet(charactersIn: "、，,/／|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: - Function badge sanitization

    /// 列表膠囊：白話 2～4 字標籤（含成分覆寫與全域清洗）。
    static func sanitizedFunctionBadge(
        functionText: String,
        englishName: String,
        chineseName: String,
        aliases: [String] = []
    ) -> String? {
        if let override = ingredientSpecificBadge(
            englishName: englishName,
            chineseName: chineseName,
            aliases: aliases
        ) {
            return override
        }

        let segments = functionText
            .components(separatedBy: CharacterSet(charactersIn: "、，,/／|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = segments.joined(separator: "、")
        let blob = joined.isEmpty ? functionText : joined

        if let global = globalFunctionSanitize(blob) {
            return global
        }

        // 「特定用途」→ 依成分特性回歸實際功能
        if blob.contains("特定用途") {
            if let resolved = resolveRestrictedUseBadge(
                englishName: englishName,
                chineseName: chineseName,
                aliases: aliases
            ) {
                return resolved
            }
            return "特殊用途"
        }

        guard let first = segments.first ?? optionalNonEmpty(functionText) else {
            return nil
        }
        return shortFunctionBadge(from: first)
    }

    /// 詳情用可讀功能字串（保留多段；法規代稱改寫）。
    static func readableFunctionDescription(
        functionText: String,
        englishName: String,
        chineseName: String,
        aliases: [String] = []
    ) -> String? {
        let trimmed = functionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("特定用途") {
            if let resolved = resolveRestrictedUseBadge(
                englishName: englishName,
                chineseName: chineseName,
                aliases: aliases
            ) {
                return resolved
            }
        }

        // 化妝品著色劑等長詞改成白話，其餘段落保留
        let parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: "、，,/／|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                if let g = globalFunctionSanitize(part) { return g }
                if part.contains("特定用途") {
                    return resolveRestrictedUseBadge(
                        englishName: englishName,
                        chineseName: chineseName,
                        aliases: aliases
                    ) ?? "特殊用途"
                }
                return part
            }

        let unique = parts.reduce(into: [String]()) { acc, item in
            if !acc.contains(item) { acc.append(item) }
        }
        return unique.isEmpty ? trimmed : unique.joined(separator: "、")
    }

    private static func optionalNonEmpty(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 依成分名稱的明確覆寫（優先於 function 字串）。
    private static func ingredientSpecificBadge(
        englishName: String,
        chineseName: String,
        aliases: [String]
    ) -> String? {
        let names = ([englishName, chineseName] + aliases)
            .map { compactKey($0) }
            .filter { !$0.isEmpty }

        if names.contains("mica") || names.contains("雲母") {
            return "礦物光澤"
        }

        if names.contains(where: {
            ($0.contains("euphorbiacerifera") || ($0.contains("candelillawax") && !$0.contains("ester")))
                || $0 == "小燭樹蠟"
        }) {
            return "質地調節"
        }
        if names.contains(where: { $0.contains("candelillawaxester") || $0.contains("小燭樹蠟酯") }) {
            return "潤膚劑"
        }
        if names.contains(where: { $0.contains("murumuru") || $0.contains("木魯星果") }) {
            return "潤膚脂"
        }
        if names.contains(where: {
            $0 == "aluminumhydroxide" || $0 == "aluminiumhydroxide" || $0.contains("氫氧化鋁")
        }) {
            return "粉體包覆"
        }

        if names.contains("dextrin") || names.contains("糊精")
            || names.contains(where: { $0.contains("dextrinpalmitate") || $0.contains("棕櫚酸糊精") })
            || names.contains(where: { $0.contains("maltodextrin") || $0.contains("麥芽糊精") }) {
            return "增稠劑"
        }

        if names.contains(where: {
            $0 == "potassiumhydroxide" || $0 == "sodiumhydroxide"
                || $0.contains("potassiumorsodiumhydroxide")
                || $0.contains("ammoniumhydroxide") || $0.contains("calciumhydroxide")
                || $0.contains("lithiumhydroxide")
                || $0.contains("氫氧化鉀") || $0.contains("氫氧化鈉") || $0.contains("氫氧化銨")
        }) {
            return "pH 調節"
        }

        // 物理防曬氧化物（優先於「著色劑」）
        if names.contains(where: {
            $0 == "titaniumdioxide" || $0 == "zincoxide" || $0 == "ci77891" || $0 == "ci77947"
                || $0.contains("二氧化鈦") || $0.contains("氧化鋅")
        }) {
            return "防曬劑"
        }

        // Lake / CI 色素代號
        if names.contains(where: isColorantNameKey) {
            return "著色劑"
        }

        return nil
    }

    private static func isColorantNameKey(_ key: String) -> Bool {
        if key.contains("lake") || key.contains("色澱") { return true }
        if key.hasPrefix("ci"), key.dropFirst(2).allSatisfy(\.isNumber) { return true }
        // "red7lake(ci15850)" 等
        if key.contains("ci"), key.range(of: #"ci\d{3,}"#, options: .regularExpression) != nil {
            // 排除非色素：citric、cinnamal 等已由 ci+digits 規則處理
            return key.contains("lake") || key.contains("紅") || key.contains("色")
                || key.hasPrefix("red") || key.hasPrefix("yellow") || key.hasPrefix("blue")
                || key.hasPrefix("green") || key.hasPrefix("orange") || key.hasPrefix("violet")
                || key.hasPrefix("black") || key.hasPrefix("acid") || key.hasPrefix("basic")
                || key.hasPrefix("hc")
        }
        return false
    }

    /// 全域功能文字清洗（不依賴成分名）。
    private static func globalFunctionSanitize(_ text: String) -> String? {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
        let compactLower = compact.lowercased(with: Locale(identifier: "en_US_POSIX"))

        if compact.contains("著色劑") || (compact.contains("著色") && compact.contains("化妝")) {
            return "著色劑"
        }
        if compact.contains("增稠成膜") {
            return "增稠劑"
        }
        if compact.contains("植物固化") {
            return "質地調節"
        }
        if compact.contains("滋養潤唇") {
            return "潤膚脂"
        }
        if compact.contains("保濕軟化") {
            return "潤膚劑"
        }
        if compact.contains("防曬包覆") || compact.contains("粉體包覆") {
            return "粉體包覆"
        }
        // 僅匹配明確 pH／酸鹼調節，避免誤傷 phosphate／phenol
        if compact.contains("酸鹼")
            || compactLower.contains("ph調節")
            || compactLower.contains("ph調整")
            || compactLower.contains("調節ph")
            || compactLower.contains("調整ph")
            || text.contains("pH") && (compact.contains("調節") || compact.contains("調整")) {
            return "pH 調節"
        }
        if compact == "載體" || compact.hasPrefix("載體") {
            return "增稠劑"
        }
        if compact.contains("凝膠化增") || compact.contains("凝膠化增稠") {
            return "增稠劑"
        }
        if compact == "珠光" || (compact.hasPrefix("珠光") && !compact.contains("著色")) {
            return "礦物光澤"
        }
        // CosIng 常把植萃歸在 fragrance／perfuming 類；那不是香精本尊，不可標過敏原。
        if compactLower == "fragrance" || compactLower == "perfuming" || compactLower == "masking"
            || compact == "香氛" || compact == "調味香氛" {
            return "肌膚調理"
        }
        return nil
    }

    /// 將「特定用途／限量管制」依成分特性對應白話功能。
    private static func resolveRestrictedUseBadge(
        englishName: String,
        chineseName: String,
        aliases: [String]
    ) -> String? {
        let keys = ([englishName, chineseName] + aliases).map { compactKey($0) }
        let blob = keys.joined(separator: " ")

        if keys.contains(where: {
            $0.contains("hydroxide") || $0.contains("氫氧化") || $0 == "ammonia" || $0.contains("氨水")
        }) {
            return "pH 調節"
        }
        if keys.contains(where: isColorantNameKey)
            || blob.contains("acidred") || blob.contains("acidblue") || blob.contains("acidyellow")
            || blob.contains("hcblue") || blob.contains("hcred") || blob.contains("hcyellow") {
            return "著色劑"
        }
        if blob.contains("chlorohydrate") || blob.contains("aluminumzirconium")
            || blob.contains("aluminiumchloride") || blob.contains("aluminumchloride")
            || blob.contains("制汗") || blob.contains("防汗") {
            return "制汗劑"
        }
        if blob.contains("octocrylene") || blob.contains("avobenzone") || blob.contains("homosalate")
            || blob.contains("ethylhexylsalicylate") || blob.contains("benzophenone")
            || blob.contains("butylmethoxydibenzoylmethane") || blob.contains("防曬")
            || blob.contains("titaniumdioxide") || blob.contains("zincoxide") {
            return "防曬劑"
        }
        if blob.contains("fluoride") || blob.contains("fluorophosphate") || blob.contains("氟") {
            return "護齒劑"
        }
        if blob.contains("hydrogenperoxide") || blob.contains("過氧化氫") || blob.contains("persulfate") {
            return "氧化劑"
        }
        if blob.contains("phenylenediamine") || blob.contains("aminophenol") || blob.contains("染髮") {
            return "染髮劑"
        }
        return nil
    }

    private static func compactKey(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "／", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    /// 將冗長功能名收斂成列表膠囊用短標籤。
    static func shortFunctionBadge(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        if let global = globalFunctionSanitize(trimmed) {
            return global
        }

        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")

        let sorted = functionBadgeAbbreviations.sorted { $0.0.count > $1.0.count }
        for (pattern, short) in sorted {
            if compact == pattern {
                return short
            }
        }
        for (pattern, short) in sorted where pattern.count >= 4 {
            if compact.hasPrefix(pattern) || compact.contains(pattern) {
                return short
            }
        }

        // 已夠短則直接使用；過長則取前 4 字作為後備（避免省略號）。
        // 「pH 調節」保留空白。
        if trimmed == "pH 調節" { return trimmed }
        if compact.count <= 4 {
            return compact
        }
        return String(compact.prefix(4))
    }

    /// 長詞優先；匹配時回傳 2～4 字短標籤。
    private static let functionBadgeAbbreviations: [(String, String)] = [
        ("懸浮穩定劑", "穩定劑"),
        ("懸浮穩定", "穩定劑"),
        ("增稠與懸浮穩定劑", "穩定劑"),
        ("增稠懸浮", "穩定劑"),
        ("凝膠化增稠劑", "增稠劑"),
        ("增稠劑", "增稠劑"),
        ("黏度調節", "增稠劑"),
        ("修護屏障保濕劑", "屏障修護"),
        ("修護屏障保濕", "屏障修護"),
        ("修護屏障", "屏障修護"),
        ("屏障修護", "屏障修護"),
        ("環保整合劑", "螯合劑"),
        ("環保螯合劑", "螯合劑"),
        ("螯合劑", "螯合劑"),
        ("抗氧化穩定劑", "抗氧化"),
        ("抗氧化劑", "抗氧化"),
        ("抗氧化", "抗氧化"),
        ("溫和界面活性劑", "界面活性"),
        ("溫和界面活性", "界面活性"),
        ("界面活性劑", "界面活性"),
        ("界面活性", "界面活性"),
        ("吸油抗結塊劑", "吸油劑"),
        ("吸油抗結塊", "吸油劑"),
        ("抗結塊劑", "吸油劑"),
        ("清爽柔潤脂", "潤膚脂"),
        ("清爽柔潤劑", "潤膚脂"),
        ("清爽柔潤", "潤膚脂"),
        ("柔潤劑", "潤膚脂"),
        ("潤膚脂", "潤膚脂"),
        ("潤膚劑", "潤膚劑"),
        ("質地調節", "質地調節"),
        ("粉體包覆", "粉體包覆"),
        ("增稠成膜劑", "增稠劑"),
        ("增稠成膜", "增稠劑"),
        ("物理防曬", "防曬劑"),
        ("化學防曬", "防曬劑"),
        ("防曬劑", "防曬劑"),
        ("礦物光澤", "礦物光澤"),
        ("礦物粉體", "礦物粉體"),
        ("珠光", "礦物光澤"),
        ("載體", "增稠劑"),
        ("著色劑", "著色劑"),
        ("pH調節劑", "pH 調節"),
        ("ph調節劑", "pH 調節"),
        ("pH調節", "pH 調節")
    ]

    /// 中文名為「香精」，或英文名／別名本身就是香精・香氛成分時，膠囊強制「過敏原」。
    /// 不用 CosIng function 字串：蠟／油脂常夾帶 fragrance 法規備註，會誤標過敏原。
    var forcesAllergenFunctionTag: Bool {
        let zh = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if zh == "香精" { return true }

        let nameKeys = ([englishName, chineseName] + (aliases ?? []))
            .map { Self.compactFragranceKey($0) }
            .filter { !$0.isEmpty }
        return nameKeys.contains { Self.fragranceEnglishKeys.contains($0) }
    }

    /// 列表／卡片「中文名稱」唯一來源（永不回退到 function／category）。
    /// 若字典誤填法規英文備註（如 "Potassium or sodium hydroxide"），改回乾淨中文名。
    var displayChineseName: String {
        let trimmed = chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned = Self.cleanedChineseSubtitle(
            chineseName: trimmed,
            englishName: englishName
        ) {
            return cleaned
        }
        if trimmed.isEmpty {
            return englishName
        }
        // 中文欄位為法規英文備註且有標準中文對照時，改顯示中文
        if Self.looksLikeRegulatoryEnglishNote(trimmed),
           let preferred = Self.preferredChineseName(forEnglish: englishName) {
            return preferred
        }
        return trimmed
    }

    /// 清洗副標題：法規英文備註 → 標準中文名。
    private static func cleanedChineseSubtitle(chineseName: String, englishName: String) -> String? {
        let compactZH = compactKey(chineseName)
        let compactEN = compactKey(englishName)

        // Potassium hydroxide 被填成 "Potassium or sodium hydroxide"
        if compactEN == "potassiumhydroxide"
            || compactZH.contains("potassiumorsodiumhydroxide")
            || compactZH == "potassiumorsodiumhydroxide" {
            return "氫氧化鉀"
        }
        if compactEN == "sodiumhydroxide", looksLikeRegulatoryEnglishNote(chineseName) {
            return "氫氧化鈉"
        }
        return nil
    }

    private static func looksLikeRegulatoryEnglishNote(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        // 含 " or " 的法規合併備註，或幾乎沒有 CJK
        if t.localizedCaseInsensitiveContains(" or ") { return true }
        let cjk = t.unicodeScalars.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count
        let letters = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return cjk == 0 && letters >= 6
    }

    private static func preferredChineseName(forEnglish englishName: String) -> String? {
        switch compactKey(englishName) {
        case "potassiumhydroxide": return "氫氧化鉀"
        case "sodiumhydroxide": return "氫氧化鈉"
        default: return nil
        }
    }

    private static func compactFragranceKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "／", with: "")
    }

    /// 常見香精／香氛成分英文鍵（compact lowercased）。
    private static let fragranceEnglishKeys: Set<String> = [
        "fragrance", "parfum", "perfume", "flavor", "flavour", "aroma",
        "geraniol", "limonene", "dlimonene", "linalool", "citronellol",
        "eugenol", "citral", "coumarin", "farnesol", "isoeugenol",
        "cinnamal", "cinnamylalcohol", "benzylalcohol", "benzylbenzoate",
        "benzylsalicylate", "benzylcinnamate", "hexylcinnamal", "amylcinnamal",
        "hydroxycitronellal", "butylphenylmethylpropional", "lilial",
        "alphaisomethylionone", "methyl2octynoate",
        "everniaprunastriextract", "everniafurfuraceaextract",
        "anisealcohol", "anisylalcohol", "amylcinnamylalcohol",
        "hydroxyisohexyl3cyclohexenecarboxaldehyde", "lyral", "hicc"
    ]

    /// 英文名、中文名與別名（已去空白）。
    var allMatchNames: [String] {
        var names = [englishName, chineseName]
        if let aliases {
            names.append(contentsOf: aliases)
        }
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 本地成分資料庫：單例快取 + O(1) 雜湊索引。
/// 以 `databaseVersion` + JSON 內容雜湊偵測更新，過期時清空並重載 Bundle 內最新 JSON。
final class IngredientDatabaseManager: @unchecked Sendable {
    static let shared = IngredientDatabaseManager()

    /// 隨 `IngredientsDatabase.json` 內容更新而遞增（App 更新後強制重載）。
    static let bundledDatabaseVersion = 15
    static let databaseVersionKey = "databaseVersion"
    static let databaseContentHashKey = "skincare.ingredientDatabaseContentHash"

    private let lock = NSLock()
    private var items: [IngredientItem] = []
    /// 扁平化 O(1) 快取：英文名／中文名／別名 → 成分（clean + compact key）。
    private var lookupDict: [String: IngredientItem] = [:]
    /// JSON `aliases` 專用扁平索引，查詢仍為 O(1)。
    private var aliasLookupDict: [String: IngredientItem] = [:]
    /// 小寫扁平索引：標準名＋aliases（含植萃展開／同義詞鍵），查詢 O(1)。
    private var lookupIndex: [String: IngredientItem] = [:]
    /// 去空格／斜線／括號／橫槓後的正規化索引，與 `lookupDict` 分離以免污染前綴模糊。
    private var normalizedLookupDict: [String: IngredientItem] = [:]
    /// 前綴分桶：cleanKey 前 6 字 → 候選，避免每次掃全庫。
    private var prefixBuckets: [String: [(key: String, item: IngredientItem)]] = [:]
    /// 正規化 key 依長度分桶，模糊比對只掃相近長度。
    private var normalizedByLength: [Int: [(key: String, item: IngredientItem)]] = [:]
    /// 鄰近拼字救援索引：首字母 → 長度 → 候選。模糊比對只走這裡，禁止掃全庫。
    private var localFuzzyByInitial: [Character: [Int: [(key: String, item: IngredientItem)]]] = [:]
    /// 僅常用／風險成分，供未命中 token 的有限 Levenshtein（禁止掃全庫）。
    private var fuzzyFallbackItems: [(key: String, item: IngredientItem)] = []
    private var isLoaded = false
    /// 本次行程已載入的 JSON 雜湊；與 UserDefaults／Bundle 比對用。
    private var loadedContentHash: String?

    private init() {}

    /// App 啟動時可先呼叫，於背景載入並常駐記憶體。
    func preload() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.ensureLoaded()
        }
    }

    /// 確保載入最新 Bundle JSON；版本或內容變更時強制清空舊快取後重載。
    @discardableResult
    func ensureLoaded() -> Bool {
        lock.lock()

        if isLoaded, !mustReloadFromBundleUnlocked() {
            lock.unlock()
            return !items.isEmpty
        }

        // 版本／內容更新：清空記憶體舊資料後重載
        if isLoaded {
            print("🔄 偵測到成分資料庫更新，清空舊快取並重新載入 IngredientsDatabase.json")
            clearMemoryCachesUnlocked()
        }

        guard let url = Bundle.main.url(forResource: "IngredientsDatabase", withExtension: "json") else {
            clearMemoryCachesUnlocked()
            isLoaded = true
            loadedContentHash = nil
            lock.unlock()
            print("📊 目前本地成分資料庫總筆數: 0 筆（找不到 JSON）")
            return false
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([IngredientItem].self, from: data)
            let hash = Self.contentHash(of: data)
            let merged = Self.mergingTraditionalChineseSearchAliases(decoded)
            items = merged
            let dicts = Self.buildLookupDicts(from: merged)
            lookupDict = dicts.exact
            aliasLookupDict = dicts.aliases
            lookupIndex = dicts.lookupIndex
            normalizedLookupDict = dicts.normalized
            prefixBuckets = dicts.prefixBuckets
            normalizedByLength = dicts.normalizedByLength
            localFuzzyByInitial = Self.buildLocalFuzzyByInitial(from: dicts.normalizedByLength)
            fuzzyFallbackItems = Self.buildFuzzyFallbackItems(
                exact: dicts.exact,
                aliases: dicts.aliases,
                normalized: dicts.normalized,
                lookupIndex: dicts.lookupIndex
            )
            isLoaded = true
            loadedContentHash = hash
            let count = items.count
            persistRevisionUnlocked(version: Self.bundledDatabaseVersion, contentHash: hash)
            lock.unlock()

            DictionaryReverseAnalyzer.resetCandidateCache()
            print("📊 目前本地成分資料庫總筆數: \(count) 筆（v\(Self.bundledDatabaseVersion)）")
            return true
        } catch {
            clearMemoryCachesUnlocked()
            isLoaded = true
            loadedContentHash = nil
            lock.unlock()
            print("📊 目前本地成分資料庫總筆數: 0 筆（解碼失敗: \(error.localizedDescription)）")
            return false
        }
    }

    /// 測試／除錯：強制忽略快取，自 Bundle 重載。
    @discardableResult
    func forceReloadFromBundle() -> Bool {
        lock.lock()
        clearMemoryCachesUnlocked()
        // 清掉已存版本，讓 ensureLoaded 一定走重載
        UserDefaults.standard.removeObject(forKey: Self.databaseVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.databaseContentHashKey)
        lock.unlock()
        DictionaryReverseAnalyzer.resetCandidateCache()
        return ensureLoaded()
    }

    // MARK: - Version / hash

    private func mustReloadFromBundleUnlocked() -> Bool {
        let storedVersion = UserDefaults.standard.integer(forKey: Self.databaseVersionKey)
        if storedVersion != Self.bundledDatabaseVersion {
            return true
        }

        let storedHash = UserDefaults.standard.string(forKey: Self.databaseContentHashKey) ?? ""

        // 本行程已載入，且版本／雜湊與 UserDefaults 一致 → 不必重讀 JSON
        if isLoaded,
           let loadedContentHash,
           !storedHash.isEmpty,
           loadedContentHash == storedHash {
            return false
        }

        guard let url = Bundle.main.url(forResource: "IngredientsDatabase", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return true
        }
        let hash = Self.contentHash(of: data)
        if hash != storedHash {
            return true
        }

        // 雜湊吻合但記憶體尚未載入（冷啟動）→ 交由後續載入路徑處理（回傳 false 時
        // ensureLoaded 因 !isLoaded 仍會繼續往下解碼）。
        return false
    }

    private func persistRevisionUnlocked(version: Int, contentHash: String) {
        UserDefaults.standard.set(version, forKey: Self.databaseVersionKey)
        UserDefaults.standard.set(contentHash, forKey: Self.databaseContentHashKey)
    }

    private func clearMemoryCachesUnlocked() {
        items = []
        lookupDict = [:]
        aliasLookupDict = [:]
        lookupIndex = [:]
        normalizedLookupDict = [:]
        prefixBuckets = [:]
        normalizedByLength = [:]
        localFuzzyByInitial = [:]
        fuzzyFallbackItems = []
        isLoaded = false
        loadedContentHash = nil
    }

    private static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let prefixBucketLength = 6

    private static func buildLookupDicts(from items: [IngredientItem]) -> (
        exact: [String: IngredientItem],
        aliases: [String: IngredientItem],
        lookupIndex: [String: IngredientItem],
        normalized: [String: IngredientItem],
        prefixBuckets: [String: [(key: String, item: IngredientItem)]],
        normalizedByLength: [Int: [(key: String, item: IngredientItem)]]
    ) {
        var map: [String: IngredientItem] = [:]
        var aliasMap: [String: IngredientItem] = [:]
        var lookupIndex: [String: IngredientItem] = [:]
        var normalized: [String: IngredientItem] = [:]
        var buckets: [String: [(key: String, item: IngredientItem)]] = [:]
        var byLength: [Int: [(key: String, item: IngredientItem)]] = [:]
        map.reserveCapacity(items.count * 4)
        aliasMap.reserveCapacity(items.count * 2)
        lookupIndex.reserveCapacity(items.count * 6)
        normalized.reserveCapacity(items.count * 4)

        for item in items {
            for raw in item.allMatchNames {
                let key = cleanKey(raw)
                guard !key.isEmpty else { continue }
                indexExact(key, item: item, into: &map, buckets: &buckets)
                registerLookupIndex(raw, item: item, into: &lookupIndex)
                // 額外索引去標點版本，提升 OCR 變體命中仍維持 O(1)
                let compact = compactKey(raw)
                if !compact.isEmpty {
                    indexExact(compact, item: item, into: &map, buckets: &buckets)
                }
                // 高分子：Acrylate ↔ Acrylates 單複數雙向索引
                for variant in acrylateNumberFoldVariants(key) where variant != key {
                    indexExact(variant, item: item, into: &map, buckets: &buckets)
                    registerLookupIndex(variant, item: item, into: &lookupIndex)
                }
                let norm = normalizedKey(raw)
                if !norm.isEmpty, normalized[norm] == nil {
                    normalized[norm] = item
                    byLength[norm.count, default: []].append((norm, item))
                }
                for variant in acrylateNumberFoldVariants(key) {
                    let variantNorm = normalizedKey(variant)
                    if !variantNorm.isEmpty, normalized[variantNorm] == nil {
                        normalized[variantNorm] = item
                        byLength[variantNorm.count, default: []].append((variantNorm, item))
                    }
                }
            }

            for alias in item.aliases ?? [] {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                registerLookupIndex(trimmed, item: item, into: &lookupIndex)
                let key = cleanKey(trimmed)
                if !key.isEmpty, aliasMap[key] == nil {
                    aliasMap[key] = item
                }
                let compact = compactKey(trimmed)
                if !compact.isEmpty, aliasMap[compact] == nil {
                    aliasMap[compact] = item
                }
                let norm = normalizedKey(trimmed)
                if !norm.isEmpty, aliasMap[norm] == nil {
                    aliasMap[norm] = item
                }
            }
        }
        return (map, aliasMap, lookupIndex, normalized, buckets, byLength)
    }

    /// 將正規化 key 依「首字母 × 長度」分桶，供鄰近拼字救援 O(候選) 掃描。
    private static func buildLocalFuzzyByInitial(
        from byLength: [Int: [(key: String, item: IngredientItem)]]
    ) -> [Character: [Int: [(key: String, item: IngredientItem)]]] {
        var index: [Character: [Int: [(key: String, item: IngredientItem)]]] = [:]
        for (length, entries) in byLength {
            for (key, item) in entries {
                guard let initial = key.first else { continue }
                index[initial, default: [:]][length, default: []].append((key, item))
            }
        }
        return index
    }

    private static let commonINCINames: [String] = [
        "WATER", "AQUA", "GLYCERIN", "GLYCEROL", "NIACINAMIDE", "NIACINAMIDE",
        "SALICYLIC ACID", "BUTYLENE GLYCOL", "METHYLPROPANEDIOL", "SODIUM HYDROXIDE",
        "POLYSORBATE 20", "TETRASODIUM EDTA", "DISODIUM EDTA",
        "CAMELLIA OLEIFERA LEAF EXTRACT", "PHENOXYETHANOL", "TOCOPHEROL",
        "PANTHENOL", "ASCORBIC ACID", "HYALURONIC ACID", "SODIUM HYALURONATE",
        "CETYL ALCOHOL", "STEARIC ACID", "DIMETHICONE", "XANTHAN GUM", "CARBOMER",
        "FRAGRANCE", "PARFUM", "LINALOOL", "LIMONENE", "CITRONELLOL", "GERANIOL",
        "BENZYL ALCOHOL", "METHYLPARABEN", "PROPYLPARABEN", "ALCOHOL DENAT",
        "ETHANOL", "PROPYLENE GLYCOL", "PENTYLENE GLYCOL", "ETHYLHEXYLGLYCERIN",
        "CITRIC ACID", "LACTIC ACID", "GLYCOLIC ACID", "RETINOL", "SQUALANE",
        "ALLANTOIN", "BISABOLOL", "CAPRYLYL GLYCOL", "SODIUM BENZOATE",
        "POTASSIUM SORBATE", "HELIANTUS ANNUUS SEED OIL", "HELIANTHUS ANNUUS SEED OIL",
        "BEESWAX", "CERA ALBA", "LANOLIN", "CANOLA OIL", "TOCOPHERYL ACETATE",
        "1,2-HEXANEDIOL", "CAPRYLIC/CAPRIC TRIGLYCERIDE",
    ]

    private static func hitFromMaps(
        _ name: String,
        exact: [String: IngredientItem],
        aliases: [String: IngredientItem],
        normalized: [String: IngredientItem],
        lookupIndex: [String: IngredientItem]
    ) -> IngredientItem? {
        let indexKey = lookupIndexKey(name)
        if !indexKey.isEmpty, let hit = lookupIndex[indexKey] ?? lookupIndex[indexKey.replacingOccurrences(of: " ", with: "")] {
            return hit
        }
        let key = cleanKey(name)
        if !key.isEmpty {
            if let hit = exact[key] ?? aliases[key] { return hit }
        }
        let compact = compactKey(name)
        if !compact.isEmpty, let hit = exact[compact] ?? aliases[compact] { return hit }
        let norm = normalizedKey(name)
        if !norm.isEmpty, let hit = normalized[norm] ?? aliases[norm] { return hit }
        return nil
    }

    private static func buildFuzzyFallbackItems(
        exact: [String: IngredientItem],
        aliases: [String: IngredientItem],
        normalized: [String: IngredientItem],
        lookupIndex: [String: IngredientItem]
    ) -> [(key: String, item: IngredientItem)] {
        var seenItem = Set<String>()
        var result: [(key: String, item: IngredientItem)] = []

        func append(_ item: IngredientItem) {
            let id = normalizedKey(item.englishName)
            guard seenItem.insert(id).inserted else { return }
            var keys = [normalizedKey(item.englishName)]
            keys.append(contentsOf: item.allMatchNames.map { normalizedKey($0) })
            for key in keys where key.count >= 7 {
                result.append((key, item))
            }
        }

        for name in commonINCINames {
            if let item = hitFromMaps(
                name,
                exact: exact,
                aliases: aliases,
                normalized: normalized,
                lookupIndex: lookupIndex
            ) {
                append(item)
            }
        }
        for keywords in IngredientMatcher.aliasTable.values {
            for keyword in keywords {
                if let item = hitFromMaps(
                    keyword,
                    exact: exact,
                    aliases: aliases,
                    normalized: normalized,
                    lookupIndex: lookupIndex
                ) {
                    append(item)
                }
            }
        }
        return result
    }

    static func lookupIndexKey(_ text: String) -> String {
        let expanded = IngredientMatcher.expandBotanicalAbbreviations(text)
        return IngredientMatcher.synonymLookupKey(expanded)
    }

    private static func registerLookupIndex(
        _ raw: String,
        item: IngredientItem,
        into index: inout [String: IngredientItem]
    ) {
        let key = lookupIndexKey(raw)
        guard !key.isEmpty else { return }
        if index[key] == nil {
            index[key] = item
        }
        let compact = key.replacingOccurrences(of: " ", with: "")
        if !compact.isEmpty, index[compact] == nil {
            index[compact] = item
        }
        let synonym = IngredientMatcher.applyINCISynonyms(key)
        if synonym != key, index[synonym] == nil {
            index[synonym] = item
        }
    }

    private static func indexExact(
        _ key: String,
        item: IngredientItem,
        into map: inout [String: IngredientItem],
        buckets: inout [String: [(key: String, item: IngredientItem)]]
    ) {
        guard !key.isEmpty, map[key] == nil else { return }
        map[key] = item
        let bucketKey = prefixBucketKey(for: key)
        buckets[bucketKey, default: []].append((key, item))
    }

    /// 高分子名稱單複數容錯：`ACRYLATE` ↔ `ACRYLATES`（不誤傷 METHACRYLATE）。
    static func acrylateNumberFoldVariants(_ cleanUpperKey: String) -> [String] {
        let key = cleanUpperKey.uppercased(with: Locale(identifier: "en_US_POSIX"))
        guard key.contains("ACRYLATE") else { return [] }

        var variants: [String] = []
        if key.contains("ACRYLATES") {
            let folded = key.replacingOccurrences(of: "ACRYLATES", with: "ACRYLATE")
            if folded != key { variants.append(folded) }
        }
        if let regex = try? NSRegularExpression(pattern: #"\bACRYLATE\b"#) {
            let range = NSRange(key.startIndex..<key.endIndex, in: key)
            let pluralized = regex.stringByReplacingMatches(
                in: key,
                options: [],
                range: range,
                withTemplate: "ACRYLATES"
            )
            if pluralized != key { variants.append(pluralized) }
        }
        return Array(Dictionary(uniqueKeysWithValues: variants.map { ($0, $0) }).keys)
    }

    private static func prefixBucketKey(for cleanKey: String) -> String {
        if cleanKey.count <= prefixBucketLength { return cleanKey }
        return String(cleanKey.prefix(prefixBucketLength))
    }

    /// Key：去頭尾空白／標點、統一連字號、壓縮空白後轉大寫。
    static func cleanKey(_ text: String) -> String {
        var value = text.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )
        let dashes = ["–", "—", "‐", "‑", "−", "﹣", "－"]
        for dash in dashes {
            value = value.replacingOccurrences(of: dash, with: "-")
        }
        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return value.uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// 去標點後的緊湊 Key（仍為 O(1) 字典查詢）。
    static func compactKey(_ text: String) -> String {
        let upper = cleanKey(text)
        let filtered = upper.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(filtered)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 寬鬆正規化：移除空格、斜線、括號、橫槓等符號後轉大寫。
    /// 例：`"HYDROGENATED POLY(C6-14 OLEFIN)"` → `"HYDROGENATEDPOLYC614OLEFIN"`
    static func normalizedKey(_ text: String) -> String {
        cleanKey(text).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { Character($0) }
            .reduce(into: "") { $0.append($1) }
    }

    /// 常見成分的繁中搜尋別名（不含簡體）。掛進 `aliases`，字典／掃描查詢都能用。
    private static let traditionalChineseSearchAliases: [String: [String]] = [
        "niacinamide": ["維他命B3", "維生素B3", "菸鹼醯胺"],
        "retinol": ["A醇", "維他命A", "維生素A", "視黃醇"],
        "retinal": ["A醛", "視黃醛"],
        "retinylpalmitate": ["維他命A棕櫚酸酯", "視黃醇棕櫚酸酯"],
        "ascorbicacid": ["維他命C", "維生素C", "左旋C", "抗壞血酸"],
        "glycerin": ["丙三醇", "甘油"],
        "hyaluronicacid": ["玻尿酸", "透明質酸"],
        "sodiumhyaluronate": ["玻尿酸鈉", "透明質酸鈉", "玻尿酸"],
        "squalane": ["角鯊烷", "鯊烷"],
        "squalene": ["角鯊烯"],
        "salicylicacid": ["水楊酸", "BHA"],
        "centellaasiaticaextract": ["積雪草", "雷公根", "CICA"],
        "madecassoside": ["羥基積雪草苷", "積雪草"],
        "asiaticoside": ["積雪草苷", "積雪草"],
        "ceramidenp": ["神經醯胺", "神經醯胺NP"],
        "ceramideap": ["神經醯胺", "神經醯胺AP"],
        "ceramideeop": ["神經醯胺", "神經醯胺EOP"],
        "ceramidens": ["神經醯胺", "神經醯胺NS"],
        "panthenol": ["維他命B5", "維生素B5", "泛醇"],
        "tocopherol": ["維他命E", "維生素E", "生育酚"],
        "dimethicone": ["矽靈", "聚二甲基矽氧烷"],
        "butyleneglycol": ["丁二醇", "BG"],
        "propyleneglycol": ["丙二醇", "PG"],
        "phenoxyethanol": ["苯氧乙醇"],
        "tranexamicacid": ["傳明酸", "氨甲環酸"],
        "azelaicacid": ["壬二酸", "杜鵑花酸"],
        "glycolicacid": ["甘醇酸", "果酸", "AHA"],
        "lacticacid": ["乳酸", "AHA"],
        "mandelicacid": ["杏仁酸"],
        "bakuchiol": ["補骨脂酚", "植物A醇"],
        "ectoin": ["依克多因"],
        "arbutin": ["熊果苷", "熊果素"],
        "kojicacid": ["曲酸", "麴酸"],
        "allantoin": ["尿囊素"],
        "betaine": ["甜菜鹼"],
        "urea": ["尿素"],
        "collagen": ["膠原蛋白"],
        "adenosine": ["腺苷"],
        "caffeine": ["咖啡因"],
        "zincoxide": ["氧化鋅", "鋅白"],
        "titaniumdioxide": ["二氧化鈦", "鈦白"],
        "camelliasinensisleafextract": ["綠茶萃取", "茶葉萃取", "綠茶"],
        "aloebarbadensisleafjuice": ["蘆薈汁", "蘆薈"],
        "butyrospermumparkiibutter": ["乳木果脂", "乳油木果脂"],
        "cholesterol": ["膽固醇"]
    ]

    /// 把繁中搜尋別名併入列，再建索引（不改 JSON 檔）。
    private static func mergingTraditionalChineseSearchAliases(_ items: [IngredientItem]) -> [IngredientItem] {
        items.map { item in
            let key = normalizedKey(item.englishName).lowercased(with: Locale(identifier: "en_US_POSIX"))
            guard let extras = traditionalChineseSearchAliases[key] else { return item }
            return item.mergingAliases(extras)
        }
    }

    /// O(1) 查詢：精確 → 去標點 → 正規化（全詞，不拆 `/`）。
    func lookup(ingredientName: String) -> IngredientItem? {
        ensureLoaded()
        let key = Self.cleanKey(ingredientName)
        guard !key.isEmpty else { return nil }

        let compact = Self.compactKey(ingredientName)
        let normalized = Self.normalizedKey(ingredientName)

        lock.lock()
        var hit = lookupIndex[Self.lookupIndexKey(ingredientName)]
            ?? lookupIndex[Self.lookupIndexKey(ingredientName).replacingOccurrences(of: " ", with: "")]
            ?? lookupDict[key]
            ?? aliasLookupDict[key]
            ?? lookupDict[compact]
            ?? aliasLookupDict[compact]
            ?? normalizedLookupDict[normalized]
            ?? aliasLookupDict[normalized]
        if hit == nil {
            for variant in Self.acrylateNumberFoldVariants(key) {
                if let folded = lookupDict[variant] {
                    hit = folded
                    break
                }
                let variantNorm = Self.normalizedKey(variant)
                if !variantNorm.isEmpty, let folded = normalizedLookupDict[variantNorm] {
                    hit = folded
                    break
                }
            }
        }
        lock.unlock()
        return hit
    }

    /// 小寫扁平索引 O(1) 查詢（標準名／別名／植萃展開鍵）。
    func lookupFromIndex(_ rawName: String) -> IngredientItem? {
        ensureLoaded()
        let key = Self.lookupIndexKey(rawName)
        guard !key.isEmpty else { return nil }
        let compact = key.replacingOccurrences(of: " ", with: "")
        let synonym = IngredientMatcher.applyINCISynonyms(key)
        lock.lock()
        let hit = lookupIndex[key]
            ?? lookupIndex[compact]
            ?? lookupIndex[synonym]
            ?? lookupIndex[synonym.replacingOccurrences(of: " ", with: "")]
        lock.unlock()
        return hit
    }

    /// 對外模糊比對入口（相容舊名）：一律走模糊沙盒。
    func fuzzyMatch(normalizedKey: String) -> IngredientItem? {
        sandboxFuzzyMatch(normalizedKey: normalizedKey)
    }

    /// 相容舊名：全數導向模糊沙盒，避免任何殘留的寬鬆容錯路徑。
    func limitedFuzzyMatch(normalizedKey: String) -> IngredientItem? {
        sandboxFuzzyMatch(normalizedKey: normalizedKey)
    }

    /// 模糊沙盒（Fuzzy Sandbox）：全 App 唯一允許的容錯比對入口。
    ///
    /// 四道硬性閘門，缺一即放棄容錯：
    /// 1. 待比對字串長度 ≥ 6；短詞噪音一律不模糊。
    /// 2. 只掃常用／風險小清單，永遠不掃全庫（效能與誤判雙重保護）。
    /// 3. 目標成分安心度 ≤ 4 且未標記禁用；評分 ≥ 7 或禁用者強制 100% 精準比對。
    /// 4. Levenshtein 距離恰為 1，且解唯一；同距離多解視為不可信，直接放棄。
    func sandboxFuzzyMatch(normalizedKey: String) -> IngredientItem? {
        ensureLoaded()
        let compact = normalizedKey.uppercased(with: Locale(identifier: "en_US_POSIX"))
        guard compact.count >= Self.fuzzySandboxMinimumLength else { return nil }

        lock.lock()
        let candidates = fuzzyFallbackItems
        lock.unlock()

        var bestItem: IngredientItem?
        var ambiguous = false

        for (key, item) in candidates where Self.isFuzzySandboxEligible(item) {
            guard key.count >= Self.fuzzySandboxMinimumLength else { continue }
            guard abs(key.count - compact.count) <= 1 else { continue }
            guard Self.levenshteinDistance(compact, key) == 1 else { continue }

            if let current = bestItem {
                if current.englishName != item.englishName { ambiguous = true }
            } else {
                bestItem = item
            }
        }

        if ambiguous { return nil }
        if let bestItem { return bestItem }
        return truncationRescue(compact: compact, candidates: candidates)
    }

    /// 曲面瓶身截斷救援：Token 的每個字元都正確、只是尾巴被裁掉
    /// （例：`METHYLPROPANEDI` → `METHYLPROPANEDIOL`）。
    ///
    /// 這不是模糊比對而是前綴補全，但仍套用同一組沙盒限制：
    /// 只對安心度 ≤ 4 的成分開放、要求唯一解、且缺字不得超過 4 個。
    private func truncationRescue(
        compact: String,
        candidates: [(key: String, item: IngredientItem)]
    ) -> IngredientItem? {
        guard compact.count >= Self.truncationRescueMinimumLength else { return nil }

        var match: IngredientItem?
        for (key, item) in candidates where Self.isFuzzySandboxEligible(item) {
            guard key.count > compact.count, key.hasPrefix(compact) else { continue }
            guard key.count - compact.count <= 4 else { continue }
            if let current = match, current.englishName != item.englishName { return nil }
            match = item
        }
        return match
    }

    /// 沙盒白名單：非禁用、非高風險，且安心度明確標示為 ≤ 4。
    /// 無評分資料者一律排除，寧可漏判也不誤標成違禁化學物。
    static func isFuzzySandboxEligible(_ item: IngredientItem) -> Bool {
        guard !item.requiresExactMatchOnly else { return false }
        guard let score = item.safetyScore else { return false }
        return score <= fuzzySandboxMaximumSafetyScore
    }

    /// 模糊沙盒門檻：長度 ≥ 6、安心度 ≤ 4、前綴救援長度 ≥ 8。
    static let fuzzySandboxMinimumLength = 6
    static let fuzzySandboxMaximumSafetyScore = 4
    private static let truncationRescueMinimumLength = 8

    /// 鄰近拼字救援最短長度。短於 6 的 Token（Honey、Urea 等）碰撞率太高，只走精準命中。
    static let localFuzzyMinimumLength = 6

    /// 候選長度與 Token 的最大差距。超過此值不可能落在動態編輯距離門檻內。
    static let localFuzzyLengthWindow = 3

    /// 單次救援最多比對的候選數。超過時改要求前兩個字母相同，避免 OCR 長句拖垮主執行緒。
    private static let localFuzzyCandidateCap = 400

    /// 依字串長度動態決定 Levenshtein 門檻：短字差 1、中字差 2、長字差 3。
    static func localFuzzyMaxDistance(forLength length: Int) -> Int {
        switch length {
        case ..<localFuzzyMinimumLength:
            return 0
        case 6...7:
            return 1
        case 8...14:
            return 2
        default:
            return 3
        }
    }

    /// 鄰近拼字模糊救援：Token 精準未命中時，只在「同首字母、長度 ±3」的分桶內算編輯距離。
    ///
    /// 絕不全庫掃描。高風險／禁用成分（`requiresExactMatchOnly`）一律排除。
    /// 同距離出現兩個不同成分時視為不可信，回傳 `nil` 讓 UI 維持灰色未收錄。
    func localLevenshteinMatch(normalizedKey: String) -> IngredientItem? {
        ensureLoaded()
        let compact = Self.normalizedKey(normalizedKey)
        let maxDistance = Self.localFuzzyMaxDistance(forLength: compact.count)
        guard maxDistance > 0, let initial = compact.first else { return nil }

        lock.lock()
        let lengthBuckets = localFuzzyByInitial[initial] ?? [:]
        lock.unlock()

        var candidates: [(key: String, item: IngredientItem)] = []
        let minLength = compact.count - Self.localFuzzyLengthWindow
        let maxLength = compact.count + Self.localFuzzyLengthWindow
        for length in minLength...maxLength {
            guard length > 0 else { continue }
            candidates.append(contentsOf: lengthBuckets[length] ?? [])
        }
        guard !candidates.isEmpty else { return nil }

        // 候選過多時改要求前兩個字母相同，把比對量壓回安全範圍。
        var pool = candidates
        if candidates.count > Self.localFuzzyCandidateCap, compact.count >= 2 {
            let prefix2 = String(compact.prefix(2))
            pool = candidates.filter { $0.key.hasPrefix(prefix2) }
            if pool.isEmpty { return nil }
        }

        switch uniqueBoundedLevenshteinHit(
            query: compact,
            candidates: pool,
            maxDistance: maxDistance
        ) {
        case .hit(let item):
            return item
        case .ambiguous, .miss:
            return nil
        }
    }

    private enum LocalFuzzyOutcome {
        case hit(IngredientItem)
        case ambiguous
        case miss
    }

    /// 在候選池中找「距離最小且唯一」的成分。距離相同但指向同一 INCI（別名）視為同一解。
    private func uniqueBoundedLevenshteinHit(
        query: String,
        candidates: [(key: String, item: IngredientItem)],
        maxDistance: Int
    ) -> LocalFuzzyOutcome {
        var bestDistance = maxDistance + 1
        var bestItem: IngredientItem?
        var ambiguous = false

        for (key, item) in candidates {
            guard !item.requiresExactMatchOnly else { continue }
            guard abs(key.count - query.count) <= maxDistance else { continue }
            guard let distance = Self.boundedLevenshteinDistance(query, key, maxDistance: maxDistance) else {
                continue
            }
            if distance < bestDistance {
                bestDistance = distance
                bestItem = item
                ambiguous = false
            } else if distance == bestDistance, bestItem?.englishName != item.englishName {
                ambiguous = true
            }
        }

        if ambiguous { return .ambiguous }
        if let bestItem { return .hit(bestItem) }
        return .miss
    }

    /// `/` 別名拆解：各段 trim 後查庫；較長候選優先。
    func resolve(_ rawName: String, logMiss: Bool = false) -> IngredientItem? {
        ensureLoaded()
        // 去除配方代碼、濃度％、尾端縮寫、頭尾標點，並修正常見的 l／| OCR 混淆。
        var trimmed = IngredientParser.removeBracketCodes(from: rawName)
        trimmed = IngredientParser.replaceCommonOCRCharacters(in: trimmed)
        trimmed = IngredientParser.stripConcentrationAndAliasCodes(trimmed)
        trimmed = IngredientParser.trimBoundaryNoise(trimmed)
        // 註腳星號（cannabis sativa seed oil*）
        trimmed = IngredientParser.stripFootnoteMarkers(trimmed)
        trimmed = IngredientParser.stripConcentrationAndAliasCodes(trimmed)
        trimmed = IngredientParser.trimBoundaryNoise(trimmed)
        trimmed = IngredientMatcher.expandBotanicalAbbreviations(trimmed)
        trimmed = IngredientMatcher.applyINCISynonyms(
            IngredientMatcher.deepNormalize(trimmed)
        )
        guard !trimmed.isEmpty else { return nil }
        guard !IngredientParser.isFootnoteDefinitionToken(rawName) else { return nil }

        // 曲面腰斬增稠劑：明確前綴／片段命中（優先於一般 OCR 表）
        if let polymer = Self.rescueTruncatedThickeners(trimmed) {
            if let hit = lookup(ingredientName: polymer) {
                return hit
            }
            trimmed = polymer
        }

        // OCR 曲面錯字 → 標準 INCI（在查庫前先歸一）
        if let corrected = Self.applyOCRCorrections(trimmed) {
            trimmed = corrected
        }

        // Step 1: 原始未拆分字串（全名 + Aliases + 正規化）
        // 含 `/` 的複合 INCI 必須先整段查詢，禁止在 Parser 切分階段拆開。
        if let direct = lookup(ingredientName: trimmed) {
            return direct
        }

        // Step 2: 整段未命中，才把 `/` 兩側當「別名候選」分別查庫（仍是單一成分）。
        // 優先較長片段，避免共聚物短詞誤命中。
        if trimmed.contains("/") {
            if let slashHit = resolveSlashAliasParts(trimmed) {
                return slashHit
            }
        }

        let candidates = Self.lookupCandidates(from: trimmed)
        for candidate in candidates where candidate != trimmed {
            if let hit = lookup(ingredientName: candidate) {
                return hit
            }
        }

        // 含 `/` 的複合名不做前綴模糊，避免把共聚物誤判成 ETHYLENE 等片段
        if !trimmed.contains("/") {
            let prefixKey = Self.cleanKey(trimmed)
            if prefixKey.count >= 6 {
                if let hit = prefixFallback(prefix: prefixKey) {
                    return hit
                }
                if let hit = reversePrefixFallback(input: prefixKey) {
                    return hit
                }
            }
        }

        // 英文長成分：僅對常用／風險清單做 1～2 字元模糊，避免全庫掃瞄。
        let normalized = Self.normalizedKey(trimmed)
        if normalized.count >= 7, let fuzzy = limitedFuzzyMatch(normalizedKey: normalized) {
            return fuzzy
        }

        if logMiss {
            print("[未命中成分] 原始字串: '\(rawName)' -> 正規化: '\(normalized)'")
        }
        return nil
    }

    /// `/` 別名拆解：各段 trim 後查庫；較長候選優先。
    private func resolveSlashAliasParts(_ text: String) -> IngredientItem? {
        let parts = text
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }

        for part in parts {
            if let hit = lookup(ingredientName: part) {
                return hit
            }
            for candidate in Self.lookupCandidates(from: part) where candidate != part {
                if let hit = lookup(ingredientName: candidate) {
                    return hit
                }
            }
        }
        return nil
    }

    /// 瓶身邊緣腰斬的增稠高分子：前綴／殘片段直接對齊標準 INCI。
    static func rescueTruncatedThickeners(_ text: String) -> String? {
        let spaced = cleanKey(text)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let compact = normalizedKey(text)

        if spaced.hasPrefix("AMMONIUM ACRYLO")
            || compact.hasPrefix("AMMONIUMACRYLO") {
            return "AMMONIUM ACRYLOYLDIMETHYLTAURATE/VP COPOLYMER"
        }

        if spaced.contains("UNLIC ATE CROSSPO")
            || compact.contains("UNLICATECROSSPO")
            || spaced.contains("UNLICATE CROSSPO") {
            return "ACRYLATES/C10-30 ALKYL ACRYLATE CROSSPOLYMER"
        }

        return nil
    }

    /// 瓶身曲面 OCR 常見錯字 → 標準 INCI。
    static func applyOCRCorrections(_ text: String) -> String? {
        let upper = cleanKey(text)
        let compact = normalizedKey(text)

        // 精確／包含別名表（長詞優先）
        let rules: [(needles: [String], canonical: String)] = [
            (
                ["PYRUS MALISI", "PYRUSMALISI", "PYRUS MALUS APPLE", "PYRUS MALUS"],
                "PYRUS MALUS (APPLE) FRUIT EXTRACT"
            ),
            (
                ["HEXAPEPTIDE-SAMIDE", "HEXAPEPTIDESAMIDE", "ACETYL SH-HEXAPEPTIDE", "ACETYL-SH-HEXAPEPTIDE"],
                "ACETYL SH-HEXAPEPTIDE-5 AMIDE"
            ),
            (
                ["LE CANOCOBALAMIN", "LECANOCOBALAMIN", "CANOCOBALAMIN"],
                "CYANOCOBALAMIN"
            ),
            (
                ["A XPROPYL TRIMONI", "AXPROPYLTRIMONI", "HYDROXYPROPYLTRIMONIUM", "XPROPYL TRIMONI"],
                "HYDROXYPROPYLTRIMONIUM HYALURONATE"
            ),
            (
                ["PHENONET", "PHENOXYETHANO"],
                "PHENOXYETHANOL"
            ),
            (
                ["ACRYLATESIC10-30", "ACRYLATESIC1030", "ACRYLATES/C10-30", "ACRYLATES C10-30",
                 "UNLIC ATE CROSSPOLYMER", "UNLIC ATE CROSSPO", "UNLICATE CROSSPOLYMER",
                 "ALKYL ACRYLATE CROSSPOLYMER", "ACRYLATE CROSSPOLYMER"],
                "ACRYLATES/C10-30 ALKYL ACRYLATE CROSSPOLYMER"
            ),
            (
                ["GIGARTINA STELLATA", "GIGARTINA STELLATA EXTRACT", "GIGARTINA STELL"],
                "GIGARTINA STELLATA EXTRACT"
            ),
            (
                ["AMMONIUM ACRYLOYLDIMETHYLTAURATE/VP", "AMMONIUM ACRYLOYLDIMETHYLTAURATE",
                 "AMMONIUM ACRYLO"],
                "AMMONIUM ACRYLOYLDIMETHYLTAURATE/VP COPOLYMER"
            ),
            (
                ["FILENE GLYCOL", "FILENEGLYCOL"],
                "BUTYLENE GLYCOL"
            ),
            (
                ["AMENE GLYCOL", "AMENEGLYCOL"],
                "PENTYLENE GLYCOL"
            ),
            (
                ["METHYLPROPANELD", "METHY|PROPANELD"],
                "METHYLPROPANEDIOL"
            )
        ]

        for rule in rules {
            for needle in rule.needles {
                let needleKey = cleanKey(needle)
                let needleNorm = normalizedKey(needle)
                let forwardHit = upper == needleKey
                    || upper.contains(needleKey)
                    || compact.contains(needleNorm)
                    || (needleNorm.count >= 8 && compact.hasPrefix(needleNorm.prefix(8)))
                // 殘字短於別名時：允許別名包含輸入（需夠長，避免 ATE 誤傷）
                let reverseHit = (upper.count >= 12 && needleKey.contains(upper))
                    || (compact.count >= 12 && needleNorm.contains(compact))
                    || (compact.count >= 10 && needleNorm.hasPrefix(compact))
                if forwardHit || reverseHit {
                    return rule.canonical
                }
            }
        }

        // 過短殘字：僅在明確含 hexapeptide / acetyl 片段時對應胜肽
        if upper.hasPrefix("ACETY"), compact.contains("HEXAPEPTIDE") || upper.contains("SAMIDE") {
            return "ACETYL SH-HEXAPEPTIDE-5 AMIDE"
        }

        return nil
    }

    /// 正規化字串 Levenshtein 模糊匹配：只掃相近長度分桶，相似度須 ≥ 85%。
    private func fuzzyNormalizedFallback(normalized: String) -> IngredientItem? {
        let maxDistance = max(1, Int((Double(normalized.count) * 0.15).rounded(.down)))
        lock.lock()
        var candidates: [(key: String, item: IngredientItem)] = []
        for length in (normalized.count - maxDistance)...(normalized.count + maxDistance) where length > 0 {
            if let bucket = normalizedByLength[length] {
                candidates.append(contentsOf: bucket)
            }
        }
        lock.unlock()

        var bestItem: IngredientItem?
        var bestSimilarity = 0.0
        var ambiguous = false

        for (key, item) in candidates {
            guard key.unicodeScalars.allSatisfy({ $0.value < 128 }) else { continue }
            let longestLength = max(key.count, normalized.count)
            guard longestLength > 0 else { continue }
            let maximumAllowedDistance = Int((Double(longestLength) * 0.15).rounded(.down))
            guard abs(key.count - normalized.count) <= maximumAllowedDistance else { continue }

            let distance = Self.levenshteinDistance(normalized, key)
            guard distance > 0 else { continue }
            let similarity = 1 - (Double(distance) / Double(longestLength))
            guard similarity >= 0.85 else { continue }

            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestItem = item
                ambiguous = false
            } else if abs(similarity - bestSimilarity) < 0.0001, let bestItem,
                      bestItem.englishName != item.englishName {
                ambiguous = true
            }
        }

        return ambiguous ? nil : bestItem
    }

    /// 經典 Levenshtein（僅用於短查詢 vs 正規化 key）。
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }

        var previous = Array(0...n)
        var current = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            current[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[n]
    }

    /// 帶上限的 Levenshtein：某一列的最小值已超過門檻即放棄，避免白算。
    static func boundedLevenshteinDistance(_ a: String, _ b: String, maxDistance: Int) -> Int? {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if abs(m - n) > maxDistance { return nil }
        if m == 0 { return n }
        if n == 0 { return m }

        var previous = Array(0...n)
        var current = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            current[0] = i
            var rowMin = current[0]
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if current[j] < rowMin { rowMin = current[j] }
            }
            if rowMin > maxDistance { return nil }
            swap(&previous, &current)
        }

        let result = previous[n]
        return result <= maxDistance ? result : nil
    }

    /// 正向前綴：只掃同前綴分桶，不遍歷全庫。
    private func prefixFallback(prefix: String) -> IngredientItem? {
        guard prefix.count >= 5 else { return nil }
        let bucketKey = Self.prefixBucketKey(for: prefix)
        lock.lock()
        let bucket = prefixBuckets[bucketKey] ?? []
        lock.unlock()

        var matched: IngredientItem?
        for (key, item) in bucket {
            guard !item.requiresExactMatchOnly else { continue }
            guard key.hasPrefix(prefix), key.count > prefix.count else { continue }
            if matched == nil {
                matched = item
            } else if matched!.englishName != item.englishName {
                return nil
            }
        }
        return matched
    }

    /// 反向前綴：沿空白逐段縮短，以 O(1) 字典查找取代全庫掃描。
    private func reversePrefixFallback(input: String) -> IngredientItem? {
        let words = input
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard words.count >= 2 else { return nil }

        var matched: IngredientItem?
        for end in stride(from: words.count - 1, through: 1, by: -1) {
            let candidate = words[0..<end].joined(separator: " ")
            guard candidate.count >= 6 else { continue }
            guard let hit = lookup(ingredientName: candidate) else { continue }
            if matched == nil {
                matched = hit
            } else if matched!.englishName != hit.englishName {
                return nil
            }
        }
        return matched
    }

    /// 批次查詢（背景執行緒安全）；走 resolve 以支援括號／雜字清理。未命中會印 Console log。
    func lookupMany(_ names: [String]) -> [String: IngredientItem] {
        ensureLoaded()
        var result: [String: IngredientItem] = [:]
        for name in names {
            if let item = resolve(name, logMiss: true) {
                result[name] = item
            }
        }
        return result
    }

    /// 由原始 OCR 字串抽出可能的比對候選（括號內外、尾端實質詞彙）。
    static func lookupCandidates(from raw: String) -> [String] {
        var candidates: [String] = []
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        candidates.append(trimmed)
        candidates.append(contentsOf: IngredientParser.unpackAliasCandidates(trimmed))

        // 植物 INCI：BUTYROSPERMUM PARKII (SHEA) BUTTER → SHEA BUTTER / BUTYROSPERMUM PARKII BUTTER
        if let botanicalRegex = try? NSRegularExpression(
            pattern: #"^(.+?)\s*\(([^)]+)\)\s*(.+)$"#
        ) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = botanicalRegex.firstMatch(in: trimmed, range: range),
               match.numberOfRanges >= 4,
               let beforeRange = Range(match.range(at: 1), in: trimmed),
               let commonRange = Range(match.range(at: 2), in: trimmed),
               let afterRange = Range(match.range(at: 3), in: trimmed) {
                let before = trimmed[beforeRange].trimmingCharacters(in: .whitespacesAndNewlines)
                let common = trimmed[commonRange].trimmingCharacters(in: .whitespacesAndNewlines)
                let after = trimmed[afterRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !common.isEmpty, !after.isEmpty {
                    candidates.append("\(common) \(after)")
                }
                if !before.isEmpty, !after.isEmpty {
                    candidates.append("\(before) \(after)")
                }
                if !common.isEmpty {
                    candidates.append(common)
                }
            }
        }

        // WATER (AQUA) / WATER（AQUA）
        let parenPatterns = [
            #"^(.*?)\(([^)]+)\)\s*$"#,
            #"^(.*?)（([^）]+)）\s*$"#
        ]
        for pattern in parenPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges >= 3,
                  let outerRange = Range(match.range(at: 1), in: trimmed),
                  let innerRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }
            let outer = trimmed[outerRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let inner = trimmed[innerRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty { candidates.append(inner) }
            if !outer.isEmpty { candidates.append(outer) }

            // 「EF A WATER」→ 嘗試尾端詞彙 WATER
            let outerWords = outer.split(whereSeparator: \.isWhitespace).map(String.init)
            if let last = outerWords.last, last.count >= 3 {
                candidates.append(last)
            }
            // 也嘗試去掉明顯雜訊前綴後的整段
            if outerWords.count >= 2 {
                candidates.append(outerWords.suffix(2).joined(separator: " "))
            }
        }

        // 去掉首尾常見包裝符號
        let stripped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]【】『』「」*#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped != trimmed, !stripped.isEmpty {
            candidates.append(stripped)
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = cleanKey(candidate)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    var ingredientCount: Int {
        ensureLoaded()
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    /// 全量成分（已排序副本），供字典瀏覽與搜尋。
    func allIngredients() -> [IngredientItem] {
        ensureLoaded()
        lock.lock()
        let snapshot = items
        lock.unlock()
        return snapshot.sorted {
            $0.englishName.localizedCaseInsensitiveCompare($1.englishName) == .orderedAscending
        }
    }

    /// 手動新增／編輯用的即時建議：比對英文名、中文名與別名（不區分大小寫）。
    /// 完全相符優先於前綴，前綴優先於包含；同層較短名稱（本尊）排在較長衍生物前面。
    /// 查詢會先套 OCR 字形修正與 `inciSynonymMap`（如 glycern → glycerin），與掃標籤救援一致。
    func suggest(matching query: String, limit: Int = 8) -> [IngredientItem] {
        ensureLoaded()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let needleVariants = Self.suggestNeedleVariants(from: trimmed)
        lock.lock()
        let snapshot = items
        lock.unlock()

        struct Scored {
            let item: IngredientItem
            let rank: Int
        }

        var scored: [Scored] = []
        scored.reserveCapacity(min(snapshot.count, 64))

        for item in snapshot {
            var bestRank: Int?

            func consider(_ text: String, exactRank: Int, prefixRank: Int, containsRank: Int) {
                let key = text.lowercased(with: Locale(identifier: "en_US_POSIX"))
                guard !key.isEmpty else { return }
                for needle in needleVariants {
                    if key == needle {
                        bestRank = min(bestRank ?? exactRank, exactRank)
                    } else if key.hasPrefix(needle) {
                        bestRank = min(bestRank ?? prefixRank, prefixRank)
                    } else if needle.count >= 2, key.contains(needle) {
                        bestRank = min(bestRank ?? containsRank, containsRank)
                    }
                }
            }

            consider(item.englishName, exactRank: 0, prefixRank: 10, containsRank: 20)
            consider(item.chineseName, exactRank: 1, prefixRank: 11, containsRank: 21)
            consider(item.displayChineseName, exactRank: 1, prefixRank: 11, containsRank: 21)
            for alias in item.aliases ?? [] {
                consider(alias, exactRank: 2, prefixRank: 12, containsRank: 22)
            }

            // 去空白／標點後再比對一次，讓「菸鹼酰胺」與括號註記較容易命中。
            let compactNeedles = needleVariants
                .map { Self.normalizedKey($0) }
                .filter { !$0.isEmpty }
            if !compactNeedles.isEmpty {
                func considerCompact(_ text: String, exactRank: Int, prefixRank: Int, containsRank: Int) {
                    let key = Self.normalizedKey(text)
                    guard !key.isEmpty else { return }
                    for compactNeedle in compactNeedles {
                        if key == compactNeedle {
                            bestRank = min(bestRank ?? exactRank, exactRank)
                        } else if key.hasPrefix(compactNeedle) {
                            bestRank = min(bestRank ?? prefixRank, prefixRank)
                        } else if compactNeedle.count >= 2, key.contains(compactNeedle) {
                            bestRank = min(bestRank ?? containsRank, containsRank)
                        }
                    }
                }
                considerCompact(item.englishName, exactRank: 3, prefixRank: 13, containsRank: 23)
                considerCompact(item.chineseName, exactRank: 4, prefixRank: 14, containsRank: 24)
                considerCompact(item.displayChineseName, exactRank: 4, prefixRank: 14, containsRank: 24)
                for alias in item.aliases ?? [] {
                    considerCompact(alias, exactRank: 5, prefixRank: 15, containsRank: 25)
                }
            }

            if let bestRank {
                scored.append(Scored(item: item, rank: bestRank))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let leftLen = lhs.item.englishName.count
            let rightLen = rhs.item.englishName.count
            if leftLen != rightLen { return leftLen < rightLen }
            return lhs.item.englishName.localizedCaseInsensitiveCompare(rhs.item.englishName) == .orderedAscending
        }
        return Array(scored.prefix(limit).map(\.item))
    }

    /// 原始查詢＋字形修正＋ INCI 同義詞展開（去重、保序）。
    private static func suggestNeedleVariants(from trimmed: String) -> [String] {
        let locale = Locale(identifier: "en_US_POSIX")
        var variants: [String] = []
        func append(_ raw: String) {
            let value = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(with: locale)
            guard !value.isEmpty, !variants.contains(value) else { return }
            variants.append(value)
        }

        append(trimmed)
        let glyphFixed = IngredientParser.replaceCommonOCRCharacters(in: trimmed)
        append(glyphFixed)
        append(IngredientMatcher.applyINCISynonyms(glyphFixed))
        append(IngredientMatcher.applyINCISynonyms(trimmed))
        return variants
    }
}
