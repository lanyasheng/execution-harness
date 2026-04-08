---
name: multi-agent
version: 2.0.0
category: knowledge
description: 多 agent 协调设计模式。当需要选择 coordinator/fork/swarm 模式或设计跨 agent 协作时使用。不适用于工具重试（用 tool-governance）或上下文管理（用 context-memory）。参见 execution-loop（coordinator 持续执行）。
license: MIT
triggers:
  - multi agent
  - 多 agent
  - coordinator
  - fork vs swarm
  - agent coordination
  - workspace isolation
  - file conflict
---

# Multi-Agent Coordination

多 agent 系统设计模式：委托模式选型、任务协调、并发控制、质量保障。纯设计指南。

## When to Use

- 选择 Coordinator/Fork/Swarm → Three delegation modes
- 多 agent 同时编辑同一文件 → File claim and lock
- 需要隔离工作空间 → Agent workspace isolation
- 协调者需要综合 worker 结果 → Synthesis gate

## When NOT to Use

- 只有 1 个 agent → 用 `execution-loop`
- 跨阶段知识传递 → 用 `context-memory`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 4.1 | Three delegation modes | [design] | Coordinator/Fork/Swarm 选型 |
| 4.2 | Shared task list protocol | [design] | 文件化任务协调 |
| 4.3 | File claim and lock | [design] | 编辑前写 claim 防并发 |
| 4.4 | Agent workspace isolation | [design] | 每 agent 独立 worktree |
| 4.5 | Synthesis gate | [design] | 协调者必须产出综合文档 |
| 4.6 | Review-execution separation | [design] | 实现和审查分离 |

## Workflow

1. **评估任务** — 判断任务规模和并发需求，决定是否需要多 agent
2. **选择委托模式** — Coordinator（需要综合判断）/ Fork（独立子任务）/ Swarm（同质大批量）
3. **工作空间隔离** — 每个 worker 分配独立 worktree，防止文件冲突
4. **分配任务** — 通过 `.coordination/tasks.json` 共享任务清单，每个 worker 认领并写 claim
5. **综合门控** — Coordinator MUST 在实现阶段之前产出 `synthesis.md`，综合所有 worker 的研究结果
6. **审查-执行分离** — 实现 worker 和审查 worker 必须是不同 agent，审查者不修代码

- Coordinator MUST 在收到 worker 结果后先综合再指派下一阶段，否则 worker 拿到的是碎片化的原始数据，实现质量会断崖式下降。
- 不要把 worker 的原始输出直接转发给下游 worker，而是由 coordinator 提炼出结构化的 synthesis 文档再分发。
- 如果不确定用哪种委托模式，从 Coordinator 开始——它覆盖最广，后续可以降级为 Fork 或升级为 Swarm。

<example>
场景: 15 个文件的跨模块重构（统一错误处理模式）
模式: Coordinator
Phase 1 — 研究: 3 个 research worker 并行扫描 5 个模块，各自输出影响分析
Phase 2 — 综合: coordinator 读取 3 份影响分析，产出 synthesis.md（统一迁移方案 + 文件优先级 + 依赖顺序）
Phase 3 — 实现: 2 个 implementation worker 按 synthesis 中的文件分配各自认领，通过 .claims/*.lock 防冲突
Phase 4 — 审查: 1 个独立 review worker 检查所有变更是否符合 synthesis 中的方案
结果: 15 个文件全部迁移，0 冲突，审查一次通过
</example>

<anti-example>
错误用法: coordinator 收到 3 个 research worker 的扫描结果后，直接说"Based on your findings, fix it"把原始数据转发给 implementation worker
问题: 3 份报告有矛盾结论（worker A 说用 Result 类型，worker B 说用 exception），implementation worker 无所适从，自己做了不一致的选择
违反: Pattern 4.5 Synthesis gate — coordinator 跳过综合步骤，把判断责任下推给 worker
修正: coordinator 必须先读取所有报告、解决矛盾、产出一份统一的 synthesis.md，再分配实现任务
</anti-example>

## Output

| 产物 | 路径 | 说明 |
|------|------|------|
| 任务清单 | `.coordination/tasks.json` | 所有 worker 的任务分配、状态、认领记录 |
| 综合文档 | `.coordination/synthesis.md` | coordinator 综合 worker 结果的结构化决策文档 |
| 文件锁 | `.claims/*.lock` | 每个 worker 编辑文件前写入的排他锁，防止并发冲突 |

## Related

- `execution-loop` — Ralph 持续执行循环，用于 coordinator 的长时间持续执行
- `context-memory` — handoff 文档，用于跨阶段（研究→综合→实现）的知识传递
- `tool-governance` — component-scoped hooks，用于给不同 worker 配置不同的工具权限
