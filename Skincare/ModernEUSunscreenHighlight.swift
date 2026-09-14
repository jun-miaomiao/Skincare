import Foundation

/// 新型歐洲主流化學防曬濾劑標示（詳情頁小提示；不改功能膠囊）。
enum ModernEUSunscreenHighlight {
    struct Info: Equatable, Sendable {
        /// 市面常見商品名，例如 `Tinosorb S`
        let tradeLabel: String
        /// 一行補充說明
        let summary: String
    }

    /// 以 INCI／中文／別名比對是否為新型歐系主流防曬濾劑。
    static func match(
        englishName: String,
        chineseName: String? = nil,
        aliases: [String] = []
    ) -> Info? {
        let parts = [englishName, chineseName ?? ""] + aliases
        let blob = parts
            .map { IngredientDatabaseManager.normalizedKey($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !blob.isEmpty else { return nil }

        // 依較具體關鍵字優先（避免短字誤中）。
        let rules: [(needles: [String], info: Info)] = [
            (
                ["bisethylhexyloxyphenolmethoxyphenyltriazine", "bemotrizinol", "tinosorbs"],
                Info(
                    tradeLabel: "Tinosorb S",
                    summary: "新型歐洲主流廣譜化學防曬濾劑（Bemotrizinol），UVA／UVB 穩定度較佳。"
                )
            ),
            (
                ["methylenebisbenzotriazolyltetramethylbutylphenol", "bisoctrizole", "tinosorbm", "mbbt"],
                Info(
                    tradeLabel: "Tinosorb M",
                    summary: "新型歐洲主流廣譜防曬濾劑（Bisoctrizole），常見於歐系配方。"
                )
            ),
            (
                ["diethylaminohydroxybenzoylhexylbenzoate", "uvinulaplus", "uvinula", "dhhb"],
                Info(
                    tradeLabel: "Uvinul A Plus",
                    summary: "新型歐洲主流 UVA 化學防曬濾劑（DHHB），光穩定性佳。"
                )
            ),
            (
                ["ethylhexyltriazone", "uvinult150", "uvinult"],
                Info(
                    tradeLabel: "Uvinul T 150",
                    summary: "新型歐洲主流 UVB 化學防曬濾劑（Ethylhexyl Triazone）。"
                )
            ),
            (
                ["drometrizoletrisiloxane", "mexorylxl"],
                Info(
                    tradeLabel: "Mexoryl XL",
                    summary: "歐萊雅系新型廣譜防曬濾劑（Drometrizole Trisiloxane），歐洲配方常見。"
                )
            ),
            (
                ["terephthalylidenedicamphorsulfonicacid", "ecamsule", "mexorylsx", "mexoryl"],
                Info(
                    tradeLabel: "Mexoryl SX",
                    summary: "歐萊雅系新型 UVA 防曬濾劑（Ecamsule），歐洲配方常見。"
                )
            )
        ]

        for rule in rules {
            if rule.needles.contains(where: { blob.contains($0) }) {
                return rule.info
            }
        }
        return nil
    }
}
