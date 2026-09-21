import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 成分比對門面（Facade）＋共用的字串正規化工具。
///
/// 真正的解析工作已拆成兩階段編譯器架構，本型別只負責轉接與提供正規化原語：
///   1. `IngredientTokenizer`：依物理順序切分 Token，括號內不切。
///   2. `IngredientResolver`：逐一解析 Token，精準查表 → 括號拆解 → 後綴展開 → 模糊沙盒。
///
/// 另外保留風險提醒比對（`checkAlerts`）與多語系別名表（中 / 英 / 日 / 韓）。
/// 資料庫比對一律走 `IngredientDatabaseManager` 的 O(1) 扁平索引，禁止線性掃庫。
enum IngredientMatcher {
    /// 啟動或掃描前預熱字典（JSON 只解一次，常駐記憶體；可在背景執行緒呼叫）。
    static func warmIngredientCache() {
        IngredientDatabaseManager.shared.ensureLoaded()
    }

    static let aliasTable: [String: [String]] = [
        "denatured-alcohol": [
            // 僅揮發性酒精／變性酒精；不含脂肪醇（Cetearyl Alcohol 等）
            "ALCOHOL",
            "ALCOHOL DENAT.",
            "ALCOHOL DENAT",
            "ETHANOL",
            "SD ALCOHOL",
            "ISOPROPYL ALCOHOL",
            "denatured alcohol",
            // 中文
            "變性酒精", "乙醇",
            // 日文
            "エタノール", "変性アルコール",
            // 韓文
            "에탄올", "변성알코올"
        ],
        "artificial-fragrance": [
            // English
            "fragrance", "parfum", "aroma",
            // 中文
            "香精", "香料", "人工香精",
            // 日文
            "香料",
            // 韓文
            "향료"
        ],
        "paraben": [
            // English
            "paraben", "methylparaben", "propylparaben", "phenoxyethanol",
            "butylparaben", "ethylparaben",
            // 中文
            "對羥基苯甲酸酯", "苯氧乙醇", "防腐劑",
            // 日文
            "パラベン", "メチルパラベン", "プロピルパラベン", "フェノキシエタノール",
            // 韓文
            "파라벤", "메틸파라벤", "프로필파라벤", "페녹시에탄올"
        ],
        "acids": [
            // English
            "salicylic acid", "glycolic acid", "aha", "bha",
            // 中文
            "水楊酸", "果酸",
            // 日文
            "サリチル酸", "グリコール酸",
            // 韓文
            "살리실릭애씨드", "글라이콜릭애씨드", "아하", "바하"
        ],
        "mineral-oil": [
            "mineral oil", "paraffinum liquidum", "petrolatum",
            "礦物油", "凡士林", "石蠟",
            "ミネラルオイル", "パラフィン", "石油",
            "미네랄오일", "파라핀", "페트롤라텀"
        ],
        "comedogenic": [
            "isopropyl myristate", "myristyl myristate", "coconut oil", "cocos nucifera", "lanolin",
            "肉豆蔻酸異丙酯", "椰子油", "羊毛脂",
            "イソプロピルミリスト酸", "ココナッツオイル", "ラノリン",
            "이소프로필미리스테이트", "코코넛오일", "라놀린"
        ],
        "essential-oils": [
            "essential oil", "tea tree", "lavender", "peppermint", "eucalyptus",
            "精油", "茶樹", "薰衣草",
            "エッセンシャルオイル", "ティーツリー", "ラベンダー",
            "에센셜오일", "티트리", "라벤더"
        ]
    ]

    static func keywords(for optionID: String) -> [String] {
        aliasTable[optionID] ?? []
    }

    // MARK: - CosIng 同義詞／植萃縮寫正規化

    /// 別名 → 標準 INCI（鍵為小寫、壓縮空白後的查找鍵）。
    static let inciSynonymMap: [String: String] = {
        let pairs: [(String, String)] = [
            ("nicotinamide", "niacinamide"),
            ("vitamin b3", "niacinamide"),
            ("vit b3", "niacinamide"),
            ("vit. b3", "niacinamide"),
            ("3-pyridinecarboxamide", "niacinamide"),
            // 常見 OCR 漏字／近形（僅精確別名，不放寬模糊門檻）
            ("niacinamid", "niacinamide"),
            ("niaclnamide", "niacinamide"),
            ("niaclnamid", "niacinamide"),
            ("glycerol", "glycerin"),
            ("glycern", "glycerin"),
            ("glycrin", "glycerin"),
            ("glycerln", "glycerin"),
            ("dimethcone", "dimethicone"),
            ("phenoxyethanl", "phenoxyethanol"),
            ("vitamin e", "tocopherol"),
            ("vit e", "tocopherol"),
            ("vitamin c", "ascorbic acid"),
            ("vit c", "ascorbic acid"),
            ("l-ascorbic acid", "ascorbic acid"),
            ("vitamin b5", "panthenol"),
            ("vit b5", "panthenol"),
            ("d-panthenol", "panthenol"),
            ("d panthenol", "panthenol"),
            ("provitamin b5", "panthenol"),
        ]
        var map: [String: String] = [:]
        map.reserveCapacity(pairs.count)
        for (alias, canonical) in pairs {
            map[synonymLookupKey(alias)] = canonical
        }
        return map
    }()

    /// 植萃印刷縮寫展開：`fld. ext.` / `ext.` / `dist.` → 完整 INCI 後綴。
    static func expandBotanicalAbbreviations(_ text: String) -> String {
        var value = text
        let rules: [(pattern: String, template: String)] = [
            (#"(?i)\bfld\.?\s*ext\.?\b"#, "fluid extract"),
            (#"(?i)\bext\."#, "extract"),
            (#"(?i)\bdist\."#, "distillate"),
            (#"(?i)\bext\b"#, "extract"),
        ]
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = regex.stringByReplacingMatches(
                in: value,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 將已標準化字串經同義詞表對應到標準 INCI；未命中則原樣返回。
    static func applyINCISynonyms(_ text: String) -> String {
        let key = synonymLookupKey(text)
        guard !key.isEmpty, let canonical = inciSynonymMap[key] else {
            return text
        }
        return canonical
    }

    static func synonymLookupKey(_ text: String) -> String {
        text
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .map { scalar -> Character in
                if CharacterSet.alphanumerics.contains(scalar) {
                    return Character(scalar)
                }
                return " "
            }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 保留 CJK / 片假名 / 韓文等 Unicode 字元，僅做小寫化供英文比對；不使用會 stripping 非 ASCII 的正則。
    static func normalizedForMatching(_ text: String) -> String {
        let withoutCodes = IngredientParser.removeBracketCodes(from: text)
        let corrected = IngredientParser.replaceCommonOCRCharacters(in: withoutCodes)
        return corrected.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// 比對 OCR 文字與使用者勾選的風險成分，回傳命中的顯示名稱（含匹配關鍵字）。
    static func matches(in ocrText: String, profile: UserProfile) -> [String] {
        checkAlerts(
            detectedIngredients: [ocrText],
            blockedTags: blockedTags(from: profile),
            customIngredients: profile.customBlockedIngredients
        )
    }

    /// 使用者已啟用的風險成分 option id 清單。
    static func blockedTags(from profile: UserProfile) -> [String] {
        AvoidIngredientOption.all
            .filter { profile.isAvoidEnabled(for: $0) }
            .map(\.id)
    }

    /// 將 OCR 辨識出的文字列與風險標籤比對，回傳命中警示文案。
    /// - Important: 僅以已切分之成分項比對；空清單不警報。不含宣稱字串一律忽略。
    static func checkAlerts(
        detectedIngredients: [String],
        blockedTags: [String],
        customIngredients: [String] = []
    ) -> [String] {
        let ingredients = detectedIngredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !IngredientParser.isNegativeClaimLine($0) }
            .filter { !IngredientParser.isMarketingNoiseToken($0) }
        guard !ingredients.isEmpty else { return [] }

        let ocrText = ingredients.joined(separator: " ")
        let normalized = normalizedForMatching(ocrText)
        guard !normalized.isEmpty else { return [] }

        var results: [String] = []

        if !blockedTags.isEmpty {
            for option in AvoidIngredientOption.all where blockedTags.contains(option.id) {
                if option.id == "denatured-alcohol" {
                    if let matched = firstDenaturedAlcoholMatch(in: ingredients) {
                        results.append("\(option.title)（\(matched)）")
                    }
                } else if option.id == "acids" {
                    if let matched = firstMatchedAcidKeyword(in: ingredients) {
                        results.append("\(option.title)（\(matched)）")
                    }
                } else if let matched = firstMatchedKeyword(in: normalized, keywords: option.keywords) {
                    results.append("\(option.title)（\(matched)）")
                }
            }
        }

        for custom in customIngredients {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let needle = normalizedForMatching(trimmed)
            // 過短英文避免誤傷；中日韓等可較短。
            guard needle.count >= 5 || needle.unicodeScalars.contains(where: { !$0.isASCII }) else { continue }

            let found = ingredients.contains { ingredient in
                let db = IngredientDatabaseManager.shared.lookup(ingredientName: ingredient)
                return CustomRiskIngredientMatcher.matchesAny(
                    name: ingredient,
                    databaseItem: db,
                    customList: [trimmed]
                )
            }
            guard found else { continue }

            let label = "自訂風險（\(trimmed)）"
            if !results.contains(label) {
                results.append(label)
            }
        }

        return results
    }

    /// 依 UserProfile 完整比對（含預設標籤與自訂成分）。
    static func checkAlerts(detectedIngredients: [String], profile: UserProfile) -> [String] {
        checkAlerts(
            detectedIngredients: detectedIngredients,
            blockedTags: blockedTags(from: profile),
            customIngredients: profile.customBlockedIngredients
        )
    }

    #if canImport(UIKit)
    static func recognizeLines(from data: Data) async -> [String] {
        guard let image = UIImage(data: data) else { return [] }
        return await OCRManager.shared.recognizeText(from: image)
    }

    /// 載入影像 → OCR → 比對風險成分，回傳命中清單。
    static func analyzeImageData(_ data: Data, profile: UserProfile?) async -> [String] {
        let lines = await recognizeLines(from: data)
        guard let profile else {
            return checkAlerts(detectedIngredients: lines, blockedTags: [], customIngredients: [])
        }
        return checkAlerts(detectedIngredients: lines, profile: profile)
    }
    #endif

    static func enabledCount(in profile: UserProfile) -> Int {
        AvoidIngredientOption.all.filter { profile.isAvoidEnabled(for: $0) }.count
            + profile.customBlockedIngredients.count
    }

    /// 批次解析使用者貼上的成分名稱（字典主引擎）。
    static func parseBatchInput(_ text: String) -> [String] {
        matchIngredientItems(in: text).map(\.englishName)
    }

    /// 從 OCR 文字列解析成分名稱（先分詞後 O(1) 查表）。
    static func parseIngredients(from lines: [String]) -> [String] {
        matchIngredientItems(in: lines.joined(separator: "\n")).map(\.englishName)
    }

    /// 符號優先、換行備用的雙重分割（先分詞後 O(1) 查表）。
    static func normalizeIngredientList(_ ingredients: [String]) -> [String] {
        matchIngredientItems(in: ingredients.joined(separator: ", ")).map(\.englishName)
    }

    /// 成分清單解析（先分詞後 O(1) 查表）。
    static func parseIngredients(from rawText: String) -> [String] {
        matchIngredientItems(in: rawText).map(\.englishName)
    }

    /// 成分清單解析（相容舊名）。
    static func splitIngredientText(_ text: String) -> [String] {
        matchIngredientItems(in: text).map(\.englishName)
    }

    // MARK: - Tokenize-then-Lookup（CosIng 萬筆級）

    /// 背景執行完整比對，完成後回傳結果（呼叫端再上主線程更新 UI）。
    static func matchIngredientItemsAsync(in rawText: String) async -> [IngredientItem] {
        await Task.detached(priority: .userInitiated) {
            matchIngredientItems(in: rawText)
        }.value
    }

    /// 兩階段管線：`IngredientTokenizer` 切分 → `IngredientResolver` 解析。
    /// 回傳僅含字典命中項，順序完全等同瓶身物理順序；未命中項請改用 `resolveIngredientList`。
    static func matchIngredientItems(in rawText: String) -> [IngredientItem] {
        var results: [IngredientItem] = []
        var seen = Set<String>()

        for entry in IngredientResolver.resolve(rawText) {
            guard let item = entry.databaseItem else { continue }
            let key = IngredientDatabaseManager.normalizedKey(item.englishName)
            guard seen.insert(key).inserted else { continue }
            results.append(item)
        }
        return results
    }

    /// 完整解析結果：含 `.matched` / `.unknown` / `.noise`，且保留每一項的原始順位。
    /// 需要「未命中成分不得丟棄」語意的呼叫端（例如成分清單手動修正）請用此入口。
    static func resolveIngredientList(in rawText: String) -> [IngredientResolver.Entry] {
        IngredientResolver.resolve(rawText)
    }

    /// 第一階段分詞（相容舊名）：括號內不切分，順序即物理順序。
    static func tokenizeCandidateList(_ text: String) -> [String] {
        IngredientTokenizer.tokenizeToStrings(text)
    }

    /// 單一 Token 清理（相容舊名）。
    static func sanitizeListToken(_ raw: String) -> String {
        IngredientTokenizer.sanitize(raw)
    }

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }

    // MARK: - 單一 Token 比對（門面）

    /// 單一 Token → 資料庫成分，實作全數委派給第二階段 `IngredientResolver`。
    /// `allowFuzzy` 保留給舊呼叫端；即使為 `true` 也只會走安心度 ≤ 4 的模糊沙盒。
    static func matchToken(
        _ rawName: String,
        logMiss: Bool = false,
        allowFuzzy: Bool = true
    ) -> IngredientItem? {
        if let hit = IngredientResolver.resolveToken(rawName) {
            return hit
        }
        if logMiss {
            print("[未命中成分] IngredientMatcher: '\(rawName)'")
        }
        return nil
    }

    /// 清除有機／天然標示星號：`oil*`、`flavor**`。
    static func stripOrganicAsterisks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "＊", with: "")
            .replacingOccurrences(of: "†", with: "")
            .replacingOccurrences(of: "‡", with: "")
    }

    /// 第一層：字串深度標準化。
    static func deepNormalize(_ text: String) -> String {
        var value = stripOrganicAsterisks(text)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))

        value = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        value = expandBotanicalAbbreviations(value)

        for dash in ["–", "—", "‐", "‑", "−", "﹣", "－"] {
            value = value.replacingOccurrences(of: dash, with: "-")
        }

        value = value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )

        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return applyINCISynonyms(value)
    }

    /// 相容舊名稱。
    static func strictNormalize(_ text: String) -> String {
        deepNormalize(text)
    }

    /// 第二層：建立斜線／括號別名候選池。
    /// 順序：完整字串 → 斜線各段（長詞優先）→ 植物括號拉丁／俗名候選。
    static func buildCandidatePool(from raw: String) -> [String] {
        let trimmed = stripOrganicAsterisks(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return IngredientParser.unpackAliasCandidates(trimmed).filter { candidate in
            letterCount(candidate) >= 1
        }
    }

    /// 以 `/` 分割括號外的多語別名；維持由左至右順序，不依字長重排。
    static func splitSlashAliases(_ text: String) -> [String] {
        IngredientParser.splitSlashOutsideBrackets(text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    /// 相容舊名稱。
    static func extractMatchCandidates(from raw: String) -> [String] {
        buildCandidatePool(from: raw).map { deepNormalize($0) }
    }

    /// 標準化後 O(1) 精確查庫。
    private static func exactMatch(afterNormalizing raw: String) -> IngredientItem? {
        let normalized = deepNormalize(raw)
        guard !normalized.isEmpty else { return nil }
        if let hit = IngredientDatabaseManager.shared.lookupFromIndex(normalized) {
            return hit
        }
        if let hit = IngredientDatabaseManager.shared.lookup(ingredientName: normalized) {
            return hit
        }
        let synonym = applyINCISynonyms(normalized)
        if synonym != normalized {
            return IngredientDatabaseManager.shared.lookupFromIndex(synonym)
                ?? IngredientDatabaseManager.shared.lookup(ingredientName: synonym)
        }
        return nil
    }

    /// 第三層：常見 OCR 近形字置換（|／夾在字母間的 1→l、0→o）。
    static func applyOCRGlyphFixes(_ text: String) -> String {
        IngredientParser.replaceCommonOCRCharacters(in: text)
    }

    /// 資料庫比對入口（相容舊名）。
    static func resolveIngredient(_ rawName: String, logMiss: Bool = false) -> IngredientItem? {
        matchToken(rawName, logMiss: logMiss)
    }

    /// 斜線別名拆解（任一命中即成功）。
    static func resolveSlashAliases(_ rawName: String) -> IngredientItem? {
        guard rawName.contains("/") else { return nil }
        // 完整字串優先（共聚物），再試各別名段
        if let whole = exactMatch(afterNormalizing: rawName) {
            return whole
        }
        for part in splitSlashAliases(rawName) {
            if let hit = exactMatch(afterNormalizing: part) {
                return hit
            }
        }
        return nil
    }

    static func isIngredientBlocked(_ ingredient: String, blockedTags: [String], customIngredients: [String] = []) -> Bool {
        let trimmed = ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
        // 疑似未切分的整段字串，不當成單一風險命中
        guard trimmed.count <= 80 else { return false }
        return !checkAlerts(
            detectedIngredients: [trimmed],
            blockedTags: blockedTags,
            customIngredients: customIngredients
        ).isEmpty
    }

    /// 單一成分命中哪些「成分提醒」選項標題（供紅色警示標籤）。
    static func matchedAvoidTitles(
        for ingredient: String,
        blockedTags: [String],
        customIngredients: [String] = []
    ) -> [String] {
        let trimmed = ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 80 else { return [] }

        var titles: [String] = []
        for option in AvoidIngredientOption.all where blockedTags.contains(option.id) {
            if isIngredientBlocked(trimmed, blockedTags: [option.id], customIngredients: []) {
                if !titles.contains(option.title) {
                    titles.append(option.title)
                }
            }
        }
        for custom in customIngredients {
            let needle = normalizedForMatching(custom)
            guard !needle.isEmpty else { continue }
            let haystack = normalizedForMatching(trimmed)
            var matched = haystack.contains(needle)
            if !matched, let db = IngredientDatabaseManager.shared.lookup(ingredientName: trimmed) {
                matched = normalizedForMatching(db.englishName).contains(needle)
                    || normalizedForMatching(db.chineseName).contains(needle)
            }
            guard matched else { continue }
            let label = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = label.isEmpty ? "自訂風險" : "自訂（\(label)）"
            if !titles.contains(title) {
                titles.append(title)
            }
        }
        return titles
    }

    /// 長鏈脂肪醇：保濕／乳化用途，不得視為酒精風險。
    private static let fattyAlcoholNames: [String] = [
        "arachidyl alcohol",
        "cetearyl alcohol",
        "behenyl alcohol",
        "cetyl alcohol",
        "stearyl alcohol",
        "myristyl alcohol",
        "lauryl alcohol"
    ]

    /// 僅命中揮發性酒精（Ethanol 類），排除「某某 Alcohol」脂肪醇。
    private static func firstDenaturedAlcoholMatch(in ingredients: [String]) -> String? {
        for raw in ingredients {
            if let hit = denaturedAlcoholMatch(for: raw) {
                return hit
            }
        }
        return nil
    }

    private static func denaturedAlcoholMatch(for raw: String) -> String? {
        let compact = compactAlcoholKey(raw)
        guard !compact.isEmpty else { return nil }

        for fatty in fattyAlcoholNames {
            if compact == fatty || compact.hasPrefix(fatty + " ") {
                return nil
            }
        }

        // 其餘「XXX alcohol」均視為脂肪醇／非乙醇（如 Benzyl Alcohol）
        if compact.hasSuffix(" alcohol"),
           compact != "isopropyl alcohol",
           compact != "sd alcohol",
           compact != "denatured alcohol" {
            return nil
        }

        if compact == "alcohol" { return "ALCOHOL" }
        if compact.hasPrefix("alcohol denat") { return "ALCOHOL DENAT" }
        if compact == "ethanol" { return "ETHANOL" }
        if compact.hasPrefix("sd alcohol") { return "SD ALCOHOL" }
        if compact == "isopropyl alcohol" || compact.hasPrefix("isopropyl alcohol ") {
            return "ISOPROPYL ALCOHOL"
        }
        if compact == "denatured alcohol" { return "ALCOHOL DENAT" }

        if compact == "變性酒精" { return "變性酒精" }
        if compact == "乙醇" { return "乙醇" }
        if compact == "エタノール" { return "エタノール" }
        if compact == "変性アルコール" { return "変性アルコール" }
        if compact == "에탄올" { return "에탄올" }
        if compact == "변성알코올" { return "변성알코올" }

        return nil
    }

    private static func compactAlcoholKey(_ text: String) -> String {
        let lowered = normalizedForMatching(text)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: " ")
        return lowered
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func firstMatchedKeyword(in normalizedText: String, keywords: [String]) -> String? {
        for keyword in keywords {
            let needle = normalizedForMatching(keyword)
            guard !needle.isEmpty else { continue }
            let asciiLetters = needle.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count
            if asciiLetters > 0, needle.count < 5 { continue }
            if normalizedText.contains(needle) {
                return keyword
            }
        }
        return nil
    }

    /// 酸類風險：逐項比對，並排除水楊酸酯類防曬劑（Ethylhexyl Salicylate 等）。
    private static func firstMatchedAcidKeyword(in ingredients: [String]) -> String? {
        let acidKeywords = keywords(for: "acids")
        for raw in ingredients {
            if looksLikeSalicylateSunscreenEster(raw) { continue }

            let normalized = normalizedForMatching(raw)
            if let hit = firstMatchedKeyword(in: normalized, keywords: acidKeywords) {
                return hit
            }

            if let db = IngredientDatabaseManager.shared.lookup(ingredientName: raw)
                ?? IngredientDatabaseManager.shared.resolve(raw, logMiss: false) {
                let names = [db.englishName, db.chineseName] + (db.aliases ?? [])
                if names.contains(where: { looksLikeSalicylateSunscreenEster($0) }) {
                    continue
                }
                let blob = names.map { normalizedForMatching($0) }.joined(separator: " ")
                if let hit = firstMatchedKeyword(in: blob, keywords: acidKeywords) {
                    return hit
                }
            }
        }
        return nil
    }

    private static let salicylateSunscreenEsterKeywords: [String] = [
        "ethylhexyl salicylate", "octisalate", "octyl salicylate",
        "homosalate", "butyloctyl salicylate",
        "水楊酸乙基己酯", "乙基己基水楊酸酯", "水楊酸辛酯",
        "胡莫柳酯", "荷莫柳酯", "水楊酸薄荷酯", "水楊酸高薄荷酯",
        "サリチル酸エチルヘキシル", "オクチサレート", "ホモサレート"
    ]

    private static func looksLikeSalicylateSunscreenEster(_ text: String) -> Bool {
        let haystack = normalizedForMatching(text)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
        guard !haystack.isEmpty else { return false }
        return salicylateSunscreenEsterKeywords.contains { keyword in
            let needle = normalizedForMatching(keyword)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "/", with: "")
            return !needle.isEmpty && haystack.contains(needle)
        }
    }
}

/// 向後相容別名。
enum IngredientAlertMatcher {
    static func matches(in ocrText: String, profile: UserProfile) -> [String] {
        IngredientMatcher.matches(in: ocrText, profile: profile)
    }

    static func enabledCount(in profile: UserProfile) -> Int {
        IngredientMatcher.enabledCount(in: profile)
    }
}
