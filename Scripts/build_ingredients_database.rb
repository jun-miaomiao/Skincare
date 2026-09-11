#!/usr/bin/env ruby
# frozen_string_literal: true
# 合併核心基底成分與 TFDA 開放資料，產出 App 相容 IngredientsDatabase.json

require "json"
require "open-uri"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "Skincare", "IngredientsDatabase.json")

DATABASE = {}

def record_payload(display_en, zh, function, score, aliases)
  func = (function.nil? || function.to_s.strip.empty?) ? "一般成分" : function.to_s.strip
  {
    # App 既有欄位
    "englishName" => display_en,
    "chineseName" => zh,
    "function" => func,
    "safetyRating" => score.to_i.to_s,
    "aliases" => aliases,
    # 規格別名（name＝英文 INCI，category＝功能分類）
    "name" => display_en,
    "category" => func
  }
end

def add_or_update(name_en, name_zh, function, score, aliases = [])
  return if name_en.nil?
  display_en = name_en.to_s.gsub(/\r/, "").strip.gsub(/\s+/, " ")
  return if display_en.empty? || display_en.length < 2

  key = display_en.upcase
  aliases = Array(aliases).map { |a| a.to_s.strip }.reject(&:empty?)

  if DATABASE.key?(key)
    existing = DATABASE[key]
    existing["aliases"] = (existing["aliases"] + aliases).uniq
    return
  end

  zh = name_zh.to_s.gsub(/\r/, "").strip
  zh = display_en if zh.empty?

  DATABASE[key] = record_payload(display_en, zh, function, score, aliases)
end

# 強制覆寫中文／功能／評級（手邊產品必備條目不得被 TFDA 佔位英文名覆蓋）
def force_upsert(name_en, name_zh, function, score, aliases = [])
  return if name_en.nil?
  display_en = name_en.to_s.gsub(/\r/, "").strip.gsub(/\s+/, " ")
  return if display_en.empty?

  key = display_en.upcase
  aliases = Array(aliases).map { |a| a.to_s.strip }.reject(&:empty?)
  zh = name_zh.to_s.gsub(/\r/, "").strip
  zh = display_en if zh.empty?

  if DATABASE.key?(key)
    existing = DATABASE[key]
    existing["englishName"] = display_en
    existing["name"] = display_en
    existing["chineseName"] = zh
    existing["function"] = function.to_s.strip.empty? ? existing["function"] : function.to_s.strip
    existing["category"] = existing["function"]
    existing["safetyRating"] = score.to_i.to_s
    existing["aliases"] = (existing["aliases"] + aliases).uniq
  else
    DATABASE[key] = record_payload(display_en, zh, function, score, aliases)
  end
end

CORE_BASE_INGREDIENTS = [
  ["Water", "水", "溶劑、基底", 1, %w[AQUA EAU 精製水 정제수 ウォーター]],
  ["Glycerin", "甘油", "保濕劑、溶劑", 1, %w[GLYCEROL グリセリン 글리세린]],
  ["Butylene Glycol", "丁二醇", "保濕劑、溶劑", 1, ["1,3-BUTANEDIOL", "BG", "부틸렌글라이콜"]],
  ["Propanediol", "1,3-丙二醇", "保濕劑、溶劑", 1, %w[프로판다이올]],
  ["Niacinamide", "菸鹼醯胺（維生素 B3）", "美白、抗老化、控油", 1, %w[NICOTINAMIDE 나이아신아마이드 ナイアシンアミド]],
  ["Dimethicone", "矽靈（聚二甲基矽氧烷）", "柔潤劑、滑順劑", 1, %w[다이메티콘 ジメチコン 矽靈]],
  ["Cyclopentasiloxane", "環戊矽氧烷（揮發矽靈）", "滑順劑、溶劑", 3, %w[D5]],
  ["Sodium Hyaluronate", "玻尿酸鈉", "強效保濕劑", 1, ["HYALURONIC ACID SODIUM", "소듐하이알루로네이트", "ヒアルロン酸Na"]],
  ["Hyaluronic Acid", "玻尿酸／透明質酸", "保濕、鎖水", 1, %w[ヒアルロン酸 히알루론산 透明質酸 玻尿酸]],
  ["Allantoin", "尿囊素", "舒緩、抗刺激", 1, %w[알란토인]],
  ["Panthenol", "泛醇（維生素 B5）", "修護、保濕", 1, %w[PROVITAMIN\ B5 판테놀 パンテノール]],
  ["Tocopherol", "生育酚（維生素 E）", "抗氧化劑", 1, %w[VITAMIN\ E 토코페롤 トコフェロール 維生素E]],
  ["Xanthan Gum", "黃原膠（三仙膠）", "增稠劑", 1, %w[잔탄검]],
  ["Carbomer", "卡波姆", "增稠懸浮劑", 1, %w[카보머]],
  ["Squalane", "角鯊烷", "柔潤保濕劑", 1, %w[스쿠알란 スクワラン]],
  ["Caprylic/Capric Triglyceride", "辛酸／癸酸甘油三酯", "清爽柔潤劑", 1, ["카프릴릭/카프릭트라이글리세라이드"]],
  ["Centella Asiatica Extract", "積雪草萃取", "舒緩、修護", 1, %w[CICA 병풀추출물 ツボクサエキス]],
  ["Alcohol", "乙醇（酒精）", "溶劑、收斂", 4, %w[ALCOHOL\ DENAT. エタノール 변성알코올 에탄올 變性酒精]],
  ["Alcohol Denat.", "變性酒精", "溶劑、揮發劑", 4, %w[變性酒精 変性アルコール]],
  ["Phenoxyethanol", "苯氧乙醇", "防腐劑", 4, %w[페녹시에탄올 フェノキシエタノール]],
  ["Methylparaben", "對羥基苯甲酸甲酯", "Paraben 類防腐劑", 4, %w[메틸파라벤]],
  ["Ethylhexylglycerin", "乙基己基甘油", "防腐助劑、保濕", 2, %w[에틸헥실글리세린]],
  ["Zinc Oxide", "氧化鋅", "物理防曬劑、收斂", 2, %w[징크옥사이드 酸化亜鉛 ZnO]],
  ["Titanium Dioxide", "二氧化鈦", "物理防曬劑、增白", 2, %w[티타늄디옥사이드 酸化チタン TiO2]],
  ["Talc", "滑石粉", "柔滑劑", 2, %w[TALC]],
  ["Trisiloxane", "三矽氧烷", "揮發性溶劑", 1, %w[TRISILOXANE]],
  ["Aluminum Hydroxide", "氫氧化鋁", "防曬包覆劑、增稠", 1, %w[ALUMINUM HYDROXIDE]],
  ["Disteardimonium Hectorite", "二硬脂二甲銨鋰蒙脫石", "增稠穩定劑", 1, %w[DISTEARDIMONIUM HECTORITE]],
  ["BHT", "二丁基羥基甲苯", "抗氧化劑", 4, %w[BHT]],
  ["Trisodium EDTA", "乙二胺四乙酸三鈉", "螯合劑", 1, %w[TRISODIUM\ EDTA]],
  # 日系防曬 / 底妝核心
  ["Ethylhexyl Methoxycinnamate", "甲氧基肉桂酸乙基己酯", "化學防曬劑", 6, %w[OCTINOXATE METHOXYCINNAMATE]],
  ["C12-15 Alkyl Benzoate", "C12-15 醇苯甲酸酯", "柔潤劑、清爽溶劑", 1, ["C12-15 ALKYL BENZOATE"]],
  ["Tranexamic Acid", "傳明酸（氨甲環酸）", "衛福部核准美白成分", 1, %w[TRANEXAMIC\ ACID]],
  ["Triisostearin", "三異硬脂酸甘油酯", "柔潤劑", 1, %w[TRIISOSTEARIN]],
  ["Sorbitan Sesquiisostearate", "山梨醇倍半異硬脂酸酯", "乳化劑", 1, %w[SORBITAN\ SESQUIISOSTEARATE]],
  ["Phytosteryl Macadamiate", "澳洲堅果油酸植物甾醇酯", "修護、保濕", 1, %w[PHYTOSTERYL\ MACADAMIATE]],
  ["PHYTOSTERYL/ISOSTEARYL/CETYL/STEARYL/BEHENYL DIMER DILINOLEATE", "植物甾醇／異硬脂醇／鯨蠟醇／硬脂醇／山萮醇二聚亞油酸酯", "柔潤鎖水", 1, ["PHYTOSTERYL ISOSTEARYL CETYL STEARYL BEHENYL DIMER DILINOLEATE", "PHYTOSTERYL/ISOSTEARYL/CETYL/STEARYL/BEHENYL DIMER DILINOLEATE"]],
  ["PHYTOSTERYL ISOSTEARYL DIMER DILINOLEATE", "植物甾醇異硬脂醇二聚亞油酸酯", "柔潤鎖水", 1, ["PHYTOSTERYL/ISOSTEARYL DIMER DILINOLEATE", "PHYTOSTERYL ISOSTEARYL DIMER DILINOLEATE", "PHYTOSTERYL-ISOSTEARYL DIMER DILINOLEATE"]],
  ["HYDROGENATED POLY(C6-14 OLEFIN)", "氫化聚(C6-14烯烴)", "柔潤成膜", 1, ["HYDROGENATED POLY (C6-14 OLEFIN)", "HYDROGENATED POLY C6-14 OLEFIN", "HYDROGENATED POLY(C6-14OLEFIN)"]],
  ["ETHYLENE/PROPYLENE/STYRENE COPOLYMER", "乙烯／丙烯／苯乙烯共聚物", "增稠穩定", 1, ["ETHYLENE PROPYLENE STYRENE COPOLYMER"]],
  ["BUTYLENE/ETHYLENE/STYRENE COPOLYMER", "丁烯／乙烯／苯乙烯共聚物", "增稠穩定", 1, ["BUTYLENE ETHYLENE STYRENE COPOLYMER"]],
  ["TRIDECAPEPTIDE-1", "十三胜肽-1", "修護抗老", 1, %w[TRIDECAPEPTIDE-1]],
  ["OLIGOPEPTIDE-1", "寡胜肽-1", "修護抗老", 1, %w[OLIGOPEPTIDE-1 OLICOPEPTIDE-1]],
  ["SODIUM PHYTATE", "植酸鈉", "螯合劑", 1, %w[SODIUM\ PHYTATE]],
  ["CYANOCOBALAMIN", "氰鈷胺（維生素B12）", "舒緩修護", 1, %w[CYANOCOBALAMIN VITAMIN\ B12]],
  ["ACETYL SH-HEXAPEPTIDE-5 AMIDE", "乙醯 SH-六胜肽-5 醯胺", "修護抗老", 1, ["ACETYL-SH-HEXAPEPTIDE-5 AMIDE", "ACETYL SH HEXAPEPTIDE-5 AMIDE"]],
  ["AMMONIUM ACRYLOYLDIMETHYLTAURATE/VP COPOLYMER", "丙烯醯二甲基牛磺酸銨／VP 共聚物", "增稠穩定", 1, ["AMMONIUM ACRYLOYLDIMETHYLTAURATE / VP COPOLYMER", "AMMONIUM ACRYLOYLDIMETHYLTAURATE", "AMMONIUM ACRYLO"]],
  ["GIGARTINA STELLATA EXTRACT", "星芒杉藻萃取", "保濕舒緩", 1, %w[GIGARTINA\ STELLATA\ EXTRACT]],
  ["PYRUS MALUS (APPLE) FRUIT EXTRACT", "蘋果果萃取", "保濕抗氧化", 1, ["PYRUS MALUS FRUIT EXTRACT", "PYRUS MALISI", "APPLE FRUIT EXTRACT"]],
  ["Acrylates/C10-30 Alkyl Acrylate Crosspolymer", "丙烯酸酯／C10-30 烷基丙烯酸酯交聯聚合物", "增稠成膜", 1, ["ACRYLATESIC10-30", "UNLIC ATE CROSSPOLYMER", "UNLIC ATE CROSSPO", "ALKYL ACRYLATE CROSSPOLYMER", "ACRYLATE CROSSPOLYMER"]],
  ["PPG-17", "聚丙二醇-17", "保濕劑、溶劑", 1, %w[PPG-17]],
  ["Hydrated Silica", "水合二氧化矽", "吸油粉體、抗結塊", 1, %w[HYDRATED\ SILICA]],
  ["Hydrogen Dimethicone", "含氫矽油", "粉體表面處理劑", 1, %w[HYDROGEN\ DIMETHICONE]],
  ["Rosa Roxburghii Fruit Extract", "刺梨果萃取", "抗氧化劑", 1, %w[ROSA\ ROXBURGHII\ FRUIT\ EXTRACT]],
  ["Rubus Idaeus Fruit Extract", "覆盆子果萃取", "抗氧化劑", 1, ["RUBUS IDAEUS (RASPBERRY) FRUIT EXTRACT"]],
  ["Potentilla Recta Root Extract", "委陵菜根萃取", "舒緩抗老", 1, %w[POTENTILLA\ RECTA\ ROOT\ EXTRACT]],
  # 重複補強（確保 TFDA 禁止清單未覆蓋時仍可命中）
  ["Aluminum Hydroxide", "氫氧化鋁", "防曬粉體包覆劑", 1, %w[ALUMINUM\ HYDROXIDE]],
  ["Disteardimonium Hectorite", "二硬脂二甲銨鋰蒙脫石", "增稠懸浮劑", 1, %w[DISTEARDIMONIUM\ HECTORITE]],
  ["Salicylic Acid", "水楊酸", "去角質、控油、抗痘", 4, %w[サリチル酸 살리실산 BHA]],
  ["Camellia Oleifera Leaf Extract", "油茶葉萃取／綠茶萃取物", "抗氧化、舒緩", 1, ["CAMELLIA OLEIFERA (GREEN TEA) LEAF EXTRACT", "GREEN TEA LEAF EXTRACT"]],
  ["Tetrasodium EDTA", "乙二胺四乙酸四鈉", "螯合劑", 1, ["TETRASODIUM EDTA"]],
  ["Methylpropanediol", "甲基丙二醇", "保濕劑", 1, ["METHYLPROPANEDIOL", "METHYLPROPANELD", "METHY|PROPANELD"]],
  ["Sodium Hydroxide", "氫氧化鈉", "pH 調節劑", 3, ["CAUSTIC SODA"]],
  # 雪芙蘭／化學防曬與乳化劑
  ["Diethylamino Hydroxybenzoyl Hexyl Benzoate", "二乙氨羥苯甲醯基苯甲酸己酯", "化學防曬劑／UVA 防護", 2, ["DHHB", "UVINUL A PLUS", "UVINUL A+"]],
  ["Methylene Bis-Benzotriazolyl Tetramethylbutylphenol", "亞甲基雙-苯並三唑基四甲基丁基酚", "Tinosorb M 防曬劑", 2, ["TINOSORB M", "MBBT"]],
  ["Ethylhexyl Triazone", "乙基己基三嗪酮", "Uvinul T 150 防曬劑", 2, ["UVINUL T 150", "UVINUL T150", "EHT"]],
  ["Ethylhexyl Salicylate", "水楊酸乙基己酯", "化學防曬劑／紫外線吸收", 3, ["OCTISALATE", "OCTYL SALICYLATE"]],
  ["Diethylhexyl Carbonate", "碳酸二乙基己酯", "清爽潤膚脂", 1, []],
  ["Microcrystalline Cellulose", "微晶纖維素", "吸油抗結塊劑", 1, ["CELLULOSE MICROCRYSTALLINE"]],
  ["Caprylyl Methicone", "辛基聚甲基矽氧烷", "絲滑矽油", 1, []],
  ["Glycereth-26", "甘油醇-26", "保濕劑", 1, ["GLYCERETH 26"]],
  ["BIS-PEG/PPG-20/5 PEG/PPG-20/5 Dimethicone", "雙-PEG/PPG-20/5 PEG/PPG-20/5 聚二甲基矽氧烷", "乳化劑", 1, ["BIS-PEG PPG-20/5 PEG PPG-20/5 DIMETHICONE"]],
  ["Methoxy PEG/PPG-25/4 Dimethicone", "甲氧基 PEG/PPG-25/4 聚二甲基矽氧烷", "乳化劑", 1, ["METHOXY PEG PPG-25/4 DIMETHICONE"]],
  ["Decyl Glucoside", "癸基葡糖苷", "溫和界面活性劑", 1, ["DECIDE GLUCOSIDE", "DECYLGLUCOSIDE"]],
  ["Sodium Potassium Aluminum Silicate", "矽酸鋁鉀鈉", "礦物粉體／柔焦劑", 1, ["SODIUM POTASSIUM ALUMINIUM SILICATE"]],
  ["Trisodium Ethylenediamine Disuccinate", "乙二胺二琥珀酸三鈉", "環保螯合劑", 1, ["EDDS", "TRISODIUM EDDS"]],
  ["Bis-Ethylhexyl Hydroxydimethoxy Benzylmalonate", "雙-乙基己基羥基二甲氧基苄基丙二酸酯", "抗氧化穩定劑", 1, ["RONACARE AP"]],
  ["Glycosphingolipids", "鞘糖脂", "修護屏障保濕劑", 1, ["GLYCOSPHINGOLIPID"]],
  # 蘭芝／口紅護唇膏油脂蠟質色料
  ["Diisostearyl Malate", "蘋果酸二異硬脂酯", "滋潤潤膚脂／唇膏基底", 1, ["DIISOSTEARYL MALATE"]],
  ["Polybutene", "聚丁烯", "增稠劑／成膜光澤劑", 1, ["POLYBUTENE"]],
  ["Microcrystalline Wax", "微晶蠟", "固化成膏劑", 1, ["CERA MICROCRISTALLINA", "CIRE MICROCRISTALLINE", "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA / CIRE MICROCRISTALLINE", "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA"]],
  ["Euphorbia Cerifera (Candelilla) Wax", "小燭樹蠟", "植物固化蠟", 1, ["CANDELILLA WAX", "CANDELILLA CERA", "EUPHORBIA CERIFERA WAX", "EUPHORBIA CERIFERA (CANDELILLA) WAX / CANDELILLA CERA"]],
  ["Astrocaryum Murumuru Seed Butter", "木魯星果棕脂", "滋養潤唇脂", 1, ["MURUMURU SEED BUTTER", "ASTROCARYUM MURUMURU BUTTER"]],
  ["Synthetic Wax", "合成蠟", "質地調節劑", 1, ["SYNTHETIC WAX"]],
  ["Candelilla Wax Esters", "小燭樹蠟酯", "保濕軟化劑", 1, ["CANDELILLA WAX ESTERS"]],
  ["Methicone", "聚甲基矽氧烷", "滑順防護劑", 1, ["METHICONE"]],
  ["Polyglyceryl-2 Triisostearate", "聚甘油-2 三異硬脂酸酯", "分散劑／潤唇脂", 1, ["POLYGLYCERYL 2 TRIISOSTEARATE"]],
  ["Red 7 Lake (CI 15850)", "紅色 7 號色澱", "化妝品著色劑", 3, ["RED 7 LAKE", "CI 15850", "RED 7"]],
  ["Copernicia Cerifera (Carnauba) Wax", "巴西棕櫚蠟", "植物硬蠟", 1, ["CARNAUBA WAX", "COPERNICIA CERIFERA WAX", "CIRE DE CARNAUBA"]],
  ["Red 6 (CI 15850)", "紅色 6 號", "著色劑", 3, ["RED 6", "CI 15850:2"]],
  ["Butyrospermum Parkii (Shea) Butter", "乳油木果脂", "深層滋養", 1, ["SHEA BUTTER", "BUTYROSPERMUM PARKII BUTTER", "BUTYROSPERMUM PARKII"]],
  ["Hydrogenated Polyisobutene", "氫化聚異丁烯", "柔潤成膜／唇膏基底", 1, ["HYDROGENATED POLYISOBUTENE"]],
  # 貝膚黛瑪／乳化脂肪醇與穩定劑
  ["Arachidyl Alcohol", "花生醇", "乳化助劑／脂肪醇", 1, ["ARACHIDYL ALCOHOL"]],
  ["Behenyl Alcohol", "山嵛醇", "乳化助劑／脂肪醇", 1, ["BEHENYL ALCOHOL"]],
  ["Coco-Glucoside", "椰油基葡糖苷", "溫和界面活性劑", 1, ["COCO GLUCOSIDE", "COCOGLUCOSIDE"]],
  ["Arachidyl Glucoside", "花生醇葡糖苷", "乳化劑", 1, ["ARACHIDYL GLUCOSIDE"]],
  ["Sodium Polyacryloyldimethyl Taurate", "聚丙烯醯基二甲基牛磺酸鈉", "增稠穩定劑", 1, ["SODIUM POLYACRYLOYLDIMETHYL TAURATE"]],
  ["Rhamnose", "鼠李糖", "保濕／糖類活性", 1, ["RHAMNOSE", "L-RHAMNOSE"]],
  ["Propyl Gallate", "沒食子酸丙酯", "抗氧化劑", 1, ["PROPYL GALLATE"]],
  ["Di-C12-13 Alkyl Malate", "二-C12-13 烷基蘋果酸酯", "清爽潤膚脂", 1, ["DI-C12-13 ALKYL MALATE"]],
  ["Propylheptyl Caprylate", "丙基庚基辛酸酯", "清爽潤膚脂", 1, ["PROPYLHEPTYL CAPRYLATE"]],
  ["Sodium Metabisulfite", "焦亞硫酸鈉", "抗氧化／還原劑", 3, ["SODIUM METABISULPHITE", "SODIUM METABISULFITE"]],
  # 花王 Curel／日系防曬常見
  ["Cetyl-PG Hydroxyethyl Palmitamide", "鯨蠟基-PG 羥乙基棕櫚醯胺（花王專利類神經醯胺）", "花王專利類神經醯胺／屏障修護", 1, ["CETYL PG HYDROXYETHYL PALMITAMIDE", "CETYL-PG HYDROXYETHYL PALMITAMIDE"]],
  ["Isononyl Isononanoate", "異壬酸異壬酯（蠶絲油）", "蠶絲油／清爽潤膚脂", 1, ["ISONONYL ISONONANOATE"]],
  ["Isotridecyl Isononanoate", "異壬酸異十三酯", "親膚潤膚劑", 1, ["ISOTRIDECYL ISONONANOATE"]],
  ["Neopentyl Glycol Dicaprate", "新戊二醇二癸酸酯", "潤膚成膜劑", 1, ["NEOPENTYL GLYCOL DICAPRATE"]],
  ["Neopentyl Glycol Diethylhexanoate", "新戊二醇二(乙基己酸)酯", "滑順保濕劑", 1, ["NEOPENTYL GLYCOL DIETHYLHEXANOATE"]],
  ["Dipentaerythrityl Tri-Polyhydroxystearate", "二季戊四醇三-多羥基硬脂酸酯", "鎖水保濕脂", 1, ["DIPENTAERYTHRITYL TRI POLYHYDROXYSTEARATE", "DIPENTAERYTHRITYL TRI-POLYHYDROXYSTEARATE"]],
  ["Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer", "丙烯酸鈉/丙烯醯基二甲基牛磺酸鈉共聚物", "高分子增稠乳化劑", 1, ["SODIUM ACRYLATE / SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER", "SODIUM ACRYLATE SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER"]],
  ["Polyhydroxystearic Acid", "聚羥基硬脂酸", "物理防曬粉體分散劑", 1, ["POLYHYDROXYSTEARIC ACID"]],
  ["Thujopsis Dolabrata Branch Extract", "羅漢柏枝萃取", "舒緩抗敏成分", 1, ["THUJOPSIS DOLABRATA EXTRACT", "HIBA EXTRACT"]],
  ["Eucalyptus Globulus Leaf Extract", "藍桉葉萃取", "保濕促進神經醯胺生成", 1, ["EUCALYPTUS GLOBULUS EXTRACT", "EUCALYPTUS LEAF EXTRACT"]],
  ["Dextrin Palmitate", "棕櫚酸糊精", "凝膠化增稠劑", 1, ["DEXTRIN PALMITATE"]],
  ["Fragrance", "香精", "香氛", 8, ["PARFUM", "香料", "フレグランス", "향료", "FRAGRANCE / PARFUM"]],
  ["Parfum", "香精", "香氛", 8, ["FRAGRANCE", "香料", "FRAGRANCE / PARFUM"]],
  ["Retinol", "視黃醇", "抗老、促進代謝", 6, %w[レチノール 레티놀]],
  # Burt's Bees / 蘭芝唇膏／天然精油過敏原
  ["Beeswax", "蜂蠟", "增稠乳化、成膜", 1, ["CERA ALBA", "BEES WAX", "CERAALBA", "CERA BLANCA"]],
  ["Lanolin", "羊毛脂", "柔潤修護", 1, %w[LANOLINE]],
  ["Cannabis Sativa Seed Oil", "大麻籽油", "舒緩滋養油", 1, ["HEMP SEED OIL", "CANNABIS SATIVA OIL", "CANNABIS SATIVA SEED OIL"]],
  ["Helianthus Annuus Seed Oil", "向日葵籽油", "植物柔潤油", 1, ["HELIANTHUS ANNUUS (SUNFLOWER) SEED OIL", "SUNFLOWER SEED OIL", "SUNFLOWER OIL"]],
  ["Cocos Nucifera Oil", "椰子油", "柔潤滋養", 1, ["COCOS NUCIFERA (COCONUT) OIL", "COCONUT OIL", "COCOS NUCIFERA OIL"]],
  ["Ricinus Communis Seed Oil", "蓖麻籽油", "滋潤成膜油", 1, ["RICINUS COMMUNIS (CASTOR) SEED OIL", "CASTOR SEED OIL", "CASTOR OIL"]],
  ["Glycine Soja Oil", "大豆油", "柔潤", 1, ["GLYCINE SOJA (SOYBEAN) OIL", "SOYBEAN OIL", "GLYCINE MAX OIL"]],
  ["Rosmarinus Officinalis Leaf Extract", "迷迭香葉萃取", "抗氧化", 1, ["ROSMARINUS OFFICINALIS (ROSEMARY) LEAF EXTRACT", "ROSEMARY LEAF EXTRACT", "ROSMARINUS OFFICINALIS EXTRACT"]],
  ["Canola Oil", "芥花油", "柔潤", 1, ["BRASSICA CAMPESTRIS OIL", "RAPESEED OIL", "BRASSICA NAPUS OIL"]],
  ["Rebaudioside A", "甜菊糖苷", "天然甜味劑", 1, ["REBAUDIOSIDE", "STEVIOL GLYCOSIDE", "STEVIA"]],
  ["Citronellol", "香精", "過敏原", 5, ["CITRONELLOL"]],
  ["Eugenol", "香精", "過敏原", 5, ["EUGENOL"]],
  ["Geraniol", "香精", "香氛", 5, ["GERANIOL"]],
  ["Limonene", "香精", "過敏原", 5, ["LIMONENE", "D-LIMONENE"]],
  ["Linalool", "香精", "過敏原", 5, ["LINALOOL"]],
  ["Flavor", "香精", "調味香氛", 4, ["FLAVOUR", "NATURAL FLAVOR", "NATURAL FLAVOUR", "AROMA"]],
  ["Tocopherol", "生育酚（維生素 E）", "抗氧化", 1, %w[VITAMIN\ E TOCOPHERYL\ ACETATE]],
  # 蘭芝果萃
  ["Lycium Chinense Fruit Extract", "枸杞果萃取", "抗氧化修護", 1, ["LYCIUM CHINENSE EXTRACT", "GOJI FRUIT EXTRACT"]],
  ["Coffea Arabica (Coffee) Seed Extract", "咖啡籽萃取", "抗氧化", 1, ["COFFEA ARABICA SEED EXTRACT", "COFFEE SEED EXTRACT"]],
  ["Fragaria Chiloensis (Strawberry) Fruit Extract", "草莓果萃取", "抗氧化保濕", 1, ["FRAGARIA CHILOENSIS FRUIT EXTRACT", "STRAWBERRY FRUIT EXTRACT"]],
  ["Vaccinium Macrocarpon (Cranberry) Fruit Extract", "蔓越莓果萃取", "抗氧化", 1, ["VACCINIUM MACROCARPON FRUIT EXTRACT", "CRANBERRY FRUIT EXTRACT"]],
  ["Rubus Idaeus (Raspberry) Fruit Extract", "覆盆子果萃取", "抗氧化", 1, ["RUBUS IDAEUS FRUIT EXTRACT", "RASPBERRY FRUIT EXTRACT"]],
  ["Pentaerythrityl Tetra-Di-T-Butyl Hydroxyhydrocinnamate", "四(二-叔丁基羥基氫化肉桂酸)季戊四醇酯", "抗氧化穩定劑", 1, ["PENTAERYTHRITYL TETRA DI T BUTYL HYDROXYHYDROCINNAMATE", "TINUVIN", "TINOGARD TT", "Pentaerythrityl Tetra-di-t-butyl Hydroxyhydrocinnamate", "PENTAERYTHRITYL TETRA-DI-T-BUTYL HYDROXYHYDROCINNAMATE"]],
  ["Rubus Chamaemorus Seed Extract", "雲莓籽萃取", "抗氧化調理劑", 1, ["CLOUDBERRY SEED EXTRACT", "RUBUS CHAMAEMORUS EXTRACT", "RUBUS CHAMAEMORUS SEED EXTRACT"]],
  ["Sapindus Mukorossi Fruit Extract", "無患子果萃取", "天然清潔／調理劑", 1, ["SAPINDUS MUKOROSSI EXTRACT", "SOAPNUT EXTRACT", "SAPINDUS MUKOROSSI FRUIT EXTRACT"]],
  ["Vaccinium Angustifolium (Blueberry) Fruit Extract", "藍莓果萃取", "抗氧化劑", 1, ["VACCINIUM ANGUSTIFOLIUM FRUIT EXTRACT", "BLUEBERRY FRUIT EXTRACT", "VACCINIUM ANGUSTIFOLIUM (BLUEBERRY) FRUIT EXTRACT"]],
  ["Diethylamino Hydroxybenzoyl Hexyl Benzoate", "二乙氨羥苯甲醯基苯甲酸己酯（DHHB）", "化學防曬劑／UVA 防護", 2, ["DHHB", "UVINUL A PLUS", "UVINUL A+"]],
  ["Methylene Bis-Benzotriazolyl Tetramethylbutylphenol", "亞甲基雙-苯並三唑基四甲基丁基酚（Tinosorb M）", "Tinosorb M 防曬劑", 2, ["TINOSORB M", "MBBT"]],
].freeze

# 手邊產品必備（建庫最後 force_upsert）
PRODUCT_MUST_INCLUDE = [
  ["Diisostearyl Malate", "蘋果酸二異硬脂酯", "滋潤潤膚脂／唇膏基底", 1, ["DIISOSTEARYL MALATE"]],
  ["Polybutene", "聚丁烯", "增稠劑／成膜光澤劑", 1, ["POLYBUTENE"]],
  ["Microcrystalline Wax", "微晶蠟", "固化成膏劑", 1, ["CERA MICROCRISTALLINA", "CIRE MICROCRISTALLINE", "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA / CIRE MICROCRISTALLINE", "MICROCRYSTALLINE WAX / CERA MICROCRISTALLINA"]],
  ["Euphorbia Cerifera (Candelilla) Wax", "小燭樹蠟", "植物固化蠟", 1, ["CANDELILLA WAX", "CANDELILLA CERA", "EUPHORBIA CERIFERA WAX", "EUPHORBIA CERIFERA (CANDELILLA) WAX / CANDELILLA CERA"]],
  ["Astrocaryum Murumuru Seed Butter", "木魯星果棕脂", "滋養潤唇脂", 1, ["MURUMURU SEED BUTTER", "ASTROCARYUM MURUMURU BUTTER"]],
  ["Candelilla Wax Esters", "小燭樹蠟酯", "保濕軟化劑", 1, ["CANDELILLA WAX ESTERS"]],
  ["Copernicia Cerifera (Carnauba) Wax", "巴西棕櫚蠟", "植物硬蠟", 1, ["CARNAUBA WAX", "COPERNICIA CERIFERA WAX", "CIRE DE CARNAUBA"]],
  ["Cannabis Sativa Seed Oil", "大麻籽油", "舒緩滋養油", 1, ["HEMP SEED OIL", "CANNABIS SATIVA OIL", "CANNABIS SATIVA SEED OIL"]],
  ["Rebaudioside A", "甜菊糖苷", "天然甜味劑", 1, ["REBAUDIOSIDE", "STEVIOL GLYCOSIDE", "STEVIA"]],
  ["Red 7 Lake (CI 15850)", "紅色 7 號色澱", "化妝品著色劑", 3, ["RED 7 LAKE", "CI 15850", "RED 7"]],
  ["Red 6 (CI 15850)", "紅色 6 號", "著色劑", 3, ["RED 6", "CI 15850:2"]],
  ["Cetyl-PG Hydroxyethyl Palmitamide", "鯨蠟基-PG 羥乙基棕櫚醯胺（花王專利類神經醯胺）", "花王專利類神經醯胺／屏障修護", 1, ["CETYL PG HYDROXYETHYL PALMITAMIDE", "CETYL-PG HYDROXYETHYL PALMITAMIDE"]],
  ["Thujopsis Dolabrata Branch Extract", "羅漢柏枝萃取", "舒緩抗敏成分", 1, ["THUJOPSIS DOLABRATA EXTRACT", "HIBA EXTRACT"]],
  ["Eucalyptus Globulus Leaf Extract", "藍桉葉萃取", "保濕促進神經醯胺生成", 1, ["EUCALYPTUS GLOBULUS EXTRACT", "EUCALYPTUS LEAF EXTRACT"]],
  ["Isononyl Isononanoate", "異壬酸異壬酯（蠶絲油）", "蠶絲油／清爽潤膚脂", 1, ["ISONONYL ISONONANOATE"]],
  ["Isotridecyl Isononanoate", "異壬酸異十三酯", "親膚潤膚劑", 1, ["ISOTRIDECYL ISONONANOATE"]],
  ["Neopentyl Glycol Dicaprate", "新戊二醇二癸酸酯", "潤膚成膜劑", 1, ["NEOPENTYL GLYCOL DICAPRATE"]],
  ["Neopentyl Glycol Diethylhexanoate", "新戊二醇二(乙基己酸)酯", "滑順保濕劑", 1, ["NEOPENTYL GLYCOL DIETHYLHEXANOATE"]],
  ["Dipentaerythrityl Tri-Polyhydroxystearate", "二季戊四醇三-多羥基硬脂酸酯", "鎖水保濕脂", 1, ["DIPENTAERYTHRITYL TRI POLYHYDROXYSTEARATE", "DIPENTAERYTHRITYL TRI-POLYHYDROXYSTEARATE"]],
  ["Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer", "丙烯酸鈉/丙烯醯基二甲基牛磺酸鈉共聚物", "高分子增稠乳化劑", 1, ["SODIUM ACRYLATE / SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER", "SODIUM ACRYLATE SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER"]],
  ["Polyhydroxystearic Acid", "聚羥基硬脂酸", "物理防曬粉體分散劑", 1, ["POLYHYDROXYSTEARIC ACID"]],
  ["Bis-Ethylhexyl Hydroxydimethoxy Benzylmalonate", "雙-乙基己基羥基二甲氧基苄基丙二酸酯", "抗氧化穩定劑", 1, ["RONACARE AP"]],
  ["Diethylamino Hydroxybenzoyl Hexyl Benzoate", "二乙氨羥苯甲醯基苯甲酸己酯（DHHB）", "化學防曬劑／UVA 防護", 2, ["DHHB", "UVINUL A PLUS", "UVINUL A+"]],
  ["Methylene Bis-Benzotriazolyl Tetramethylbutylphenol", "亞甲基雙-苯並三唑基四甲基丁基酚（Tinosorb M）", "Tinosorb M 防曬劑", 2, ["TINOSORB M", "MBBT"]],
  ["Ethylhexyl Triazone", "乙基己基三嗪酮", "Uvinul T 150 防曬劑", 2, ["UVINUL T 150", "UVINUL T150", "EHT"]],
  ["Arachidyl Alcohol", "花生醇", "乳化助劑／脂肪醇", 1, ["ARACHIDYL ALCOHOL"]],
  ["Behenyl Alcohol", "山嵛醇", "乳化助劑／脂肪醇", 1, ["BEHENYL ALCOHOL"]],
  ["Coco-Glucoside", "椰油基葡糖苷", "溫和界面活性劑", 1, ["COCO GLUCOSIDE", "COCOGLUCOSIDE"]],
  ["Arachidyl Glucoside", "花生醇葡糖苷", "乳化劑", 1, ["ARACHIDYL GLUCOSIDE"]],
  ["Sodium Polyacryloyldimethyl Taurate", "聚丙烯醯基二甲基牛磺酸鈉", "增稠穩定劑", 1, ["SODIUM POLYACRYLOYLDIMETHYL TAURATE"]],
  ["Rhamnose", "鼠李糖", "保濕／糖類活性", 1, ["RHAMNOSE", "L-RHAMNOSE"]],
  ["Propyl Gallate", "沒食子酸丙酯", "抗氧化劑", 1, ["PROPYL GALLATE"]],
  ["PENTAERYTHRITYL TETRA-DI-T-BUTYL HYDROXYHYDROCINNAMATE", "四(二-叔丁基羥基氫化肉桂酸)季戊四醇酯", "抗氧化穩定劑", 1, ["Pentaerythrityl Tetra-di-t-butyl Hydroxyhydrocinnamate", "Tinogard TT", "Pentaerythrityl Tetra-Di-T-Butyl Hydroxyhydrocinnamate", "TINOGARD TT"]],
  ["RUBUS CHAMAEMORUS SEED EXTRACT", "雲莓籽萃取", "抗氧化調理劑", 1, ["CLOUDBERRY SEED EXTRACT", "Rubus Chamaemorus Seed Extract"]],
  ["SAPINDUS MUKOROSSI FRUIT EXTRACT", "無患子果萃取", "天然清潔／調理劑", 1, ["SOAPNUT EXTRACT", "Sapindus Mukorossi Fruit Extract"]],
  ["VACCINIUM ANGUSTIFOLIUM (BLUEBERRY) FRUIT EXTRACT", "藍莓果萃取", "抗氧化劑", 1, ["BLUEBERRY FRUIT EXTRACT", "Vaccinium Angustifolium (Blueberry) Fruit Extract"]],
  ["HDI/Trimethylol Hexyllactone Crosspolymer", "HDI/三羥甲基己內酯交聯聚合物", "柔焦粉體、觸感調節", 1, ["HDI/TRIMETHYLOL HEXYLLACTONE CROSSPOLYMER", "HDI TRIMETHYLOL HEXYLLACTONE CROSSPOLYMER"]],
  ["PEG/PPG-14/7 Dimethyl Ether", "PEG/PPG-14/7 二甲醚", "溶劑、觸感調節", 1, ["PEG/PPG-14/7 DIMETHYL ETHER", "PEG PPG-14/7 DIMETHYL ETHER"]],
  ["Distearyldimonium Chloride", "二硬脂基二甲基氯化銨", "抗靜電、調理", 3, ["DISTEARYLDIMONIUM CHLORIDE", "DISTEARYL DIMONIUM CHLORIDE"]],
  ["Prunus Speciosa Leaf Extract", "大島櫻葉萃取", "抗氧化、舒緩", 1, ["PRUNUS SPECIOSA LEAF EXTRACT", "CERASUS SPECIOSA LEAF EXTRACT"]],
  ["Rosa Canina Fruit Extract", "玫瑰果萃取", "抗氧化、保濕", 1, ["ROSA CANINA FRUIT EXTRACT", "ROSEHIP EXTRACT", "ROSE HIP EXTRACT"]],
].freeze

# 歐盟 26 種香精過敏原（中文名統一「香精」；風險標籤放 function）
EU26_FRAGRANCE_ALLERGENS = [
  ["Amyl Cinnamal", "香精", "過敏原（EU26）", 5, ["AMYL CINNAMAL"]],
  ["Benzyl Alcohol", "香精", "過敏原、溶劑（EU26）", 5, ["BENZYL ALCOHOL"]],
  ["Cinnamyl Alcohol", "香精", "過敏原（EU26）", 5, ["CINNAMYL ALCOHOL"]],
  ["Citral", "香精", "過敏原（EU26）", 5, ["CITRAL"]],
  ["Eugenol", "香精", "過敏原（EU26）", 5, ["EUGENOL"]],
  ["Hydroxycitronellal", "香精", "過敏原（EU26）", 5, ["HYDROXYCITRONELLAL"]],
  ["Isoeugenol", "香精", "過敏原（EU26）", 5, ["ISOEUGENOL"]],
  ["Amylcinnamyl Alcohol", "香精", "過敏原（EU26）", 5, ["AMYLCINNAMYL ALCOHOL"]],
  ["Benzyl Salicylate", "香精", "過敏原（EU26）", 5, ["BENZYL SALICYLATE"]],
  ["Cinnamal", "香精", "過敏原（EU26）", 5, ["CINNAMAL", "CINNAMIC ALDEHYDE"]],
  ["Coumarin", "香精", "過敏原（EU26）", 5, ["COUMARIN"]],
  ["Geraniol", "香精", "過敏原（EU26）", 5, ["GERANIOL"]],
  ["Hydroxyisohexyl 3-Cyclohexene Carboxaldehyde", "香精", "過敏原（EU26）", 5, ["LYRAL", "HICC"]],
  ["Anise Alcohol", "香精", "過敏原（EU26）", 5, ["ANISE ALCOHOL", "ANISYL ALCOHOL"]],
  ["Benzyl Cinnamate", "香精", "過敏原（EU26）", 5, ["BENZYL CINNAMATE"]],
  ["Farnesol", "香精", "過敏原（EU26）", 5, ["FARNESOL"]],
  ["Butylphenyl Methylpropional", "香精", "過敏原（EU26）", 5, ["LILIAL", "BMHCA"]],
  ["Linalool", "香精", "過敏原（EU26）", 5, ["LINALOOL"]],
  ["Benzyl Benzoate", "香精", "過敏原（EU26）", 5, ["BENZYL BENZOATE"]],
  ["Citronellol", "香精", "過敏原（EU26）", 5, ["CITRONELLOL"]],
  ["Hexyl Cinnamal", "香精", "過敏原（EU26）", 5, ["HEXYL CINNAMAL"]],
  ["Limonene", "香精", "過敏原（EU26）", 5, ["LIMONENE", "D-LIMONENE"]],
  ["Methyl 2-Octynoate", "香精", "過敏原（EU26）", 5, ["METHYL 2-OCTYNOATE", "METHYL HEPTINE CARBONATE"]],
  ["Alpha-Isomethyl Ionone", "香精", "過敏原（EU26）", 5, ["ALPHA ISOMETHYL IONONE", "Α-ISOMETHYL IONONE"]],
  ["Evernia Prunastri Extract", "香精", "過敏原（EU26）", 5, ["OAKMOSS EXTRACT", "EVERNIA PRUNASTRI"]],
  ["Evernia Furfuracea Extract", "香精", "過敏原（EU26）", 5, ["TREEMOSS EXTRACT", "EVERNIA FURFURACEA"]],
].freeze

# 常見 CI 著色劑（FDA／CosIng Annex IV 高頻）
CI_COLORANTS = [
  ["CI 77891", "二氧化鈦（CI 77891）", "化妝品著色劑／物理防曬", 2, ["CI77891"]],
  ["CI 77491", "氧化鐵紅（CI 77491）", "化妝品著色劑", 2, ["CI77491"]],
  ["CI 77492", "氧化鐵黃（CI 77492）", "化妝品著色劑", 2, ["CI77492"]],
  ["CI 77499", "氧化鐵黑（CI 77499）", "化妝品著色劑", 2, ["CI77499"]],
  ["CI 77007", "群青（CI 77007）", "化妝品著色劑", 2, ["ULTRAMARINES", "CI77007"]],
  ["CI 77510", "鐵藍（CI 77510）", "化妝品著色劑", 2, ["FERRIC FERROCYANIDE", "CI77510"]],
  ["CI 19140", "黃色 5 號（CI 19140）", "化妝品著色劑", 3, ["YELLOW 5", "TARTRAZINE", "CI19140"]],
  ["CI 15985", "黃色 6 號（CI 15985）", "化妝品著色劑", 3, ["YELLOW 6", "CI15985"]],
  ["CI 16035", "紅色 40 號（CI 16035）", "化妝品著色劑", 3, ["RED 40", "CI16035"]],
  ["CI 42090", "藍色 1 號（CI 42090）", "化妝品著色劑", 3, ["BLUE 1", "CI42090"]],
  ["CI 15850", "紅色 7 號／紅色 6 號（CI 15850）", "化妝品著色劑", 3, ["CI15850"]],
  ["CI 45410", "紅色 28 號（CI 45410）", "化妝品著色劑", 3, ["RED 28", "CI45410"]],
  ["CI 17200", "紅色 33 號（CI 17200）", "化妝品著色劑", 3, ["RED 33", "CI17200"]],
  ["CI 14700", "紅色 4 號（CI 14700）", "化妝品著色劑", 3, ["RED 4", "CI14700"]],
  ["CI 47005", "黃色 10 號（CI 47005）", "化妝品著色劑", 3, ["YELLOW 10", "CI47005"]],
  ["CI 60730", "紫色 2 號（CI 60730）", "化妝品著色劑", 3, ["EXT VIOLET 2", "CI60730"]],
  ["CI 61565", "綠色 6 號（CI 61565）", "化妝品著色劑", 3, ["GREEN 6", "CI61565"]],
  ["CI 61570", "綠色 3 號（CI 61570）", "化妝品著色劑", 3, ["GREEN 3", "CI61570"]],
  ["CI 45380", "紅色 22 號（CI 45380）", "化妝品著色劑", 3, ["RED 22", "CI45380"]],
  ["CI 45100", "紅色 52 號（CI 45100）", "化妝品著色劑", 3, ["RED 52", "CI45100"]],
  ["CI 12085", "紅色 36 號（CI 12085）", "化妝品著色劑", 3, ["RED 36", "CI12085"]],
  ["CI 26100", "紅色 17 號（CI 26100）", "化妝品著色劑", 3, ["RED 17", "CI26100"]],
  ["CI 73360", "紅色 30 號（CI 73360）", "化妝品著色劑", 3, ["RED 30", "CI73360"]],
  ["CI 77019", "雲母（CI 77019）", "珠光著色劑", 1, ["CI77019"]],
  ["CI 77163", "氯氧化鉍（CI 77163）", "珠光著色劑", 1, ["BISMUTH OXYCHLORIDE", "CI77163"]],
  ["CI 77861", "氧化錫（CI 77861）", "珠光助劑", 1, ["TIN OXIDE", "CI77861"]],
  ["CI 75470", "胭脂蟲紅（CI 75470）", "天然著色劑", 2, ["CARMINE", "CI75470"]],
  ["CI 75120", "安納托（CI 75120）", "天然著色劑", 1, ["ANNATTO", "CI75120"]],
  ["CI 75810", "葉綠素銅複合物（CI 75810）", "天然著色劑", 1, ["CHLOROPHYLLIN-COPPER COMPLEX", "CI75810"]],
  ["CI 75130", "β-胡蘿蔔素（CI 75130）", "天然著色劑", 1, ["BETA-CAROTENE", "CI75130"]],
].freeze

CORE_BASE_INGREDIENTS.each do |row|
  add_or_update(row[0], row[1], row[2], row[3], row[4])
end

(EU26_FRAGRANCE_ALLERGENS + CI_COLORANTS).each do |row|
  add_or_update(row[0], row[1], row[2], row[3], row[4])
end

def split_inci(value)
  value.to_s.gsub(/\r/, "").split(%r{[/\n;,]}).map { |n| n.gsub(/\(\d+\)/, "").strip }.reject { |n| n.length < 3 }
end

def ingest_tfda_rows(rows, default_func, default_score)
  rows.each do |row|
    name_en = row["INCI名"] || row["成分英文名稱"] || row["INCI_NAME"] || row["英文名稱"]
    name_zh = row["成分名"] || row["成分中文名稱"] || row["INGREDIENTS_NAME"] || row["中文名稱"] || row["成分名稱"]

    # 禁止清單常只有成分名稱
    if name_en.nil? || name_en.to_s.strip.empty?
      name_en = row["成分名稱"] || row["成分名"]
    end

    next if name_en.nil? || name_en.to_s.strip.empty?

    zh = name_zh.to_s.strip
    names = split_inci(name_en)
    names = [name_en.to_s.strip] if names.empty?

    names.each do |n|
      aliases = []
      aliases << zh if !zh.empty? && zh.upcase != n.upcase
      add_or_update(n, zh.empty? ? n : zh, default_func, default_score, aliases)
    end
  end
end

SOURCES = [
  ["/tmp/tfda_restricted.json", "特定用途／限量管制成分", 4],
  ["/tmp/tfda_preservative.json", "法定防腐劑", 4],
  ["/tmp/tfda_sunscreen.json", "防曬劑", 3],
  ["/tmp/tfda_banned.json", "禁止使用成分", 9]
].freeze

SOURCES.each do |path, func, score|
  unless File.exist?(path)
    warn "缺少檔案：#{path}，略過"
    next
  end
  rows = JSON.parse(File.read(path))
  unless rows.is_a?(Array)
    warn "格式異常：#{path}"
    next
  end
  before = DATABASE.size
  ingest_tfda_rows(rows, func, score)
  puts "已合併 #{File.basename(path)}（+#{DATABASE.size - before}），累計 #{DATABASE.size}"
end

# CosIng 常用高頻成分：僅補洞，不覆蓋既有 TFDA／核心資料
cosing_path = File.join(__dir__, "cosing_common_ingredients.json")
if File.exist?(cosing_path)
  before = DATABASE.size
  JSON.parse(File.read(cosing_path)).each do |row|
    add_or_update(row[0], row[1], row[2], row[3], row[4] || [])
  end
  puts "已合併 CosIng 常用原料（+#{DATABASE.size - before}），累計 #{DATABASE.size}"
else
  warn "缺少 CosIng 清單：#{cosing_path}"
end

# CosIng 大批量擴充（Scripts/fetch_cosing_expansion.rb 產出）
expansion_path = File.join(__dir__, "cosing_expansion.json")
if File.exist?(expansion_path)
  before = DATABASE.size
  JSON.parse(File.read(expansion_path)).each do |row|
    add_or_update(row[0], row[1], row[2], row[3], row[4] || [])
  end
  puts "已合併 CosIng 擴充庫（+#{DATABASE.size - before}），累計 #{DATABASE.size}"
else
  warn "缺少 CosIng 擴充：#{expansion_path}（可執行 ruby Scripts/fetch_cosing_expansion.rb）"
end

# 手邊產品必備：強制覆寫中文與別名
PRODUCT_MUST_INCLUDE.each do |row|
  force_upsert(row[0], row[1], row[2], row[3], row[4])
end
puts "已強制覆寫手邊產品必備 #{PRODUCT_MUST_INCLUDE.size} 筆"

if DATABASE.size < 3500
  warn "警告：資料庫僅 #{DATABASE.size} 筆，未達 3500+"
end

output = DATABASE.values.sort_by { |x| x["englishName"].downcase }
File.write(OUTPUT, JSON.pretty_generate(output))
puts "已完成！共產出 #{output.size} 筆成分資料"
puts "已儲存至 #{OUTPUT}"
