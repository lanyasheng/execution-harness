---
name: execution-harness
version: 1.0.0
description: Claude Code agent 执行可靠性增强。当 agent 提前停止、context 压缩丢失决策、工具重试死循环、或限速后挂死时使用。提供 Stop hook 持续执行、handoff 文档上下文存活、工具错误升级、限速恢复等 12 个可组合模式。不用于任务调度或编排（这是执行层，不是调度层）。参见 Claude Code hooks 文档了解 hook 机制。
license: MIT
triggers:
  - harness
  - ralph
  - persistent execution
  - 持续执行
  - 不要停
  - keep going
  - handoff
  - context survival
  - 上下文存活
  - rate limit
  - 限速恢复
  - tool retry
  - 工具重试
  - agent keeps stopping
  - crash recovery
  - session state
---

# Execution Harness Patterns

Claude Code agent 执行可靠性增强。解决 5 类失败：提前停止、上下文丢失、重试死循环、限速挂死、crash 状态丢失。

蒸馏自 Claude Code 内部架构和 oh-my-claudecode (OMC) 生产实践。每个 pattern 的完整实现细节见 `references/patterns/`。

## When to Use

- Agent 在多文件修改任务中只改了一部分就停了
- 长任务中 context 被压缩后 agent 忘记了设计决策
- 工具调用反复失败但 agent 一直重试同一个命令
- Agent 遇到 API 限速后 tmux session 挂死
- 需要 crash 后恢复执行进度而不是从头开始

## When NOT to Use

- 任务调度和依赖管理（编排层的工作）
- 单次简单任务（不需要持续执行保障）
- Headless `-p` 模式（Stop hook 不触发，用 `--max-turns`）

---

## 12 Patterns 快速参考

| # | Pattern | 解决什么 | 机制 | 详情 |
|---|---------|---------|------|------|
| 1 | **Ralph 持续执行** | Agent 提前停止 | Stop hook 阻止终止，注入续航指令 | [详情](references/patterns/01-ralph.md) |
| 2 | **Handoff 文档** | Context 压缩丢信息 | 阶段结束时写 Decided/Rejected/Risks 到磁盘 | [详情](references/patterns/02-handoff.md) |
| 3 | **工具错误升级** | 同一工具重试死循环 | PostToolUseFailure 追踪，5 次后强制换方案 | [详情](references/patterns/03-tool-error.md) |
| 4 | **Rate Limit 恢复** | 限速后 session 挂死 | 扫描 tmux pane 关键词，限速解除后发 Enter 恢复 | [详情](references/patterns/04-rate-limit.md) |
| 5 | **Context 估算** | 不知道 context 用了多少 | 读 transcript 最后 4KB 提取 input_tokens/context_window | [详情](references/patterns/05-context-estimation.md) |
| 6 | **原子文件写入** | 并发读写状态文件损坏 | write-then-rename（POSIX 原子操作） | [详情](references/patterns/06-atomic-write.md) |
| 7 | **Cancel TTL** | 旧取消信号影响新 session | 取消信号带 30s 过期时间 | [详情](references/patterns/07-cancel-ttl.md) |
| 8 | **Compaction 记忆提取** | 压缩时丢失重要发现 | PreCompact hook 在压缩前写 handoff | [详情](references/patterns/08-compaction-extract.md) |
| 9 | **权限否决追踪** | Agent 换表述绕过拒绝 | 追踪否决模式，3 次后降级，5 次后 session 级禁止 | [详情](references/patterns/09-denial-tracking.md) |
| 10 | **三门控记忆合并** | 跨 session 记忆碎片化 | Time/Session/Lock 三道门控后批量合并 | [详情](references/patterns/10-memory-consolidation.md) |
| 11 | **Hook Pair Bracket** | 不知道每轮消耗多少 | UserPromptSubmit + Stop 配对测量 | [详情](references/patterns/11-hook-bracket.md) |
| 12 | **Component-Scoped Hooks** | 全局 hooks 太粗粒度 | 在 SKILL.md frontmatter 中声明局部 hooks | [详情](references/patterns/12-scoped-hooks.md) |

## 常见场景选型

| 场景 | 推荐组合 |
|------|---------|
| 多文件 bugfix，怕 agent 半途停 | Pattern 1 (Ralph) + Pattern 5 (Context 估算做安全阀) |
| 多阶段任务（plan → implement → verify） | Pattern 2 (Handoff) + Pattern 8 (Compaction 提取) |
| Agent 在陌生环境跑（依赖可能缺失） | Pattern 3 (工具错误升级) + Pattern 9 (权限否决追踪) |
| 批量 dispatch 多个 agent 到 tmux | Pattern 4 (Rate Limit 恢复) + Pattern 11 (Hook Bracket 监控) |
| 高价值任务（安全修复、生产热修） | Pattern 1 模式 C (Agent-type hook 验证) + Pattern 12 (Scoped hooks) |

## Session State Layout

所有状态统一在 `sessions/<session-id>/` 下。详见 [session-state-layout.md](references/session-state-layout.md)。

## Scripts

| 脚本 | 用途 |
|------|------|
| `scripts/ralph-init.sh <session-id> [max-iter]` | 初始化 Ralph 状态（支持 crash 恢复） |
| `scripts/ralph-stop-hook.sh` | Stop hook，读 stdin 输出 block/continue JSON |
| `scripts/ralph-cancel.sh <session-id> [reason]` | 发送带 30s TTL 的取消信号 |

## 工作流程

### Step 1: 选型

根据「常见场景选型」表选择 pattern 组合。

### Step 2: 初始化

```bash
# 持续执行：初始化 Ralph 状态
scripts/ralph-init.sh my-bugfix-001 50
# 上下文存活：在 prompt 中注入 handoff 指令
```

### Step 3: 执行期间

Stop hook 自动介入。MUST 在 context >= 95% 时放行，otherwise 会导致溢出崩溃。

### Step 4: 结束

Ralph 自动释放。如果不确定是否需要手动取消，使用 `ralph-cancel.sh`。

## 条件判断规则

- 如果 agent 在 headless `-p` 模式 → 不要用 Ralph（用 `--max-turns`），而是依赖 `--max-turns` 控制
- 如果任务预计 < 5 分钟 → 不需要 Ralph，避免不必要的 overhead
- 如果不确定 → 先不启用，观察 agent 是否提前停止再决定

## Output

| 脚本 | returns |
|------|---------|
| `ralph-init.sh` | 创建 `sessions/<id>/ralph.json`，stdout 输出初始化确认 |
| `ralph-stop-hook.sh` | stdout JSON: `{"continue":true}` 或 `{"decision":"block","reason":"..."}` |
| `ralph-cancel.sh` | 创建 `sessions/<id>/cancel.json`（30s TTL），stdout 输出确认 |

## Related Skills

- **prompt-hardening**：P13 = hooks（代码级强制）；P5 可强化 Ralph block 消息；P9 配合 Hook Bracket
- **improvement-evaluator**：长评估任务用 Ralph 保证 task suite 全部跑完
- **improvement-gate**：用 agent-type hook 添加语义验证层
