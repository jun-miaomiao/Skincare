#!/usr/bin/env ruby
# frozen_string_literal: true
# 用公開官方對照補中文名：中國 IECIC、2010 標準中文名稱目錄、衛福部 TFDA。
# 只填「中文名仍是 INCI 原文」的列，不覆蓋已有中文。

require "json"

ROOT = File.expand_path("..", __dir__)
DB_PATH = File.join(ROOT, "Skincare", "IngredientsDatabase.json")
VENDOR = File.join(__dir__, "vendor")
CATALOGUE_2010 = File.join(__dir__, "vendor", "inci_chinese_catalogue_2010.txt")
MAPPING_OUT = File.join(__dir__, "inci_chinese_names.json")

def has_cjk?(text)
  text.to_s =~ /[\u4e00-\u9fff]/
end

def decode_xml(text)
  text.to_s
      .gsub("&amp;", "&")
      .gsub("&lt;", "<")
      .gsub("&gt;", ">")
      .gsub("&#10;", "\n")
end

def load_opencc
  chars = {}
  char_path = File.join(VENDOR, "STCharacters.txt")
  if File.exist?(char_path)
    File.foreach(char_path) do |line|
      from, to = line.strip.split("\t", 2)
      next if from.nil? || to.nil?
      chars[from] = to.split(" ").first
    end
  end
  phrases = [
    ["头发", "頭髮"], ["护发", "護髮"], ["发用", "髮用"], ["发胶", "髮膠"],
    ["发蜡", "髮蠟"], ["发膜", "髮膜"], ["洗发", "洗髮"], ["润发", "潤髮"],
    ["染发", "染髮"], ["烫发", "燙髮"], ["发油", "髮油"], ["发乳", "髮乳"],
    ["条件剂", "調理劑"], ["皮肤", "皮膚"]
  ]
  [chars, phrases]
end

def to_traditional(text, chars, phrases)
  value = text.to_s.dup
  phrases.each { |from, to| value.gsub!(from, to) }
  value.gsub!(/./u) { |ch| chars[ch] || ch }
  value
      .gsub("提取物", "萃取")
      .gsub("提取", "萃取")
      .gsub(/（[A-Z0-9 \-\/.,'+]+）/, "")
      .gsub(/\*+\z/, "")
      .gsub(/\s+/, "")
      .strip
end

def parse_iecic
  ss_path = File.join(VENDOR, "iecic_unzip/xl/sharedStrings.xml")
  sheet_path = File.join(VENDOR, "iecic_unzip/xl/worksheets/sheet1.xml")
  return {} unless File.exist?(ss_path) && File.exist?(sheet_path)

  ss_xml = File.read(ss_path)
  strings = ss_xml.scan(/<si>(.*?)<\/si>/m).map { |s|
    chunk = s.is_a?(Array) ? s.join : s
    decode_xml(chunk.scan(/<t[^>]*>([^<]*)<\/t>/).flatten.join)
  }
  sheet = File.read(sheet_path)
  map = {}
  header_seen = false
  sheet.scan(/<row [^>]*>(.*?)<\/row>/m) do |row|
    row = row.is_a?(Array) ? row.join : row
    cells = {}
    row.scan(/<c ([^>]*)>(.*?)<\/c>/m) do |attrs, body|
      attrs = attrs.is_a?(Array) ? attrs.join : attrs
      body = body.is_a?(Array) ? body.join : body
      col = attrs[/r="([A-Z]+)\d+"/, 1]
      t = attrs[/t="([^"]+)"/, 1]
      v = body[/<v>([^<]*)<\/v>/, 1]
      val = if v.nil? then "" elsif t == "s" then strings[v.to_i].to_s else v end
      cells[col] = val if col
    end
    zh = cells["B"].to_s.strip
    en = cells["C"].to_s.strip
    unless header_seen
      header_seen = true if zh.include?("中文名称") || en.include?("INCI")
      next
    end
    next if en.empty? || zh.empty? || !has_cjk?(zh)
    en.split(/\n/).each do |piece|
      piece = piece.strip
      next if piece.empty?
      map[piece.upcase] ||= zh
    end
  end
  map
end

def parse_catalogue_2010
  return {} unless File.exist?(CATALOGUE_2010)
  raw = File.read(CATALOGUE_2010)
  text = raw.gsub(/No\.\s*INCI Name\s*Chinese Name\s*CAS No\./i, " ")
  text = text.gsub(/Catalogue of Standard Chinese Name[^\n]*/, " ")
  text = text.gsub(/\r/, " ").gsub(/\n/, " ").gsub(/\s+/, " ")
  map = {}
  re = /(\d{1,5})\s+([A-Z][A-Z0-9 \-\/().,'+*:;%]{2,}?)\s+([\u4e00-\u9fff][^\d]{0,80}?)(?=\s+\d{1,5}\s+[A-Z]|\s+\d{2,5}-\d{2}-\d|\s*$)/
  text.scan(re) do |_idx, inci, zh|
    inci = inci.gsub(/\s+/, " ").strip
    zh = zh.gsub(/\s+/, "").strip
    next if inci.length < 3 || !has_cjk?(zh)
    map[inci.upcase] ||= zh
  end
  map
end

def parse_tfda
  map = {}
  Dir[File.join(VENDOR, "tfda_*.json")].each do |path|
    JSON.parse(File.read(path)).each do |row|
      next unless row.is_a?(Hash)
      en = row["INCI名"] || row["INCI_NAME"] || row["成分英文名稱"]
      zh = row["成分名"] || row["成分中文名稱"] || row["中文名稱"] || row["成分名稱"]
      next if en.to_s.strip.empty? || !has_cjk?(zh)
      en.to_s.split(%r{[/\n;,]}).each do |piece|
        piece = piece.gsub(/\(\d+\)/, "").strip
        next if piece.length < 3
        map[piece.upcase] ||= zh.to_s.strip
      end
    end
  end
  map
end

chars, phrases = load_opencc
puts "opencc chars=#{chars.size} phrases=#{phrases.size}"

tfda = parse_tfda
iecic = parse_iecic
cat2010 = parse_catalogue_2010
puts "tfda=#{tfda.size} iecic=#{iecic.size} catalogue2010=#{cat2010.size}"

combined = {}
# 覆蓋優先：較舊／較廣的先放，官方較新的後放，TFDA 繁中最後。
[cat2010, iecic, tfda].each do |src|
  src.each { |k, v| combined[k] = v }
end

traditional = {}
combined.each do |en, zh|
  zh_tw = to_traditional(zh, chars, phrases)
  next if zh_tw.empty? || !has_cjk?(zh_tw)
  next if zh_tw.upcase == en
  traditional[en] = zh_tw
end
File.write(MAPPING_OUT, JSON.pretty_generate(traditional))
puts "mapping=#{traditional.size} -> #{MAPPING_OUT}"

db = JSON.parse(File.read(DB_PATH))
filled = 0
skipped_curated = 0
missed = 0
db.each do |item|
  en = item["englishName"].to_s.strip
  current = item["chineseName"].to_s.strip
  already = has_cjk?(current) && current.upcase != en.upcase
  if already
    skipped_curated += 1
    next
  end
  zh = traditional[en.upcase]
  unless zh
    missed += 1
    next
  end
  item["chineseName"] = zh
  filled += 1
end
File.write(DB_PATH, JSON.pretty_generate(db) + "\n")
puts "filled=#{filled} curated_kept=#{skipped_curated} still_english=#{missed} total=#{db.size}"
