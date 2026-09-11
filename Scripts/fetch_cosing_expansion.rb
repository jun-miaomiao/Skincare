#!/usr/bin/env ruby
# frozen_string_literal: true
# 自 CosIng Checker 公開 API 拉取歐盟 INCI，寫入 cosing_expansion.json（離線可重用）。
# 既有列會保留；已在 IngredientsDatabase.json 的名稱仍寫進 expansion，方便之後整庫重建。

require "json"
require "net/http"
require "uri"

STDOUT.sync = true
ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(__dir__, "cosing_expansion.json")
CHECKPOINT = File.join(__dir__, ".cosing_fetch_checkpoint.json")

FUNCTION_ZH = {
  "SKIN CONDITIONING" => "肌膚調理",
  "EMOLLIENT" => "柔潤劑",
  "HUMECTANT" => "保濕劑",
  "SURFACTANT" => "界面活性劑",
  "EMULSIFYING" => "乳化劑",
  "VISCOSITY CONTROLLING" => "黏度調節",
  "PRESERVATIVE" => "防腐劑",
  "ANTIOXIDANT" => "抗氧化劑",
  "UV FILTER" => "防曬劑",
  "UV ABSORBER" => "紫外線吸收劑",
  "HAIR CONDITIONING" => "護髮調理",
  "CLEANSING" => "清潔劑",
  "FOAMING" => "起泡劑",
  "PERFUMING" => "香氛",
  "SOLVENT" => "溶劑",
  "BINDING" => "黏合劑",
  "FILM FORMING" => "成膜劑",
  "OPACIFYING" => "遮光劑",
  "COLORANT" => "著色劑",
  "ANTISTATIC" => "抗靜電",
  "BUFFERING" => "緩衝劑",
  "CHELATING" => "螯合劑",
  "DENATURANT" => "變性劑",
  "ABRASIVE" => "磨砂劑",
  "ABSORBENT" => "吸附劑",
  "ANTICAKING" => "抗結塊",
  "ANTIFOAMING" => "消泡劑",
  "ANTIMICROBIAL" => "抗菌劑",
  "ASTRINGENT" => "收斂劑",
  "BLEACHING" => "漂白",
  "BULKING" => "填充劑",
  "DEODORANT" => "體香劑",
  "DEPILATORY" => "脫毛",
  "EMULSION STABILISING" => "乳化穩定",
  "GEL FORMING" => "凝膠成型",
  "HAIR DYEING" => "染髮",
  "HAIR FIXING" => "定型",
  "HAIR WAVING OR STRAIGHTENING" => "燙髮／直髮",
  "KERATOLYTIC" => "角質軟化",
  "MASKING" => "掩味／掩味劑",
  "MOISTURISING" => "保濕",
  "NAIL CONDITIONING" => "護甲",
  "ORAL CARE" => "口腔護理",
  "OXIDISING" => "氧化劑",
  "PLASTICISER" => "塑化劑",
  "PROPELLANT" => "推進劑",
  "REDUCING" => "還原劑",
  "REFATTING" => "回脂劑",
  "REFRESHING" => "清涼感",
  "SKIN PROTECTING" => "肌膚防護",
  "SMOOTHING" => "柔滑",
  "SOOTHING" => "舒緩",
  "STABILISING" => "穩定劑",
  "TONIC" => "調理",
  "UV STABILISER" => "紫外線穩定"
}.freeze

# 先拉含 a 的大宗（API 約 2.8 萬筆），再補植萃關鍵字與其餘字母。
BOTANICAL_QUERIES = %w[
  extract oil water wax butter leaf fruit flower root seed
  ferment distillate juice powder peel bark rhizome sprout
  nectar hydrosol absolute resin gum honey milk
].freeze
LETTER_QUERIES = ("b".."z").to_a
EXTRA_QUERIES = %w[
  peg ppg sodium cetearyl cetyl stearyl glyceryl polyglyceryl
  acrylate dimethicone silica CI titanium zinc acid
  alcohol ester polymer copolymer peptide ceramide
  hyaluron panthenol tocopheryl ascorbyl paraben phenoxy
  fragrance limonene linalool citronellol geraniol eugenol
  benzophenone octocrylene avobenzone glycol siloxane
  bht edta ci
].freeze

def fetch_page(query, page)
  uri = URI("https://cosingchecker.com/api/v1/ingredients/")
  uri.query = URI.encode_www_form("q" => query, "per_page" => 100, "page" => page)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 20
  http.read_timeout = 40
  req = Net::HTTP::Get.new(uri)
  req["User-Agent"] = "SkincareIngredientDB/1.0"
  res = http.request(req)
  return nil unless res.is_a?(Net::HTTPSuccess)
  JSON.parse(res.body)
rescue StandardError => e
  warn "fetch failed q=#{query} page=#{page}: #{e}"
  nil
end

def fetch_page_retry(query, page, attempts: 4)
  attempts.times do |i|
    data = fetch_page(query, page)
    return data unless data.nil?
    sleep(0.4 * (i + 1))
  end
  nil
end

def acceptable_inci?(name)
  return false if name.nil?
  s = name.to_s.strip
  return false if s.length < 3 || s.length > 110
  return false if s.count("/") >= 4
  return false if s.split(/\s+/).length > 12
  return false if s.include?(" + ")
  true
end

def map_function(row)
  funcs = Array(row["functions"]).map { |f| f.to_s.upcase.strip }.reject(&:empty?)
  funcs = [row["function"].to_s.upcase.strip] if funcs.empty? && row["function"]
  mapped = funcs.map { |f| FUNCTION_ZH[f] || f.downcase.tr("_", " ") }.uniq
  mapped.empty? ? "一般成分" : mapped.join("、")
end

def safety_for(function_text)
  t = function_text.to_s
  return 8 if t.include?("香氛") || t.downcase.include?("perfum")
  return 4 if t.include?("防腐")
  return 3 if t.include?("著色") || t.include?("防曬") || t.include?("紫外線")
  return 5 if t.include?("過敏")
  1
end

def row_from_api(api_row)
  inci = api_row["inci_name"].to_s.strip
  func = map_function(api_row)
  display = inci
  if inci != inci.upcase && !inci.include?("-") && !inci.include?("/")
    display = inci.split.map(&:capitalize).join(" ").gsub(/\bCi\b/, "CI")
  end
  aliases = []
  %w[inn_name ph_eur_name].each do |field|
    extra = api_row[field].to_s.strip
    aliases << extra unless extra.empty? || extra.upcase == inci.upcase
  end
  [display, inci, func, safety_for(func), aliases]
end

def persist_expansion(collected)
  rows = collected.values.sort_by { |r| r[0].to_s.downcase }
  File.write(OUTPUT, JSON.pretty_generate(rows))
  rows.size
end

collected = {}
if File.exist?(OUTPUT)
  JSON.parse(File.read(OUTPUT)).each do |row|
    key = row[0].to_s.strip.upcase
    next if key.empty?
    collected[key] = row
  end
end
puts "seeded expansion #{collected.size}"
puts "fetching CosIng inventory…"

done_queries = {}
if File.exist?(CHECKPOINT)
  begin
    done_queries = JSON.parse(File.read(CHECKPOINT))
  rescue StandardError
    done_queries = {}
  end
end

def ingest_query(query, max_pages, collected, done_queries)
  start_page = Integer(done_queries[query] || 0) + 1
  page = start_page
  while page <= max_pages
    data = fetch_page_retry(query, page)
    if data.nil?
      warn "skip persist; will retry q=#{query} page=#{page} next run"
      break
    end
    results = Array(data["results"])
    api_pages = Integer(data["num_pages"] || 0)
    api_pages = max_pages if api_pages <= 0
    if results.empty?
      done_queries[query] = page
      break
    end
    before = collected.size
    results.each do |row|
      inci = row["inci_name"].to_s.strip
      next unless acceptable_inci?(inci)
      key = inci.upcase
      next if collected.key?(key)
      collected[key] = row_from_api(row)
    end
    done_queries[query] = page
    added = collected.size - before
    puts "q=#{query} page=#{page}/#{api_pages} +#{added} expansion=#{collected.size} api_count=#{data["count"]}"
    if (page % 10).zero?
      persist_expansion(collected)
      File.write(CHECKPOINT, JSON.pretty_generate(done_queries))
    end
    break if page >= api_pages || page >= max_pages
    page += 1
    sleep 0.05
  end
end

ingest_query("a", 400, collected, done_queries)
BOTANICAL_QUERIES.each { |q| ingest_query(q, 120, collected, done_queries) }
# q=a 已覆蓋大多數含 a 的 INCI；其餘字母只補缺口，避免重跑 2.8 萬筆。
if collected.size < 12_000
  LETTER_QUERIES.each { |q| ingest_query(q, 25, collected, done_queries) }
  EXTRA_QUERIES.each { |q| ingest_query(q, 15, collected, done_queries) }
else
  EXTRA_QUERIES.each { |q| ingest_query(q, 8, collected, done_queries) }
end

size = persist_expansion(collected)
File.write(CHECKPOINT, JSON.pretty_generate(done_queries))
puts "Wrote #{size} rows -> #{OUTPUT}"
