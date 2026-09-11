#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
# 為「中文欄仍是 INCI 原文」的植萃列補顯示用中文。
# 學名從庫內已有中文的列反推；部位／製法用固定表。不覆蓋已有漢字，不猜化學名。

require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
DB_PATH = File.join(ROOT, "Skincare", "IngredientsDatabase.json")
DRY_RUN = ARGV.include?("--dry-run")

CJK = /[\u4e00-\u9fff]/

PROCESS = {
  "EXTRACT" => "萃取",
  "OIL" => "油",
  "WATER" => "水",
  "WAX" => "蠟",
  "POWDER" => "粉",
  "JUICE" => "汁",
  "BUTTER" => "脂",
  "FILTRATE" => "濾液"
}.freeze

# 長的先比。
PARTS = [
  ["AERIAL PARTS", "地上部"],
  ["WHOLE PLANT", "全株"],
  ["FLOWER/LEAF/STEM", "花/葉/莖"],
  ["LEAF/STEM", "葉/莖"],
  ["FLOWER/LEAF", "花/葉"],
  ["FLOWER/STEM", "花/莖"],
  ["FRUIT/LEAF", "果/葉"],
  ["BRANCH/LEAF", "枝/葉"],
  ["ROOT/BARK", "根/樹皮"],
  ["SEEDCAKE", "籽餅"],
  ["CALLUS", "癒傷組織"],
  ["NEEDLE", "針葉"],
  ["KERNEL", "仁"],
  ["RHIZOME", "根莖"],
  ["FLOWER", "花"],
  ["FRUIT", "果"],
  ["SEED", "籽"],
  ["LEAF", "葉"],
  ["ROOT", "根"],
  ["BARK", "樹皮"],
  ["STEM", "莖"],
  ["BRANCH", "枝"],
  ["PEEL", "果皮"],
  ["WOOD", "木"],
  ["HERB", "草"],
  ["SPROUT", "芽"],
  ["BUD", "芽"],
  ["CONE", "球果"],
  ["SHOOT", "嫩枝"],
  ["BERRY", "莓"],
  ["NUT", "堅果"],
  ["HULL", "殼"],
  ["HUSK", "殼"],
  ["GERM", "胚芽"],
  ["PULP", "果肉"],
  ["RESIN", "樹脂"]
].freeze

LATIN_NOISE = %w[
  ADVENTITIOUS CULTURE CELL CELLS MERISTEM PROTOPLAST SUSPENSION MEDIA
  FERMENT FERMENTED LYSATE CONDITIONED SECRETION EXOSOME VESICLE VESICLES
  HYDROSOL DISTILLATE ABSOLUTE CONCRETE TINCTURE BIOMASS MYCELIUM
  RECOMBINANT SYNTHETIC HYDROLYZED
].to_set

CHEM_HEAD = %w[
  SODIUM POTASSIUM AMMONIUM CALCIUM MAGNESIUM ZINC IRON TITANIUM SILICA SILICATE
  PEG PPG PEGS GLYCERIN GLYCEROL WATER AQUA ALCOHOL PHENOXYETHANOL TOCOPHEROL
  DIMETHICONE METHICONE CYCLOPENTASILOXANE CARBOMER ACRYLATE ACRYLATES POLY
  HYDROGENATED HYDROGEN CI RED YELLOW BLUE GREEN BLACK ORANGE BROWN
  ETHYLHEXYL BUTYLENE PROPYLENE METHYLPROPANEDIOL NIACINAMIDE SALICYLIC
  PHENOXY ETHYLHEXYLGLYCERIN SQUALANE PANTHENOL ALLANTOIN
  LACTOBACILLUS BIFIDA BIFIDOBACTERIUM SACCHAROMYCES LEUCONOSTOC
  POLYSORBATE CARBOMER
].to_set

# 掃得到、學名對照失敗時的保底（僅在括號通名或學名命中時使用）。
CURATED_BINOMIAL = {
  "VITIS VINIFERA" => "葡萄",
  "CUCUMIS SATIVUS" => "小黃瓜",
  "ALOE BARBADENSIS" => "蘆薈",
  "ALOE VERA" => "蘆薈",
  "CAMELLIA SINENSIS" => "茶",
  "CAMELLIA JAPONICA" => "山茶",
  "CENTELLA ASIATICA" => "積雪草",
  "GINKGO BILOBA" => "銀杏",
  "PANAX GINSENG" => "人參",
  "PUNICA GRANATUM" => "石榴",
  "ROSA CANINA" => "玫瑰",
  "ROSA DAMASCENA" => "突厥薔薇",
  "HIPPOPHAE RHAMNOIDES" => "沙棘",
  "CANNABIS SATIVA" => "大麻",
  "PRUNUS SPECIOSA" => "大島櫻",
  "THUJOPSIS DOLABRATA" => "羅漢柏",
  "EUCALYPTUS GLOBULUS" => "藍桉",
  "BUTYROSPERMUM PARKII" => "乳木果",
  "PERSEA GRATISSIMA" => "酪梨",
  "PERSEA AMERICANA" => "酪梨",
  "OLEA EUROPAEA" => "橄欖",
  "COCOS NUCIFERA" => "椰子",
  "HELIANTHUS ANNUUS" => "向日葵",
  "GLYCINE SOJA" => "大豆",
  "GLYCINE MAX" => "大豆",
  "ORYZA SATIVA" => "米",
  "TRITICUM VULGARE" => "小麥",
  "AVENA SATIVA" => "燕麥",
  "CHAMOMILLA RECUTITA" => "洋甘菊",
  "MATRICARIA CHAMOMILLA" => "洋甘菊",
  "LAVANDULA ANGUSTIFOLIA" => "薰衣草",
  "MENTHA PIPERITA" => "胡椒薄荷",
  "ROSMARINUS OFFICINALIS" => "迷迭香",
  "SALVIA ROSMARINUS" => "迷迭香",
  "HAMAMELIS VIRGINIANA" => "金縷梅",
  "MELALEUCA ALTERNIFOLIA" => "茶樹",
  "CITRUS LIMON" => "檸檬",
  "CITRUS AURANTIUM" => "苦橙",
  "CITRUS SINENSIS" => "甜橙",
  "CITRUS PARADISI" => "葡萄柚",
  "CITRUS RETICULATA" => "柑橘",
  "CITRUS JUNOS" => "柚子",
  "PORTULACA OLERACEA" => "馬齒莧",
  "HOUTTUYNIA CORDATA" => "魚腥草",
  "GLYCYRRHIZA URALENSIS" => "甘草",
  "GLYCYRRHIZA GLABRA" => "光果甘草",
  "SCUTELLARIA BAICALENSIS" => "黃芩",
  "PAEONIA LACTIFLORA" => "芍藥",
  "PAEONIA SUFFRUTICOSA" => "牡丹",
  "ANGELICA GIGAS" => "韓國當歸",
  "ANGELICA SINENSIS" => "當歸",
  "CNIDIUM OFFICINALE" => "川芎",
  "REHMANNIA GLUTINOSA" => "地黃",
  "ARTEMISIA PRINCEPS" => "艾",
  "ARTEMISIA VULGARIS" => "艾",
  "ZINGIBER OFFICINALE" => "薑",
  "CURCUMA LONGA" => "薑黃",
  "COFFEA ARABICA" => "咖啡",
  "THEOBROMA CACAO" => "可可",
  "FRAGARIA CHILOENSIS" => "草莓",
  "FRAGARIA VESCA" => "草莓",
  "VACCINIUM MACROCARPON" => "蔓越莓",
  "VACCINIUM MYRTILLUS" => "越橘",
  "RUBUS IDAEUS" => "覆盆子",
  "LYCIUM CHINENSE" => "枸杞",
  "LYCIUM BARBARUM" => "枸杞",
  "PRUNUS AMYGDALUS" => "杏仁",
  "PRUNUS ARMENIACA" => "杏",
  "PRUNUS PERSICA" => "桃",
  "PRUNUS DOMESTICA" => "李",
  "MALUS DOMESTICA" => "蘋果",
  "PYRUS MALUS" => "蘋果",
  "MANGIFERA INDICA" => "芒果",
  "CARICA PAPAYA" => "木瓜",
  "ANANAS SATIVUS" => "鳳梨",
  "CITRULLUS LANATUS" => "西瓜",
  "CUCURBITA PEPO" => "南瓜",
  "DAUCUS CAROTA" => "胡蘿蔔",
  "SOLANUM LYCOPERSICUM" => "番茄",
  "SOLANUM MELONGENA" => "茄子",
  "BRASSICA OLERACEA" => "甘藍",
  "NASTURTIUM OFFICINALE" => "西洋菜",
  "OCIMUM BASILICUM" => "羅勒",
  "THYMUS VULGARIS" => "百里香",
  "SALVIA OFFICINALIS" => "鼠尾草",
  "ORIGANUM VULGARE" => "牛至",
  "FOENICULUM VULGARE" => "茴香",
  "PIMPINELLA ANISUM" => "茴芹",
  "CORIANDRUM SATIVUM" => "芫荽",
  "PETROSELINUM CRISPUM" => "巴西里",
  "ANETHUM GRAVEOLENS" => "蒔蘿",
  "JUNIPERUS COMMUNIS" => "杜松",
  "PINUS SYLVESTRIS" => "歐洲赤松",
  "CEDRUS ATLANTICA" => "大西洋雪松",
  "CUPRESSUS SEMPERVIRENS" => "地中海柏木",
  "BETULA ALBA" => "白樺",
  "BETULA PENDULA" => "歐洲樺",
  "SALIX ALBA" => "白柳",
  "QUERCUS ROBUR" => "英國櫟",
  "ULMUS DAVIDIANA" => "榆",
  "MORUS ALBA" => "白桑",
  "FICUS CARICA" => "無花果",
  "SIMMONDSIA CHINENSIS" => "荷荷芭",
  "ARGANIA SPINOSA" => "阿甘油樹",
  "MACADAMIA TERNIFOLIA" => "澳洲堅果",
  "MACADAMIA INTEGRIFOLIA" => "澳洲堅果",
  "PRUNUS AMYGDALUS DULCIS" => "甜杏仁",
  "OENOTHERA BIENNIS" => "月見草",
  "BORAGO OFFICINALIS" => "琉璃苣",
  "LINUM USITATISSIMUM" => "亞麻",
  "SESAMUM INDICUM" => "芝麻",
  "RICINUS COMMUNIS" => "蓖麻",
  "GOSSYPIUM HERBACEUM" => "棉",
  "TRIFOLIUM PRATENSE" => "紅三葉",
  "MEDICAGO SATIVA" => "苜蓿",
  "EQUISETUM ARVENSE" => "問荊",
  "URTICA DIOICA" => "異株蕁麻",
  "TARAXACUM OFFICINALE" => "蒲公英",
  "HEDERA HELIX" => "常春藤",
  "AESCULUS HIPPOCASTANUM" => "歐洲七葉樹",
  "CALENDULA OFFICINALIS" => "金盞花",
  "ANTHEMIS NOBILIS" => "羅馬洋甘菊",
  "CHAMAEMELUM NOBILE" => "羅馬洋甘菊",
  "JASMINUM OFFICINALE" => "茉莉",
  "GARDENIA JASMINOIDES" => "梔子",
  "LILIUM CANDIDUM" => "白百合",
  "NELUMBO NUCIFERA" => "蓮",
  "HIBISCUS SABDARIFFA" => "洛神",
  "VIOLA ODORATA" => "香堇菜",
  "VIOLA TRICOLOR" => "三色堇",
  "PELARGONIUM GRAVEOLENS" => "香葉天竺葵",
  "CANANGA ODORATA" => "依蘭",
  "SANTALUM ALBUM" => "檀香",
  "POGOSTEMON CABLIN" => "廣藿香",
  "VETIVERIA ZIZANOIDES" => "岩蘭草",
  "CHRYSOPOGON ZIZANIOIDES" => "岩蘭草",
  "CEDRUS DEODARA" => "喜馬拉雅雪松",
  "ABIES SIBIRICA" => "西伯利亞冷杉",
  "ABIES ALBA" => "歐洲冷杉",
  "PICEA ABIES" => "挪威雲杉",
  "LAMINARIA DIGITATA" => "掌狀海帶",
  "FUCUS VESICULOSUS" => "墨角藻",
  "CHONDRUS CRISPUS" => "皺波角叉菜",
  "SPIRULINA PLATENSIS" => "螺旋藻",
  "CHLORELLA VULGARIS" => "小球藻"
}.freeze

VERNACULAR = {
  "LEMON" => "檸檬", "LIME" => "萊姆", "ORANGE" => "橙", "GRAPEFRUIT" => "葡萄柚",
  "SWEET ALMOND" => "甜杏仁", "ALMOND" => "杏仁", "SHEA" => "乳木果",
  "COCONUT" => "椰子", "OLIVE" => "橄欖", "GRAPE" => "葡萄", "CUCUMBER" => "黃瓜",
  "GREEN TEA" => "綠茶", "TEA" => "茶", "ROSE" => "玫瑰", "LAVENDER" => "薰衣草",
  "CHAMOMILE" => "洋甘菊", "PEPPERMINT" => "胡椒薄荷", "ROSEMARY" => "迷迭香",
  "CALENDULA" => "金盞花", "GINGER" => "薑", "TURMERIC" => "薑黃",
  "GINSENG" => "人參", "LICORICE" => "甘草", "ALOE VERA" => "蘆薈", "ALOE" => "蘆薈",
  "JOJOBA" => "荷荷芭", "ARGAN" => "阿甘油樹", "MACADAMIA" => "澳洲堅果",
  "AVOCADO" => "酪梨", "SUNFLOWER" => "向日葵", "SESAME" => "芝麻",
  "RICE" => "米", "SOY" => "大豆", "SOYBEAN" => "大豆", "WHEAT" => "小麥",
  "OAT" => "燕麥", "APPLE" => "蘋果", "PEACH" => "桃", "APRICOT" => "杏",
  "CHERRY" => "櫻桃", "STRAWBERRY" => "草莓", "RASPBERRY" => "覆盆子",
  "BLUEBERRY" => "藍莓", "CRANBERRY" => "蔓越莓", "POMEGRANATE" => "石榴",
  "WATERMELON" => "西瓜", "MANGO" => "芒果", "PAPAYA" => "木瓜",
  "PINEAPPLE" => "鳳梨", "BANANA" => "香蕉", "COFFEE" => "咖啡", "COCOA" => "可可",
  "VANILLA" => "香草", "CINNAMON" => "肉桂", "TEA TREE" => "茶樹",
  "WITCH HAZEL" => "金縷梅", "EVENING PRIMROSE" => "月見草", "SEA BUCKTHORN" => "沙棘",
  "GOTU KOLA" => "積雪草", "CENTELLA" => "積雪草", "HONEYSUCKLE" => "忍冬",
  "JASMINE" => "茉莉", "GARDENIA" => "梔子", "LOTUS" => "蓮", "HIBISCUS" => "木槿",
  "PEONY" => "芍藥", "MUGWORT" => "艾", "BAMBOO" => "竹",
  "LICORICE ROOT" => "甘草", "CANDELILLA" => "小燭樹", "CARNAUBA" => "巴西棕櫚",
  "MURUMURU" => "木魯星果棕", "CUPUACU" => "杯芋", "KAKADU PLUM" => "卡卡杜李",
  "ACAI" => "阿薩伊", "GOJI" => "枸杞", "JUJUBE" => "棗", "DATE" => "椰棗",
  "FIG" => "無花果", "POMELO" => "柚", "YUZU" => "柚子", "BERGAMOT" => "佛手柑",
  "NEROLI" => "橙花", "PETITGRAIN" => "苦橙葉", "TANGERINE" => "柑橘",
  "MANDARIN" => "柑橘", "SWEET ORANGE" => "甜橙", "BITTER ORANGE" => "苦橙"
}.freeze

def has_cjk?(text)
  text.to_s =~ CJK
end

def already_zh?(en, zh)
  z = zh.to_s.strip
  has_cjk?(z) && z.upcase != en.to_s.strip.upcase
end

def skip_formula?(en)
  s = en.to_s
  return true if s.start_with?("(", "[", "{")
  return true if s.include?("+") || s.include?("&")
  return true if s.count("/") >= 3
  return true if s =~ /\bFERMENT\b/ && s.include?("/")
  false
end

def tokenize(en)
  en.to_s.upcase
    .gsub(/[()（）]/, " ")
    .gsub("×", " ")
    .gsub(/,/, " ")
    .split
    .reject(&:empty?)
end

def match_part(tokens)
  PARTS.each do |en, zh|
    words = en.split
    n = words.size
    next if tokens.size < n
    return [zh, n] if tokens.last(n).join(" ") == en
  end
  nil
end

def parse_botanical(en)
  return nil if skip_formula?(en)
  tokens = tokenize(en)
  return nil if tokens.size < 2

  process_zh = nil
  if tokens.last && PROCESS[tokens.last]
    process_zh = PROCESS[tokens.last]
    tokens = tokens[0...-1]
  end

  part_zhs = []
  loop do
    hit = match_part(tokens)
    break unless hit
    zh, n = hit
    part_zhs.unshift(zh)
    tokens = tokens[0...-n]
  end

  return nil if process_zh.nil? && part_zhs.empty?
  return nil if tokens.empty?
  return nil if tokens.any? { |t| t =~ /\d/ || t.include?("-") && t =~ /PEG|PPG|C\d/ }

  head = tokens.first
  return nil if CHEM_HEAD.include?(head)
  return nil unless tokens.all? { |t| t =~ /\A[A-Z]{2,}\z/ }
  return nil if tokens.any? { |t| LATIN_NOISE.include?(t) }
  return nil if tokens.size > 4

  latin = tokens.join(" ")
  [latin, part_zhs.join, process_zh.to_s]
end

def strip_morphology(zh, part_joined, process_zh)
  value = zh.to_s.gsub(/\s+/, "").gsub(/／.*/, "")
  return nil if value.include?("/") || value.include?("、")
  suffix = "#{part_joined}#{process_zh}"
  if !suffix.empty? && value.end_with?(suffix)
    value = value[0...-suffix.length]
  else
    value = value.sub(/#{Regexp.escape(process_zh)}\z/, "") unless process_zh.empty?
    value = value.sub(/#{Regexp.escape(part_joined)}\z/, "") unless part_joined.empty?
  end
  value = value.strip
  return nil unless has_cjk?(value)
  return nil if value.length < 2
  value
end

def compose(plant, part_joined, process_zh)
  "#{plant}#{part_joined}#{process_zh}"
end

def pick_voted(votes)
  return nil if votes.nil? || votes.empty?
  total = votes.values.sum
  plant, count = votes.max_by { |_, n| n }
  return nil if plant.nil?
  return nil if count < 1
  return nil if votes.size > 1 && count < 2
  return nil if votes.size > 1 && count.to_f / total < 0.5
  plant
end

def vernacular_from(en)
  return nil unless en =~ /\(([^)]+)\)/
  inner = Regexp.last_match(1).to_s.upcase.gsub(/[^A-Z ]/, " ").gsub(/\s+/, " ").strip
  return nil if inner.empty?
  return VERNACULAR[inner] if VERNACULAR[inner]
  inner.split.each do |w|
    return VERNACULAR[w] if VERNACULAR[w]
  end
  nil
end

db = JSON.parse(File.read(DB_PATH))

votes = Hash.new { |h, k| h[k] = Hash.new(0) }
db.each do |item|
  en = item["englishName"].to_s.strip
  zh = item["chineseName"].to_s.strip
  next unless already_zh?(en, zh)
  parsed = parse_botanical(en)
  next unless parsed
  latin, parts, process = parsed
  plant = strip_morphology(zh, parts, process)
  next unless plant
  votes[latin][plant] += 1
  words = latin.split
  votes[words.first(2).join(" ")][plant] += 1 if words.size >= 3
end

learned = {}
votes.each do |latin, tally|
  plant = pick_voted(tally)
  learned[latin] = plant if plant
end
CURATED_BINOMIAL.each do |latin, plant|
  learned[latin] = plant
end

def resolve_plant(latin, en, learned)
  return learned[latin] if learned[latin]
  words = latin.split
  if words.size >= 3
    bi = words.first(2).join(" ")
    return learned[bi] if learned[bi]
  end
  if words.size >= 2
    bi = words.first(2).join(" ")
    return learned[bi] if learned[bi]
  end
  vernacular_from(en)
end

filled = 0
skipped_curated = 0
unresolved = 0
samples = []
occupied = {}
db.each do |item|
  zh = item["chineseName"].to_s.strip
  next unless already_zh?(item["englishName"], zh)
  occupied[zh] ||= item["englishName"]
end

db.each do |item|
  en = item["englishName"].to_s.strip
  zh = item["chineseName"].to_s.strip
  if already_zh?(en, zh)
    parsed = parse_botanical(en)
    should_fix_cone = parsed && parsed[1].include?("球果") && !zh.include?("球果") && !zh.include?("／")
    unless should_fix_cone
      skipped_curated += 1
      next
    end
  end
  parsed = parse_botanical(en)
  unless parsed
    unresolved += 1
    next
  end
  latin, parts, process = parsed
  plant = resolve_plant(latin, en, learned)
  unless plant && has_cjk?(plant)
    unresolved += 1
    next
  end
  generated = compose(plant, parts, process)
    .gsub("面包", "麵包")
    .gsub("头发", "頭髮")
  unless has_cjk?(generated) && generated.length >= 3
    unresolved += 1
    next
  end
  item["chineseName"] = generated
  occupied[generated] ||= en
  filled += 1
  samples << [en, generated] if samples.size < 25
end

puts "learned_latin=#{learned.size} filled=#{filled} curated_kept=#{skipped_curated} untouched=#{unresolved} total=#{db.size}"
samples.each { |en, zh| puts "  #{en} => #{zh}" }

check = [
  "VITIS VINIFERA SEED EXTRACT",
  "CUCUMIS SATIVUS FRUIT EXTRACT",
  "CAMELLIA JAPONICA LEAF EXTRACT",
  "ROSA CANINA FRUIT EXTRACT",
  "ALOE BARBADENSIS LEAF EXTRACT",
  "WATER"
]
by = {}
db.each { |i| by[i["englishName"].to_s.strip.upcase] = i["chineseName"] }
puts "--- checks ---"
check.each { |en| puts "#{en} => #{by[en]}" }

if DRY_RUN
  puts "dry-run: not writing"
  exit 0
end

File.write(DB_PATH, JSON.pretty_generate(db) + "\n")
puts "wrote #{DB_PATH}"
