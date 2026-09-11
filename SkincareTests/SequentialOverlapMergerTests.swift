import Testing
@testable import Skincare

struct SequentialOverlapMergerTests {

    @Test func mergesOnTailHeadOverlap() {
        let a = ["Water", "Glycerin", "Niacinamide", "Panthenol", "Allantoin"]
        let b = ["Panthenol", "Allantoin", "Carbomer", "Phenoxyethanol"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == [
            "Water", "Glycerin", "Niacinamide", "Panthenol", "Allantoin",
            "Carbomer", "Phenoxyethanol"
        ])
    }

    @Test func appendsDedupedWhenNoOverlap() {
        let a = ["Water", "Glycerin", "Niacinamide"]
        let b = ["Phenoxyethanol", "Limonene", "Linalool"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == a + b)
    }

    @Test func mergeAllPreservesSelectionOrder() {
        let photo1 = ["Aqua", "Butylene Glycol", "Niacinamide"]
        let photo2 = ["Niacinamide", "Adenosine", "Tocopherol"]
        let photo3 = ["Tocopherol", "Limonene", "Linalool"]
        let merged = SequentialOverlapMerger.mergeAll([photo1, photo2, photo3])
        #expect(merged == [
            "Aqua", "Butylene Glycol", "Niacinamide",
            "Adenosine", "Tocopherol",
            "Limonene", "Linalool"
        ])
    }

    @Test func fuzzyContainsCountsAsOverlap() {
        let a = ["Hydrogenated Polyisobutene", "Dimethicone"]
        let b = ["Polyisobutene", "Dimethicone", "Phenoxyethanol"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged.last == "Phenoxyethanol")
        #expect(merged.contains("Dimethicone"))
    }

    @Test func longSlidingWindowOverlap_beyondFourItems() {
        let a = [
            "TokenAlpha", "TokenBeta", "TokenGamma", "TokenDelta",
            "TokenEpsilon", "TokenZeta", "TokenEta", "TokenTheta"
        ]
        let b = [
            "TokenDelta", "TokenEpsilon", "TokenZeta", "TokenEta",
            "TokenTheta", "TokenIota", "TokenKappa"
        ]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == a + ["TokenIota", "TokenKappa"])
        #expect(Set(merged).count == merged.count)
    }

    @Test func punctuationAndCaseNormalizedOverlap() {
        let a = ["Glycerin", "Niacinamide.", "Panthenol"]
        let b = ["niacinamide", "panthenol", "Allantoin"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == ["Glycerin", "Niacinamide.", "Panthenol", "Allantoin"])
    }

    @Test func droppedItemInOverlap_usesMaximumSubsequence() {
        let a = ["Glycerin", "Niacinamide", "Panthenol", "Allantoin"]
        let b = ["Niacinamide", "Allantoin", "Carbomer"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == ["Glycerin", "Niacinamide", "Panthenol", "Allantoin", "Carbomer"])
        #expect(merged.filter { SequentialOverlapMerger.isSimilar($0, "Allantoin") }.count == 1)
    }

    @Test func gapTooLarge_appendsUniquesInOrder() {
        let a = ["Glycerin", "Niacinamide", "Panthenol"]
        let b = ["Carbomer", "Phenoxyethanol", "Ethylhexylglycerin"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == a + b)
    }

    @Test func orderPreservingUnique_keepsFirstOccurrenceOnly() {
        let items = [
            "Glycerin",
            "Niacinamide",
            "glycerin",
            "NIACINAMIDE.",
            "Panthenol",
            "Glycerin"
        ]
        let unique = SequentialOverlapMerger.orderPreservingUnique(items)
        #expect(unique == ["Glycerin", "Niacinamide", "Panthenol"])
    }

    @Test func noOverlapAppend_stripsAlreadyPresentItems() {
        let a = ["Glycerin", "Niacinamide", "Panthenol"]
        let b = ["Carbomer", "Niacinamide", "Phenoxyethanol"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == ["Glycerin", "Niacinamide", "Panthenol", "Carbomer", "Phenoxyethanol"])
        #expect(merged.filter { SequentialOverlapMerger.isSimilar($0, "Niacinamide") }.count == 1)
    }

    @Test func noOverlap_doesNotAppendUnknownFragmentsFromListB() {
        let a = ["Water", "Glycerin", "Niacinamide"]
        let b = [
            "9IEAHZRUE",
            "MOISTURIZE PM",
            "Phenoxyethanol",
            "0123456789012"
        ]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged.contains("Phenoxyethanol"))
        #expect(!merged.contains("9IEAHZRUE"))
        #expect(!merged.contains("MOISTURIZE PM"))
        #expect(!merged.contains("0123456789012"))
        #expect(merged == ["Water", "Glycerin", "Niacinamide", "Phenoxyethanol"])
    }

    @Test func crossImageBoundary_stitchesFragmentsOnlyWhenDictionaryHits() {
        let a = ["Water", "Glycerin", "ETHYLHEXYL"]
        let b = ["TRIAZONE", "Phenoxyethanol"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        let joined = merged.joined(separator: " | ").uppercased()
        #expect(joined.contains("ETHYLHEXYL"))
        #expect(joined.contains("TRIAZONE") || joined.contains("ETHYLHEXYL TRIAZONE"))
        #expect(!merged.contains { $0.uppercased() == "TRIAZONE" })
        #expect(!merged.contains { $0.uppercased() == "ETHYLHEXYL" })
        #expect(merged.contains("Phenoxyethanol") || merged.contains { $0.uppercased().contains("PHENOXYETHANOL") })
    }

    @Test func crossImageBoundary_doesNotGlueTwoRealIngredients() {
        let a = ["Water", "Glycerin"]
        let b = ["Niacinamide", "Phenoxyethanol"]
        let merged = SequentialOverlapMerger.mergeIngredients(listA: a, listB: b)
        #expect(merged == ["Water", "Glycerin", "Niacinamide", "Phenoxyethanol"])
    }

    @Test func wrapAroundSecondShot_keepsGlycerinBeforeMidListPolymers() {
        // 矮胖瓶：第 1 張從中段起拍，第 2 張繞回開頭（缺 Water／Squalane）。
        let midToEnd = [
            "Dimethicone",
            "Pentylene Glycol",
            "1,2-Hexanediol",
            "Butylene Glycol",
            "Hydroxyacetophenone",
            "Sodium Acrylates Copolymer",
            "Acrylates/C10-30 Alkyl Acrylate Crosspolymer",
            "Tridecapeptide-1",
            "Oligopeptide-1",
            "Sodium Phytate",
            "Propanediol",
            "Lecithin",
            "Hydroxypropyltrimonium Hyaluronate"
        ]
        let startWrap = [
            "Glycerin",
            "Sodium Acrylates Copolymer",
            "Gigartina Stellata Extract",
            "Oligopeptide-1",
            "Sodium Phytate",
            "Propanediol",
            "Lecithin"
        ]

        let merged = SequentialOverlapMerger.mergeAll([midToEnd, startWrap])
        let glycerin = merged.firstIndex { SequentialOverlapMerger.isSimilar($0, "Glycerin") }
        let pentylene = merged.firstIndex { SequentialOverlapMerger.isSimilar($0, "Pentylene Glycol") }
        let hydroxy = merged.firstIndex { SequentialOverlapMerger.isSimilar($0, "Hydroxyacetophenone") }
        let polymer = merged.firstIndex {
            SequentialOverlapMerger.isSimilar($0, "Sodium Acrylates Copolymer")
        }
        let gigartina = merged.firstIndex {
            SequentialOverlapMerger.isSimilar($0, "Gigartina Stellata Extract")
        }
        let ha = merged.firstIndex {
            SequentialOverlapMerger.isSimilar($0, "Hydroxypropyltrimonium Hyaluronate")
        }

        #expect(glycerin != nil && pentylene != nil && hydroxy != nil && ha != nil)
        if let glycerin, let pentylene {
            #expect(glycerin < pentylene, "甘油應在戊二醇之前：\(merged)")
        }
        if let glycerin, let hydroxy {
            #expect(glycerin < hydroxy, "甘油不應掉到羥基苯乙酮之後：\(merged)")
        }
        if let hydroxy, let polymer {
            #expect(hydroxy < polymer, "對羥基苯乙酮應在增稠聚合物之前：\(merged)")
        }
        if let polymer, let gigartina {
            #expect(polymer < gigartina, "增稠劑應在藻萃取之前：\(merged)")
        }
        if let glycerin, let ha {
            #expect(glycerin < ha, "甘油不應掉到表尾玻尿酸之後：\(merged)")
        }
        #expect(merged.first.map { SequentialOverlapMerger.isSimilar($0, "Dimethicone") } == true
            || merged.first.map { SequentialOverlapMerger.isSimilar($0, "Glycerin") } == true)
    }

    @Test func stripRedundantUnknowns_dropsMatchedFragmentsAndPackaging() {
        let items = [
            "Water",
            "Gigartina Stellata Extract",
            "GIGARTINA STE",
            "Acrylates/C10-30 Alkyl Acrylate Crosspolymer",
            "ACRYLATES/C1",
            "Ammonium Acryloyldimethyltaurate/VP Copolymer",
            "MION UMACRY",
            "EERPRO-COLLAGEN",
            "DISTURIZEIPM",
            "MSTURILE A PF",
            "MOAETERGHEA",
            "REESABEIN",
            "Lecithin",
            "LECIH IRMONIU",
            "Phenoxyethanol"
        ]
        let cleaned = SequentialOverlapMerger.stripRedundantUnknowns(items)
        #expect(cleaned.contains("Gigartina Stellata Extract"))
        #expect(cleaned.contains("Acrylates/C10-30 Alkyl Acrylate Crosspolymer"))
        #expect(cleaned.contains("Ammonium Acryloyldimethyltaurate/VP Copolymer"))
        #expect(cleaned.contains("Lecithin"))
        #expect(cleaned.contains("Phenoxyethanol"))
        #expect(!cleaned.contains("GIGARTINA STE"))
        #expect(!cleaned.contains("ACRYLATES/C1"))
        #expect(!cleaned.contains("MION UMACRY"))
        #expect(!cleaned.contains("EERPRO-COLLAGEN"))
        #expect(!cleaned.contains("DISTURIZEIPM"))
        #expect(!cleaned.contains("MSTURILE A PF"))
        #expect(!cleaned.contains("MOAETERGHEA"))
        #expect(!cleaned.contains("REESABEIN"))
        #expect(!cleaned.contains("LECIH IRMONIU"))
    }

    @Test func rotateLists_prefersWaterLeadingShot() {
        let mid = ["Dimethicone", "Glycerin", "Phenoxyethanol"]
        let start = ["Water", "Dimethicone", "Glycerin"]
        let end = ["Glycerin", "Phenoxyethanol", "Limonene"]
        let rotated = SequentialOverlapMerger.rotateListsToIngredientStart([mid, start, end])
        #expect(rotated.first == start)
        #expect(rotated[1] == end)
        #expect(rotated[2] == mid)
    }
}
