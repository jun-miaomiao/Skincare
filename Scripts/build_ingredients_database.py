#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""下載 TFDA 開放資料並產出 App 相容的 IngredientsDatabase.json。

正確下載參數（政府資料開放平臺）：
  InfoId=199 logType=5  → 化粧品成分使用限制
  InfoId=201 logType=5  → 化粧品防腐劑成分使用限制
  InfoId=202 logType=5  → 化粧品防曬劑成分使用限制
  InfoId=203 logType=5  → 化粧品禁止使用成分
"""

import json
import urllib.request
import re
from pathlib import Path

TFDA_RESTRICTED_URL = (
    "https://data.fda.gov.tw/opendata/exportDataList.do"
    "?method=ExportData&InfoId=199&logType=5"
)
TFDA_PRESERVATIVE_URL = (
    "https://data.fda.gov.tw/opendata/exportDataList.do"
    "?method=ExportData&InfoId=201&logType=5"
)
TFDA_SUNSCREEN_URL = (
    "https://data.fda.gov.tw/opendata/exportDataList.do"
    "?method=ExportData&InfoId=202&logType=5"
)
TFDA_BANNED_URL = (
    "https://data.fda.gov.tw/opendata/exportDataList.do"
    "?method=ExportData&InfoId=203&logType=5"
)

OUTPUT_PATH = Path(__file__).resolve().parent.parent / "Skincare" / "IngredientsDatabase.json"

database = {}


def add_or_update(name_en, name_zh, function, score, aliases=None):
    if not name_en:
        return
    display_en = " ".join(str(name_en).replace("\r", "").split())
    if len(display_en) < 2:
        return
    key = display_en.upper()
    aliases = aliases or []
    if key in database:
        existing = database[key]
        existing["aliases"] = list(dict.fromkeys((existing.get("aliases") or []) + aliases))
        return

    database[key] = {
        "englishName": display_en,
        "chineseName": (name_zh or display_en).strip(),
        "function": function if function else "一般成分",
        "safetyRating": str(int(score)),
        "aliases": aliases,
    }


CORE_BASE_INGREDIENTS = [
    ("Water", "水", "溶劑、基底", 1, ["AQUA", "EAU", "精製水", "정제수", "ウォーター"]),
    ("Glycerin", "甘油", "保濕劑、溶劑", 1, ["GLYCEROL", "グリセリン", "글리세린"]),
    ("Butylene Glycol", "丁二醇", "保濕劑、溶劑", 1, ["1,3-BUTANEDIOL", "BG", "부틸렌글라이콜"]),
    ("Propanediol", "1,3-丙二醇", "保濕劑、溶劑", 1, ["프로판다이올"]),
    ("Niacinamide", "菸鹼醯胺（維生素 B3）", "美白、抗老化、控油", 1, ["NICOTINAMIDE", "나이아신아마이드", "ナイアシンアミド"]),
    ("Dimethicone", "矽靈（聚二甲基矽氧烷）", "柔潤劑、滑順劑", 1, ["다이메티콘", "ジメチコン", "矽靈"]),
    ("Cyclopentasiloxane", "環戊矽氧烷（揮發矽靈）", "滑順劑、溶劑", 3, ["D5"]),
    ("Sodium Hyaluronate", "玻尿酸鈉", "強效保濕劑", 1, ["HYALURONIC ACID SODIUM", "소듐하이알루로네이트", "ヒアルロン酸Na"]),
    ("Hyaluronic Acid", "玻尿酸／透明質酸", "保濕、鎖水", 1, ["ヒアルロン酸", "히알루론산", "透明質酸", "玻尿酸"]),
    ("Allantoin", "尿囊素", "舒緩、抗刺激", 1, ["알란토인"]),
    ("Panthenol", "泛醇（維生素 B5）", "修護、保濕", 1, ["PROVITAMIN B5", "판테놀", "パンテノール"]),
    ("Tocopherol", "生育酚（維生素 E）", "抗氧化劑", 1, ["VITAMIN E", "토코페롤", "トコフェロール", "維生素E"]),
    ("Xanthan Gum", "黃原膠（三仙膠）", "增稠劑", 1, ["잔탄검"]),
    ("Carbomer", "卡波姆", "增稠懸浮劑", 1, ["카보머"]),
    ("Squalane", "角鯊烷", "柔潤保濕劑", 1, ["스쿠알란", "スクワラン"]),
    ("Caprylic/Capric Triglyceride", "辛酸／癸酸甘油三酯", "清爽柔潤劑", 1, ["카프릴릭/카프릭트라이글리세라이드"]),
    ("Centella Asiatica Extract", "積雪草萃取", "舒緩、修護", 1, ["CICA", "병풀추출물", "ツボクサエキス"]),
    ("Alcohol", "乙醇（酒精）", "溶劑、收斂", 4, ["ALCOHOL DENAT.", "에탄올", "변성알코올", "에탄올", "變性酒精"]),
    ("Alcohol Denat.", "變性酒精", "溶劑、揮發劑", 4, ["變性酒精", "変性アルコール"]),
    ("Phenoxyethanol", "苯氧乙醇", "防腐劑", 4, ["페녹시에탄올", "フェノキシエタノール"]),
    ("Methylparaben", "對羥基苯甲酸甲酯", "Paraben 類防腐劑", 4, ["메틸파라벤"]),
    ("Ethylhexylglycerin", "乙基己基甘油", "防腐助劑、保濕", 2, ["에틸헥실글리세린"]),
    ("Zinc Oxide", "氧化鋅", "物理防曬劑、收斂", 2, ["징크옥사이드", "酸化亜鉛", "ZnO"]),
    ("Titanium Dioxide", "二氧化鈦", "物理防曬劑、增白", 2, ["티타늄디옥사이드", "酸化チタン", "TiO2"]),
    ("Salicylic Acid", "水楊酸", "去角質、控油、抗痘", 4, ["サリチル酸", "살리실산", "BHA"]),
    ("Camellia Oleifera Leaf Extract", "油茶葉萃取／綠茶萃取物", "抗氧化、舒緩", 1, [
        "CAMELLIA OLEIFERA (GREEN TEA) LEAF EXTRACT",
        "GREEN TEA LEAF EXTRACT",
    ]),
    ("Tetrasodium EDTA", "乙二胺四乙酸四鈉", "螯合劑", 1, ["TETRASODIUM EDTA"]),
    ("Methylpropanediol", "甲基丙二醇", "保濕劑", 1, [
        "METHYLPROPANEDIOL",
        "METHYLPROPANELD",
        "METHY|PROPANELD",
    ]),
    ("Sodium Hydroxide", "氫氧化鈉", "pH 調節劑", 3, ["CAUSTIC SODA"]),
    # 雪芙蘭／化學防曬與乳化劑
    ("Diethylamino Hydroxybenzoyl Hexyl Benzoate", "二乙氨羥苯甲醯基苯甲酸己酯", "化學防曬劑／UVA 防護", 2, [
        "DHHB", "UVINUL A PLUS", "UVINUL A+",
    ]),
    ("Methylene Bis-Benzotriazolyl Tetramethylbutylphenol", "亞甲基雙-苯並三唑基四甲基丁基酚", "Tinosorb M 防曬劑", 2, [
        "TINOSORB M", "MBBT",
    ]),
    ("Ethylhexyl Triazone", "乙基己基三嗪酮", "Uvinul T 150 防曬劑", 2, [
        "UVINUL T 150", "UVINUL T150", "EHT",
    ]),
    ("Ethylhexyl Salicylate", "水楊酸乙基己酯", "化學防曬劑／紫外線吸收", 3, [
        "OCTISALATE", "OCTYL SALICYLATE",
    ]),
    ("Diethylhexyl Carbonate", "碳酸二乙基己酯", "清爽潤膚脂", 1, []),
    ("Microcrystalline Cellulose", "微晶纖維素", "吸油抗結塊劑", 1, ["CELLULOSE MICROCRYSTALLINE"]),
    ("Caprylyl Methicone", "辛基聚甲基矽氧烷", "絲滑矽油", 1, []),
    ("Glycereth-26", "甘油醇-26", "保濕劑", 1, ["GLYCERETH 26"]),
    ("BIS-PEG/PPG-20/5 PEG/PPG-20/5 Dimethicone", "雙-PEG/PPG-20/5 PEG/PPG-20/5 聚二甲基矽氧烷", "乳化劑", 1, [
        "BIS-PEG PPG-20/5 PEG PPG-20/5 DIMETHICONE",
    ]),
    ("Methoxy PEG/PPG-25/4 Dimethicone", "甲氧基 PEG/PPG-25/4 聚二甲基矽氧烷", "乳化劑", 1, [
        "METHOXY PEG PPG-25/4 DIMETHICONE",
    ]),
    ("Decyl Glucoside", "癸基葡糖苷", "溫和界面活性劑", 1, [
        "DECIDE GLUCOSIDE", "DECYLGLUCOSIDE",
    ]),
    ("Sodium Potassium Aluminum Silicate", "矽酸鋁鉀鈉", "礦物粉體／柔焦劑", 1, [
        "SODIUM POTASSIUM ALUMINIUM SILICATE",
    ]),
    ("Trisodium Ethylenediamine Disuccinate", "乙二胺二琥珀酸三鈉", "環保螯合劑", 1, [
        "EDDS", "TRISODIUM EDDS",
    ]),
    ("Bis-Ethylhexyl Hydroxydimethoxy Benzylmalonate", "雙-乙基己基羥基二甲氧基苄基丙二酸酯", "抗氧化穩定劑", 1, [
        "RONACARE AP",
    ]),
    ("Glycosphingolipids", "鞘糖脂", "修護屏障保濕劑", 1, ["GLYCOSPHINGOLIPID"]),
    # 蘭芝／口紅護唇膏油脂蠟質色料
    ("Diisostearyl Malate", "蘋果酸二異硬脂酯", "滋潤潤膚脂／唇膏基底", 1, ["DIISOSTEARYL MALATE"]),
    ("Polybutene", "聚丁烯", "增稠劑／成膜光澤劑", 1, ["POLYBUTENE"]),
    ("Microcrystalline Wax", "微晶蠟", "固化成膏劑", 1, [
        "CERA MICROCRISTALLINA",
        "CIRE MICROCRISTALLINE",
        "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA / CIRE MICROCRISTALLINE",
        "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA",
    ]),
    ("Euphorbia Cerifera (Candelilla) Wax", "小燭樹蠟", "植物固化蠟", 1, [
        "CANDELILLA WAX",
        "CANDELILLA CERA",
        "EUPHORBIA CERIFERA WAX",
        "EUPHORBIA CERIFERA (CANDELILLA) WAX / CANDELILLA CERA",
    ]),
    ("Astrocaryum Murumuru Seed Butter", "木魯星果棕脂", "滋養潤唇脂", 1, [
        "MURUMURU SEED BUTTER",
        "ASTROCARYUM MURUMURU BUTTER",
    ]),
    ("Synthetic Wax", "合成蠟", "質地調節劑", 1, ["SYNTHETIC WAX"]),
    ("Candelilla Wax Esters", "小燭樹蠟酯", "保濕軟化劑", 1, ["CANDELILLA WAX ESTERS"]),
    ("Methicone", "聚甲基矽氧烷", "滑順防護劑", 1, ["METHICONE"]),
    ("Polyglyceryl-2 Triisostearate", "聚甘油-2 三異硬脂酸酯", "分散劑／潤唇脂", 1, [
        "POLYGLYCERYL 2 TRIISOSTEARATE",
    ]),
    ("Red 7 Lake (CI 15850)", "紅色 7 號色澱", "化妝品著色劑", 3, [
        "RED 7 LAKE",
        "CI 15850",
        "RED 7",
    ]),
    ("Copernicia Cerifera (Carnauba) Wax", "巴西棕櫚蠟", "植物硬蠟", 1, [
        "CARNAUBA WAX",
        "COPERNICIA CERIFERA WAX",
        "CIRE DE CARNAUBA",
    ]),
    ("Red 6 (CI 15850)", "紅色 6 號", "著色劑", 3, [
        "RED 6",
        "CI 15850:2",
    ]),
    ("Butyrospermum Parkii (Shea) Butter", "乳油木果脂／酪梨樹果脂", "深層滋養", 1, [
        "SHEA BUTTER",
        "BUTYROSPERMUM PARKII BUTTER",
        "BUTYROSPERMUM PARKII",
    ]),
    ("Hydrogenated Polyisobutene", "氫化聚異丁烯", "柔潤成膜／唇膏基底", 1, [
        "HYDROGENATED POLYISOBUTENE",
    ]),
    # 貝膚黛瑪／乳化脂肪醇與穩定劑
    ("Arachidyl Alcohol", "花生醇", "乳化助劑／脂肪醇", 1, ["ARACHIDYL ALCOHOL"]),
    ("Behenyl Alcohol", "山嵛醇", "乳化助劑／脂肪醇", 1, ["BEHENYL ALCOHOL"]),
    ("Coco-Glucoside", "椰油基葡糖苷", "溫和界面活性劑", 1, ["COCO GLUCOSIDE", "COCOGLUCOSIDE"]),
    ("Arachidyl Glucoside", "花生醇葡糖苷", "乳化劑", 1, ["ARACHIDYL GLUCOSIDE"]),
    ("Sodium Polyacryloyldimethyl Taurate", "聚丙烯醯基二甲基牛磺酸鈉", "增稠穩定劑", 1, [
        "SODIUM POLYACRYLOYLDIMETHYL TAURATE",
        "SODIUM POLYACRY- LOYLDIMETHYL TAURATE",
    ]),
    ("Rhamnose", "鼠李糖", "保濕／糖類活性", 1, ["RHAMNOSE", "L-RHAMNOSE"]),
    ("Propyl Gallate", "沒食子酸丙酯", "抗氧化劑", 1, ["PROPYL GALLATE"]),
    ("Di-C12-13 Alkyl Malate", "二-C12-13 烷基蘋果酸酯", "清爽潤膚脂", 1, ["DI-C12-13 ALKYL MALATE"]),
    ("Propylheptyl Caprylate", "丙基庚基辛酸酯", "清爽潤膚脂", 1, ["PROPYLHEPTYL CAPRYLATE"]),
    ("Sodium Metabisulfite", "焦亞硫酸鈉", "抗氧化／還原劑", 3, ["SODIUM METABISULPHITE", "SODIUM METABISULFITE"]),
    # 花王 Curel／日系防曬常見
    ("Cetyl-PG Hydroxyethyl Palmitamide", "鯨蠟基-PG 羥乙基棕櫚醯胺", "花王專利類神經醯胺／屏障修護", 1, [
        "CETYL PG HYDROXYETHYL PALMITAMIDE",
        "CETYL-PG HYDROXYETHYL PALMITAMIDE",
    ]),
    ("Isononyl Isononanoate", "異壬酸異壬酯", "蠶絲油／清爽潤膚脂", 1, ["ISONONYL ISONONANOATE"]),
    ("Isotridecyl Isononanoate", "異壬酸異十三酯", "親膚潤膚劑", 1, ["ISOTRIDECYL ISONONANOATE"]),
    ("Neopentyl Glycol Dicaprate", "新戊二醇二癸酸酯", "潤膚成膜劑", 1, ["NEOPENTYL GLYCOL DICAPRATE"]),
    ("Neopentyl Glycol Diethylhexanoate", "新戊二醇二(乙基己酸)酯", "滑順保濕劑", 1, [
        "NEOPENTYL GLYCOL DIETHYLHEXANOATE",
    ]),
    ("Dipentaerythrityl Tri-Polyhydroxystearate", "二季戊四醇三-多羥基硬脂酸酯", "鎖水保濕脂", 1, [
        "DIPENTAERYTHRITYL TRI POLYHYDROXYSTEARATE",
        "DIPENTAERYTHRITYL TRI-POLYHYDROXYSTEARATE",
    ]),
    ("Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer", "丙烯酸鈉／丙烯醯基二甲基牛磺酸鈉共聚物", "高分子增稠乳化劑", 1, [
        "SODIUM ACRYLATE / SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER",
        "SODIUM ACRYLATE SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER",
    ]),
    ("Sodium Acrylates Copolymer", "丙烯酸鈉共聚物", "增稠成膜劑、親水性高分子增稠劑、乳化穩定劑，賦予清爽滑順質地", 1, [
        "SODIUM ACRYLATES COPOLYMER",
        "SODIUM ACRYLATE COPOLYMER",
        "SODIUM POLYACRYLATE",
        "丙烯酸鈉共聚物",
    ]),
    ("Polyhydroxystearic Acid", "聚羥基硬脂酸", "物理防曬粉體分散劑", 1, ["POLYHYDROXYSTEARIC ACID"]),
    ("Thujopsis Dolabrata Branch Extract", "羅漢柏枝萃取", "舒緩抗敏成分", 1, [
        "THUJOPSIS DOLABRATA EXTRACT",
        "HIBA EXTRACT",
    ]),
    ("Eucalyptus Globulus Leaf Extract", "藍桉葉萃取／尤加利葉萃取", "保濕促進神經醯胺生成", 1, [
        "EUCALYPTUS GLOBULUS EXTRACT",
        "EUCALYPTUS LEAF EXTRACT",
    ]),
    ("Dextrin Palmitate", "棕櫚酸糊精", "凝膠化增稠劑", 1, ["DEXTRIN PALMITATE"]),
    ("Fragrance", "香精", "香氛", 8, ["PARFUM", "香料", "フレグランス", "향료", "FRAGRANCE / PARFUM"]),
    ("Parfum", "香精", "香氛", 8, ["FRAGRANCE", "香料", "FRAGRANCE / PARFUM"]),
    ("Retinol", "視黃醇", "抗老、促進代謝", 6, ["レチノール", "레티놀"]),
    ("PHYTOSTERYL/ISOSTEARYL/CETYL/STEARYL/BEHENYL DIMER DILINOLEATE", "植物甾醇／異硬脂醇／鯨蠟醇／硬脂醇／山萮醇二聚亞油酸酯", "柔潤鎖水", 1, [
        "PHYTOSTERYL ISOSTEARYL CETYL STEARYL BEHENYL DIMER DILINOLEATE",
        "PHYTOSTERYL/ISOSTEARYL/CETYL/STEARYL/BEHENYL DIMER DILINOLEATE",
    ]),
    ("PHYTOSTERYL ISOSTEARYL DIMER DILINOLEATE", "植物甾醇異硬脂醇二聚亞油酸酯", "柔潤鎖水", 1, [
        "PHYTOSTERYL/ISOSTEARYL DIMER DILINOLEATE",
        "PHYTOSTERYL ISOSTEARYL DIMER DILINOLEATE",
        "PHYTOSTERYL-ISOSTEARYL DIMER DILINOLEATE",
    ]),
    ("HYDROGENATED POLY(C6-14 OLEFIN)", "氫化聚(C6-14烯烴)", "柔潤成膜", 1, [
        "HYDROGENATED POLY (C6-14 OLEFIN)",
        "HYDROGENATED POLY C6-14 OLEFIN",
        "HYDROGENATED POLY(C6-14OLEFIN)",
    ]),
    ("ETHYLENE/PROPYLENE/STYRENE COPOLYMER", "乙烯／丙烯／苯乙烯共聚物", "增稠穩定", 1, [
        "ETHYLENE PROPYLENE STYRENE COPOLYMER",
    ]),
    ("BUTYLENE/ETHYLENE/STYRENE COPOLYMER", "丁烯／乙烯／苯乙烯共聚物", "增稠穩定", 1, [
        "BUTYLENE ETHYLENE STYRENE COPOLYMER",
    ]),
    ("TRIDECAPEPTIDE-1", "十三胜肽-1", "修護抗老", 1, ["TRIDECAPEPTIDE-1"]),
    ("OLIGOPEPTIDE-1", "寡胜肽-1", "修護抗老", 1, ["OLIGOPEPTIDE-1", "OLICOPEPTIDE-1"]),
    ("SODIUM PHYTATE", "植酸鈉", "螯合劑", 1, ["SODIUM PHYTATE"]),
    ("CYANOCOBALAMIN", "氰鈷胺（維生素B12）", "舒緩修護", 1, ["CYANOCOBALAMIN", "VITAMIN B12"]),
    ("ACETYL SH-HEXAPEPTIDE-5 AMIDE", "乙醯 SH-六胜肽-5 醯胺", "修護抗老", 1, [
        "ACETYL-SH-HEXAPEPTIDE-5 AMIDE",
        "ACETYL SH HEXAPEPTIDE-5 AMIDE",
    ]),
    ("AMMONIUM ACRYLOYLDIMETHYLTAURATE/VP COPOLYMER", "丙烯醯二甲基牛磺酸銨／VP 共聚物", "增稠穩定", 1, [
        "AMMONIUM ACRYLOYLDIMETHYLTAURATE / VP COPOLYMER",
        "AMMONIUM ACRYLOYLDIMETHYLTAURATE",
        "AMMONIUM ACRYLO",
    ]),
    ("GIGARTINA STELLATA EXTRACT", "星芒杉藻萃取", "保濕舒緩", 1, ["GIGARTINA STELLATA EXTRACT"]),
    ("Beeswax", "蜂蠟", "增稠乳化、成膜", 1, ["CERA ALBA", "BEES WAX", "BEESWAX", "CERAALBA", "CERA BLANCA"]),
    ("Lanolin", "羊毛脂", "柔潤修護", 1, ["LANOLINE"]),
    ("Cannabis Sativa Seed Oil", "大麻籽油", "舒緩滋養油", 1, ["HEMP SEED OIL", "CANNABIS SATIVA OIL", "CANNABIS SATIVA SEED OIL"]),
    ("Helianthus Annuus Seed Oil", "向日葵籽油", "植物柔潤油", 1, [
        "HELIANTHUS ANNUUS (SUNFLOWER) SEED OIL",
        "SUNFLOWER SEED OIL",
        "SUNFLOWER OIL",
    ]),
    ("Cocos Nucifera Oil", "椰子油", "柔潤滋養", 1, [
        "COCOS NUCIFERA (COCONUT) OIL",
        "COCONUT OIL",
        "COCOS NUCIFERA OIL",
    ]),
    ("Ricinus Communis Seed Oil", "蓖麻籽油", "滋潤成膜油", 1, [
        "RICINUS COMMUNIS (CASTOR) SEED OIL",
        "CASTOR SEED OIL",
        "CASTOR OIL",
    ]),
    ("Glycine Soja Oil", "大豆油", "柔潤", 1, ["GLYCINE SOJA (SOYBEAN) OIL", "SOYBEAN OIL", "GLYCINE MAX OIL"]),
    ("Rosmarinus Officinalis Leaf Extract", "迷迭香葉萃取", "抗氧化", 1, [
        "ROSMARINUS OFFICINALIS (ROSEMARY) LEAF EXTRACT",
        "ROSEMARY LEAF EXTRACT",
        "ROSMARINUS OFFICINALIS EXTRACT",
    ]),
    ("Canola Oil", "芥花油", "柔潤", 1, ["BRASSICA CAMPESTRIS OIL", "RAPESEED OIL", "BRASSICA NAPUS OIL"]),
    ("Rebaudioside A", "甜菊糖苷", "天然甜味劑", 1, ["REBAUDIOSIDE", "STEVIOL GLYCOSIDE", "STEVIA"]),
    ("Citronellol", "香精", "過敏原", 5, ["CITRONELLOL"]),
    ("Eugenol", "香精", "過敏原", 5, ["EUGENOL"]),
    ("Geraniol", "香精", "香氛", 5, ["GERANIOL"]),
    ("Limonene", "香精", "過敏原", 5, ["LIMONENE", "D-LIMONENE"]),
    ("Linalool", "香精", "過敏原", 5, ["LINALOOL"]),
    ("Flavor", "香精", "調味香氛", 4, ["FLAVOUR", "NATURAL FLAVOR", "NATURAL FLAVOUR", "AROMA"]),
    ("Fragrance", "香精", "香氛", 8, ["PARFUM", "香料", "フレグランス", "향료", "FRAGRANCE / PARFUM"]),
    ("Lycium Chinense Fruit Extract", "枸杞果萃取", "抗氧化修護", 1, ["LYCIUM CHINENSE EXTRACT", "GOJI FRUIT EXTRACT"]),
    ("Coffea Arabica (Coffee) Seed Extract", "咖啡籽萃取", "抗氧化", 1, ["COFFEA ARABICA SEED EXTRACT", "COFFEE SEED EXTRACT"]),
    ("Fragaria Chiloensis (Strawberry) Fruit Extract", "草莓果萃取", "抗氧化保濕", 1, [
        "FRAGARIA CHILOENSIS FRUIT EXTRACT",
        "STRAWBERRY FRUIT EXTRACT",
    ]),
    ("Vaccinium Macrocarpon (Cranberry) Fruit Extract", "蔓越莓果萃取", "抗氧化", 1, [
        "VACCINIUM MACROCARPON FRUIT EXTRACT",
        "CRANBERRY FRUIT EXTRACT",
    ]),
    ("Rubus Idaeus (Raspberry) Fruit Extract", "覆盆子果萃取", "抗氧化", 1, [
        "RUBUS IDAEUS FRUIT EXTRACT",
        "RASPBERRY FRUIT EXTRACT",
    ]),
    ("Pentaerythrityl Tetra-Di-T-Butyl Hydroxyhydrocinnamate", "四(二-叔丁基羥基氫化肉桂酸)季戊四醇酯", "抗氧化穩定劑", 1, [
        "PENTAERYTHRITYL TETRA DI T BUTYL HYDROXYHYDROCINNAMATE",
        "PENTAERYTHRITYL TETRA-DI-T-BUTYL HYDROXYHYDROCINNAMATE",
        "Pentaerythrityl Tetra-di-t-butyl Hydroxyhydrocinnamate",
        "Tinogard TT",
        "TINOGARD TT",
    ]),
    ("Rubus Chamaemorus Seed Extract", "雲莓籽萃取", "抗氧化調理劑", 1, [
        "CLOUDBERRY SEED EXTRACT",
        "RUBUS CHAMAEMORUS EXTRACT",
        "RUBUS CHAMAEMORUS SEED EXTRACT",
    ]),
    ("Sapindus Mukorossi Fruit Extract", "無患子果萃取", "天然清潔／調理劑", 1, [
        "SAPINDUS MUKOROSSI EXTRACT",
        "SOAPNUT EXTRACT",
        "SAPINDUS MUKOROSSI FRUIT EXTRACT",
    ]),
    ("Vaccinium Angustifolium (Blueberry) Fruit Extract", "藍莓果萃取", "抗氧化劑", 1, [
        "VACCINIUM ANGUSTIFOLIUM FRUIT EXTRACT",
        "BLUEBERRY FRUIT EXTRACT",
        "VACCINIUM ANGUSTIFOLIUM (BLUEBERRY) FRUIT EXTRACT",
    ]),
]

# Ensure acrylates OCR stubs stay on the C10-30 crosspolymer entry when rebuilt.
add_or_update(
    "Acrylates/C10-30 Alkyl Acrylate Crosspolymer",
    "丙烯酸酯／C10-30 烷基丙烯酸酯交聯聚合物",
    "增稠成膜",
    1,
    [
        "ACRYLATESIC10-30",
        "UNLIC ATE CROSSPOLYMER",
        "UNLIC ATE CROSSPO",
        "ALKYL ACRYLATE CROSSPOLYMER",
        "ACRYLATE CROSSPOLYMER",
    ],
)

for item in CORE_BASE_INGREDIENTS:
    add_or_update(item[0], item[1], item[2], item[3], item[4])

headers = {"User-Agent": "Mozilla/5.0 (compatible; SkincareIngredientDB/1.0)"}


def fetch_json(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_and_parse_tfda(url, default_func, default_score):
    data = fetch_json(url)
    if not isinstance(data, list):
        raise ValueError(f"Unexpected payload type: {type(data)}")

    for row in data:
        if not isinstance(row, dict):
            continue
        name_en = (
            row.get("INCI名")
            or row.get("成分英文名稱")
            or row.get("INCI_NAME")
            or row.get("英文名稱")
        )
        name_zh = (
            row.get("成分名")
            or row.get("成分中文名稱")
            or row.get("INGREDIENTS_NAME")
            or row.get("中文名稱")
            or row.get("成分名稱")
        )
        if not name_en:
            name_en = row.get("成分名稱") or row.get("成分名")
        if not name_en:
            continue

        for n in re.split(r"[/\n;,]", str(name_en)):
            clean_n = re.sub(r"\(\d+\)", "", n).strip()
            if len(clean_n) > 2:
                aliases = []
                if name_zh and str(name_zh).strip().upper() != clean_n.upper():
                    aliases.append(str(name_zh).strip())
                add_or_update(clean_n, name_zh, default_func, default_score, aliases)
    print(f"成功處理 TFDA 資料集，目前累積成分數: {len(database)}")


print("正在取得 TFDA 官方資料...")
for url, func, score in [
    (TFDA_RESTRICTED_URL, "特定用途／限量管制成分", 4),
    (TFDA_PRESERVATIVE_URL, "法定防腐劑", 4),
    (TFDA_SUNSCREEN_URL, "防曬劑", 3),
    (TFDA_BANNED_URL, "禁止使用成分", 9),
]:
    try:
        fetch_and_parse_tfda(url, func, score)
    except Exception as e:
        print(f"下載失敗 ({func}): {e}")

cosing_path = Path(__file__).resolve().parent / "cosing_common_ingredients.json"
if cosing_path.exists():
    before = len(database)
    for row in json.loads(cosing_path.read_text(encoding="utf-8")):
        add_or_update(row[0], row[1], row[2], row[3], row[4] if len(row) > 4 else [])
    print(f"已合併 CosIng 常用原料（+{len(database) - before}），累計 {len(database)}")

output_list = sorted(database.values(), key=lambda x: x["englishName"].lower())
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
    json.dump(output_list, f, ensure_ascii=False, indent=2)

print(f"已完成！共產出 {len(output_list)} 筆成分資料")
print(f"已儲存至 {OUTPUT_PATH}")
