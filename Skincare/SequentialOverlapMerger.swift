import Foundation

/// 多圖 OCR 成分清單的陣列對齊合併（Array Alignment Merge）。
///
/// 假設 Photo 1 → 2 → 3 為瓶身連續區段拍攝，但矮胖／圓瓶可能從中段起拍、最後一張才回到開頭。
/// 合併策略：
/// 1. 先把「最像清單開頭」的照片轉到第一張；
/// 2. 優先用 A 尾／B 頭連續重疊拼接；
/// 3. 否則用兩圖共同字典命中當錨點 zipper，錨點前片段以通用成分帶穩定排序；
/// 4. 再不行才保序追加（只收 B 側已命中字典的新項）。
enum SequentialOverlapMerger {

    /// 檢視 A 尾／B 頭的最大窗口（項數）。
    private static let maxWindow = 16
    /// 可靠重疊至少 2 項；單項僅在高相似度時採用。
    private static let minReliableOverlap = 2
    /// 正規化後相似度門檻（1 - editDistance / maxLen）。
    private static let similarityThreshold = 0.78
    /// 單項重疊需更高相似度，避免短詞誤撞。
    private static let singleOverlapSimilarity = 0.90
    /// 保序去重用的高相似度（不含「短詞被長詞包含」）。
    private static let duplicateSimilarity = 0.92
    /// 較短字串被較長字串包含時，亦視為 overlap 命中（OCR 截斷）。
    private static let containmentMinLength = 4
    /// 子字串包含須占較長字串足夠比例，避免不同丙烯酸酯聚合物互撞。
    private static let containmentMinRatio = 0.82

    /// 依選取順序將多張照片的成分陣列合併為單一清單（最終保序去重）。
    static func mergeAll(_ lists: [[String]]) -> [String] {
        let cleaned = lists
            .map { orderPreservingUnique($0) }
            .filter { !$0.isEmpty }
        guard let first = cleaned.first else { return [] }
        guard cleaned.count > 1 else { return stripRedundantUnknowns(first) }

        let rotated = rotateListsToIngredientStart(cleaned)
        let merged = rotated.dropFirst().reduce(rotated[0]) { mergeIngredients(listA: $0, listB: $1) }
        return stripRedundantUnknowns(orderPreservingUnique(merged))
    }

    /// 多圖合併後：丟掉已命中項的 OCR 半截，以及包裝品名／用法殘字。
    /// 與詳情列同一套 `matchToken` 判定，避免 lookup 寬、UI 窄造成半截殘留。
    static func stripRedundantUnknowns(_ items: [String]) -> [String] {
        let hosts: [(raw: String, key: String)] = items.compactMap { name in
            guard let item = IngredientMatcher.matchToken(name) else { return nil }
            let key = IngredientDatabaseManager.normalizedKey(item.englishName)
            guard !key.isEmpty else { return nil }
            return (item.englishName, key)
        }
        let hostKeys = hosts.map(\.key)

        return items.filter { name in
            if IngredientParser.isPackagingMarketingToken(name) { return false }
            if IngredientMatcher.matchToken(name) != nil { return true }

            if !IngredientResolver.shouldKeepAsUnmatchedUnknown(name) {
                return false
            }

            let fragment = IngredientDatabaseManager.normalizedKey(name)
            guard fragment.count >= 5 else { return true }
            for host in hostKeys {
                if isMergedOCRFragment(fragment, of: host) { return false }
            }
            return true
        }
    }

    private static func isMergedOCRFragment(_ fragment: String, of host: String) -> Bool {
        let f = fragment.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let h = host.lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard !f.isEmpty, !h.isEmpty else { return false }

        if h.count >= f.count {
            if h.hasPrefix(f) || h.contains(f) { return true }
        }
        // 未命中字串是「已命中 INCI + OCR 尾巴」時也丢掉。
        if f.count > h.count,
           Double(h.count) / Double(f.count) >= 0.72,
           f.hasPrefix(h) || f.contains(h) {
            return true
        }
        // 共享前綴夠長且 fragment 幾乎整段都是 host 前綴（ACRYLATES/C1 ⊂ ACRYLATES/C10-30…）。
        let shared = f.commonPrefix(with: h).count
        if shared >= 8, h.count > f.count, Double(shared) >= Double(f.count) * 0.82 {
            return true
        }
        // 最長共同子字串：AMMONIUM ACRY… ↔ MION UMACRY…
        let lcs = longestCommonSubstringLength(f, h)
        if lcs >= 6, Double(lcs) / Double(min(f.count, h.count)) >= 0.55 {
            return true
        }
        // 已命中項的近形 OCR（距離 ≤2），不當成第二筆未收錄。
        if f.count >= 5, h.count >= 5, abs(f.count - h.count) <= 3 {
            let distance = IngredientDatabaseManager.levenshteinDistance(f, h)
            if distance <= 2 { return true }
        }
        // 多詞殘字：任一字是 host 前綴／近形也丢掉（LECIH ≈ Lecithin）。
        let words = f.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for word in words where word.count >= 5 {
            if h.hasPrefix(word) || word.hasPrefix(String(h.prefix(min(h.count, word.count)))) {
                let prefixLen = word.commonPrefix(with: h).count
                if prefixLen >= 5, Double(prefixLen) >= Double(min(word.count, h.count)) * 0.8 {
                    return true
                }
            }
            if abs(word.count - h.count) <= 3,
               IngredientDatabaseManager.levenshteinDistance(word, h) <= 2 {
                return true
            }
        }
        return false
    }

    private static func longestCommonSubstringLength(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        guard !aChars.isEmpty, !bChars.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: bChars.count + 1)
        var current = Array(repeating: 0, count: bChars.count + 1)
        var best = 0
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    current[j] = previous[j - 1] + 1
                    best = max(best, current[j])
                } else {
                    current[j] = 0
                }
            }
            swap(&previous, &current)
            for j in current.indices {
                current[j] = 0
            }
        }
        return best
    }

    /// 將 `listB` 接到 `listA`：優先尾頭重疊；否則共同錨點 zipper；再否則保序追加。
    static func mergeIngredients(listA: [String], listB: [String]) -> [String] {
        let a = listA.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let b = listB.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !a.isEmpty else { return orderPreservingUnique(b) }
        guard !b.isEmpty else { return orderPreservingUnique(a) }

        let (alignedA, alignedB) = stitchCrossImageBoundary(listA: a, listB: b)

        if let skipCount = overlapSkipCount(listA: alignedA, listB: alignedB) {
            return stripRedundantUnknowns(
                orderPreservingUnique(alignedA + Array(alignedB.dropFirst(skipCount)))
            )
        }

        if let zippered = mergeBySharedAnchors(listA: alignedA, listB: alignedB) {
            return stripRedundantUnknowns(orderPreservingUnique(zippered))
        }

        // 無重疊時：若 B 比較像清單開頭，改以 B 為先再接 A，修正矮胖瓶繞回開頭。
        if listStartScore(alignedB) > listStartScore(alignedA) {
            if let skipCount = overlapSkipCount(listA: alignedB, listB: alignedA) {
                return stripRedundantUnknowns(
                    orderPreservingUnique(alignedB + Array(alignedA.dropFirst(skipCount)))
                )
            }
            if let zippered = mergeBySharedAnchors(listA: alignedB, listB: alignedA) {
                return stripRedundantUnknowns(orderPreservingUnique(zippered))
            }
            return stripRedundantUnknowns(
                orderPreservingUnique(appendKeepingOrder(listA: alignedB, listB: alignedA))
            )
        }

        return stripRedundantUnknowns(
            orderPreservingUnique(appendKeepingOrder(listA: alignedA, listB: alignedB))
        )
    }

    /// 保序去重：同名或同 INCI 僅保留第一次出現的位置。
    static func orderPreservingUnique(_ items: [String]) -> [String] {
        var result: [String] = []
        var seenKeys = Set<String>()
        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = identityKey(trimmed)
            if !key.isEmpty, seenKeys.contains(key) { continue }
            if result.contains(where: { isDuplicateIngredient($0, trimmed) }) { continue }
            result.append(trimmed)
            if !key.isEmpty { seenKeys.insert(key) }
        }
        return result
    }

    /// 跨圖接縫：上一張結尾碎片 + 下一張開頭，接起來能精準命中才合成一筆。
    private static func stitchCrossImageBoundary(
        listA: [String],
        listB: [String]
    ) -> (a: [String], b: [String]) {
        guard let last = listA.last, let first = listB.first else {
            return (listA, listB)
        }

        for joined in IngredientResolver.joinCandidates([last, first]) {
            if let item = IngredientResolver.exactResolveToken(joined) {
                return (Array(listA.dropLast()) + [item.englishName], Array(listB.dropFirst()))
            }
        }

        let lastKey = similarityKey(last)
        let firstKey = similarityKey(first)
        if lastKey.count >= containmentMinLength,
           firstKey.count > lastKey.count,
           firstKey.hasPrefix(lastKey),
           isDictionaryConfirmed(first),
           !isDictionaryConfirmed(last) {
            return (Array(listA.dropLast()), listB)
        }

        return (listA, listB)
    }

    // MARK: - Start rotation / scoring

    /// 把最像「全成分開頭」的那張轉到第一位，其餘保持相對旋轉順序。
    static func rotateListsToIngredientStart(_ lists: [[String]]) -> [[String]] {
        guard lists.count > 1 else { return lists }
        var bestIndex = 0
        var bestScore = Int.min
        for (index, list) in lists.enumerated() {
            let score = listStartScore(list)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        guard bestIndex > 0 else { return lists }
        return Array(lists[bestIndex...]) + Array(lists[..<bestIndex])
    }

    /// 越高越像清單開頭：水在前加分；防腐／香精／螯合劑在前扣分。
    static func listStartScore(_ list: [String]) -> Int {
        guard !list.isEmpty else { return Int.min / 4 }
        var score = 0
        for (index, name) in list.enumerated() {
            let band = orderBand(for: name)
            let proximity = max(list.count - index, 1)
            switch band {
            case .water:
                score += 400 - index * 40
            case .silicone, .emollient:
                score += 80 + proximity
            case .humectant:
                score += 60 + proximity / 2
            case .midSupport:
                score += index < 3 ? -10 : 15
            case .polymer:
                score += index < 3 ? -20 : 10
            case .preservativeChelator, .fragrance:
                score += index < 4 ? -120 : 20
            case .other:
                score += index == 0 ? -10 : 0
            }
        }
        if let first = list.first {
            switch orderBand(for: first) {
            case .water: score += 200
            case .silicone, .emollient, .humectant: score += 40
            case .preservativeChelator, .fragrance: score -= 80
            default: break
            }
        }
        return score
    }

    // MARK: - Shared-anchor zipper

    /// 兩圖都命中的字典成分當錨點，分段合併後再接回。
    private static func mergeBySharedAnchors(listA: [String], listB: [String]) -> [String]? {
        let anchors = sharedAnchorKeys(listA: listA, listB: listB)
        guard !anchors.isEmpty else { return nil }

        var result: [String] = []
        var indexA = 0
        var indexB = 0

        for anchor in anchors {
            guard let posA = listA[indexA...].firstIndex(where: { identityKey($0) == anchor }),
                  let posB = listB[indexB...].firstIndex(where: { identityKey($0) == anchor })
            else { continue }

            let segmentA = Array(listA[indexA..<posA])
            let segmentB = Array(listB[indexB..<posB])
            result.append(contentsOf: mergeSegmentsBeforeAnchor(segmentA, segmentB))
            result.append(preferredDisplay(listA[posA], listB[posB]))
            indexA = posA + 1
            indexB = posB + 1
        }

        guard indexA > 0 || indexB > 0 else { return nil }

        result.append(contentsOf: mergeSegmentsBeforeAnchor(
            Array(listA[indexA...]),
            Array(listB[indexB...])
        ))
        return result
    }

    private static func sharedAnchorKeys(listA: [String], listB: [String]) -> [String] {
        let keysB = Set(listB.map(identityKey).filter { !$0.isEmpty })
        var seen = Set<String>()
        var ordered: [String] = []
        for name in listA {
            let key = identityKey(name)
            guard !key.isEmpty, keysB.contains(key), !seen.contains(key) else { continue }
            // 錨點必須是字典命中，避免 OCR 殘字當接縫。
            guard isDictionaryConfirmed(name) else { continue }
            seen.insert(key)
            ordered.append(key)
        }
        return ordered
    }

    /// 錨點前兩段：以通用成分帶排序，同帶時保留 A 再 B 的穩定順序。
    private static func mergeSegmentsBeforeAnchor(_ segmentA: [String], _ segmentB: [String]) -> [String] {
        if segmentA.isEmpty { return segmentB }
        if segmentB.isEmpty { return segmentA }

        struct Ranked {
            let name: String
            let band: OrderBand
            let priority: Int
            let source: Int
            let index: Int
        }

        // 兩段都非空時，較像清單開頭的那段在同帶內優先（矮胖瓶繞回開頭）。
        let preferBFirst = listStartScore(segmentB) > listStartScore(segmentA)

        var ranked: [Ranked] = []
        ranked.reserveCapacity(segmentA.count + segmentB.count)
        for (index, name) in segmentA.enumerated() {
            ranked.append(Ranked(
                name: name,
                band: orderBand(for: name),
                priority: withinBandPriority(for: name),
                source: preferBFirst ? 1 : 0,
                index: index
            ))
        }
        for (index, name) in segmentB.enumerated() {
            let key = identityKey(name)
            if !key.isEmpty, ranked.contains(where: { identityKey($0.name) == key }) {
                continue
            }
            if ranked.contains(where: { isDuplicateIngredient($0.name, name) }) {
                continue
            }
            ranked.append(Ranked(
                name: name,
                band: orderBand(for: name),
                priority: withinBandPriority(for: name),
                source: preferBFirst ? 0 : 1,
                index: index
            ))
        }

        ranked.sort {
            if $0.band != $1.band { return $0.band.rawValue < $1.band.rawValue }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.source != $1.source { return $0.source < $1.source }
            return $0.index < $1.index
        }
        return ranked.map(\.name)
    }

    /// 同帶內的通用先後（甘油常早於多元醇；不綁品牌／特定配方）。
    private static func withinBandPriority(for name: String) -> Int {
        let key = similarityKey(name)
        guard !key.isEmpty else { return 50 }
        if matchesAny(key, ["water", "aqua", "eau"]) { return 0 }
        if matchesAny(key, ["dimethicone", "dimethiconol", "cyclopentasiloxane"]) { return 5 }
        if matchesAny(key, ["squalane", "squalene", "isododecane", "isohexadecane"]) { return 8 }
        if matchesAny(key, ["glycerin", "glycerol"]) { return 10 }
        if matchesAny(key, [
            "butyleneglycol", "propyleneglycol", "pentyleneglycol",
            "propanediol", "hexanediol", "methylpropanediol"
        ]) { return 20 }
        if matchesAny(key, ["panthenol", "betaine", "trehalose", "pca"]) { return 25 }
        if matchesAny(key, ["hydroxyacetophenone", "caprylylglycol"]) { return 28 }
        if matchesAny(key, ["hyaluronate", "hyaluronicacid"]) { return 35 }
        if matchesAny(key, ["acrylate", "carbomer", "copolymer", "crosspolymer"]) { return 40 }
        if matchesAny(key, [
            "phenoxyethanol", "ethylhexylglycerin", "phytate", "edta"
        ]) { return 45 }
        return 50
    }

    private static func preferredDisplay(_ a: String, _ b: String) -> String {
        if isDictionaryConfirmed(a), let item = IngredientResolver.exactResolveToken(a)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: a) {
            return item.englishName
        }
        if isDictionaryConfirmed(b), let item = IngredientResolver.exactResolveToken(b)
            ?? IngredientDatabaseManager.shared.lookup(ingredientName: b) {
            return item.englishName
        }
        return a.count >= b.count ? a : b
    }

    // MARK: - Order bands（功能形態，不是品牌／特定配方）
    // 常見瓶身：水 → 矽／油 → 保濕 → 中段機能 → 增稠聚合物 → 活性／植萃 → 防腐／螯合 → 香精

    private enum OrderBand: Int {
        case water = 0
        case silicone = 1
        case emollient = 2
        case humectant = 3
        case midSupport = 4
        case polymer = 5
        case other = 6
        case preservativeChelator = 7
        case fragrance = 8
    }

    private static func orderBand(for name: String) -> OrderBand {
        let key = similarityKey(name)
        guard !key.isEmpty else { return .other }

        if matchesAny(key, ["water", "aqua", "eau"]) { return .water }
        if matchesAny(key, [
            "dimethicone", "dimethiconol", "cyclopentasiloxane", "cyclohexasiloxane",
            "polysilicone", "trimethylsiloxysilicate"
        ]) { return .silicone }
        if matchesAny(key, [
            "squalane", "squalene", "isododecane", "isohexadecane",
            "capryliccaprictriglyceride", "mineraloil", "paraffinumliquidum"
        ]) || key.hasSuffix("oil") || key.hasSuffix("butter") {
            return .emollient
        }
        if matchesAny(key, [
            "glycerin", "glycerol", "butyleneglycol", "propyleneglycol", "pentyleneglycol",
            "propanediol", "hexanediol", "methylpropanediol", "panthenol",
            "hyaluronate", "hyaluronicacid", "betaine", "trehalose", "pca"
        ]) { return .humectant }
        // 對羥基苯乙酮等常夾在多元醇與增稠劑之間，不當表尾防腐排。
        if matchesAny(key, ["hydroxyacetophenone", "caprylylglycol"]) {
            return .midSupport
        }
        if matchesAny(key, [
            "acrylate", "carbomer", "xanthan", "taurate", "copolymer", "crosspolymer",
            "polyacrylate", "polyacrylamide"
        ]) { return .polymer }
        if matchesAny(key, [
            "phenoxyethanol", "ethylhexylglycerin", "edta", "phytate",
            "benzoate", "sorbate", "phenoxy"
        ]) { return .preservativeChelator }
        if matchesAny(key, [
            "fragrance", "parfum", "limonene", "linalool", "citronellol", "geraniol", "coumarin"
        ]) { return .fragrance }
        return .other
    }

    private static func matchesAny(_ key: String, _ needles: [String]) -> Bool {
        needles.contains { key == $0 || key.contains($0) }
    }

    // MARK: - Overlap detection

    /// 回傳 listB 開頭應略過的項數；找不到可靠重疊則 `nil`。
    private static func overlapSkipCount(listA: [String], listB: [String]) -> Int? {
        let windowA = min(maxWindow, listA.count)
        let windowB = min(maxWindow, listB.count)
        guard windowA >= 1, windowB >= 1 else { return nil }

        let tail = Array(listA.suffix(windowA))
        let head = Array(listB.prefix(windowB))

        if let skip = maxConsecutiveOverlapSkip(tail: tail, head: head) {
            return skip
        }
        if let skip = maxSubsequenceOverlapSkip(tail: tail, head: head) {
            return skip
        }
        return nil
    }

    /// 滑動窗口：listA 後綴與 listB 前綴的最長連續模糊相符。
    private static func maxConsecutiveOverlapSkip(tail: [String], head: [String]) -> Int? {
        let maxLen = min(tail.count, head.count)
        guard maxLen >= 1 else { return nil }

        for length in stride(from: maxLen, through: 1, by: -1) {
            let aPart = Array(tail.suffix(length))
            let bPart = Array(head.prefix(length))
            guard zip(aPart, bPart).allSatisfy({ isSimilar($0, $1) }) else { continue }
            guard isReliableOverlap(length: length, lhs: aPart, rhs: bPart) else { continue }
            return length
        }
        return nil
    }

    /// 最大重疊子序列：B 的前綴與 A 的後綴對齊，容許 overlap 區漏抓 1 項。
    private static func maxSubsequenceOverlapSkip(tail: [String], head: [String]) -> Int? {
        let n = tail.count
        let m = head.count
        guard n >= minReliableOverlap, m >= minReliableOverlap else { return nil }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if isSimilar(tail[i - 1], head[j - 1]) {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        let lcsLength = dp[n][m]
        guard lcsLength >= minReliableOverlap else { return nil }

        var i = n
        var j = m
        var latestTail = -1
        var latestHead = 0
        var earliestHead = Int.max
        while i > 0, j > 0 {
            if isSimilar(tail[i - 1], head[j - 1]), dp[i][j] == dp[i - 1][j - 1] + 1 {
                if latestTail < 0 {
                    latestTail = i - 1
                    latestHead = j
                }
                earliestHead = j
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        // 必須是 A 後綴 ∩ B 前綴，避免把清單中段同名項當成接縫。
        guard latestTail >= n - 2, earliestHead == 1 else { return nil }
        // overlap 區在 B 側最多比命中數多 1 項（漏字／多抓）。
        guard latestHead - lcsLength <= 1 else { return nil }
        return latestHead
    }

    private static func isReliableOverlap(length: Int, lhs: [String], rhs: [String]) -> Bool {
        if length >= minReliableOverlap { return true }
        guard let a = lhs.first, let b = rhs.first else { return false }
        return pairSimilarity(a, b) >= singleOverlapSimilarity
    }

    /// 對齊失敗時的保序追加：只收下 listB 裡已能對到字典、且 listA 尚未出現的項。
    private static func appendKeepingOrder(listA: [String], listB: [String]) -> [String] {
        var result = listA
        var seen = Set(listA.map(identityKey).filter { !$0.isEmpty })
        for item in listB {
            guard isDictionaryConfirmed(item) else { continue }
            let key = identityKey(item)
            if !key.isEmpty, seen.contains(key) { continue }
            if result.contains(where: { isDuplicateIngredient($0, item) }) { continue }
            result.append(item)
            if !key.isEmpty { seen.insert(key) }
        }
        return result
    }

    /// 以既有精準／別名查找判斷是否為字典命中；不另外放寬模糊。
    private static func isDictionaryConfirmed(_ text: String) -> Bool {
        if IngredientResolver.exactResolveToken(text) != nil { return true }
        if IngredientDatabaseManager.shared.lookupFromIndex(text) != nil { return true }
        return IngredientDatabaseManager.shared.lookup(ingredientName: text) != nil
    }

    // MARK: - Similarity / identity

    /// Overlap 比對：標準化小寫 + 去空白／標點，容許邊緣字元輕微瑕疵。
    static func isSimilar(_ lhs: String, _ rhs: String) -> Bool {
        let a = similarityKey(lhs)
        let b = similarityKey(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }

        if a.count >= containmentMinLength, b.count >= containmentMinLength {
            let shorter = a.count <= b.count ? a : b
            let longer = a.count <= b.count ? b : a
            // 前後綴截斷（Hydrogenated Polyisobutene ↔ Polyisobutene）維持可對。
            if longer.hasPrefix(shorter) || longer.hasSuffix(shorter) {
                return true
            }
            // 中間包含須夠長，避免不同丙烯酸酯聚合物互相誤判為同一項。
            let ratio = Double(shorter.count) / Double(longer.count)
            if ratio >= containmentMinRatio, longer.contains(shorter) {
                return true
            }
        }

        return pairSimilarity(lhs, rhs) >= similarityThreshold
    }

    private static func isDuplicateIngredient(_ lhs: String, _ rhs: String) -> Bool {
        let aKey = identityKey(lhs)
        let bKey = identityKey(rhs)
        if !aKey.isEmpty, aKey == bKey { return true }

        let a = similarityKey(lhs)
        let b = similarityKey(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }

        let longest = max(a.count, b.count)
        let shortest = min(a.count, b.count)
        guard longest > 0, Double(shortest) / Double(longest) >= 0.85 else { return false }
        return pairSimilarity(lhs, rhs) >= duplicateSimilarity
    }

    private static func pairSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = similarityKey(lhs)
        let b = similarityKey(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let longest = max(a.count, b.count)
        let distance = IngredientDatabaseManager.levenshteinDistance(a, b)
        return 1 - (Double(distance) / Double(longest))
    }

    /// 比對鍵：小寫 + 去除空白與標點（僅保留字母數字）。
    private static func similarityKey(_ text: String) -> String {
        text
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// 身分鍵：能命中字典時用標準 INCI／英文名；否則用正規化字面。
    private static func identityKey(_ text: String) -> String {
        if let item = IngredientDatabaseManager.shared.lookup(ingredientName: text) {
            return IngredientDatabaseManager.normalizedKey(item.englishName)
        }
        return IngredientDatabaseManager.normalizedKey(text)
    }
}
