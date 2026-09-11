import Foundation

/// 第一階段：標點與語法分詞器（Lexer）。
///
/// 職責邊界：**只做語法切分，完全不碰資料庫**。
/// 任何查表、別名還原、模糊容錯一律屬於第二階段 `IngredientResolver`。
///
/// 三項不可違反的規則：
/// 1. 輸出順序等同瓶身由前到後的物理順序，禁止任何形式的重排。
/// 2. 括號內的逗號（`(Aqua, Eau)`、`(1,2-Ethenediyl)`）不得切分。
/// 3. 僅在括號層級為 0 時，遇逗號／分號／頓號才切分。
///    換行**不是**清單分隔符：密排 INCI 常在單字中間折行，
///    行尾若不是逗號／分號／頓號，換行改當空白接到下一行。
enum IngredientTokenizer {

    /// 有序 Token。`index` 為 0-based 物理順位，後續階段必須原封不動地沿用。
    struct Token: Sendable, Hashable {
        let index: Int
        /// 清理過的比對用字串（僅保留合法 INCI 字元）。
        let text: String
        /// 切分後、清理前的原始片段。
        ///
        /// 雜訊判斷必須看這一份：`.com`、`fl. oz.`、`U.S.` 的句點在 `sanitize` 會被抹成空白，
        /// 只看 `text` 就再也認不出網址與容量標示了。
        let raw: String
    }

    // MARK: - 語法字元集

    /// 括號層級 0 時才生效的清單分隔符。
    ///
    /// 換行刻意不在此集合：見 `newlineAction`。
    /// 句末標點（`。！？`）仍算分隔符，避免中文行銷句與下一個 INCI 黏死。
    /// 中圓點／Bullet 是日韓台標常見分隔（沒有逗號），必須與逗號同等切分。
    private static let listDelimiters: Set<Character> = [
        ",", "，", ";", "；", "、",
        "。", "｡", "！", "？",
        "•", "·", "・", "･", "●", "∙", "‧"
    ]

    private static let trailingListSeparators: Set<Character> = [
        ",", "，", ";", "；", "、",
        "•", "·", "・", "･", "●", "∙", "‧"
    ]

    /// 貼上／OCR 常見的清單中圓點，先正規成逗號再切分。
    private static let bulletSeparators = ["•", "·", "・", "･", "●", "∙", "‧"]

    private static let openBrackets: Set<Character> = ["(", "（", "[", "［", "{", "｛"]
    private static let closeBrackets: Set<Character> = [")", "）", "]", "］", "}", "｝"]

    /// 尾端句點屬於 INCI 縮寫的一部分，不得裁掉。
    private static let protectedTrailingAbbreviations = [
        "denat.", "ext.", "dist.", "fld.", "spp.", "var."
    ]

    // MARK: - 入口

    /// OCR 全文 → 有序 Token 陣列。
    static func tokenize(_ rawText: String) -> [Token] {
        let prepared = prepare(rawText)
        guard !prepared.isEmpty else { return [] }

        var tokens: [Token] = []
        for piece in splitPreservingBrackets(prepared) {
            let cleaned = sanitize(piece)
            guard !cleaned.isEmpty else { continue }
            let raw = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            tokens.append(
                Token(
                    index: tokens.count,
                    text: cleaned,
                    raw: raw.isEmpty ? cleaned : raw
                )
            )
        }
        return tokens
    }

    /// 純字串版本，供既有呼叫端使用；順序與 `tokenize` 完全一致。
    static func tokenizeToStrings(_ rawText: String) -> [String] {
        tokenize(rawText).map(\.text)
    }

    // MARK: - 前處理（純語法層級）

    /// 全文層級的語法清理；不做任何語意判斷，也不切分。
    ///
    /// 步驟順序不可調換：`[批號]`、`(6.0%)` 這類標記必須在 `sanitize` 之前於全文層級清掉，
    /// 因為 `[`、`]`、`%` 在合法 INCI 字元檢查中會被抹成空白，屆時就認不出原本的樣式了。
    private static func prepare(_ rawText: String) -> String {
        var value = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for bullet in bulletSeparators {
            value = value.replacingOccurrences(of: bullet, with: ",")
        }

        // 起始／結束錨點裁切 + 首項標題前綴清理，把外包裝雜訊擋在分詞之前。
        value = IngredientParser.cropToIngredientListSection(value)
        value = IngredientMatcher.applyOCRGlyphFixes(value)
        value = IngredientParser.removeBracketCodes(from: value)
        value = IngredientParser.stripAllConcentrationPercents(from: value)

        // 有機／註腳星號屬於標示符號，不是成分內容。
        for mark in ["*", "＊", "†", "‡"] {
            value = value.replacingOccurrences(of: mark, with: " ")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 括號保護切分

    /// OCR 漏掉右括號時的防呆距離：括號開啟超過這個字元數仍未閉合，視為辨識錯誤並強制歸零。
    /// 沒有這道保險，一個漏掉的 `)` 會讓整份成分表黏成單一 Token。
    private static let maxUnclosedBracketSpan = 80

    /// 依括號巢狀層級切分；層級 > 0 時所有分隔符一律視為成分名稱的一部分。
    static func splitPreservingBrackets(_ text: String) -> [String] {
        let chars = Array(text)
        var pieces: [String] = []
        var current = ""
        var depth = 0
        var outermostOpenIndex = -1

        for (index, ch) in chars.enumerated() {
            if depth > 0, index - outermostOpenIndex > maxUnclosedBracketSpan {
                depth = 0
                outermostOpenIndex = -1
            }

            if openBrackets.contains(ch) {
                if depth == 0 { outermostOpenIndex = index }
                depth += 1
                current.append(ch)
                continue
            }
            if closeBrackets.contains(ch), depth > 0 {
                depth -= 1
                if depth == 0 { outermostOpenIndex = -1 }
                current.append(ch)
                continue
            }
            if ch == "\n" || ch == "\r" {
                applyNewline(at: index, in: chars, depth: depth, current: &current, pieces: &pieces)
                continue
            }
            if depth == 0,
               listDelimiters.contains(ch),
               !isChemicalNumberComma(at: index, in: chars) {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        pieces.append(current)
        return pieces
    }

    private enum NewlineAction {
        /// 接到下一行，中間補一個空白。
        case joinAsSpace
        /// 丟掉換行（行尾已有逗號，或連字號折行）。
        case skip
        /// 當作清單分隔（例如中文行銷句與英文成分分屬兩行）。
        case split
    }

    /// 括號內換行一律當空白，不得切分。
    /// 括號外：行尾已是清單分隔符就跳過；兩側都是 INCI 可續寫字元則接成同一 Token；
    /// 其餘（中／英交界、行銷句）仍切開，避免把品名與成分黏死。
    private static func applyNewline(
        at index: Int,
        in chars: [Character],
        depth: Int,
        current: inout String,
        pieces: inout [String]
    ) {
        if depth > 0 {
            appendSpaceIfNeeded(&current)
            return
        }
        switch newlineAction(at: index, in: chars) {
        case .joinAsSpace:
            appendSpaceIfNeeded(&current)
        case .skip:
            break
        case .split:
            pieces.append(current)
            current = ""
        }
    }

    private static func appendSpaceIfNeeded(_ current: inout String) {
        guard !current.isEmpty, !current.hasSuffix(" ") else { return }
        current.append(" ")
    }

    private static func newlineAction(at index: Int, in chars: [Character]) -> NewlineAction {
        let previous = previousNonWhitespace(before: index, in: chars)
        let next = nextNonWhitespace(after: index, in: chars)

        if let previous, trailingListSeparators.contains(previous) {
            return .skip
        }
        // `POLYACRY-\nLOYL`：連字號折行，直接接上、不另加空白。
        if let previous, previous == "-" || previous == "‐" || previous == "–" {
            return .skip
        }
        if let previous, let next, isINCIContinuable(previous), isINCIContinuable(next) {
            return .joinAsSpace
        }
        return .split
    }

    /// 拉丁字母、數字、INCI 常見連字號／斜線：折行後仍屬同一化學名。
    private static func isINCIContinuable(_ ch: Character) -> Bool {
        guard ch.isASCII else { return false }
        return ch.isLetter || ch.isNumber || ch == "-" || ch == "/" || ch == "'" || ch == "+"
    }

    private static func previousNonWhitespace(before index: Int, in chars: [Character]) -> Character? {
        var cursor = index - 1
        while cursor >= 0 {
            let ch = chars[cursor]
            if !ch.isWhitespace { return ch }
            cursor -= 1
        }
        return nil
    }

    private static func nextNonWhitespace(after index: Int, in chars: [Character]) -> Character? {
        var cursor = index + 1
        while cursor < chars.count {
            let ch = chars[cursor]
            if !ch.isWhitespace { return ch }
            cursor += 1
        }
        return nil
    }

    /// `1,2-Hexanediol`：數字之間的逗號是化學式編號，不是清單分隔。
    private static func isChemicalNumberComma(at index: Int, in chars: [Character]) -> Bool {
        let ch = chars[index]
        guard ch == "," || ch == "，" else { return false }
        guard index > 0, index + 1 < chars.count else { return false }
        return chars[index - 1].isNumber && chars[index + 1].isNumber
    }

    // MARK: - Token 清理

    /// 僅去除首尾空白與尾端句點，並壓縮空白。
    /// 括號、斜線、連字號、化學式逗號、單引號一律保留（合法 INCI 字元）。
    static func sanitize(_ raw: String) -> String {
        var value = IngredientParser.retainingLegalINCICharacters(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while value.hasSuffix(".") || value.hasSuffix("。") {
            let lower = value.lowercased(with: Locale(identifier: "en_US_POSIX"))
            if protectedTrailingAbbreviations.contains(where: { lower.hasSuffix($0) }) {
                break
            }
            value = String(value.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}
