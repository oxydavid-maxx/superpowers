# SUPERPOWER-FEEDBACK 2026-07-03 — expected-mock 教義缺失導致跨 session 品質滑坡

## 現象
superpower-graph Phase 3 的 expected mock v1 只畫了「變更切片」(新節點+鄰近),被光佑退件。Phase 2 的 mock 是「全景+變更標注」(phase2-mock-v3-product-map.svg),品質標準明顯更高。

## Root cause
教義只存在於歷史 artifact 的檔名與該次對話,brainstorming skill 原文只寫「produce expected mock artifact」——不夠 generic & 精確,新 session 照字面執行必然滑坡。

## 建議修改(brainstorming skill 的 Expected mock 節)
把 mock 要求改為:
1. 基底 = 整個流程/產品的**成品全景**(pipeline 類:每站 skill/能力/input/品質放行/獨立審核/退回 loop;UI 類:全部 surfaces);
2. 本次 spec 變更以 **overlay 高亮 + Cap-ID 掛牌**標注在受影響位置,未變更部分照畫但降飽和;
3. v2 於 FINAL 後按同一基底重疊(教義:mock 是「成品長什麼樣+這次動哪裡」,不是「這次做了什麼」)。

## 佐證
- 光佑原話:「mock 要以整個流程的成品來做為基底,然後把 spec change 掛上去標示」(2026-07-03)。
- 已同步寫入使用者 memory(mock-doctrine-baseline-plus-overlay)。
