#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true
# 補常見缺本尊 INCI／別名；只做局部字串修補，不整檔 pretty 重寫。

Encoding.default_external = Encoding::UTF_8
path = File.expand_path("../Skincare/IngredientsDatabase.json", __dir__)
text = File.read(path, encoding: "UTF-8")

replacements = [
  [
    %(    "englishName": "Pyridoxine",\n    "safetyRating": "1",\n    "aliases": [\n      "VITAMIN B6"\n    ],),
    %(    "englishName": "Pyridoxine",\n    "safetyRating": "1",\n    "aliases": [\n      "VITAMIN B6",\n      "PYRIDOXINE HCL",\n      "PYRIDOXINE HYDROCHLORIDE",\n      "VITAMIN B6 HCL"\n    ],)
  ],
  [
    %(    "englishName": "3-O-ethyl ascorbic acid",\n    "aliases": [\n\n    ],),
    %(    "englishName": "3-O-ethyl ascorbic acid",\n    "aliases": [\n      "ETHYL ASCORBIC ACID",\n      "3-O-ETHYL-ASCORBIC ACID",\n      "ETHYL ASCORBATE"\n    ],)
  ],
  [
    "    \"englishName\": \"Retinal\",\n    \"safetyRating\": \"5\",\n    \"chineseName\": \"視黃醛\",\n    \"name\": \"Retinal\",\n    \"aliases\": [\n\n    ]",
    "    \"englishName\": \"Retinal\",\n    \"safetyRating\": \"5\",\n    \"chineseName\": \"視黃醛\",\n    \"name\": \"Retinal\",\n    \"aliases\": [\n      \"RETINALDEHYDE\",\n      \"RETINALDEHYD\"\n    ]"
  ],
  [
    %(    "englishName": "OLIGOPEPTIDE-1",\n    "aliases": [\n      "OLIGOPEPTIDE-1",\n      "OLICOPEPTIDE-1"\n    ],),
    %(    "englishName": "OLIGOPEPTIDE-1",\n    "aliases": [\n      "OLIGOPEPTIDE-1",\n      "OLICOPEPTIDE-1",\n      "SH-OLIGOPEPTIDE-1",\n      "RH-OLIGOPEPTIDE-1",\n      "EGF"\n    ],)
  ]
].map { |pair| pair.map { |s| s.encode("UTF-8") } }

replacements.each_with_index do |(old, new), idx|
  raise "alias patch #{idx} not found:\n#{old.inspect}" unless text.include?(old)
  text = text.sub(old, new)
end

raise "Ectoin already present" if text.include?('"englishName": "Ectoin"')
raise "Inulin already present" if text.match?(/"englishName": "Inulin"/)
raise "Polyisobutene already present" if text.match?(/"englishName": "Polyisobutene"/)
raise "Xylitylglucoside already present" if text.match?(/"englishName": "Xylitylglucoside"/)

append = <<~'JSON'.chomp
,
  {
    "englishName": "Ectoin",
    "name": "Ectoin",
    "chineseName": "依克多因",
    "function": "保濕劑、肌膚調理",
    "category": "保濕劑、肌膚調理",
    "safetyRating": "1",
    "aliases": [
      "ECTOINE",
      "四氫甲基嘧啶羧酸",
      "エクトイン",
      "엑토인"
    ]
  },
  {
    "englishName": "Inulin",
    "name": "Inulin",
    "chineseName": "菊粉",
    "function": "肌膚調理、保濕",
    "category": "肌膚調理、保濕",
    "safetyRating": "1",
    "aliases": [
      "INULIN POWDER",
      "イヌリン",
      "이눌린"
    ]
  },
  {
    "englishName": "Polyisobutene",
    "name": "Polyisobutene",
    "chineseName": "聚異丁烯",
    "function": "黏度調節、成膜",
    "category": "黏度調節、成膜",
    "safetyRating": "1",
    "aliases": [
      "POLYISOBUTENE",
      "PIB",
      "ポリイソブテン",
      "폴리이소부텐"
    ]
  },
  {
    "englishName": "Xylitylglucoside",
    "name": "Xylitylglucoside",
    "chineseName": "木糖醇基葡糖苷",
    "function": "保濕劑",
    "category": "保濕劑",
    "safetyRating": "1",
    "aliases": [
      "XYLITYL GLUCOSIDE",
      "キシリチルグルコシド",
      "자일리틸글루코사이드"
    ]
  }
JSON

stripped = text.rstrip
raise "unexpected end" unless stripped[-1] == "]"
body = stripped[0...-1].rstrip
raise "expected object before array end" unless body.end_with?("}")
text = body + append + "\n]\n"

require "json"
JSON.parse(text)

File.write(path, text)
puts "patched OK bytes=#{text.bytesize}"
