import Foundation

/// 第二階段：確定性解析器（Deterministic Resolver）。
///
/// 職責邊界：接收 `IngredientTokenizer` 產出的**有序** Token，逐一對應資料庫。
/// 本階段不做任何切分決策，也不重排；輸出的 index 永遠等同瓶身物理順序。
///
/// 單一 Token 的解析由嚴格到寬鬆：
///   Step 1 精準查表（O(1)）→ Step 2 括號拆解 → Step 3 植萃後綴展開
///   → Step 4 鄰近拼字模糊救援（局部 Levenshtein，絕不全庫掃描）。
/// 四步皆未命中時，Token 以 `.unknown` 保留原字串，**絕不從陣列中刪除**。
enum IngredientResolver {

    // MARK: - 結果模型

    /// 單一 Token 的解析結論。
    enum Resolution: Sendable, Hashable {
        /// 命中資料庫。
        case matched(IngredientItem)
        /// 疑似成分但字典查無此筆；原字串必須原位保留供使用者手動修正。
        case unknown
        /// 地址／行銷語／註腳等非成分文字；保留在結果中但標記為雜訊，由呈現層決定是否顯示。
        case noise
    }

    /// 解析後的單筆結果，`index` 即最終顯示順位。
    struct Entry: Sendable, Hashable, Identifiable {
        /// 最終輸出順位（0-based），嚴格等同瓶身由前到後的物理順序。
        let index: Int
        /// 來源 Token 在分詞階段的物理順位。
        let tokenIndex: Int
        /// 分詞後未經正規化的原始字串。
        let rawToken: String
        let resolution: Resolution

        var id: Int { index }

        var databaseItem: IngredientItem? {
            if case .matched(let item) = resolution { return item }
            return nil
        }

        var isUnknown: Bool {
            if case .unknown = resolution { return true }
            return false
        }

        var isNoise: Bool {
            if case .noise = resolution { return true }
            return false
        }

        /// 命中則顯示標準 INCI 名稱，未命中則保留原字串。
        var displayName: String {
            databaseItem?.englishName ?? rawToken
        }
    }

    // MARK: - 管線入口

    /// 完整兩階段管線：OCR 全文 → 有序解析結果（含未命中項）。
    static func resolve(_ rawText: String) -> [Entry] {
        IngredientDatabaseManager.shared.ensureLoaded()

        let tokens = IngredientTokenizer.tokenize(rawText)
        let start = firstHighConfidenceStart(in: tokens)

        var entries: [Entry] = []
        for token in tokens {
            if token.index < start {
                entries.append(prefixEntry(for: token, at: entries.count))
                continue
            }

            for resolution in resolutions(for: token.text, raw: token.raw) {
                entries.append(
                    Entry(
                        index: entries.count,
                        tokenIndex: token.index,
                        rawToken: resolution.raw,
                        resolution: resolution.result
                    )
                )
            }
        }
        entries = stitchAdjacentUnknowns(entries)
        entries = demoteNonINCIUnknowns(entries)
        entries = demoteOCRFragmentsOfNeighbors(entries)
        entries = demoteTrailingCompanyAddressRun(entries)
        return reindexed(entries)
    }

    /// 背景執行版本；呼叫端取得結果後再回主線程更新 UI。
    static func resolveAsync(_ rawText: String) async -> [Entry] {
        await Task.detached(priority: .userInitiated) {
            resolve(rawText)
        }.value
    }

    // MARK: - 起點偵測（資料庫命中驅動）

    /// 密度視窗：候選 Token 本身加上其後 3 個。
    private static let startDensityWindow = 4

    /// 視窗內至少要有這麼多個 Token 能對應到成分，才確認這裡是成分表起點。
    /// 這道門檻專門用來擋行銷文案順口提到的單一成分（「保濕成分、Glycerin、植物萃取…」）。
    private static let startDensityRequirement = 2

    /// 高信度命中的最短字母數，排除單一字母與無意義短詞。
    private static let minimumConfidentLetters = 3

    /// 資料庫命中驅動的動態起點判定（Data-Driven First-Hit）。
    ///
    /// 不依賴任何標題關鍵字，因此不受排版差異、標題缺失或 OCR 黏字影響：
    /// 由前往後找「第一個精準命中字典、且鄰近確實還有其他成分」的 Token，該位置即成分表起點。
    ///
    /// 兩個判準刻意採用不同嚴格度：
    /// - **候選起點**必須是零容錯的精準命中，模糊救援回來的成分不足以當作起點證據。
    /// - **密度計算**則採計完整解析（含模糊沙盒），因為真實成分表常在中間夾雜 OCR 錯字
    ///   （`Water (Aqua), Methylpropanedi, Manufactured for…, Bitylene Glycol`）。
    ///   若密度只認精準命中，這種瓶身的起點會通不過檢查，反而把開頭的 Water 一起丟掉。
    ///
    /// 找不到符合密度條件的位置時回傳 0（完全不裁），寧可多留也不冒險砍掉真成分。
    /// 起點之前像 INCI 的未收錄項由 `prefixEntry` 保留，不會在這裡刪掉。
    ///
    /// 迴圈契約（不可違反）：
    /// 1. 從頭走到尾，逐一尋找精準命中。
    /// 2. 命中後做密度檢查。
    /// 3. 密度通過 → 立刻回傳該 index。
    /// 4. 密度失敗 → **什麼都不做**，繼續找下一個精準命中。禁止 `break` / `return 0`。
    /// 5. 只有整份陣列都掃完，才 `return 0`。
    static func firstHighConfidenceStart(in tokens: [IngredientTokenizer.Token]) -> Int {
        guard tokens.count > 1 else { return 0 }

        for index in tokens.indices {
            // 1. 尋找精準命中。不是候選就換下一個，絕不可因此結束掃描。
            guard isExactStartCandidate(tokens[index]) else { continue }

            // 2. 密度檢查。
            // 3. 通過 → 這就是成分表起點。
            if checkDensity(in: tokens, from: index) {
                return index
            }

            // 4. 密度不足：這只是行銷文案順口提到的單一成分。
            //    繼續往下找下一個精準命中，禁止在此 return / break。
        }

        // 5. 整份掃完仍找不到夠密集的起點 → 完全不裁。
        return 0
    }

    /// 視窗內（含起點本身）至少 `startDensityRequirement` 個 Token 能對應到成分。
    private static func checkDensity(
        in tokens: [IngredientTokenizer.Token],
        from start: Int
    ) -> Bool {
        let end = min(start + startDensityWindow, tokens.count)
        var hits = 0
        for index in start..<end where isDensityHit(tokens[index]) {
            hits += 1
            if hits >= startDensityRequirement { return true }
        }
        return false
    }

    /// 候選起點：零容錯精準命中，且不是單一字母或無意義短詞。
    private static func isExactStartCandidate(_ token: IngredientTokenizer.Token) -> Bool {
        guard !isNoiseToken(token.text, raw: token.raw) else { return false }
        guard letterCount(token.text) >= minimumConfidentLetters else { return false }
        guard let item = exactResolveToken(token.text) else { return false }
        return letterCount(item.englishName) >= minimumConfidentLetters
    }

    /// 密度採計：完整解析（含模糊沙盒），因為真成分表中間常夾 OCR 錯字。
    private static func isDensityHit(_ token: IngredientTokenizer.Token) -> Bool {
        guard !isNoiseToken(token.text, raw: token.raw) else { return false }
        guard letterCount(token.text) >= minimumConfidentLetters else { return false }
        return resolveToken(token.text) != nil
    }

    /// 標題之後、第一個字典命中之前：只有化學形態的未收錄項才保留。
    /// 品名形態一律丢掉；字典已收錄的孤立命中視為行銷順口提到的成分。
    private static func prefixEntry(for token: IngredientTokenizer.Token, at index: Int) -> Entry {
        let resolution: Resolution
        if shouldKeepUnregisteredPrefix(token) {
            resolution = .unknown
        } else {
            resolution = .noise
        }
        return Entry(
            index: index,
            tokenIndex: token.index,
            rawToken: token.text,
            resolution: resolution
        )
    }

    /// 起點之前只留「化學形態」未收錄項。
    ///
    /// 有標題時，錨點之前已在分詞前裁掉；這裡處理的是錨點之後到第一個字典命中之間。
    /// 沒讀到標題時，同一條化學形態規則仍適用：品名丢掉、聚合物留下。
    private static func shouldKeepUnregisteredPrefix(_ token: IngredientTokenizer.Token) -> Bool {
        if isNoiseToken(token.text, raw: token.raw) { return false }
        if isUsageOrProductTitle(token.text) { return false }
        guard looksLikeIngredientName(token.text) else { return false }
        guard IngredientParser.looksLikeChemicalName(token.text) else { return false }
        // 字典已收錄 → 行銷段順口提到的成分，不是「尚未收錄的第一項」。
        if exactResolveToken(token.text) != nil { return false }
        return true
    }

    /// 用途／用法，或零售品名形態。不以詞數當主條件。
    /// 化學名（含兩詞聚合物）即使短，也不得當品名。
    private static func isUsageOrProductTitle(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if lower.contains("用途") || lower.contains("用法") || lower.contains("使用方法")
            || lower.contains("how to use") || lower.contains("directions") {
            return true
        }
        if IngredientParser.looksLikeChemicalName(token) { return false }
        return IngredientParser.isRetailProductNameToken(token)
    }

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }

    // MARK: - 單一 Token 解析

    /// 單一 Token → 資料庫成分。四步皆未命中時回傳 `nil`（呼叫端負責保留原字串）。
    static func resolveToken(_ rawToken: String) -> IngredientItem? {
        if let exact = exactResolveToken(rawToken) { return exact }

        guard !IngredientParser.isFootnoteDefinitionToken(rawToken) else { return nil }
        let cleaned = normalizeQuery(rawToken)
        guard !cleaned.isEmpty else { return nil }

        // 絕對雜訊（網址、容量、地址、長句文案）不進模糊救援，避免把包裝雜訊「救成」成分。
        if IngredientParser.isAbsoluteNoiseToken(rawToken)
            || IngredientParser.isAbsoluteNoiseToken(cleaned) {
            return nil
        }

        let query = IngredientMatcher.expandBotanicalAbbreviations(cleaned)

        // Step 4a：既有模糊沙盒（常用清單、距離 1）——便宜且精準。
        if let sandbox = sandboxFuzzy(query) { return sandbox }

        // Step 4b：鄰近拼字救援。只掃同首字母、長度 ±3 的分桶，動態門檻 1–3。
        return localLevenshteinRescue(query)
    }

    /// Step 1–3：精準查表 → 括號拆解 → 植萃後綴展開。**完全不含模糊比對**。
    ///
    /// 起點偵測只認這種零容錯的命中，模糊救援回來的成分不足以當作
    /// 「成分清單從這裡開始」的證據。
    static func exactResolveToken(_ rawToken: String) -> IngredientItem? {
        if let hit = exactResolveCore(rawToken) { return hit }
        for stripped in IngredientParser.candidatesByDroppingLeadingOCRJunk(rawToken) where stripped != rawToken {
            if let hit = exactResolveCore(stripped) { return hit }
        }
        return nil
    }

    /// 精準查表本體；不含「去掉 OCR 短前綴」以免遞迴。
    private static func exactResolveCore(_ rawToken: String) -> IngredientItem? {
        IngredientDatabaseManager.shared.ensureLoaded()

        guard !IngredientParser.isFootnoteDefinitionToken(rawToken) else { return nil }

        // `preserved` 保留完整括號內容，`cleaned` 額外剝掉尾端的縮寫代碼。
        // 兩者都要參與括號拆解，才不會遺漏「括號內才是可查名稱」的情況。
        let preserved = preservedQuery(rawToken)
        let cleaned = normalizeQuery(rawToken)
        guard !cleaned.isEmpty else { return nil }

        // Step 1：清理首尾空白與句號後，向扁平字典做 O(1) 精準查表。
        if let hit = exactLookup(cleaned) { return hit }

        // Step 2：括號拆解。先查括號外文字（Water (Aqua/Eau) → water），
        //         再查括號內文字（→ aqua），最後才試斜線別名各段。
        for candidate in bracketCandidates(of: cleaned) {
            if let hit = exactLookup(candidate) { return hit }
        }
        if preserved != cleaned {
            for candidate in bracketCandidates(of: preserved) {
                if let hit = exactLookup(candidate) { return hit }
            }
        }

        // Step 3：植萃後綴展開（ext. → extract、dist. → distillate、fld. ext. → fluid extract）。
        let expanded = IngredientMatcher.expandBotanicalAbbreviations(cleaned)
        if expanded != cleaned {
            if let hit = exactLookup(expanded) { return hit }
            for candidate in bracketCandidates(of: expanded) {
                if let hit = exactLookup(candidate) { return hit }
            }
        }

        // Step 4：瓶身曲面 OCR 對照表（精準別名／前綴，不含編輯距離模糊）。
        if let corrected = IngredientDatabaseManager.applyOCRCorrections(cleaned),
           corrected.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame,
           let hit = exactLookup(corrected) {
            return hit
        }
        if let polymer = IngredientDatabaseManager.rescueTruncatedThickeners(cleaned),
           let hit = exactLookup(polymer) {
            return hit
        }
        return nil
    }

    // MARK: - Token 分類

    private struct TokenResolution {
        let raw: String
        let result: Resolution
    }

    /// 一個 Token 通常對應一筆結果；唯有 OCR 漏標點造成的黏字串會展開成多筆，
    /// 且展開後仍嚴格依單字在原文中的位置排列。
    private static func resolutions(for token: String, raw: String) -> [TokenResolution] {
        if isNoiseToken(token, raw: raw) {
            return [TokenResolution(raw: token, result: .noise)]
        }

        if let hit = resolveToken(token) {
            return [TokenResolution(raw: token, result: .matched(hit))]
        }

        let glued = resolveGluedToken(token)
        if !glued.isEmpty {
            return glued.map { TokenResolution(raw: $0.raw, result: .matched($0.item)) }
        }

        // 硬雜訊以外的未命中先標成 .unknown，讓後續「相鄰接合」有機會把它們拼回完整 INCI。
        // 拼不中、也不像成分名的，會在 `demoteNonINCIUnknowns` 降為 .noise。
        return [TokenResolution(raw: token, result: .unknown)]
    }

    /// 未命中字串必須看起來像 INCI 才保留給使用者修正。
    ///
    /// 以拉丁字母為主、長度與詞數合理；西里爾／條碼數字／過短半截詞／純亂碼一律不是成分名。
    /// 合法的長拉丁學名即使字典尚未收錄，仍回傳 true（為 CosIng 植萃預留）。
    static func looksLikeIngredientName(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if containsCyrillicOrDisallowedScript(trimmed) { return false }
        if looksLikeBarcodeOrLotCode(trimmed) { return false }
        if isIncompleteStandaloneFragment(trimmed) { return false }
        if looksLikeRandomGibberish(trimmed) { return false }

        let letters = letterCount(trimmed)
        guard letters >= 3 else { return false }
        let latin = latinLetterCount(trimmed)
        guard latin >= 3, latin * 2 >= letters else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...8).contains(words.count) else { return false }
        guard trimmed.count <= 80 else { return false }

        return letters * 2 >= trimmed.count
    }

    /// 西里爾字母或與拉丁明顯混雜的非 INCI 文字。
    private static func containsCyrillicOrDisallowedScript(_ token: String) -> Bool {
        token.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x0400...0x04FF).contains(value)
                || (0x0500...0x052F).contains(value)
                || (0x2DE0...0x2DFF).contains(value)
                || (0xA640...0xA69F).contains(value)
        }
    }

    /// 條碼、批號：數字過密，或整段以數字為主。
    private static func looksLikeBarcodeOrLotCode(_ token: String) -> Bool {
        let digits = token.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        guard digits >= 4 else { return false }
        if digits >= 8 { return true }
        return digits * 2 >= token.filter { !$0.isWhitespace }.count
    }

    /// 折行後落單、本身不是完整 INCI 的半截詞。
    /// 若能與相鄰 Token 拼中，接合階段會先把它們吃掉，不會走到這裡。
    private static func isIncompleteStandaloneFragment(_ token: String) -> Bool {
        let key = IngredientMatcher.synonymLookupKey(token)
        return incompleteStandaloneFragments.contains(key)
    }

    private static let incompleteStandaloneFragments: Set<String> = [
        "glycol", "triazone", "acetate", "rosa",
        "leaf", "extract", "extracts", "oil", "acid", "seed", "flower", "fruit",
        "root", "bark", "juice", "gum", "wax", "butter", "powder",
        "ester", "polymer", "copolymer", "crosspolymer",
        "tea", "green", "white", "black", "red"
    ]

    /// 無母音的長輔音串、連續重複字母（條碼被讀成 `SRUETBRRRUVBR`）、或數字開頭的亂碼。
    private static func looksLikeRandomGibberish(_ token: String) -> Bool {
        let words = token.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }

        if hasRepeatedLetterRun(token, minimum: 3) { return true }

        let vowels = CharacterSet(charactersIn: "AEIOUYaeiouy")
        for word in words where word.count >= 5 {
            let hasVowel = word.unicodeScalars.contains { vowels.contains($0) }
            if !hasVowel { return true }
        }

        // 長單詞卻無 INCI 詞根／化學形態：曲面亂碼（MOAETERGHEA）不進灰區。
        if words.count == 1, let word = words.first, word.count >= 10 {
            let letterCount = word.filter(\.isLetter).count
            let vowelCount = word.unicodeScalars.filter { vowels.contains($0) }.count
            if letterCount >= 10,
               !IngredientParser.hasTypicalINCIRoot(token),
               !IngredientParser.looksLikeChemicalName(token),
               vowelCount * 2 <= letterCount {
                return true
            }
        }

        let compact = token.filter { $0.isLetter || $0.isNumber }
        if let first = compact.first, first.isNumber, compact.count >= 6 {
            let letters = compact.filter(\.isLetter).count
            if letters >= 3 { return true }
        }
        return false
    }

    /// INCI 幾乎不會連續三個相同字母；條碼／刮痕 OCR 常出現 `RRR`、`BBB`。
    private static func hasRepeatedLetterRun(_ token: String, minimum: Int) -> Bool {
        var last: Character?
        var run = 0
        for character in token.uppercased() where character.isLetter {
            if character == last {
                run += 1
                if run >= minimum { return true }
            } else {
                last = character
                run = 1
            }
        }
        return false
    }

    private static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }.count
    }

    /// 非成分文字：地址、行銷語、註腳定義、否定宣稱（「不含酒精」）、頁尾資訊、網址與容量標示。
    ///
    /// 注意：這是「這段文字根本不是成分」的判斷，與「字典查無此成分」是兩回事。
    /// 後者一律走 `.unknown` 保留原字串，只有本函式為真時才標記為雜訊。
    ///
    /// - Parameter raw: 分詞後、清理前的原始片段。網址與容量單位的句點在清理階段會消失，
    ///   因此絕對雜訊過濾必須拿原始片段來判斷。
    static func isNoiseToken(_ token: String, raw: String? = nil) -> Bool {
        if IngredientParser.isAddressNoiseToken(token)
            || IngredientParser.isMarketingNoiseToken(token)
            || IngredientParser.isFootnoteDefinitionToken(token)
            || IngredientParser.isNegativeClaimLine(token)
            || IngredientParser.isPureFooterLine(token)
            || IngredientParser.isFooterLedLine(token) {
            return true
        }

        // 原始片段與清理後字串都要過一次：句點被抹掉後 `www.x.com` 會變成 `www x com`，
        // 但清理也可能反過來把單位黏字拆得更好認。
        if let original = raw, original != token, IngredientParser.isAbsoluteNoiseToken(original) {
            return true
        }
        return IngredientParser.isAbsoluteNoiseToken(token)
    }

    // MARK: - 相鄰未命中接合（折行 INCI 的反向黏回）

    /// 密排／折行把一個 INCI 拆成相鄰碎片時，用空白、去連字號或直接黏回再走精準查表。
    ///
    /// 只呼叫 `exactResolveToken`（精準 → 括號 → 植萃縮寫），**不走模糊沙盒**，
    /// 避免短詞 `Leaf` / `Rosa` 被模糊救成另一筆成分。
    /// 兩個都已命中的相鄰項（Water + Glycerin）不黏。
    private static func stitchAdjacentUnknowns(_ entries: [Entry]) -> [Entry] {
        var result: [Entry] = []
        var index = 0
        while index < entries.count {
            if let merged = stitch(from: index, in: entries, span: 3) {
                result.append(merged)
                index += 3
                continue
            }
            if let merged = stitch(from: index, in: entries, span: 2) {
                result.append(merged)
                index += 2
                continue
            }

            result.append(entries[index])
            index += 1
        }
        return result
    }

    private static func stitch(from start: Int, in entries: [Entry], span: Int) -> Entry? {
        let end = start + span
        guard end <= entries.count else { return nil }
        let slice = Array(entries[start..<end])
        guard slice.contains(where: \.isUnknown) else { return nil }
        guard !slice.contains(where: \.isNoise) else { return nil }
        guard !slice.allSatisfy({ $0.databaseItem != nil }) else { return nil }

        let parts = slice.map(\.rawToken)
        for joined in joinCandidates(parts) {
            guard let item = exactResolveToken(joined) else { continue }
            return Entry(
                index: entries[start].index,
                tokenIndex: entries[start].tokenIndex,
                rawToken: joined,
                resolution: .matched(item)
            )
        }
        return nil
    }

    /// 空白、直接黏合、去連字號後再黏；接起來必須能精準命中才採用。
    static func joinCandidates(_ parts: [String]) -> [String] {
        let stripped = parts.map { part in
            part.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-‐−–—"))
        }
        .filter { !$0.isEmpty }
        guard stripped.count >= 2 else { return [] }

        var results: [String] = []
        func appendUnique(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !results.contains(trimmed) else { return }
            results.append(trimmed)
        }
        appendUnique(stripped.joined(separator: " "))
        appendUnique(stripped.joined())
        appendUnique(stripped.joined(separator: "-"))
        return results
    }

    /// 接合後仍未命中、且不像 INCI 的碎片降為 `.noise`（仍留在內部陣列，顯示層會濾掉）。
    /// 灰區只留「真的像沒入庫的成分」：化學名、植萃形態、色料。品名、國名、批號丟掉。
    private static func demoteNonINCIUnknowns(_ entries: [Entry]) -> [Entry] {
        entries.map { entry in
            guard entry.isUnknown else { return entry }
            if isUsageOrProductTitle(entry.rawToken) || !shouldKeepAsUnmatchedUnknown(entry.rawToken) {
                return Entry(
                    index: entry.index,
                    tokenIndex: entry.tokenIndex,
                    rawToken: entry.rawToken,
                    resolution: .noise
                )
            }
            return entry
        }
    }

    /// 未命中項能否進「可能未辨識」。要比「看起來像拉丁字」更嚴，必須像化學名／植萃／色料。
    static func shouldKeepAsUnmatchedUnknown(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeIngredientName(trimmed) else { return false }
        if looksLikeRandomGibberish(trimmed) { return false }
        if IngredientParser.isPackagingMarketingToken(trimmed) { return false }
        if IngredientParser.isRetailProductNameToken(trimmed),
           !IngredientParser.looksLikeChemicalName(trimmed) {
            return false
        }
        return IngredientParser.shouldKeepTrailingUnknown(trimmed)
    }

    /// 已命中項旁邊的 OCR 半截：正規化後若是清單內任一命中英文名的前綴或高重疊子字串，改為雜訊。
    ///
    /// 只比正規化後的精準包含／前綴，不走模糊沙盒。多圖合併後另見 `SequentialOverlapMerger.stripRedundantUnknowns`。
    private static func demoteOCRFragmentsOfNeighbors(_ entries: [Entry]) -> [Entry] {
        let hosts: [String] = entries.compactMap { entry in
            guard let item = entry.databaseItem else { return nil }
            return IngredientDatabaseManager.normalizedKey(item.englishName)
        }
        guard !hosts.isEmpty else { return entries }

        return entries.map { entry in
            guard entry.isUnknown else { return entry }
            let fragment = IngredientDatabaseManager.normalizedKey(entry.rawToken)
            guard isLongEnoughFragment(fragment) else { return entry }

            for host in hosts {
                if isOCRFragment(fragment, of: host) {
                    return Entry(
                        index: entry.index,
                        tokenIndex: entry.tokenIndex,
                        rawToken: entry.rawToken,
                        resolution: .noise
                    )
                }
                if fragment.count > host.count,
                   Double(host.count) / Double(fragment.count) >= 0.72,
                   fragment.hasPrefix(host) || fragment.contains(host) {
                    return Entry(
                        index: entry.index,
                        tokenIndex: entry.tokenIndex,
                        rawToken: entry.rawToken,
                        resolution: .noise
                    )
                }
            }
            return entry
        }
    }

    private static func isLongEnoughFragment(_ compact: String) -> Bool {
        compact.count >= 6 || compact.filter(\.isLetter).count >= 8
    }

    private static func isOCRFragment(_ fragment: String, of host: String) -> Bool {
        guard !fragment.isEmpty, host.count >= fragment.count else { return false }
        guard isLongEnoughFragment(fragment) else { return false }
        if host.hasPrefix(fragment) { return true }
        return host.contains(fragment)
    }

    /// 最後一個字典命中之後的未收錄項：不像化學名／著色劑就當頁尾丢掉。
    ///
    /// 各國標籤在成分表後常接公司名與地址，OCR 不一定讀到 Made in／製造廠。
    /// 未收錄但長得像 INCI（含尚未入庫的植萃、聚合物、CI 色料）仍保留。
    private static func demoteTrailingCompanyAddressRun(_ entries: [Entry]) -> [Entry] {
        guard let lastMatch = entries.lastIndex(where: { $0.databaseItem != nil }) else {
            return entries
        }
        let trailingStart = lastMatch + 1
        guard trailingStart < entries.count else { return entries }

        return entries.enumerated().map { offset, entry in
            guard offset >= trailingStart, entry.databaseItem == nil else { return entry }
            if IngredientParser.shouldKeepTrailingUnknown(entry.rawToken) {
                return entry
            }
            return Entry(
                index: entry.index,
                tokenIndex: entry.tokenIndex,
                rawToken: entry.rawToken,
                resolution: .noise
            )
        }
    }

    private static func reindexed(_ entries: [Entry]) -> [Entry] {
        entries.enumerated().map { offset, entry in
            Entry(
                index: offset,
                tokenIndex: entry.tokenIndex,
                rawToken: entry.rawToken,
                resolution: entry.resolution
            )
        }
    }

    // MARK: - 黏字串救援（OCR 漏標點）

    /// OCR 漏掉逗號時，一個 Token 會黏成 `Water Glycerin Butylene Glycol`。
    /// 此處以「長詞優先」的滑動視窗切開，但輸出**依單字起始位置排序**，
    /// 因此不可能改變成分的先後順位。
    private static func resolveGluedToken(_ token: String) -> [(raw: String, item: IngredientItem)] {
        let words = token.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return [] }

        var consumed = [Bool](repeating: false, count: words.count)
        var hits: [(start: Int, raw: String, item: IngredientItem)] = []

        // 由長到短掃描，確保 `Camellia Sinensis Leaf Extract` 先於 `Leaf` 被吃掉。
        for gramSize in stride(from: min(maxGramSize, words.count), through: 1, by: -1) {
            var index = 0
            while index <= words.count - gramSize {
                let range = index..<(index + gramSize)
                guard !range.contains(where: { consumed[$0] }) else {
                    index += 1
                    continue
                }
                if gramSize == 1, isNonSpecificWord(words[index]) {
                    index += 1
                    continue
                }

                let phrase = words[range].joined(separator: " ")
                if let hit = exactResolveForGram(phrase, gramSize: gramSize) {
                    hits.append((start: index, raw: phrase, item: hit))
                    range.forEach { consumed[$0] = true }
                    index += gramSize
                    continue
                }
                index += 1
            }
        }

        return hits
            .sorted { $0.start < $1.start }
            .map { (raw: $0.raw, item: $0.item) }
    }

    /// 黏字串內部一律走精準路徑（不開放模糊），並禁止單字命中明顯更長的成分。
    private static func exactResolveForGram(_ phrase: String, gramSize: Int) -> IngredientItem? {
        let cleaned = normalizeQuery(phrase)
        guard !cleaned.isEmpty else { return nil }

        var hit = exactLookup(cleaned)
        if hit == nil {
            for candidate in bracketCandidates(of: cleaned) {
                if let found = exactLookup(candidate) {
                    hit = found
                    break
                }
            }
        }
        if hit == nil {
            let expanded = IngredientMatcher.expandBotanicalAbbreviations(cleaned)
            if expanded != cleaned { hit = exactLookup(expanded) }
        }
        guard let hit else { return nil }
        guard gramSize >= 2 else { return isSpecificEnough(hit, for: phrase) ? hit : nil }
        return hit
    }

    /// 防子詞誤判：單字 `Oil` 不得代表 `Helianthus Annuus Seed Oil`。
    private static func isSpecificEnough(_ item: IngredientItem, for phrase: String) -> Bool {
        let phraseKey = IngredientDatabaseManager.normalizedKey(phrase)
        let hitKey = IngredientDatabaseManager.normalizedKey(item.englishName)
        return hitKey.count <= phraseKey.count + 3
    }

    private static let maxGramSize = 8

    /// 連接詞與泛用詞：單獨出現時不具成分辨識力。
    private static let nonSpecificWords: Set<String> = [
        "and", "or", "with", "of", "the", "a", "an", "plus", "including", "and/or",
        "及", "與", "和", "以及",
        "extract", "extracts", "oil", "leaf", "tea", "acid", "seed", "flower", "fruit",
        "root", "bark", "juice", "gum", "wax", "butter", "powder",
        "green", "white", "black", "red", "glycol", "ester", "rosa",
        "polymer", "copolymer", "crosspolymer", "acetate", "triazone"
    ]

    private static func isNonSpecificWord(_ word: String) -> Bool {
        nonSpecificWords.contains(IngredientMatcher.synonymLookupKey(word))
    }

    // MARK: - 查表原語

    /// 完整查詢字串：OCR 近形字修復 → 批號／濃度％移除 → 合法字元清理。括號內容全數保留。
    ///
    /// 清理順序不可調換：`%`、`[`、`]` 在 `sanitize` 眼中都是非法字元會被抹成空白，
    /// 若先 `sanitize`，`Salicylic Acid 2%` 就會變成查不到的 `Salicylic Acid 2`。
    /// 同理，近形字修復必須最先做，否則 `Methy|propanediol` 的 `|` 會先被抹掉而無從還原。
    private static func preservedQuery(_ rawToken: String) -> String {
        var value = IngredientMatcher.applyOCRGlyphFixes(rawToken)
        value = IngredientParser.removeBracketCodes(from: value)
        value = IngredientParser.stripAllConcentrationPercents(from: value)
        value = IngredientMatcher.stripOrganicAsterisks(value)
        value = IngredientParser.stripFootnoteMarkers(value)
        return collapseWhitespace(IngredientTokenizer.sanitize(value))
    }

    /// 在 `preservedQuery` 之上，再剝掉尾端的短縮寫代碼（`(DHHB)`、`(Aqua)`）。
    private static func normalizeQuery(_ rawToken: String) -> String {
        var value = IngredientMatcher.applyOCRGlyphFixes(rawToken)
        value = IngredientParser.removeBracketCodes(from: value)
        value = IngredientParser.stripConcentrationAndAliasCodes(value)
        value = IngredientMatcher.stripOrganicAsterisks(value)
        value = IngredientParser.stripFootnoteMarkers(value)
        return collapseWhitespace(IngredientTokenizer.sanitize(value))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 括號／斜線拆解出的候選字串，順序為：括號外 → 括號內 → 斜線各段。
    private static func bracketCandidates(of text: String) -> [String] {
        IngredientParser.unpackAliasCandidates(text).filter { $0 != text }
    }

    /// 標準化後的 O(1) 精準查表；此函式**不含任何模糊邏輯**。
    private static func exactLookup(_ text: String) -> IngredientItem? {
        let key = IngredientMatcher.deepNormalize(text)
        guard !key.isEmpty else { return nil }
        return IngredientDatabaseManager.shared.lookupFromIndex(key)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: key)
    }

    /// 模糊沙盒的唯一呼叫點；門檻與白名單由 `IngredientDatabaseManager` 統一把關。
    private static func sandboxFuzzy(_ text: String) -> IngredientItem? {
        let normalized = IngredientMatcher.deepNormalize(text)
        let compact = IngredientDatabaseManager.normalizedKey(normalized)
        guard compact.count >= IngredientDatabaseManager.fuzzySandboxMinimumLength else {
            return nil
        }
        return IngredientDatabaseManager.shared.sandboxFuzzyMatch(normalizedKey: compact)
    }

    /// 鄰近拼字救援：同首字母、長度 ±3 的局部 Levenshtein。
    /// 命中即回傳標準 INCI 成分（中文名、風險評級、功效標籤一併帶上）。
    private static func localLevenshteinRescue(_ text: String) -> IngredientItem? {
        let normalized = IngredientMatcher.deepNormalize(text)
        let compact = IngredientDatabaseManager.normalizedKey(normalized)
        guard compact.count >= IngredientDatabaseManager.localFuzzyMinimumLength else {
            return nil
        }
        return IngredientDatabaseManager.shared.localLevenshteinMatch(normalizedKey: compact)
    }
}
