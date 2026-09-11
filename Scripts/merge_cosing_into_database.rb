#!/usr/bin/env ruby
# frozen_string_literal: true
# 將 CosIng expansion／common 補進現有 IngredientsDatabase.json。
# 只新增缺列，不覆蓋已整理的中文名、功能、評級。

require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
DB_PATH = File.join(ROOT, "Skincare", "IngredientsDatabase.json")
EXPANSION_PATH = File.join(__dir__, "cosing_expansion.json")
COMMON_PATH = File.join(__dir__, "cosing_common_ingredients.json")
SUNSCREEN_PATH = File.join(__dir__, "cosing_sunscreen_extras.json")

def acceptable_inci?(name)
  s = name.to_s.strip
  return false if s.length < 3 || s.length > 110
  return false if s.count("/") >= 4
  return false if s.split(/\s+/).length > 12
  return false if s.include?(" + ")
  true
end

def record_payload(display_en, zh, function, score, aliases)
  func = (function.nil? || function.to_s.strip.empty?) ? "一般成分" : function.to_s.strip
  {
    "englishName" => display_en,
    "chineseName" => zh,
    "function" => func,
    "safetyRating" => score.to_i.to_s,
    "aliases" => aliases,
    "name" => display_en,
    "category" => func
  }
end

def add_missing(db_by_key, name_en, name_zh, function, score, aliases)
  display_en = name_en.to_s.gsub(/\r/, "").strip.gsub(/\s+/, " ")
  return :skip if display_en.empty? || !acceptable_inci?(display_en)

  key = display_en.upcase
  aliases = Array(aliases).map { |a| a.to_s.strip }.reject(&:empty?)

  if db_by_key.key?(key)
    existing = db_by_key[key]
    merged = (Array(existing["aliases"]) + aliases).map { |a| a.to_s.strip }.reject(&:empty?).uniq
    if merged.size != Array(existing["aliases"]).size
      existing["aliases"] = merged
      return :alias
    end
    return :exists
  end

  zh = name_zh.to_s.gsub(/\r/, "").strip
  zh = display_en if zh.empty?
  db_by_key[key] = record_payload(display_en, zh, function, score, aliases)
  :added
end

def ingest_tuple_file(path, db_by_key, stats)
  unless File.exist?(path)
    warn "缺少 #{path}"
    return
  end
  JSON.parse(File.read(path)).each do |row|
    result = add_missing(db_by_key, row[0], row[1], row[2], row[3], row[4] || [])
    stats[result] += 1
  end
end

db = JSON.parse(File.read(DB_PATH))
before = db.size
db_by_key = {}
db.each do |item|
  key = item["englishName"].to_s.strip.upcase
  next if key.empty?
  db_by_key[key] ||= item
end

stats = Hash.new(0)
ingest_tuple_file(COMMON_PATH, db_by_key, stats)
ingest_tuple_file(SUNSCREEN_PATH, db_by_key, stats)
ingest_tuple_file(EXPANSION_PATH, db_by_key, stats)

# 安耐曬等高頻缺列：若已存在則只補別名，不覆蓋中文。
must_include = [
  ["HDI/Trimethylol Hexyllactone Crosspolymer", "HDI/三羥甲基己內酯交聯聚合物", "柔焦粉體、觸感調節", 1, ["HDI/TRIMETHYLOL HEXYLLACTONE CROSSPOLYMER", "HDI TRIMETHYLOL HEXYLLACTONE CROSSPOLYMER"]],
  ["PEG/PPG-14/7 Dimethyl Ether", "PEG/PPG-14/7 二甲醚", "溶劑、觸感調節", 1, ["PEG/PPG-14/7 DIMETHYL ETHER", "PEG PPG-14/7 DIMETHYL ETHER"]],
  ["Distearyldimonium Chloride", "二硬脂基二甲基氯化銨", "抗靜電、調理", 3, ["DISTEARYLDIMONIUM CHLORIDE", "DISTEARYL DIMONIUM CHLORIDE"]],
  ["Prunus Speciosa Leaf Extract", "大島櫻葉萃取", "抗氧化、舒緩", 1, ["PRUNUS SPECIOSA LEAF EXTRACT", "CERASUS SPECIOSA LEAF EXTRACT"]],
  ["Rosa Canina Fruit Extract", "玫瑰果萃取", "抗氧化、保濕", 1, ["ROSA CANINA FRUIT EXTRACT", "ROSEHIP EXTRACT", "ROSE HIP EXTRACT"]]
]
must_include.each do |row|
  key = row[0].to_s.strip.upcase
  if db_by_key.key?(key)
    existing = db_by_key[key]
    existing["aliases"] = (Array(existing["aliases"]) + row[4]).map { |a| a.to_s.strip }.reject(&:empty?).uniq
  else
    db_by_key[key] = record_payload(*row)
    stats[:added] += 1
  end
end

output = db_by_key.values.sort_by { |x| x["englishName"].to_s.downcase }
File.write(DB_PATH, JSON.pretty_generate(output) + "\n")
puts "before=#{before} after=#{output.size} added=#{stats[:added]} alias=#{stats[:alias]} exists=#{stats[:exists]} skip=#{stats[:skip]}"
