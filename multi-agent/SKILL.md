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
author: OpenClaw Team
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

| # | Pattern | Description |
|---|---------|-------------|
| 4.1 | Three delegation modes | Coordinator（worker 从零开始，适合多阶段复杂任务）、Fork（child 继承 parent 完整上下文和 prompt cache，启动快但限单层）、Swarm（扁平名单 + file-based mailbox，适合长期独立工作流）。不确定选哪个时从 Coordinator 开始——覆盖最广，后续可降级。 → [详见](references/delegation-modes.md) |
| 4.2 | Shared task list protocol | 用 `.coordination/tasks.json` 做共享任务板，每个任务有 pending/claimed/done/failed 四态，worker 通过 lockfile + 指数退避领取任务。零依赖——只需文件系统，跨 session、跨机器可用。 → [详见](references/task-coordination.md) |
| 4.3 | File claim and lock | 编辑文件前在 `.claims/` 写排他锁，PreToolUse hook 检测到锁时拒绝其他 agent 的 Write/Edit。锁带 10 分钟超时防 crash 死锁。粒度是整个文件——需要更细粒度时用 workspace isolation 替代。 → [详见](references/file-claim-lock.md) |
| 4.4 | Agent workspace isolation | 每个 worker 用独立 git worktree，共享 .git 仓库但有独立工作目录和 index。彻底消除并发文件冲突，代价是 merge 阶段冲突集中爆发，需 coordinator 处理。 → [详见](references/workspace-isolation.md) |
| 4.5 | Synthesis gate | Research 和 Implementation 之间的强制关卡：coordinator 必须自己消化所有 research 结果，产出包含结论、依据、行动计划的 `synthesis.md`，gate 脚本验证长度和结构后才放行。核心原则：coordinator must synthesize, not delegate understanding——把原始结果直接转发给下游是反模式。 → [详见](references/synthesis-gate.md) |
| 4.6 | Review-execution separation | Implementation 和 review 由两个隔离 session 的 agent 分别执行，review agent 只看代码和需求，不知道 implementation agent 的推理过程。这种盲审消除确认偏误，可以用不同模型组合增加视角多样性。 → [详见](references/review-execution-separation.md) |
| E4.x | Extended patterns | Cache-safe forking、完整 context 隔离、4-phase workflow、file-based mailbox、permission delegation、结构化消息协议——核心 pattern 的补充实现细节。 → [详见](references/extended-patterns.md) |

## Workflow

选模式用决策树，选完后按对应路径执行。

```
需要多 agent？
├── Worker 需要 parent 已加载的 context？
│   └── 是 → Fork
│         · child 继承完整上下文 + prompt cache，首次调用只付 cache read 价格
│         · 单层限制：child 不能再 Fork
│         · 任务和 parent context 无关时别用 Fork，浪费 context 装无关内容
│
├── Workers 之间需要分阶段协调？
│   └── 是 → Coordinator（4 阶段）
│         1. Research — 多 worker 并行探索
│         2. Synthesis — coordinator 独占，综合所有结果产出 synthesis.md
│            （不可委派，不可跳过——直接转发原始结果会让下游无所适从）
│         3. Implementation — 按文件集分配，同文件串行防 merge conflict
│         4. Verification — 独立 review agent 盲审，不看 implementation 推理
│
└── 各自独立、同质任务？
    └── 是 → Swarm
          · 扁平名单：teammate 不能 spawn 新 teammate
          · 通过 file-based mailbox 通信（per-agent inbox JSON + lockfile）
          · 用 .coordination/tasks.json 共享任务状态
```

所有模式通用：每个 worker 分配独立 worktree（Pattern 4.4），编辑文件前写 claim lock（Pattern 4.3）。

<example>
场景: 15 个文件的跨模块重构（统一错误处理）
模式: Coordinator
Phase 1 — 研究: 3 个 worker 并行扫描，各自输出影响分析
Phase 2 — 综合: coordinator 产出 synthesis.md（迁移方案 + 文件优先级 + 依赖顺序）
Phase 3 — 实现: 2 个 worker 按 synthesis 认领文件，.claims/*.lock 防冲突
Phase 4 — 审查: 1 个独立 review worker 对照 synthesis 盲审所有变更
结果: 15 文件迁移完成，0 冲突，审查一次通过
</example>

<anti-example>
错误: coordinator 收到 3 份 research 报告后直接说 "Based on your findings, fix it" 转发给 implementation worker
后果: 3 份报告有矛盾结论（Result 类型 vs exception），implementation worker 自己做了不一致的选择
违反: Pattern 4.5 — coordinator 跳过 synthesis，把判断责任下推给 worker
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
