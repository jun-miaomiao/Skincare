import Foundation

/// OCR 文字清洗與雜訊判斷（兩階段管線的支援層）。
///
/// 職責僅有三項：全文層級清洗、成分表標題錨點裁切、非成分文字（地址／行銷／頁尾）的判斷。
/// **不負責切分，也不負責查表**：
///   - 切分 → `IngredientTokenizer`（第一階段）
///   - 查表 → `IngredientResolver`（第二階段）
///
/// 萃取前會以通用標題錨點裁切文案／品名；**禁止**以特定產品或成分名稱當起點。
enum IngredientParser {

    // MARK: - OCR 行拼接（供 OCRManager）

    /// OCR 行拼接：行末 `-` 與下一行相接；其餘保留換行。
    static func joinOCRLines(_ lines: [String]) -> String {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        var parts: [String] = []
        var index = 0
        while index < cleaned.count {
            var current = cleaned[index]
            while index + 1 < cleaned.count, current.hasSuffix("-") {
                index += 1
                current = String(current.dropLast()) + cleaned[index]
            }
            parts.append(current)
            index += 1
        }
        return parts.joined(separator: "\n")
    }

    /// 跨行斷詞修復：`-\n`、字母間 `- ` 軟換行；其餘換行改空白。
    static func joinBrokenLines(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if let regex = try? NSRegularExpression(pattern: #"-[ \t]*\n[ \t]*"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        if let softWrap = try? NSRegularExpression(pattern: #"(?<=[A-Za-z])-\s+(?=[A-Za-z])"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = softWrap.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        result = result.replacingOccurrences(of: "\n", with: " ")
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Token／字串清洗（供 Matcher／DatabaseManager）

    static func isNegativeClaimLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if lower.contains("formulated without") { return true }
        if lower.contains("free of") { return true }
        if lower.contains("free from") { return true }
        if trimmed.contains("不含") { return true }
        if trimmed.contains("無添加") { return true }
        return false
    }

    static func removeBracketCodes(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\[.*?\]"#,
            with: "",
            options: .regularExpression
        )
    }

    static func stripAllConcentrationPercents(from text: String) -> String {
        var result = text
        for pattern in [
            #"\(\s*\d+(?:\.\d+)?\s*%\s*\)"#,
            #"（\s*\d+(?:\.\d+)?\s*%\s*）"#,
            #"\s+\d+(?:\.\d+)?\s*%"#
        ] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimBoundaryNoise(_ text: String) -> String {
        var boundaryNoise = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
        boundaryNoise.remove(charactersIn: "()（）/-'")
        return text.trimmingCharacters(in: boundaryNoise)
    }

    /// 合法 INCI 字元：字母、數字、空白、連字號、斜線、化學式逗號、單引號、括號。
    static func retainingLegalINCICharacters(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        for (index, ch) in chars.enumerated() {
            if isLegalINCICharacter(ch, chars: chars, index: index) {
                result.append(ch)
            } else if ch.isWhitespace || ch.isNewline {
                result.append(" ")
            } else {
                result.append(" ")
            }
        }
        return result
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func isLegalINCICharacter(_ ch: Character, chars: [Character], index: Int) -> Bool {
        if ch.isLetter || ch.isNumber || ch == "-" || ch == "/" || ch == "'" || ch == "’" {
            return true
        }
        if ch == "(" || ch == ")" || ch == "（" || ch == "）" {
            return true
        }
        if ch == "," || ch == "，" {
            // 化學式編號逗號（`1,2-Hexanediol`）；其餘逗號在分詞階段已被消化。
            return index > 0 && index + 1 < chars.count
                && chars[index - 1].isNumber && chars[index + 1].isNumber
        }
        if ch == "." {
            // 縮寫句點（`Ext.`、`Denat.`、`Dist.`）：緊接在字母後、且後面是空白或字串結尾。
            guard index > 0, chars[index - 1].isLetter else { return false }
            return index + 1 >= chars.count || chars[index + 1].isWhitespace
        }
        if ch.isWhitespace { return true }
        return false
    }

    /// 括號解構：核心前綴、括號內別名、去括號後重組（不丟棄含括號／斜線的原字串）。
    static func unpackAliasCandidates(_ raw: String) -> [String] {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return [] }

        var pool: [String] = [token]

        if let parts = splitFirstBrackets(token) {
            let stripped = [parts.before, parts.after]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !stripped.isEmpty { pool.append(stripped) }
            if !parts.before.isEmpty { pool.append(parts.before) }
            if !parts.after.isEmpty { pool.append(parts.after) }

            let vernacular = [parts.inner, parts.after]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !vernacular.isEmpty { pool.append(vernacular) }

            for alias in splitSlashOutsideBrackets(parts.inner) {
                if !alias.isEmpty { pool.append(alias) }
                let aliasWithAfter = [alias, parts.after]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !aliasWithAfter.isEmpty { pool.append(aliasWithAfter) }
            }
            if !parts.inner.isEmpty { pool.append(parts.inner) }
        }

        for part in splitSlashOutsideBrackets(token) where part != token {
            pool.append(part)
        }

        var seen = Set<String>()
        var ordered: [String] = []
        for item in pool {
            let key = item
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(item)
        }
        return ordered
    }

    static func splitFirstBrackets(_ text: String) -> (before: String, inner: String, after: String)? {
        let chars = Array(text)
        var depth = 0
        var openIndex: Int?
        var closeIndex: Int?
        for (index, ch) in chars.enumerated() {
            if ch == "(" || ch == "（" {
                if depth == 0 { openIndex = index }
                depth += 1
            } else if (ch == ")" || ch == "）"), depth > 0 {
                depth -= 1
                if depth == 0 {
                    closeIndex = index
                    break
                }
            }
        }
        guard let open = openIndex, let close = closeIndex, close > open else { return nil }
        let before = String(chars[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = String(chars[(open + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = close + 1 < chars.count
            ? String(chars[(close + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (before, inner, after)
    }

    /// 僅在括號外切斜線，避免拆壞 `Water (Aqua/Eau)`，同時保留 `ACRYLATES/C10-30 …`。
    static func splitSlashOutsideBrackets(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in text {
            if ch == "(" || ch == "（" {
                depth += 1
                current.append(ch)
            } else if (ch == ")" || ch == "）"), depth > 0 {
                depth -= 1
                current.append(ch)
            } else if depth == 0, ch == "/" {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { parts.append(piece) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { parts.append(last) }
        return parts.count >= 2 ? parts : []
    }

    static func replaceCommonOCRCharacters(in text: String) -> String {
        // 與 IngredientMatcher.applyOCRGlyphFixes 同一套規則（|、字母間 1→l、0→o）。
        var value = text.replacingOccurrences(of: "|", with: "l")
        if let oneAsL = try? NSRegularExpression(pattern: #"(?<=[A-Za-z])1(?=[A-Za-z])"#) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = oneAsL.stringByReplacingMatches(in: value, range: range, withTemplate: "l")
        }
        if let zeroAsO = try? NSRegularExpression(pattern: #"(?<=[A-Za-z])0(?=[A-Za-z])"#) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = zeroAsO.stringByReplacingMatches(in: value, range: range, withTemplate: "o")
        }
        return value
    }

    /// 剝離**尾端**濃度％與短縮寫代碼（`(DHHB)`、`(6.0%)`）；句中的植物括號別名不動。
    ///
    /// 因為只處理字串尾端，`Pyrus Malus (Apple) Fruit Extract` 這類句中別名不受影響。
    /// 而 `Water (Aqua)` 這類尾端括號被剝掉後仍可查表；萬一括號內才是可查的名稱，
    /// `IngredientResolver` 會另外以「未剝離」的原字串再跑一次括號拆解，不會漏掉。
    static func stripConcentrationAndAliasCodes(_ token: String) -> String {
        var text = stripAllConcentrationPercents(from: token)

        if let regex = try? NSRegularExpression(
            pattern: #"\s*[\(（]([A-Za-z][A-Za-z0-9\-]{1,11})[\)）]\s*$"#
        ) {
            while true {
                let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
                guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                      let fullRange = Range(match.range, in: text) else {
                    break
                }
                text = String(text[..<fullRange.lowerBound])
                    + String(text[fullRange.upperBound...])
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isFootnoteDefinitionToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") || trimmed.hasPrefix("＊") else { return false }
        // 僅「* = 說明」或極短註腳定義才丟棄；`*hemp seed oil` 應剝星後繼續比對
        let stripped = stripFootnoteMarkers(trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("=") || stripped.hasPrefix("：") || stripped.hasPrefix(":") {
            return true
        }
        // 純註腳標記、無可比對內容
        return stripped.count < 3
    }

    static func stripFootnoteMarkers(_ token: String) -> String {
        token
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "＊", with: "")
            .replacingOccurrences(of: "†", with: "")
            .replacingOccurrences(of: "‡", with: "")
    }

    // MARK: - 成分區塊擷取（起始錨點 → 結束錨點 → 首項前綴清理）

    /// 從整罐包裝的 OCR 全文中，只切出真正的成分清單段落。
    ///
    /// 三個步驟：
    /// 1. 起始錨點：捨棄「全成分／Ingredients:」**之前**的品名與行銷文案。
    /// 2. 結束錨點：捨棄「注意事項／Distributed by／容量」**之後**的地址、網址與說明。
    /// 3. 首項前綴：抹掉黏在第一個成分上的標題殘字（`全成分WATER` → `WATER`）。
    ///
    /// 三者都是選用的：找不到就保留該側的全部文字，寧可多留也不砍掉真成分。
    ///
    /// - Important: **起始錨點已降級為輔助手段**。不同產品的排版差異太大，單靠標題關鍵字
    ///   永遠打不完地鼠，因此真正決定成分表起點的是
    ///   `IngredientResolver.firstHighConfidenceStart(in:)` 的資料庫命中驅動判定。
    ///   這裡的正規式只在標題確實存在時提供一個精準的提前量，並負責把
    ///   黏在首項上的標題字剝乾淨，讓第一個成分能被精準查表。
    ///   結束錨點則相反，仍是主力防線（硬錨點無條件切斷、軟錨點需區塊邊界）。
    static func cropToIngredientListSection(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let start = bestIngredientListAnchorUpperBound(in: trimmed) ?? trimmed.startIndex
        let end = ingredientListEndLowerBound(in: trimmed, after: start) ?? trimmed.endIndex
        guard start <= end else { return trimmed }
        let body = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return trimmed }

        return stripIngredientHeaderPrefix(body)
    }

    /// 相容舊名。
    static func cropToIngredientListStart(_ text: String) -> String {
        cropToIngredientListSection(text)
    }

    /// 標題錨點正規式：最長中文標題優先，避免「全成分」被拆成「成分」。
    ///
    /// **刻意不限制行首或前置換行**：OCR 常把前一句話與標題黏成
    /// 「…貼妝效果。全成分WATER…」，加了行首限制就整個失效。
    ///
    /// 唯一的邊界限制留給裸「成分」：它必須帶冒號才算標題，
    /// 否則敘述句中的「含有活性成分與保濕因子」會被誤判成起點。
    /// 「全成分／主要成分」語意明確，不需要任何前後文條件。
    private static let ingredientListStartRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)(?:全\s*成\s*[份分](?:\s*表)?|主\s*要\s*成\s*[份分](?:\s*表)?"#
            + #"|成\s*[份分](?:\s*表)?\s*[:：]"#
            + #"|\b(?:ingredient\s+list|ingredients?|inci(?:\s+name)?|composition|contains?)\b)[:：\s]*"#
    )

    /// **硬結束錨點**：語意上百分之百屬於成分表之後的區塊，無論位於何處都直接一刀切斷。
    ///
    /// OCR 經常漏掉句號與換行，產生 `…PHENOXYETHANOL注意事項：避免接觸眼睛` 這種黏字，
    /// 所以這一組刻意不要求行首或句號邊界。
    /// 清單內容經過嚴選：不含任何可能夾在成分清單中間的字眼。
    private static let hardIngredientListEndRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)(?:注意事項|使用注意事項|使用方法|使用說明|用法用量"#
            + #"|用\s*[途法]\s*[:：]|保存方法|保存方式|保存期限|保存條件|有效期限|有效期間|賞味期限"#
            + #"|容\s*量\s*[:：]?\s*\d|淨\s*重\s*[:：]?\s*\d|淨含量\s*[:：]?\s*\d|批\s*號"#
            + #"|\bdistributed\s+(?:by|in)\b|\bmade\s+in\b)"#
    )

    /// **軟結束錨點**：字面上也可能合法地出現在成分清單中間，因此額外要求區塊邊界。
    ///
    /// 關鍵案例：`Water (Aqua), Methylpropanediol, Manufactured for XXX, Butylene Glycol`
    /// 這種夾在清單中間的製造商字樣不得截斷整份清單，該片段改由 Token 層的頁尾判斷處理。
    private static let softIngredientListEndRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)(?:原產地|製造[廠商]|製造日期|製造年月|產地|輸入業者|進口商|代理商|委託商|經銷商"#
            + #"|規\s*格|警\s*語|廠\s*址|地\s*址|電\s*話|服務專線|消費者服務"#
            + #"|\bmanufactured\s+(?:by|for|in)\b|\bmarketed\s+by\b|\bimported\s+by\b"#
            + #"|\bnet\s+(?:wt|weight)\b|\bdirections?\b|\bprecautions?\b|\bwarnings?\b"#
            + #"|\bcautions?\b|\bstorage\b|\bhow\s+to\s+use\b|\bexp(?:iry|iration)?\s*date\b"#
            + #"|\bbatch\s+(?:no|code|number)\b|\ball\s+rights\s+reserved\b"#
            + #"|\bcorporation\b|\bco\.?\s*,?\s*ltd\.?\b|\bpte\.?\s*ltd\.?\b|\bgmbh\b|\bllc\b)"#
    )

    /// 結束錨點之前必須至少留下這麼多字元，否則視為誤判並改試下一個錨點。
    private static let minimumIngredientBodyLength = 12

    /// 找出最早的一個「可信」結束錨點。
    ///
    /// 兩組錨點各自往後掃，取兩者中位置較前的有效命中。
    /// 共同的防呆只有一條：錨點之前留下的內容必須具備成分表特徵（夠長、有字母、帶分隔符）。
    private static func ingredientListEndLowerBound(
        in text: String,
        after start: String.Index
    ) -> String.Index? {
        let searchRange = NSRange(start..<text.endIndex, in: text)
        var earliest: String.Index?

        for (regex, requiresSectionBoundary) in [
            (hardIngredientListEndRegex, false),
            (softIngredientListEndRegex, true)
        ] {
            guard let regex else { continue }
            for match in regex.matches(in: text, options: [], range: searchRange) {
                guard let range = Range(match.range, in: text), range.lowerBound > start else { continue }
                if requiresSectionBoundary, !startsNewSection(in: text, at: range.lowerBound) { continue }
                guard looksLikeIngredientBody(text[start..<range.lowerBound]) else { continue }

                if earliest == nil || range.lowerBound < earliest! {
                    earliest = range.lowerBound
                }
                break
            }
        }
        return earliest
    }

    /// 錨點是否位於行首（前面只有空白），或緊接在句子結尾標點之後。
    private static func startsNewSection(in text: String, at index: String.Index) -> Bool {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let ch = text[previous]
            if ch.isNewline { return true }
            if "。．.；;!！?？」）)".contains(ch) { return true }
            guard ch.isWhitespace else { return false }
            cursor = previous
        }
        return true
    }

    /// 成分表特徵：長度、字母數、以及至少一個清單分隔符。
    /// 沒有分隔符的短句多半是行銷文案，此時寧可不裁，交給 Token 層逐項判斷。
    private static func looksLikeIngredientBody(_ body: Substring) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumIngredientBodyLength else { return false }
        guard trimmed.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8 else {
            return false
        }
        return trimmed.contains { ",，、;；\n".contains($0) }
    }

    /// 抹除黏在首項成分上的標題殘字。
    ///
    /// 實體標籤常常沒有空格，OCR 會產出 `全成分WATER(AQUA/EAU)` 或 `Ingredients:Dimethicone`。
    /// 起始錨點通常已經吃掉標題，這裡是第二道保險：確保第一個真實成分能被獨立切分與精準查表。
    static func stripIngredientHeaderPrefix(_ text: String) -> String {
        guard let regex = ingredientHeaderPrefixRegex else { return text }

        var value = text
        // 「全成分 Ingredients:」這類雙標題需要剝多次；設上限避免病態輸入空轉。
        for _ in 0..<3 {
            let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: nsRange),
                  let range = Range(match.range, in: value),
                  !range.isEmpty else {
                break
            }
            let stripped = String(value[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else { break }
            value = stripped
        }
        return value
    }

    private static let ingredientHeaderPrefixRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*(?:全\s*成\s*[份分]|主\s*要\s*成\s*[份分]|成\s*[份分])(?:\s*表)?\s*[:：、,，\-–—]*\s*"#
            + #"|^\s*(?:ingredient\s+list|ingredients?|inci(?:\s+name)?|composition|contains?)\b\s*[:：、,，\-–—]*\s*"#,
        options: [.caseInsensitive]
    )

    private struct IngredientListAnchor {
        let range: Range<String.Index>
        let hasColon: Bool
        let isFullHeader: Bool
    }

    /// 原文是否含成分表標題錨點（全成分／INGREDIENTS／Contains 等）。
    /// 有標題時，錨點之前的品牌、品名、用途已由 `cropToIngredientListSection` 裁掉。
    static func hasIngredientListTitleAnchor(_ text: String) -> Bool {
        bestIngredientListAnchorUpperBound(in: text) != nil
    }

    private static func bestIngredientListAnchorUpperBound(in text: String) -> String.Index? {
        guard let regex = ingredientListStartRegex else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return nil }

        let anchors: [IngredientListAnchor] = matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let matched = String(text[range])
            let compact = matched
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: " ", with: "")
            let hasColon = matched.contains(":") || matched.contains("：")
            let isFullHeader = compact.contains("全成")
                || compact.contains("ingredient")
                || compact.contains("contain")
            return IngredientListAnchor(range: range, hasColon: hasColon, isFullHeader: isFullHeader)
        }
        guard !anchors.isEmpty else { return nil }

        let colonAnchors = anchors.filter(\.hasColon)
        let fullHeaders = anchors.filter(\.isFullHeader)
        let chosen: IngredientListAnchor
        if let lastColon = colonAnchors.last {
            // 有冒號的標題幾乎必為正式成分表；取最後一個以略過文案中的假標題。
            chosen = lastColon
        } else if let lastFull = fullHeaders.last {
            chosen = lastFull
        } else {
            chosen = anchors[0]
        }
        return chosen.range.upperBound
    }

    /// 成分表全文預處理：標題錨點裁切 → 星號備註清除；保留括號內英文與 INCI 斜線／連字號。
    ///
    /// 這裡**只做全文層級的清洗**，不做任何切分。
    /// 切分屬於 `IngredientTokenizer`，查表屬於 `IngredientResolver`，兩者不得在此混用。
    static func preprocessIngredientListText(_ text: String) -> String {
        var value = cropToIngredientListSection(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        value = IngredientMatcher.expandBotanicalAbbreviations(value)

        // 星號／註腳標記 → 空白（保留後續成分，避免整段被當註解丟棄）
        for mark in ["*", "＊", "†", "‡"] {
            value = value.replacingOccurrences(of: mark, with: " ")
        }

        // 保留括號內英文別名（如 APPLE、AQUA）；切分由 tokenize 依括號深度處理。
        while value.contains("  ") {
            value = value.replacingOccurrences(of: "  ", with: " ")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 絕對雜訊過濾（第三道防線）

    /// 明顯不可能是化妝品成分的 Token。
    ///
    /// 與「字典查無此成分」是完全不同的兩件事：未收錄的合法成分必須保留給使用者查看與修正，
    /// 但網址、容量標示、地址國別與整句中文文案沒有任何保留價值，一律標記 `.noise`。
    ///
    /// 判斷對象應為**分詞前的原始片段**，才看得到 `.com`、`fl. oz.`、`U.S.` 這類含句點的樣式。
    static func isAbsoluteNoiseToken(_ token: String) -> Bool {
        isWebNoiseToken(token)
            || isMeasurementNoiseToken(token)
            || isGeographicNoiseToken(token)
            || isVerboseNonLatinToken(token)
            || isCorporateLegalNameToken(token)
            || isAdminRoadSuffixToken(token)
    }

    /// 網址與電子郵件。
    ///
    /// OCR 很常把網域的點吃掉，`www.paulaschoice.com` 會變成 `PaulasChoice com`，
    /// 因此點是選用的、也允許以空白代替。
    /// 頂級域名後方仍要求不得再接字母，`ALCOHOL DENAT.ORGANIC …` 這種黏字才不會被誤殺。
    static func isWebNoiseToken(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if lower.contains("http") {
            return true
        }
        for pattern in [
            #"(?<![\p{L}])www(?![\p{L}])"#,
            #"(?:www\s*\.?\s*)?[a-z0-9-]+\s*[.\s]\s*(?:com|net|org|gov|edu|tw|uk)(?![\p{L}\p{N}])"#,
            #"[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#
        ] where lower.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// 容量與物理單位標示（`30ml`、`1.7 fl. oz.`、`50 g`）。
    ///
    /// 扣掉「數字＋單位」後若幾乎不剩內容才判定為雜訊，
    /// 因此 `Polysorbate 20`、`PEG-40 Hydrogenated Castor Oil` 這類含數字的 INCI 不會被誤殺。
    static func isMeasurementNoiseToken(_ token: String) -> Bool {
        let residue = token.replacingOccurrences(
            of: measurementPattern,
            with: " ",
            options: .regularExpression
        )
        guard residue != token else { return false }
        return residue.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count <= 3
    }

    private static let measurementPattern =
        #"(?i)\d+(?:[.,]\d+)?\s*(?:fl\.?\s*oz\.?|floz|ml|mls|cc|l|g|gr|mg|kg|oz|lb"#
        + #"|毫升|公升|公克|公斤|克|盎司|液量盎司)(?![\p{L}\p{N}])"#

    /// 純地址、國家聲明與公司據點城市
    /// （`U.S. and Canada`、`(U S. and Canada)`、`London`、`Amersfoort. NL.`、`台北市信義路 5 號`）。
    ///
    /// 判斷方式是「扣除法」：先抹掉所有已知的國家與城市名，
    /// 若剩下的字只有連接詞或國別縮寫，代表這個 Token 除了地名什麼都沒有。
    /// 因此 `China Clay`、`Japan Wax` 這類含地名的合法成分不會被誤殺。
    static func isGeographicNoiseToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // OCR 常把地址整段包在括號裡（`(U S. and Canada)`）；括號一律視為空白。
        var lower = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for bracket in "()（）[]［］{}｛｝" {
            lower = lower.replacingOccurrences(of: String(bracket), with: " ")
        }

        // `lane`／`street` 等地址結構字不得誤殺含該詞的 INCI（`Sample Lane Extract`、`Silane`）。
        if !hasTypicalINCIRoot(trimmed),
           let regex = addressStructureRegex,
           regex.firstMatch(in: lower, options: [], range: NSRange(lower.startIndex..., in: lower)) != nil {
            return true
        }

        guard let placeRegex = placeNameRegex else { return false }
        let residue = placeRegex.stringByReplacingMatches(
            in: lower,
            options: [],
            range: NSRange(lower.startIndex..., in: lower),
            withTemplate: " "
        )
        guard residue != lower else { return false }

        return residue
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == "." })
            .allSatisfy { isGeographicResidue($0) }
    }

    /// 扣掉地名後允許殘留的字：連接詞、國別縮寫，以及門牌／郵遞區號之類的短數字碼
    /// （`4C. Seattle` 的 `4C`）。只有在已命中地名的前提下才會走到這裡。
    private static func isGeographicResidue(_ word: Substring) -> Bool {
        if geographicConnectors.contains(String(word)) { return true }
        return word.count <= 6 && word.contains(where: \.isNumber)
    }

    /// 街道與門牌等地址結構字。一律加字母邊界，避免 `ave` 誤中 `Avena Sativa`、`lane` 誤中 `Silane`。
    private static let addressStructureRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![\p{L}])(?:street|road|avenue|boulevard|suite|floor|drive|lane|parkway)(?![\p{L}])"#
            + #"|(?<![\p{L}])(?:st|rd|ave|blvd|hwy|apt|dept)\.(?![\p{L}])"#
            + #"|p\.?\s?o\.?\s+box"#
            + #"|[0-9]\s*(?:號|樓|巷|弄)"#
            + #"|郵遞區號|郵政信箱"#
    )

    /// 國家／城市名合併為單一正規式：最長優先，確保 `united states` 不會只被吃掉 `states`。
    private static let placeNameRegex: NSRegularExpression? = {
        let literals = (countryRegionNames + companyCityNames)
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        let alternatives = (abbreviatedCountryPatterns + literals).joined(separator: "|")
        return try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])(?:"# + alternatives + #")(?![\p{L}\p{N}])"#
        )
    }()

    /// OCR 會把 `U.S.A.` 的點吃成空白（`U S. and Canada`），故縮寫以樣式而非字面比對。
    /// 前後的字母邊界由 `placeNameRegex` 統一補上，`Mucus` 的 `us` 不會命中。
    private static let abbreviatedCountryPatterns = [
        #"u\s*\.?\s*s\s*\.?\s*a\s*\.?"#,
        #"u\s*\.?\s*s\s*\.?"#,
        #"u\s*\.?\s*k\s*\.?"#,
        #"e\s*\.?\s*u\s*\.?"#
    ]

    private static let countryRegionNames: [String] = [
        "united states of america", "united states", "united kingdom", "great britain",
        "canada", "france", "germany", "italy", "spain", "japan", "korea", "china",
        "taiwan", "netherlands", "holland", "belgium", "switzerland", "ireland", "sweden",
        "denmark", "australia", "singapore", "thailand", "malaysia", "poland", "mexico",
        "brazil", "india",
        "美國", "英國", "法國", "德國", "義大利", "日本", "韓國", "中國", "台灣", "臺灣",
        "加拿大", "澳洲", "瑞士", "荷蘭", "比利時", "西班牙", "泰國", "新加坡", "馬來西亞"
    ]

    /// 跨國保養品公司常見據點。OCR 抓到的 `London`、`Amersfoort. NL.` 都是總部地址殘留，
    /// 不可能是成分名，且與任何 INCI 字根都不衝突。
    private static let companyCityNames: [String] = [
        "london", "amersfoort", "paris", "new york", "seoul", "tokyo", "osaka", "seattle",
        "los angeles", "san francisco", "chicago", "boston", "toronto", "milan", "milano",
        "amsterdam", "rotterdam", "brussels", "madrid", "barcelona", "munich", "berlin",
        "vienna", "zurich", "geneva", "copenhagen", "stockholm", "dublin", "sydney",
        "melbourne", "shanghai", "taipei", "hong kong",
        "倫敦", "巴黎", "紐約", "首爾", "東京", "大阪", "上海", "台北", "臺北", "香港"
    ]

    /// 扣掉地名後允許殘留的字：連接詞與國別縮寫。
    /// 只有在「已經命中至少一個地名」的前提下才會用到，因此收錄縮寫是安全的。
    private static let geographicConnectors: Set<String> = [
        "and", "or", "in", "the", "of", "&", "及", "與", "和", "以及",
        "nl", "ca", "fr", "de", "jp", "kr", "cn", "tw", "hk", "sg", "au", "ie", "ch"
    ]

    /// 整句非拉丁文案：長度超過門檻且過半字母為非拉丁字，視為中文行銷說明。
    static func isVerboseNonLatinToken(_ token: String) -> Bool {
        guard token.count > verboseTokenLengthThreshold else { return false }

        let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 8 else { return false }

        // U+0250 之前涵蓋基本拉丁與拉丁擴充 A/B，其餘視為非拉丁。
        let nonLatin = letters.filter { $0.value > 0x024F }.count
        return nonLatin * 2 > letters.count
    }

    private static let verboseTokenLengthThreshold = 40

    // MARK: - 公司法律後綴與行政道路後綴（形態規則，不含品牌／城市名單）

    /// Token 主體是公司法律後綴，或以其結尾。
    ///
    /// 各國標籤在成分表後常接製造商英文名，OCR 不一定讀到 Made in／製造廠。
    /// 只認法律後綴形態，禁止維護公司名單。
    static func isCorporateLegalNameToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let regex = corporateLegalSuffixRegex else { return false }
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: nsRange) != nil
    }

    private static let corporateLegalSuffixRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)(?:^|\s)(?:corporation|corp\.?|incorporated|inc\.?|llc|gmbh|ltd\.?|limited)\s*$"#
            + #"|(?i)\bco\.?\s*,?\s*ltd\.?\b"#
            + #"|(?i)\bpte\.?\s*ltd\.?\b"#
            + #"|(?i)\bs\.\s*p\.\s*a\.?\b"#
            + #"|(?i)\bs\.\s*a\.?\b"#
    )

    /// 整個 Token 是「拉丁字 + 連字號 + 行政／道路後綴」，後綴必須在結尾。
    ///
    /// 後綴僅限全球標籤常見的行政區／道路形態，加字母邊界，避免 `Silane`、`Crosspolymer` 被誤切。
    static func isAdminRoadSuffixToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard hasTypicalINCIRoot(trimmed) == false else { return false }
        guard let regex = adminRoadSuffixRegex else { return false }
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: nsRange) != nil
    }

    /// 後綴由長到短排列，避免 `GUN` 被拆成 `GU`。
    private static let adminRoadSuffixRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)^[\p{L}]+(?:-[\p{L}]+)*-(?:MACHI|DONG|GUN|CHO|SI|DO|GU|RO|RI|KU)\s*$"#
    )

    /// 典型 INCI 詞根。用於區分「未收錄成分」與「公司名／地址殘句」。
    /// 這是功能詞素，不是特定成分或品牌名單。
    static func hasTypicalINCIRoot(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for root in inciFunctionalRoots {
            let pattern = #"(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: root) + #"(?![\p{L}])"#
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static let inciFunctionalRoots: [String] = [
        "acid", "extract", "extracts", "oil", "oils", "wax", "waxes", "glycol", "glycols",
        "copolymer", "polymer", "crosspolymer", "sodium", "water", "aqua", "eau",
        "glycerin", "glycerol", "alcohol", "alcohols", "butter", "seed", "leaf", "fruit",
        "gum", "ester", "siloxane", "silane", "peptide", "cellulose", "acrylate",
        "phosphate", "sulfate", "sulphate", "chloride", "hydroxide", "acetate",
        "hydrogenated", "dimethicone", "juice", "hydrosol", "filtrate", "flower",
        "root", "bark", "stem", "peel", "kernel", "rhizome"
    ]

    /// 化學名前綴字素。只錨左邊界，才能認 `Polyisobutene` 的 poly-，
    /// 並要求後面至少還有兩個字母，避免 `Laura` 被 `laur` 誤中。
    private static let chemicalPrefixMorphemes: [String] = [
        "hydrogenated", "dimethicone", "poly", "iso", "butyl", "ethyl", "methyl",
        "propyl", "stear", "laur", "cetyl", "glycol", "silox"
    ]

    /// 是否像化學名／INCI（有一項即可）。功能字素，不是特定成分名單。
    static func looksLikeChemicalName(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if looksLikeChemicalMorphology(trimmed) { return true }
        if hasTwoOrMoreLongLatinWords(trimmed) { return true }
        if hasChemicalFunctionalAffix(trimmed) { return true }
        if hasTypicalINCIRoot(trimmed) {
            // 單獨 oil 可能是 INCI；與品類／部位詞組在同一 Token 時不當化學名。
            if isOilOnlyRoot(trimmed), hasRetailProductContext(trimmed) {
                return false
            }
            return true
        }
        return false
    }

    /// 斜線共聚物、PEG-40 這類編號；或單段 ≥16 字母且帶化學詞素的黏字 INCI。
    /// 純長拉丁亂碼（條碼被讀成 `SRUETBRRRUVBR`）不得只因夠長就被當成化學名。
    static func looksLikeChemicalMorphology(_ token: String) -> Bool {
        if token.contains("/") { return true }
        if token.range(of: #"[A-Za-z]{2,}-\d"#, options: .regularExpression) != nil { return true }
        let compact = token.filter(\.isLetter)
        guard compact.count >= 16, token.split(whereSeparator: \.isWhitespace).count == 1 else {
            return false
        }
        return hasChemicalFunctionalAffix(token) || hasTypicalINCIRoot(token)
    }

    /// 兩個以上單詞且每個都是長拉丁詞（≥7 字母），例如 `Hydrogenated Polyisobutene`。
    static func hasTwoOrMoreLongLatinWords(_ token: String) -> Bool {
        let words = latinLetterWords(in: token)
        guard words.count >= 2 else { return false }
        return words.allSatisfy { $0.count >= 7 }
    }

    static func hasChemicalFunctionalAffix(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for stem in chemicalPrefixMorphemes {
            let pattern = #"(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: stem) + #"[\p{L}]{2,}"#
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        for word in latinLetterWords(in: lower) {
            if hasChemicalSuffix(word) { return true }
        }
        return false
    }

    /// `-ene -ane -ol -ate -ide -ine`；`-ol` 較易誤中英文詞，門檻加長。
    private static func hasChemicalSuffix(_ word: String) -> Bool {
        if word.count >= 6 {
            for suffix in ["ene", "ane", "ate", "ide", "ine"] where word.hasSuffix(suffix) {
                return true
            }
        }
        return word.count >= 9 && word.hasSuffix("ol")
    }

    private static func latinLetterWords(in token: String) -> [String] {
        token.split(whereSeparator: { !$0.isLetter }).map { word in
            String(word.unicodeScalars.filter {
                (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value)
            })
        }.filter { !$0.isEmpty }
    }

    private static func isOilOnlyRoot(_ token: String) -> Bool {
        guard hasWholeWord(token, in: ["oil", "oils"]) else { return false }
        let withoutOil = token.replacingOccurrences(
            of: #"(?i)(?<![\p{L}])oils?(?![\p{L}])"#,
            with: " ",
            options: .regularExpression
        )
        return !hasTypicalINCIRoot(withoutOil) && !hasChemicalFunctionalAffix(withoutOil)
    }

    // MARK: - 零售品名形態（禁止品牌名單，只認品類／部位功能詞）

    private static let retailCategoryWords: [String] = [
        "balm", "cream", "lotion", "serum", "mask", "toner", "essence",
        "moisturizer", "sunscreen", "sunblock", "cleanser", "shampoo",
        "lipstick", "gloss", "ampoule", "emulsion", "gel", "milk",
        "mist", "spray", "wash", "soap", "paste", "stick", "drops",
        "booster", "capsule"
    ]

    /// 與 oil 組在同一 Token 才視為品名的部位／行銷詞。`glow` 要吃到 `glowy`。
    private static let retailCompanionPattern =
        #"(?<![\p{L}])(?:lip|face|body|berry|kit|set|spf\d*|glow)"#

    /// 零售品名：含品類詞，或 oil 加上部位／行銷詞。化學名優先，不當品名。
    static func isRetailProductNameToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasRetailCategoryWord(trimmed) { return true }
        if isPackagingMarketingToken(trimmed) { return true }
        return hasRetailOilContext(trimmed)
    }

    /// 包裝行銷／用法殘字（非品牌名單）：Pro-Collagen 品線、Moisturize AM/PM 等。
    static func isPackagingMarketingToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Pro-Collagen 品線殘字優先判定（常夾 multi-peptide 行銷詞）。
        if isCollagenMarketingOnly(trimmed) { return true }

        // 已是完整化學名時不當作行銷殘字。
        if hasTypicalINCIRoot(trimmed) { return false }

        let lower = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let compact = lower
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()

        // Moisturize／Hydrate 用法殘字（含 MSTURILE、DISTURIZEIPM 等 OCR 變形）。
        if compact.range(
            of: #"(?:moisturiz|moisturile|msturile|msturi|hydrat|disturiz)"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if compact.range(
            of: #"(?:moisturiz|hydrat|disturiz).{0,6}(?:am|pm)$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if lower.range(
            of: #"(?<![\p{L}])(?:moisturize|moisturise|hydrate)\s*(?:am|pm)(?![\p{L}])"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    private static func isCollagenMarketingOnly(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let compact = lower
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        guard compact.contains("colla") else { return false }
        // 真 INCI：Hydrolyzed Collagen、Soluble Collagen、Atelocollagen…
        if lower.range(
            of: #"(?<![\p{L}])(?:hydrolyzed|soluble|atelocollagen|collagen\s+amino)(?![\p{L}])"#,
            options: .regularExpression
        ) != nil {
            return false
        }
        // 品線常見：Pro-Collagen、PROCOLLAGEN、OCR 前綴雜訊 + PRO-COLLA…
        return compact.range(of: #"procolla"#, options: .regularExpression) != nil
            || lower.range(of: #"pro[\s\-]*colla"#, options: .regularExpression) != nil
    }

    /// 品名語境（品類詞或 oil 的部位／行銷搭配），供 oil-only 化學名排除使用。
    static func hasRetailProductContext(_ token: String) -> Bool {
        hasRetailCategoryWord(token) || hasRetailCompanion(token)
    }

    private static func hasRetailCategoryWord(_ token: String) -> Bool {
        hasWholeWord(token, in: retailCategoryWords)
    }

    private static func hasRetailOilContext(_ token: String) -> Bool {
        guard hasWholeWord(token, in: ["oil", "oils"]) else { return false }
        return hasRetailCategoryWord(token) || hasRetailCompanion(token)
    }

    private static func hasRetailCompanion(_ token: String) -> Bool {
        token.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .range(of: retailCompanionPattern, options: .regularExpression) != nil
    }

    private static func hasWholeWord(_ token: String, in words: [String]) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for word in words {
            let pattern = #"(?<![\p{L}])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![\p{L}])"#
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// 門牌數字：有數字，但不是 INCI 常見的 C12-15／PEG-40／CI 77891／1,2- 化學編號。
    static func hasAddressHouseNumber(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isNumber) else { return false }
        if hasTypicalINCIRoot(trimmed) { return false }
        let lower = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if lower.range(of: #"(?i)\b(?:ci|fd&c|d&c)\s*\d"#, options: .regularExpression) != nil {
            return false
        }
        if lower.range(of: #"(?i)\b(?:peg|ppg|steareth|ceteareth|laureth)-?\d"#, options: .regularExpression) != nil {
            return false
        }
        if lower.range(of: #"(?i)\bc\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil {
            return false
        }
        if lower.range(of: #"\d,\d-"#, options: .regularExpression) != nil {
            return false
        }
        // 門牌幾乎都以數字開頭（`12`、`4C`）；詞尾編號是 INCI（`Polysorbate 20`）。
        guard let first = trimmed.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) else {
            return false
        }
        return true
    }

    /// 清單末段連續未命中項是否像頁尾公司名／地址（純拉丁、無 INCI 詞根、帶後綴或門牌）。
    static func isLatinCompanyOrAddressResidue(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let latin = trimmed.unicodeScalars.filter {
            (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value)
        }.count
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard latin >= 3, latin == letters else { return false }
        guard !hasTypicalINCIRoot(trimmed) else { return false }
        return isCorporateLegalNameToken(trimmed)
            || isAdminRoadSuffixToken(trimmed)
            || hasAddressHouseNumber(trimmed)
    }

    /// 最後一個字典命中之後，仍值得保留的未收錄項（化學名、植萃、CI 色料）。
    static func shouldKeepTrailingUnknown(_ token: String) -> Bool {
        looksLikeChemicalName(token)
            || looksLikeStandaloneINCIWord(token)
            || hasTypicalINCIRoot(token)
            || looksLikeColorantToken(token)
    }

    /// 像 `ECTOIN` / `Allantoin` 這類單字 INCI：沒詞根也不是品牌詞時，仍保留灰區供修正。
    static func looksLikeStandaloneINCIWord(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.split(whereSeparator: \.isWhitespace).count == 1 else { return false }
        guard !isRetailProductNameToken(trimmed) else { return false }
        guard !isCorporateLegalNameToken(trimmed) else { return false }
        guard !isAdminRoadSuffixToken(trimmed) else { return false }
        guard !hasAddressHouseNumber(trimmed) else { return false }

        let latinWords = latinLetterWords(in: trimmed)
        guard latinWords.count == 1, let word = latinWords.first else { return false }
        guard (5...14).contains(word.count) else { return false }

        let lower = word.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let vowels = lower.filter { "aeiouy".contains($0) }.count
        guard vowels >= 2 else { return false }

        for suffix in ["oin", "one", "ine", "ium", "ose", "ate", "ide", "ene", "ane", "ol", "ain"] {
            if lower.hasSuffix(suffix) {
                return true
            }
        }
        return false
    }

    /// 化妝品著色劑形態：`CI 15850`、`RED 7 LAKE`。不是品牌名單。
    static func looksLikeColorantToken(_ token: String) -> Bool {
        let lower = token.lowercased(with: Locale(identifier: "en_US_POSIX"))
        if lower.range(of: #"(?i)\b(?:ci|fd&c|d&c)\s*\d"#, options: .regularExpression) != nil {
            return true
        }
        return lower.range(of: #"(?i)\blake\b"#, options: .regularExpression) != nil
    }

    /// OCR 常在第一項前面黏上 2～5 個字母的短雜訊（標題殘字）。
    /// 只丟「不像化學名」的短詞，再把剩下的當查表候選；最多丟兩段。
    static func candidatesByDroppingLeadingOCRJunk(_ token: String) -> [String] {
        let words = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard words.count >= 2 else { return [] }

        var results: [String] = []
        var drop = 0
        while drop < 2, drop < words.count - 1, isLeadingOCRJunkWord(words[drop]) {
            drop += 1
            let rest = words.dropFirst(drop).joined(separator: " ")
            if looksLikeChemicalName(rest) || hasTypicalINCIRoot(rest) || rest.filter(\.isLetter).count >= 12 {
                results.append(rest)
            }
        }
        return results
    }

    /// 短、無連字號／斜線、也不是化學名的前置音節，視為 OCR 殘字。
    private static func isLeadingOCRJunkWord(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard (2...5).contains(letters.count) else { return false }
        if word.contains("/") || word.contains("-") { return false }
        if looksLikeChemicalName(word) { return false }
        if hasTypicalINCIRoot(word) { return false }
        return true
    }

    // MARK: - 雜訊判斷（供 Resolver 分類 .noise）

    private static let footerLineKeywords = [
        "注意事項", "使用注意事項", "保存方法", "保存期限", "批號", "容量",
        "有效期間", "原產地", "製造廠", "輸入業者",
        "Made in", "Manufactured for", "Manufactured by", "Manufactured",
        "Distributed by", "Distributed in", "Distributed",
        "Directions", "Precautions",
        "Net Wt", "Net Weight",
        "All Rights Reserved", "Rights Reserved", "trademark",
        "components",
        "Dist.",
        "Tel:", "TEL:",
    ]

    static func isAddressNoiseToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let upper = trimmed.uppercased(with: Locale(identifier: "en_US_POSIX"))
        if upper.range(of: #"\b\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"\b[A-Z]{2}\s+\d{5}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func isMarketingNoiseToken(_ token: String) -> Bool {
        if isNegativeClaimLine(token) { return true }
        let upper = token.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let markers = [
            "NO ANIMAL", "ANIMAL TESTING", "CRUELTY", "RECYCLABLE", "CARTON",
            "FORMULATED WITHOUT", "FREE FROM", "FREE OF",
            "DERMATOLOGIST", "CLINICALLY",
            "TRADEMARK", "RIGHTS RESERVED", "CERTIFIED", "ORGANIC CERT",
            "INGREDIENTS FROM NATURE", "FROM NATURE",
            "不含", "無添加"
        ]
        return markers.contains { upper.contains($0) }
    }

    static func isPureFooterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains(",") || trimmed.contains("，")
            || trimmed.contains(";") || trimmed.contains("；") {
            return false
        }
        return lineContainsFooterKeyword(trimmed)
    }

    static func isFooterLedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cut = earliestFooterKeywordIndex(in: trimmed) else { return false }
        let prefix = String(trimmed[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty
    }

    private static func lineContainsFooterKeyword(_ line: String) -> Bool {
        for keyword in footerLineKeywords {
            if let range = line.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) {
                if isShortEnglishEndKeyword(keyword),
                   !isWholeWordMatch(keyword, in: line, range: range) {
                    continue
                }
                if keyword.lowercased() == "components",
                   !isWholeWordMatch(keyword, in: line, range: range) {
                    continue
                }
                return true
            }
        }
        return false
    }

    private static func earliestFooterKeywordIndex(in line: String) -> String.Index? {
        var earliest: String.Index?
        for keyword in footerLineKeywords {
            guard let range = line.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            if isShortEnglishEndKeyword(keyword),
               !isWholeWordMatch(keyword, in: line, range: range) {
                continue
            }
            if earliest == nil || range.lowerBound < earliest! {
                earliest = range.lowerBound
            }
        }
        return earliest
    }

    private static func isShortEnglishEndKeyword(_ keyword: String) -> Bool {
        let short: Set<String> = ["4C", "4C.", "LLC", "Dist.", "Tel:", "TEL:", "800-"]
        return short.contains(keyword)
    }

    private static func isWholeWordMatch(_ keyword: String, in text: String, range: Range<String.Index>) -> Bool {
        if keyword.hasSuffix(".") || keyword.hasSuffix("-") || keyword.hasSuffix(":") {
            return true
        }
        let beforeOK: Bool = {
            guard range.lowerBound > text.startIndex else { return true }
            let prev = text[text.index(before: range.lowerBound)]
            return !prev.isLetter && !prev.isNumber
        }()
        let afterOK: Bool = {
            guard range.upperBound < text.endIndex else { return true }
            let next = text[range.upperBound]
            return !next.isLetter && !next.isNumber
        }()
        return beforeOK && afterOK
    }
}
