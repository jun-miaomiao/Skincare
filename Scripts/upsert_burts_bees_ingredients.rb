# encoding: utf-8
require "json"

path = File.expand_path("../Skincare/IngredientsDatabase.json", __dir__)
db = JSON.parse(File.read(path))

def upsert!(db, en, zh, func, score, aliases)
  norm = ->(s) { s.to_s.upcase.gsub(/[^A-Z0-9]/, "") }
  target = norm.call(en)
  idx = db.index { |e| norm.call(e["englishName"]) == target }
  idx ||= db.index do |e|
    Array(e["aliases"]).any? { |a| norm.call(a) == target }
  end

  if idx
    item = db[idx]
    als = Array(item["aliases"]).map(&:to_s)
    ([en] + aliases).each do |a|
      als << a unless als.map { |x| x.upcase }.include?(a.upcase)
    end
    item["aliases"] = als.uniq
    if item["chineseName"].to_s.strip.empty? || item["chineseName"] == item["englishName"]
      item["chineseName"] = zh
    end
    item["function"] = func if item["function"].to_s.strip.empty?
    item["safetyRating"] = score.to_s if item["safetyRating"].to_s.strip.empty?
    puts "update #{item["englishName"]}"
  else
    db << {
      "englishName" => en,
      "chineseName" => zh,
      "function" => func,
      "safetyRating" => score.to_s,
      "aliases" => ([en] + aliases).uniq
    }
    puts "add #{en}"
  end
end

upsert!(db, "Beeswax", "蜂蠟", "增稠乳化、成膜", 1, ["CERA ALBA", "BEES WAX", "CERAALBA", "BEESWAX"])
upsert!(db, "Lanolin", "羊毛脂", "柔潤修護", 1, ["LANOLINE", "LANOLIN"])
upsert!(db, "Cannabis Sativa Seed Oil", "大麻籽油", "柔潤滋養", 1, ["HEMP SEED OIL", "CANNABIS SATIVA OIL", "CANNABIS SATIVA SEED OIL"])
upsert!(db, "Cocos Nucifera Oil", "椰子油", "柔潤滋養", 1, ["COCOS NUCIFERA (COCONUT) OIL", "COCONUT OIL", "COCOS NUCIFERA OIL"])
upsert!(db, "Glycine Soja Oil", "大豆油", "柔潤", 1, ["GLYCINE SOJA (SOYBEAN) OIL", "SOYBEAN OIL", "GLYCINE MAX OIL"])
upsert!(db, "Rosmarinus Officinalis Leaf Extract", "迷迭香葉萃取", "抗氧化", 1, ["ROSMARINUS OFFICINALIS (ROSEMARY) LEAF EXTRACT", "ROSEMARY LEAF EXTRACT"])
upsert!(db, "Canola Oil", "芥花油", "柔潤", 1, ["BRASSICA CAMPESTRIS OIL", "RAPESEED OIL", "BRASSICA NAPUS OIL"])
upsert!(db, "Rebaudioside A", "甜菊糖苷", "甜味劑", 1, ["REBAUDIOSIDE", "STEVIOL GLYCOSIDE", "STEVIA"])
upsert!(db, "Flavor", "香料", "調味香氛", 4, ["FLAVOUR", "NATURAL FLAVOR", "NATURAL FLAVOUR", "AROMA"])
upsert!(db, "Tocopherol", "生育酚（維生素 E）", "抗氧化", 1, ["VITAMIN E", "TOCOPHERYL ACETATE"])

File.write(path, JSON.pretty_generate(db) + "\n")
puts "total #{db.size}"
