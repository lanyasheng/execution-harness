# Article Gap Analysis: ata-execution-harness-v3.md vs Current Codebase

Generated: 2026-04-06

---

## 1. What the Article Describes (v3 article)

- **21 patterns** in a flat numbered list (1-21)
- **3 skills** organized by reader type:
  - `agent-hooks/` (developer: install hooks, configure settings.json)
  - `harness-design-patterns/` (architect: design reference)
  - `agent-ops/` (SRE: monitoring, recovery, protection)
- **8 bash scripts**, 42 tests
- **No meta-principles layer** -- jumps straight from motivation to architecture
- Source baseline: Claude Code v2.1.88
- Detailed deep-dives on 7 patterns: Ralph, Doubt Gate, Tool Error Escalation, Handoff, Adaptive Complexity, Checkpoint+Rollback, Post-Edit Diagnostics
- `npx skills add` installation
- Session-scoped state layout in `sessions/<session-id>/`

## 2. What Currently Exists (v2 codebase)

- **38 patterns** in hierarchical numbering (X.Y per axis)
- **6 skills** organized by functional axis:
  - `execution-loop/` (7 patterns)
  - `tool-governance/` (6 patterns)
  - `context-memory/` (7 patterns)
  - `multi-agent/` (6 patterns)
  - `error-recovery/` (6 patterns)
  - `quality-verification/` (6 patterns)
- **17 bash scripts**, 42 tests (5 test files), 45 reference docs
- **10 meta-principles** in `principles.md` (M1-M10)
- README badge says "38 patterns"
- Sources expanded: now includes Harness Engineering book (`harness-books`)

## 3. Specific Discrepancies

### 3.1 Architecture (CRITICAL -- completely different)

| Dimension | Article | Reality |
|-----------|---------|---------|
| Skill count | 3 | 6 |
| Organizational principle | by reader type (dev/architect/SRE) | by functional axis |
| Skill names | agent-hooks, harness-design-patterns, agent-ops | execution-loop, tool-governance, context-memory, multi-agent, error-recovery, quality-verification |
| Pattern count | 21 | 38 |
| Pattern numbering | flat 1-21 | hierarchical X.Y (1.1-6.6) |
| Script count | 8 | 17 |
| Meta-principles | not mentioned | 10 (M1-M10) |

### 3.2 Pattern Mapping (21 article patterns vs 38 reality)

Article patterns that still exist (but renumbered/relocated):

| Article # | Article Name | Current Location | Notes |
|-----------|-------------|-----------------|-------|
| 1 | Ralph persistent execution | 1.1 execution-loop | Mostly unchanged |
| 2 | Handoff documents | 3.1 context-memory | Mostly unchanged |
| 3 | Tool error escalation | 2.1 tool-governance | Mostly unchanged |
| 4 | Rate limit recovery | 5.1 error-recovery | Mostly unchanged |
| 5 | Context estimation | 3.5 context-memory | Mostly unchanged |
| 6 | Atomic file writes | 6.5 quality-verification | Mostly unchanged |
| 7 | Cancel TTL | Folded into 1.1 Ralph | No longer standalone |
| 8 | Compaction memory extraction | 3.2 context-memory | Mostly unchanged |
| 9 | Denial tracking | 2.2 tool-governance | Renamed "Denial circuit breaker" |
| 10 | Three-gate memory consolidation | 3.3 context-memory | Mostly unchanged |
| 11 | Hook pair bracket | 6.3 quality-verification | Mostly unchanged |
| 12 | Component-scoped hooks | 2.5 tool-governance | Mostly unchanged |
| 13 | Doubt gate | 1.2 execution-loop | Mostly unchanged |
| 14 | Three delegation modes | 4.1 multi-agent | Mostly unchanged |
| 15 | Post-edit diagnostics | 6.1 quality-verification | Mostly unchanged |
| 16 | Adaptive complexity | 1.3 execution-loop | Mostly unchanged |
| 17 | Stale session daemon | 5.3 error-recovery | Mostly unchanged |
| 18 | Hook runtime profiles | 6.2 quality-verification | Mostly unchanged |
| 19 | Checkpoint + rollback | 2.3 tool-governance | Mostly unchanged |
| 20 | Token budget per subtask | 3.4 context-memory | Mostly unchanged |
| 21 | Auto model fallback | 5.6 error-recovery | Renamed "Model fallback advisory" |

**17 patterns in reality that do not exist in the article:**

| # | Pattern | Axis | Type |
|---|---------|------|------|
| 1.4 | Task completion verifier | execution-loop | [script] |
| 1.5 | Drift re-anchoring | execution-loop | [script] |
| 1.6 | Headless execution control | execution-loop | [config] |
| 1.7 | Iteration-aware messaging | execution-loop | [design] |
| 2.4 | Graduated permission rules | tool-governance | [config] |
| 2.6 | Tool input guard | tool-governance | [script] |
| 3.6 | Filesystem as working memory | context-memory | [design] |
| 3.7 | Compaction quality audit | context-memory | [design] |
| 4.2 | Shared task list protocol | multi-agent | [design] |
| 4.3 | File claim and lock | multi-agent | [design] |
| 4.4 | Agent workspace isolation | multi-agent | [design] |
| 4.5 | Synthesis gate | multi-agent | [design] |
| 4.6 | Review-execution separation | multi-agent | [design] |
| 5.2 | Crash state recovery | error-recovery | [design] |
| 5.4 | MCP reconnection | error-recovery | [design] |
| 5.5 | Graceful tool degradation | error-recovery | [design] |
| 6.4 | Test-before-commit gate | quality-verification | [script] |
| 6.6 | Session state hygiene | quality-verification | [design] |

### 3.3 Scripts Not in Article (9 of 17)

Article mentions 8 scripts. Reality has 17. The 9 new ones:

1. `task-completion-gate.sh` -- reads .harness-tasks.json, blocks if incomplete
2. `drift-reanchor.sh` -- re-injects original task every N turns
3. `denial-tracker.sh` -- infers permission denials from conversation
4. `checkpoint-rollback.sh` -- git stash before destructive bash commands
5. `tool-input-guard.sh` -- path boundary + dangerous pattern validation
6. `bracket-hook.sh` -- per-turn time/tool-call measurement
7. `test-before-commit.sh` -- runs tests before git commit
8. `compaction-extract.sh` -- extracts key decisions to handoff
9. `context-usage.sh` -- estimates context window usage

Note: checkpoint-rollback.sh, compaction-extract.sh, and context-usage.sh are described as design patterns in the article but now have actual script implementations. This contradicts the article's claim of "13 design reference, 8 executable."

### 3.4 Settings.json Paths

Article references: `skills/agent-hooks/scripts/ralph-stop-hook.sh`
Reality uses: `skills/execution-loop/scripts/ralph-stop-hook.sh`

Every settings.json example in the article has wrong paths.

### 3.5 Numbers Throughout the Article

| Claim in article | Reality | Location in article |
|-----------------|---------|---------------------|
| "21 patterns" | 38 patterns | TL;DR, section title, multiple places |
| "8 bash scripts" | 17 scripts | TL;DR, section 3.1 |
| "13 design reference" | 21 design patterns | TL;DR, section 6 |
| "3 skills" | 6 skills | Section 3.1, architecture diagram |
| "3 types of readers" | N/A (organized by function) | Section 3 |
| "21 pattern → 3 skill" | 38 patterns → 6 skills | Source attribution diagram |
| "从 12 到 21" | From 12 to 38 | Section 5.2 |
| "从一个文件到三个 Skill" | From one file to six skills | Section 5.2 |

### 3.6 Missing Entirely from Article

- **10 meta-principles (M1-M10)** -- `principles.md` defines foundational principles. The article has zero mention.
- **harness-books source** -- README cites `github.com/wquguru/harness-books` as a primary source for the meta-principles. Article doesn't reference it.
- **"What This Is NOT" section** -- README has a clear anti-pattern section. Article doesn't.
- **Reference files** -- 45 reference docs across 6 skills. Article mentions numbered references but describes old naming scheme.

### 3.7 Article Content That Doesn't Match Reality

- **Section 3.1**: "12 patterns 全塞一个 SKILL.md" then "所以拆了" into 3 skills. Reality: it was further split into 6.
- **Section 3.1 directory tree**: Shows `agent-hooks/`, `harness-design-patterns/`, `agent-ops/`. These directories do not exist.
- **Section 3.1 diagram**: Three-column layout (agent-hooks / harness-design-patterns / agent-ops). Completely wrong.
- **Pattern overview table (21 rows)**: Missing 17 patterns. All pattern numbers wrong.
- **"常见场景选型" table**: References patterns by old names.
- **Section 3.4 Hook Protocol table**: Shows 5 hook events with old script names.
- **Section 3.5 Installation**: `npx skills add` example may still work but skill listing is wrong (3 vs 6).
- **Section 4.8**: References pattern numbers (P1, P5, P9, P13) that are prompt-hardening numbers, not execution-harness numbers -- this is actually correct as-is, but the execution-harness pattern references within 4.8 use old numbers.
- **Section 5.1**: "4 轮 × 3 agent" review -- may be outdated if additional review rounds were done for v2.
- **Section 5.2**: The narrative "12→21, 1 file→3 skills" is now "12→38, 1 file→6 skills."

---

## 4. Salvageability Assessment

### High Salvageability (80%+ reusable)

| Section | Salvage % | Why |
|---------|-----------|-----|
| 1. Motivation ("你的 Agent 真的在干活吗") | 95% | Pain points unchanged. Just update "21 patterns" → "38 patterns" in one line. |
| 2.1 PCA analogy | 95% | Methodology unchanged. |
| 2.2 Review-Execution separation | 95% | Process unchanged. |
| 2.3 Distillation pitfalls | 90% | Anecdotes unchanged. |
| 4.1 Ralph deep-dive | 85% | Core logic same. Minor name/path updates. |
| 4.2 Doubt Gate deep-dive | 85% | Core logic same. |
| 4.3 Tool Error Escalation deep-dive | 85% | Core logic same. |
| 4.4 Handoff deep-dive | 80% | Core logic same. |
| 4.6 Checkpoint+Rollback deep-dive | 80% | Core logic same. |
| 4.7 Post-Edit Diagnostics deep-dive | 80% | Core logic same. |
| 4.9 E2E verification | 80% | Flow may have expanded but base scenario same. |
| 6. Known limitations | 70% | Some new, some may be resolved. |
| 7. Open questions | 70% | Some new questions needed. |

### Medium Salvageability (40-70% reusable)

| Section | Salvage % | Why |
|---------|-----------|-----|
| 2.4 Source attribution | 60% | New sources needed, table needs expansion. |
| 4.5 Adaptive Complexity | 70% | Now 1.3, may have evolved. |
| 4.8 prompt-hardening relationship | 60% | Pattern cross-references need updating to new IDs. |
| 5.1 Four-round review | 50% | Numbers changed, may need additional review coverage. |
| 5.2 "12→21" narrative | 40% | Numbers entirely wrong, narrative arc needs rewrite. |
| 5.3 Quality metrics | 50% | Concept same, specifics may have changed. |
| "常见场景选型" table | 40% | Pattern names all wrong, new combos possible. |

### Low Salvageability (needs near-total rewrite)

| Section | Salvage % | Why |
|---------|-----------|-----|
| 3.1 Architecture ("拆分原因") | 15% | 3 skills → 6 axes. Story, diagram, directory tree all wrong. |
| 3.2 Session state layout | 50% | May have new state files for new patterns. |
| 3.3 bash+jq rationale | 80% | Still valid. |
| 3.4 Hook protocol table | 30% | More hooks, more scripts, old paths. |
| 3.5 Installation | 40% | Skills listing wrong. |
| Pattern overview table (21 rows) | 0% | Complete rewrite. Need 38-row table with new numbering. |
| All HTML diagrams | 20% | Architecture diagrams show wrong skill names. |

### Overall: ~60% of article content is salvageable in substance, but ~40% of sections need structural rework.

---

## 5. New Content Needed

### Must-add (article is incomplete without these)

1. **10 meta-principles section** -- The article has no mention of M1-M10. This is now a defining feature of the project, sourced from harness-books. Needs ~500-800 words.

2. **Updated pattern overview table** -- 38 rows, hierarchical numbering, organized by axis. The existing 21-row table must be replaced entirely.

3. **Updated architecture section** -- The 3-skills-by-reader narrative must become 6-axes-by-function. New directory tree, new diagrams (6-column instead of 3-column), new rationale for the split.

4. **New pattern summaries** -- At least brief coverage of 17 new patterns. Not all need deep-dives, but the article currently has zero mention of drift re-anchoring, task completion verification, tool input guards, file claim/lock, workspace isolation, MCP reconnection, test-before-commit, etc.

5. **Updated source attribution** -- harness-books is now a primary source. The 12+ sources list needs updating.

### Should-add (strengthens the article)

6. **Deep-dive candidates from new patterns** -- Drift re-anchoring (1.5) and Tool input guard (2.6) are new scripts with interesting design choices. At least one deserves a 4.X-level deep-dive.

7. **"From 21 to 38" evolution narrative** -- The "从 12 到 21" section could become "从 12 到 38" with the intermediate step, showing the growth pattern.

8. **Updated settings.json examples** -- All path references need `execution-loop` instead of `agent-hooks`, etc.

### Nice-to-have

9. **Updated scenario recommendation table** -- With 38 patterns and new names, the "常见场景选型" needs refresh.

10. **Updated hook protocol table** -- More hook events in use now, more scripts to list.

---

## 6. Recommendation

**HEAVY EDIT** -- not rewrite from scratch, not light update.

### Justification

**Why not "rewrite from scratch":**
- The narrative arc (problem → methodology → architecture → deep dives → quality → limitations → open questions) is sound and should be preserved.
- ~60% of the actual prose is reusable. The deep-dive sections (4.1-4.7) are the heart of the article and are 80-85% intact.
- The distillation methodology section (Section 2) is essentially unchanged.
- The motivation section (Section 1) needs trivial updates.
- The writing voice and style are established -- rewriting would lose that.

**Why not "light update":**
- The architecture section (Section 3.1) is structurally wrong -- 3 skills vs 6 axes is not a tweak, it's a different organizational model.
- 17 patterns are completely absent from the article. Not mentioning 45% of the project's patterns makes the article factually misleading.
- Every number in the article (21 patterns, 8 scripts, 3 skills, 13 design refs) is wrong. These appear in TL;DR, section headers, diagrams, tables, and inline text. Touching every instance is more than a light pass.
- The HTML diagrams (3-column architecture, source attribution funnel) embed wrong data and need rebuilding.
- The pattern overview table is a complete replacement.

**Estimated effort breakdown:**
- Section 1 (motivation): 15 minutes -- number substitutions
- Section 2 (methodology): 30 minutes -- add harness-books source, minor updates
- Section 3 (architecture): 3-4 hours -- near-total rewrite of 3.1, update 3.2-3.5, rebuild HTML diagrams
- Pattern overview table: 1 hour -- replace 21-row with 38-row
- Section 4 (deep dives): 2 hours -- update pattern IDs, add 1-2 new deep dives
- New meta-principles section: 1-2 hours
- Section 5 (quality): 1 hour -- update all numbers, extend narrative
- Sections 6-7: 30 minutes -- add new limitations/questions
- Consistency pass: 1 hour -- catch all stale references
- **Total: ~10-14 hours of focused editing**

### Execution Order

1. Update all hard numbers globally (21→38, 8→17, 3→6, 13→21)
2. Rewrite Section 3 (architecture) with 6-axis structure
3. Replace pattern overview table
4. Add meta-principles section (new Section 3.0 or integrate into Section 3)
5. Update Section 4 deep-dives for new pattern IDs and paths
6. Add brief coverage of 17 new patterns (could be a new "4.10 Notable New Patterns" section)
7. Update source attribution
8. Update Sections 5, 6, 7
9. Rebuild HTML diagrams
10. Full consistency check
