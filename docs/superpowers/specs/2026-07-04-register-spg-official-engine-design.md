# Register superpower-graph (spg) as Official Superpower Execution Engine

- Status: **FINAL**(2026-07-04,光佑 directive:「把 superpower graph 註冊為正式的 superpower. 把 current 指過去。」)
- Date: 2026-07-04
- Owner: 光佑(approver)/ orchestrator session(author)
- Upstream evidence: superpower-graph Phase 3 verify(558 tests green;verify-arch 16/16 reachable;verify-spec 16/16 MATCHES;`C:\dev\superpower-graph\.superpowers\verify\verdicts-{arch,spec}-p3.json`)

## Problem

superpower-graph Phase 3 已達可量產狀態,但生態系的 superpower 入口(fork 的
`using-superpowers` Entry Comprehension Gate)仍宣告 S4_BUILD executor 預設為
`current session`,未向任何 session 揭示 spg 為正式執行引擎。光佑指示「把 current
指過去」——生態系中唯一的 `current` 指標是
`~/.claude/plugins/cache/superpowers-dev/superpowers/current`(plugin 安裝 junction)。
直接把該 junction 指到 C:\dev\superpower-graph(Python repo,非 plugin)會使
superpowers plugin 無法載入、所有 superpowers:* skills 失效,故正確實現是:
**發一版 fork(vmodel.15)載明 spg 為正式引擎,`current` junction 依標準發版
routine 指到該新版**。

## Non-Goals

- S5/S6 移入 spg(Phase 4 才有 verify/release 節點,在此之前仍走 in-session skills)。
- 修復 fork 既有的 FSM runtime 測試破損(test-design.json lint 缺 exploratory/
  forbidden-state 類別;4423828 收緊 lint 所致,先於本變更存在,另案處理)。

## Capability Registry

```registry
[
  {"cap_id": "CAP-REG-01", "need_ids": ["N-REG-01"],
   "user_outcome": "任何新 session 讀到的 superpower 入口 gate 都載明:正式 superpower 執行引擎=superpower-graph(spg);S4_BUILD executor 預設=spg fleet(spg-compatible repo),fallback=current session;S5/S6 仍走 in-session skills 直到 spg Phase 4",
   "entry_point": "using-superpowers SKILL.md", "entry_type": "skill",
   "reachable_path": "SessionStart hook 注入 using-superpowers 全文 → Entry Comprehension Gate 表 S4_BUILD 行 + Registered Superpower Engine 節",
   "acceptance": {"given": "fork 發版 vmodel.15 且 pin 完成", "when": "解析 cache/superpowers-dev/superpowers/current 下的 skills/using-superpowers/SKILL.md", "then": "含 'Registered Superpower Engine' 節、S4_BUILD 表行載 superpower-graph (spg)、executor 預設條款改為 spg-when-compatible;manifest 7 目標同版 6.0.3-vmodel.15;current junction 解析到 vmodel.15 目錄"},
   "failure_modes": ["current junction 指到 Python repo → plugin 載入失敗(本設計明確禁止)", "只改 cache 不改 source → 下次 update 被覆蓋(FORK-MAINTENANCE NEVER-do)"],
   "type_tags": ["behavior_rule"], "gap_questions": []}
]
```

## Verification

- 發版 gates(全綠才可 push):`bump-version.sh --check`、`test-manifest-version-coherency.sh`、`test-fork-provenance.sh`、`test-vmodel-contracts.ps1`。
- 獨立 verdict(非建造者 agent):斷言 SKILL.md 三處變更存在且與本 registry 一致 → `.superpowers/verify/verdicts-spec-register-spg.json`。
- Pin 後驗證:`verify-local-fork-install.ps1 -ExpectedVersion 6.0.3-vmodel.15`(current 指標+HEAD+manifest 三方一致)。
