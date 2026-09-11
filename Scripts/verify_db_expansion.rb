# frozen_string_literal: true
# 驗證：資料庫 ≥3500、手邊必備中文、六品牌命中率
require "json"

ROOT = File.expand_path("..", __dir__)
DB = JSON.parse(File.read(File.join(ROOT, "Skincare", "IngredientsDatabase.json")))

def deep_normalize(text)
  value = text.to_s.gsub(/[*＊†‡]/, "").downcase
  value = value.gsub(/[\r\n]+/, " ").gsub(/[–—‐‑−﹣－]/, "-")
  value = value.strip.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, "")
  value.split(/\s+/).join(" ")
end

def normalized_key(text)
  deep_normalize(text).gsub(/[^a-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/, "")
end

index = {}
DB.each do |item|
  ([item["englishName"], item["chineseName"], item["name"]] + Array(item["aliases"])).compact.each do |n|
    next if n.to_s.strip.empty?
    index[normalized_key(n)] ||= item
  end
end

def split_slash(text)
  return [] unless text.include?("/")
  text.split("/").map { |s| s.strip.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, "") }.reject { |s| s.length < 2 }
      .sort_by { |s| -s.length }
end

def paren_candidates(text)
  out = []
  if text =~ /^(.*?)\(([^)]+)\)\s*(.*)$/
    before, inner, after = $1.strip, $2.strip, $3.strip
    latin = [before, after].reject(&:empty?).join(" ").strip
    vern = [inner, after].reject(&:empty?).join(" ").strip
    out << latin unless latin.empty?
    out << vern unless vern.empty?
    out << before unless before.empty?
    out << inner unless inner.empty?
    out << after unless after.empty?
  end
  out
end

def candidate_pool(raw)
  trimmed = raw.to_s.gsub(/[*＊†‡]/, "").strip
  pool = [trimmed]
  pool.concat(split_slash(trimmed)) if trimmed.include?("/")
  pool.concat(paren_candidates(trimmed))
  split_slash(trimmed).each { |p| pool.concat(paren_candidates(p)) }
  seen = {}
  pool.select do |item|
    key = deep_normalize(item)
    next false if key.length < 2 || seen[key]
    seen[key] = true
    true
  end
end

def match_token(raw, index)
  prepared = raw.to_s
    .gsub(/\[[^\]]*\]/, "")
    .gsub(/\([^)]*%[^)]*\)/, "")
    .gsub(/\(DHHB\)/i, "")
    .gsub(/\d+(\.\d+)?\s*%/, "")
    .gsub(/[*＊†‡]/, "")
    .strip
  candidate_pool(prepared).each do |c|
    hit = index[normalized_key(c)]
    return hit if hit
  end
  nil
end

puts "DB size=#{DB.size}"
abort("FAIL size < 8000") if DB.size < 8000

# schema sample
sample = DB.first
%w[englishName chineseName aliases function safetyRating name category].each do |k|
  abort("FAIL missing key #{k}") unless sample.key?(k)
end
puts "schema OK (name/category + englishName/function)"

must = {
  "DIISOSTEARYL MALATE" => "蘋果酸二異硬脂酯",
  "POLYBUTENE" => "聚丁烯",
  "MICROCRYSTALLINE WAX" => "微晶蠟",
  "EUPHORBIA CERIFERA (CANDELILLA) WAX" => "小燭樹蠟",
  "ASTROCARYUM MURUMURU SEED BUTTER" => "木魯星果棕脂",
  "CANDELILLA WAX ESTERS" => "小燭樹蠟酯",
  "COPERNICIA CERIFERA (CARNAUBA) WAX" => "巴西棕櫚蠟",
  "CANNABIS SATIVA SEED OIL" => "大麻籽油",
  "REBAUDIOSIDE A" => "甜菊糖苷",
  "RED 7 LAKE (CI 15850)" => "紅色 7 號色澱",
  "RED 6 (CI 15850)" => "紅色 6 號",
  "CETYL-PG HYDROXYETHYL PALMITAMIDE" => "鯨蠟基-PG 羥乙基棕櫚醯胺",
  "THUJOPSIS DOLABRATA BRANCH EXTRACT" => "羅漢柏枝萃取",
  "EUCALYPTUS GLOBULUS LEAF EXTRACT" => "藍桉葉萃取",
  "ISONONYL ISONONANOATE" => "異壬酸異壬酯",
  "ISOTRIDECYL ISONONANOATE" => "異壬酸異十三酯",
  "NEOPENTYL GLYCOL DICAPRATE" => "新戊二醇二癸酸酯",
  "NEOPENTYL GLYCOL DIETHYLHEXANOATE" => "新戊二醇二(乙基己酸)酯",
  "DIPENTAERYTHRITYL TRI-POLYHYDROXYSTEARATE" => "二季戊四醇三-多羥基硬脂酸酯",
  "SODIUM ACRYLATE/SODIUM ACRYLOYLDIMETHYL TAURATE COPOLYMER" => "丙烯酸鈉",
  "POLYHYDROXYSTEARIC ACID" => "聚羥基硬脂酸",
  "BIS-ETHYLHEXYL HYDROXYDIMETHOXY BENZYLMALONATE" => "雙-乙基己基羥基二甲氧基苄基丙二酸酯",
  "DIETHYLAMINO HYDROXYBENZOYL HEXYL BENZOATE" => "二乙氨羥苯甲醯基苯甲酸己酯",
  "METHYLENE BIS-BENZOTRIAZOLYL TETRAMETHYLBUTYLPHENOL" => "亞甲基雙-苯並三唑基四甲基丁基酚",
  "ETHYLHEXYL TRIAZONE" => "乙基己基三嗪酮",
  "ARACHIDYL ALCOHOL" => "花生醇",
  "BEHENYL ALCOHOL" => "山嵛醇",
  "COCO-GLUCOSIDE" => "椰油基葡糖苷",
  "ARACHIDYL GLUCOSIDE" => "花生醇葡糖苷",
  "SODIUM POLYACRYLOYLDIMETHYL TAURATE" => "聚丙烯醯基二甲基牛磺酸鈉",
  "RHAMNOSE" => "鼠李糖",
  "PROPYL GALLATE" => "沒食子酸丙酯",
}

must.each do |en, zh|
  hit = match_token(en, index)
  abort("FAIL miss #{en}") unless hit
  abort("FAIL zh #{en} => #{hit['chineseName']}") unless hit["chineseName"].include?(zh)
end
puts "must-include OK (#{must.size})"

eu26 = %w[LIMONENE LINALOOL CITRONELLOL EUGENOL GERANIOL CITRAL COUMARIN FARNESOL]
eu26.each { |n| abort("FAIL EU26 #{n}") unless match_token(n, index) }
puts "EU26 sample OK"

cosing = %w[
  HIPPOPHAE\ RHAMNOIDES\ FRUIT\ EXTRACT
  CAMELLIA\ JAPONICA\ LEAF\ EXTRACT
  CENTELLA\ ASIATICA\ LEAF\ EXTRACT
  ROSA\ DAMASCENA\ FLOWER\ EXTRACT
  VITIS\ VINIFERA\ SEED\ EXTRACT
  GINKGO\ BILOBA\ LEAF\ EXTRACT
  PANAX\ GINSENG\ ROOT\ EXTRACT
]
cosing.each { |n| abort("FAIL CosIng #{n}") unless match_token(n, index) }
puts "CosIng botanical sample OK"

{
  "VITIS VINIFERA SEED EXTRACT" => "葡萄",
  "CUCUMIS SATIVUS FRUIT EXTRACT" => "黃瓜",
  "CAMELLIA JAPONICA LEAF EXTRACT" => "山茶",
}.each do |en, zh|
  hit = match_token(en, index)
  abort("FAIL display zh miss #{en}") unless hit
  abort("FAIL display zh #{en} => #{hit['chineseName']}") unless hit["chineseName"].include?(zh)
end
puts "botanical display Chinese OK"

products = {
  "Paula" => %w[Water Methylpropanediol Butylene\ Glycol Salicylic\ Acid Polysorbate\ 20 Camellia\ Oleifera\ Leaf\ Extract Sodium\ Hydroxide Tetrasodium\ EDTA],
  "Softyman" => %w[
    WATER GLYCERIN BUTYLENE\ GLYCOL DIMETHICONE
    DIETHYLAMINO\ HYDROXYBENZOYL\ HEXYL\ BENZOATE ETHYLHEXYL\ SALICYLATE ETHYLHEXYL\ TRIAZONE
    METHYLENE\ BIS-BENZOTRIAZOLYL\ TETRAMETHYLBUTYLPHENOL C12-15\ ALKYL\ BENZOATE DIETHYLHEXYL\ CARBONATE
    MICROCRYSTALLINE\ CELLULOSE CAPRYLYL\ METHICONE GLYCERETH-26
    BIS-PEG/PPG-20/5\ PEG/PPG-20/5\ DIMETHICONE METHOXY\ PEG/PPG-25/4\ DIMETHICONE DECYL\ GLUCOSIDE
    SODIUM\ POTASSIUM\ ALUMINUM\ SILICATE ALUMINUM\ HYDROXIDE HYDRATED\ SILICA HYDROGEN\ DIMETHICONE
    NIACINAMIDE PANTHENOL ALLANTOIN SODIUM\ HYALURONATE TOCOPHEROL XANTHAN\ GUM CARBOMER
    PHENOXYETHANOL ETHYLHEXYLGLYCERIN TRISODIUM\ ETHYLENEDIAMINE\ DISUCCINATE
    BIS-ETHYLHEXYL\ HYDROXYDIMETHOXY\ BENZYLMALONATE GLYCOSPHINGOLIPIDS CENTELLA\ ASIATICA\ EXTRACT
    ROSA\ ROXBURGHII\ FRUIT\ EXTRACT RUBUS\ IDAEUS\ FRUIT\ EXTRACT POTENTILLA\ RECTA\ ROOT\ EXTRACT SQUALANE
  ],
  "Laneige" => %w[
    HYDROGENATED\ POLYISOBUTENE DIISOSTEARYL\ MALATE POLYBUTENE
    MICROCRYSTALLINE\ WAX\ /\ CERA\ MICROCRISTALLINA\ /\ CIRE\ MICROCRISTALLINE
    PHYTOSTERYL/ISOSTEARYL/CETYL/STEARYL/BEHENYL\ DIMER\ DILINOLEATE
    BUTYROSPERMUM\ PARKII\ (SHEA)\ BUTTER SYNTHETIC\ WAX METHICONE POLYGLYCERYL-2\ TRIISOSTEARATE
    EUPHORBIA\ CERIFERA\ (CANDELILLA)\ WAX\ /\ CANDELILLA\ CERA
    ASTROCARYUM\ MURUMURU\ SEED\ BUTTER CANDELILLA\ WAX\ ESTERS COPERNICIA\ CERIFERA\ (CARNAUBA)\ WAX
    TOCOPHEROL LYCIUM\ CHINENSE\ FRUIT\ EXTRACT COFFEA\ ARABICA\ (COFFEE)\ SEED\ EXTRACT
    FRAGARIA\ CHILOENSIS\ (STRAWBERRY)\ FRUIT\ EXTRACT VACCINIUM\ MACROCARPON\ (CRANBERRY)\ FRUIT\ EXTRACT
    RUBUS\ IDAEUS\ (RASPBERRY)\ FRUIT\ EXTRACT RED\ 7\ LAKE\ (CI\ 15850) RED\ 6\ (CI\ 15850)
    TITANIUM\ DIOXIDE MICA SILICA AMMONIUM\ ACRYLOYLDIMETHYLTAURATE/VP\ COPOLYMER
    ETHYLENE/PROPYLENE/STYRENE\ COPOLYMER BUTYLENE/ETHYLENE/STYRENE\ COPOLYMER
    HYDROGENATED\ POLY(C6-14\ OLEFIN) CAPRYLIC/CAPRIC\ TRIGLYCERIDE SQUALANE DIMETHICONE
  ],
  "Curel" => %w[
    WATER ETHYLHEXYL\ METHOXYCINNAMATE ISONONYL\ ISONONANOATE ISOTRIDECYL\ ISONONANOATE
    CETYL-PG\ HYDROXYETHYL\ PALMITAMIDE NEOPENTYL\ GLYCOL\ DICAPRATE NEOPENTYL\ GLYCOL\ DIETHYLHEXANOATE
    DIPENTAERYTHRITYL\ TRI-POLYHYDROXYSTEARATE SODIUM\ ACRYLATE/SODIUM\ ACRYLOYLDIMETHYL\ TAURATE\ COPOLYMER
    POLYHYDROXYSTEARIC\ ACID THUJOPSIS\ DOLABRATA\ BRANCH\ EXTRACT EUCALYPTUS\ GLOBULUS\ LEAF\ EXTRACT
    DEXTRIN\ PALMITATE GLYCERIN BUTYLENE\ GLYCOL DIMETHICONE CYCLOPENTASILOXANE ZINC\ OXIDE TITANIUM\ DIOXIDE
    ALUMINUM\ HYDROXIDE HYDRATED\ SILICA HYDROGEN\ DIMETHICONE SILICA TOCOPHEROL PHENOXYETHANOL
    ETHYLHEXYLGLYCERIN XANTHAN\ GUM CARBOMER SODIUM\ HYDROXIDE BG PROPANEDIOL SQUALANE ALLANTOIN
    SODIUM\ HYALURONATE CENTELLA\ ASIATICA\ EXTRACT
  ],
  "Bioderma" => %w[
    AQUA/WATER/EAU DI-C12-13\ ALKYL\ MALATE GLYCERIN PROPYLHEPTYL\ CAPRYLATE
    SODIUM\ POLYACRYLOYLDIMETHYL\ TAURATE ARACHIDYL\ ALCOHOL BEHENYL\ ALCOHOL COCO-GLUCOSIDE
    ARACHIDYL\ GLUCOSIDE SALICYLIC\ ACID SODIUM\ HYDROXIDE CITRIC\ ACID PROPYL\ GALLATE RHAMNOSE
    PENTYLENE\ GLYCOL BUTYLENE\ GLYCOL PROPANEDIOL XANTHAN\ GUM DISODIUM\ EDTA SODIUM\ CITRATE
    SODIUM\ METABISULFITE FRAGRANCE
  ],
  "BurtsBees" => %w[
    beeswax cannabis\ sativa\ seed\ oil* cocos\ nucifera\ (coconut)\ oil
    helianthus\ annuus\ (sunflower)\ seed\ oil lanolin glycine\ soja\ (soybean)\ oil canola\ oil
    rosmarinus\ officinalis\ (rosemary)\ leaf\ extract tocopherol flavor** rebaudioside\ A
  ],
}

products.each do |label, tokens|
  hits = tokens.select { |t| match_token(t, index) }
  rate = hits.size.to_f / tokens.size
  misses = tokens.reject { |t| match_token(t, index) }
  puts "#{label}: #{format('%.1f', rate * 100)}% (#{hits.size}/#{tokens.size})"
  abort("FAIL #{label} #{misses.inspect}") if rate < 0.90
end

puts "ALL OK"
