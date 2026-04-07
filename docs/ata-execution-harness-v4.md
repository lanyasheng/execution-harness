# Execution Harness: 38 个 Pattern 让 Claude Code Agent 把活干完

## TL;DR

Claude Code agent 经常只干一半就停、工具失败了用同样的参数重试 12 次、压缩后忘掉所有设计决策。Execution Harness 是 17 个 bash 脚本（13 个 hook + 4 个独立工具）+ 20 个设计模式 + 4 个配置模式，覆盖 agent 执行可靠性的 6 个维度：执行循环、工具治理、上下文记忆、多 agent 协调、错误恢复、质量验证。全部基于 Claude Code 的 hook 协议，不做模型调用，不是框架——只管住执行层。

数字：38 core patterns（14 个 script + 20 个 design + 4 个 config），17 个 bash 脚本，10 条设计原则，90 个测试用例，从 4 个开源项目蒸馏而来。

---

## 1. 问题：Agent 不靠谱的 6 类场景

先看 6 个真实场景，每个对应一个维度。

### 场景 1：做了一半就停了（执行循环）

给 agent 一个跨 7 个文件的重构任务。它改完前 2 个文件后发了 `end_turn`，回复"已完成重构，其余文件的修改方式类似"。剩下 5 个文件没动。

根因：LLM 倾向于在完成一个"有意义的单元"后停止。它不知道你的 7 个文件是一个原子任务。

### 场景 2：同一个错误重试 12 次（工具治理）

容器里没装 cargo。Agent 第 1 次 `cargo build` 失败，第 2 次 `cargo build` 失败，第 12 次还是 `cargo build`。每次失败后它会说"让我再试一次"，参数一字不改。

根因：`PostToolUseFailure` 之后 agent 默认行为是重试。没有外部机制打断"同一个工具 + 同样参数 = 同样失败"的死循环。

### 场景 3：压缩后忘了关键决策（上下文记忆）

花了 20 轮讨论后决定用 Redis 而不是 Memcached。Context 压缩后 agent 突然开始写 Memcached 的配置代码，因为压缩摘要里那段讨论被删了。

根因：Claude Code 的 Full Compact 用 LLM 生成摘要，但你无法控制保留什么。推理过程（为什么选 Redis、为什么排除 Memcached）在压缩中最容易丢失。

### 场景 4：5 个 agent 编辑同一个文件（多 agent 协调）

Coordinator 分派 5 个 worker 做不同的 subtask。3 个 worker 需要改 `config.yaml`。Agent A 读取文件，Agent B 改完保存，Agent A 基于过期内容覆写，Agent B 的修改消失。

根因：多 agent 共享文件系统但没有锁机制。Agent 不知道其他 agent 的存在。

### 场景 5：限速后 tmux 挂死（错误恢复）

在 tmux 里跑 3 个 agent 做并发任务。其中一个触发 API 429 限速，Claude Code 显示"Rate limited, press Enter to retry"。没人按 Enter。30 分钟后你发现那个 pane 还挂在那里。

根因：限速恢复需要人工交互（按 Enter），在无人值守的 tmux session 里没有自动恢复机制。

### 场景 6：提交了编译不过的代码（质量验证）

Agent 改了一个 TypeScript 文件并 `git commit`。你 pull 下来发现有类型错误——agent 改文件时没跑 `tsc`。

根因：编辑和验证是分离的。Agent 写完文件后不会自动跑 linter，commit 前不会自动跑测试。

---

## 2. 10 条设计原则（M1-M10）

这些原则不是空洞的 slogan。每一条对应一个具体的设计决策。

### M1: Determinism over Persuasion

Prompt 说"不要重试超过 3 次"——agent 在压力下会无视这条指令。`PostToolUseFailure` hook 数到 5 直接 block——agent 绕不过去。

凡是能用 hook 做的，不要用 prompt 做。Hook 是确定性的，prompt 是概率性的。

### M2: Filesystem as the Coordination Medium

所有跨 agent、跨 session、跨 hook 的通信都走磁盘文件。没有内存状态，没有自定义 IPC。JSON 文件 + 原子写入（write-to-temp-then-rename）+ 每个 session 一个目录。

为什么不用数据库或消息队列：bash 脚本能直接读写文件。引入 Redis 意味着每个 hook 脚本都要依赖 Redis 客户端，调试变困难，部署变复杂。文件系统是 bash 的 native storage。

### M3: Safety Valves on Every Enforcement Loop

任何阻止 agent 继续的机制都必须有逃生条件。Ralph 的 Stop hook 阻止 agent 退出——但认证失败（401/403）、cancel 信号、2 小时闲置、迭代上限这 4 种情况下必须放行。

原因：没有安全阀的 enforcement 会变成 trap。Agent 在循环里卡死比提前退出更糟。

### M4: Session-Scoped Isolation

一个 session 的状态不能泄漏到另一个 session。每个 session 有自己的目录（`sessions/<session-id>/`），错误计数器、ralph 状态、handoff 文档都隔离。跨 session 传递只通过显式机制（handoff 文档、memory consolidation）。

这条原则的直接后果：所有状态文件路径都包含 `session_id`。如果你看到一个不含 session_id 的状态文件路径，那是 bug。

### M5: Fail-Open on Uncertainty

状态文件不存在？JSON 解析失败？Session ID 拿不到？默认放行。`echo '{"continue":true}'; exit 0` 是每个 hook 脚本的 fallback。

例外：安全相关的 guard（`tool-input-guard.sh` 检测 `rm -rf /`）翻转为 fail-closed——宁可误拦也不能放过。

### M6: Proportional Intervention

5 分钟改个 typo 不需要 Ralph 持续执行 + doubt gate + post-edit diagnostics + drift re-anchoring。2 小时的多文件重构才需要全套 hook。

实现方式：Pattern 1.3 Adaptive Complexity Triage 按任务复杂度自动选 harness 强度。简单任务跳过大部分 hook，复杂任务启用全套。

### M7: Observe Before Intervening

先部署观测（tool-error-tracker 记录失败次数），再部署干预（tool-error-advisor 阻止重试）。顺序不能反。

实际例子：如果你只装了 `tool-error-advisor.sh`（PreToolUse blocker）但没装 `tool-error-tracker.sh`（PostToolUseFailure tracker），advisor 读不到错误计数文件，永远不会触发 block。

### M8: Explicit Knowledge Transfer

设计决策写磁盘，格式结构化，内容在写入时确定。不依赖 LLM 摘要——LLM 压缩时会丢推理过程。

Handoff 文档的 5 段式结构（Decided / Rejected / Risks / Files / Remaining）就是这条原则的产物。"为什么选 Redis 不选 Memcached"写在 Rejected 段里，压缩删不掉。

### M9: Coordinator Synthesizes, Never Delegates Understanding

"Based on your findings, fix it" 是反模式。Coordinator 从 worker 拿到 research 结果后，必须自己消化出 synthesis 文档——包含结论、依据、行动计划——然后把 synthesis 交给 implementation worker。

Coordinator 是大脑，不是邮局。如果 coordinator 只做转发，worker 在缺乏上下文的情况下工作，产出质量会断崖式下降。

### M10: Honest Limitation Labeling

Pattern 5.6 Model Fallback Advisory：hook 不能切换模型。这是 Claude Code 的限制——hook 没有切模型的 API。所以这个 pattern 标注为 `[ADVISORY ONLY]`，只能在 `additionalContext` 里建议 agent 考虑换模型。

"标注为 advisory"比"假装能切"好。静默失效是最差的结果。

---

## 3. 6 轴架构

```
execution-harness/
├── principles.md                    10 条设计原则
├── execution-loop/                  让 agent 继续工作直到完成
│   ├── SKILL.md                     7 patterns (4 script, 2 design, 1 config)
│   ├── scripts/                     ralph-stop-hook, doubt-gate, task-completion-gate...
│   └── references/                  每个 pattern 的深度参考
├── tool-governance/                 让工具使用安全可控
│   ├── SKILL.md                     6 patterns (4 script, 2 config)
│   ├── scripts/                     tool-error-tracker, tool-input-guard...
│   └── references/
├── context-memory/                  让知识跨压缩存活
│   ├── SKILL.md                     7 patterns (2 script, 5 design)
│   ├── scripts/                     context-usage, compaction-extract
│   └── references/
├── multi-agent/                     让多个 agent 协同而非冲突
│   ├── SKILL.md                     6 patterns (全部 design)
│   └── references/
├── error-recovery/                  让 agent 从故障中恢复
│   ├── SKILL.md                     6 patterns (1 script, 5 design)
│   ├── scripts/                     rate-limit-recovery
│   └── references/
└── quality-verification/            让输出质量有保障
    ├── SKILL.md                     6 patterns (3 script, 1 config, 2 design)
    ├── scripts/                     post-edit-check, bracket-hook, test-before-commit
    └── references/
```

每个轴是独立的 Claude Code skill。你可以只装 execution-loop 解决"agent 总是提前退出"的问题，不碰其他 5 个轴。轴之间有协作关系（比如 tool-governance 的 tracker 为 error-recovery 的 degradation 提供数据）但没有硬依赖。

### 3.1 Execution Loop（7 patterns）

定位：控制 agent 的执行生命周期。解决"做一半就停"、"说完就走不验证"、"越做越偏"三类问题。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 1.1 | Ralph persistent loop | script | Stop hook 阻止提前退出，4 个安全阀保底 |
| 1.2 | Doubt gate | script | 检测"可能""大概"等投机语言，要求验证 |
| 1.3 | Adaptive complexity triage | design | 按任务复杂度自动选 harness 强度 |
| 1.4 | Task completion verifier | script | 读任务清单，未完成项存在则阻止 |
| 1.5 | Drift re-anchoring | script | 每 N 轮重新注入原始任务描述 |
| 1.6 | Headless execution control | config | `-p` 模式下的替代控制方案 |
| 1.7 | Iteration-aware messaging | design | 按迭代阶段调整 block 消息语气 |

代表性脚本：`ralph-stop-hook.sh`（124 行）、`doubt-gate.sh`（42 行）、`drift-reanchor.sh`。

### 3.2 Tool Governance（6 patterns）

定位：工具使用的安全护栏。解决"重试死循环"、"绕过否决"、"破坏性命令"三类问题。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 2.1 | Tool error escalation | script | 连续 3 次提示、5 次强制换方案 |
| 2.2 | Denial circuit breaker | script | 追踪否决次数，3 次警告、5 次建议替代 |
| 2.3 | Checkpoint + rollback | script | 破坏性 bash 命令前自动 git stash |
| 2.4 | Graduated permission rules | config | 按风险分层：auto-allow / warn / deny |
| 2.5 | Component-scoped hooks | config | 任务级别的 hook 控制 |
| 2.6 | Tool input guard | script | 拦截 `rm -rf /`、`curl \| sh` 等危险模式 |

代表性脚本：`tool-error-tracker.sh`（追踪）+ `tool-error-advisor.sh`（阻止）构成 M7 的 observe-then-intervene 配对。

### 3.3 Context & Memory（7 patterns）

定位：上下文窗口生命周期管理。解决"压缩后失忆"、"跨阶段传递断裂"、"不知道还剩多少 context"三类问题。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 3.1 | Handoff documents | design | 阶段边界写入 Decided/Rejected/Remaining |
| 3.2 | Compaction memory extraction | script | 定期快照关键知识到 handoff 文件 |
| 3.3 | Three-gate memory consolidation | design | 跨 session 记忆合并（时间/数量/锁三门控） |
| 3.4 | Token budget allocation | design | 注入预算感知指令 |
| 3.5 | Context token count | script | 从 transcript 提取 input token 数 |
| 3.6 | Filesystem as working memory | design | 用 `.working-state/` 目录作活跃工作状态 |
| 3.7 | Compaction quality audit | design | 压缩后验证关键信息是否存活 |

代表性脚本：`compaction-extract.sh`、`context-usage.sh`。

### 3.4 Multi-Agent Coordination（6 patterns）

定位：多 agent 系统的协调模式。解决"选错委托模式"、"文件冲突"、"coordinator 当传话筒"三类问题。全部是 design pattern，没有可执行脚本——因为多 agent 编排逻辑因场景差异太大，硬编码脚本不合适。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 4.1 | Three delegation modes | design | Coordinator / Fork / Swarm 选型指南 |
| 4.2 | Shared task list protocol | design | 文件化任务协调 + 状态跟踪 |
| 4.3 | File claim and lock | design | 编辑前写 claim 标记防并发冲突 |
| 4.4 | Agent workspace isolation | design | 每个 agent 独立 git worktree |
| 4.5 | Synthesis gate | design | 协调者必须综合 worker 结果后才能委派 |
| 4.6 | Review-execution separation | design | 实现和审查用不同 agent |

### 3.5 Error Recovery（6 patterns）

定位：agent session 的容错与恢复。解决"限速挂死"、"crash 丢进度"、"MCP 断连"三类问题。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 5.1 | Rate limit recovery | script | 扫描 tmux pane 自动发 Enter 恢复 |
| 5.2 | Crash state recovery | design | 检测残留状态，从断点恢复 |
| 5.3 | Stale session daemon | design | 死 session 的知识回收 |
| 5.4 | MCP reconnection | design | MCP 断连检测 + 指数退避重连 |
| 5.5 | Graceful tool degradation | design | 首选工具不可用时的降级映射 |
| 5.6 | Model fallback advisory | design | 3 次失败后建议升级模型（advisory only） |

代表性脚本：`rate-limit-recovery.sh`——这不是 hook，是独立脚本，用 cron 或手动跑。

### 3.6 Quality & Verification（6 patterns）

定位：输出质量保障。解决"编辑引入错误不自知"、"提交未测试代码"、"不知道 hook 本身跑了多久"三类问题。

| # | Pattern | Type | 做什么 |
|---|---------|------|--------|
| 6.1 | Post-edit diagnostics | script | 每次编辑后跑 linter / type checker |
| 6.2 | Hook runtime profiles | config | minimal / standard / strict 三档切换 |
| 6.3 | Session turn metrics | script | 记录每轮耗时和 turn 计数 |
| 6.4 | Test-before-commit gate | script | `git commit` 前自动跑测试套件 |
| 6.5 | Atomic state writes | design | write-to-temp-then-rename 保证 crash safety |
| 6.6 | Session state hygiene | design | 定期清理 stale session 和 orphaned lock |

代表性脚本：`post-edit-check.sh`、`test-before-commit.sh`。

---

## 4. Deep Dives

5 个核心 pattern 的详细解析。每个 pattern 按"问题 -> 方案 -> 代码 -> tradeoff"结构展开。

### 4.1 Ralph Persistent Loop (Pattern 1.1)

**问题**

Claude Code agent 在 interactive 模式下每次 `end_turn` 都需要等你发新消息才会继续。对于"重构这 7 个文件"这种大任务，agent 改完 2 个文件觉得"差不多了"就停了。你得反复说"继续"。

**方案**

利用 Claude Code 的 Stop hook：agent 每次尝试结束时触发这个 hook。Hook 读取状态文件，如果任务还没做完（`active=true` 且 `iteration < max`），返回 `{"decision":"block","reason":"..."}` 阻止退出并注入"继续工作"的指令。

4 个安全阀保证不会卡死：
1. 认证错误（401/403）——直接放行
2. Cancel 信号（带 TTL 的文件）——放行并清理
3. 闲置 2 小时——放行并标记 stale
4. 达到最大迭代数——放行并标记完成

**代码**

初始化：

```bash
# 创建 session 状态，设最多 50 轮
bash execution-loop/scripts/ralph-init.sh my-task 50
# 输出: Ralph initialized: sessions/my-task/ralph.json (max 50 iterations)
```

状态文件 `sessions/my-task/ralph.json`：

```json
{
  "session_id": "my-task",
  "active": true,
  "iteration": 0,
  "max_iterations": 50,
  "created_at": "2026-04-05T10:00:00Z",
  "last_checked_at": "2026-04-05T10:00:00Z"
}
```

Stop hook 核心逻辑（`ralph-stop-hook.sh` 简化版）：

```bash
# 读取 hook 输入（Claude Code Stop hook protocol）
INPUT=$(head -c 20000)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

STATE_FILE="sessions/${SESSION_ID}/ralph.json"
[ -f "$STATE_FILE" ] || { echo '{"continue":true}'; exit 0; }  # 无状态则放行

ACTIVE=$(jq -r '.active' "$STATE_FILE")
[ "$ACTIVE" = "true" ] || { echo '{"continue":true}'; exit 0; }

ITERATION=$(jq -r '.iteration' "$STATE_FILE")
MAX=$(jq -r '.max_iterations' "$STATE_FILE")

# 安全阀 1: 认证失败
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""')
if echo "$LAST_MSG" | grep -qiE '401|403|unauthorized|forbidden'; then
  # 停用 ralph 并放行
  jq '.active = false | .deactivation_reason = "auth_error"' "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"
  echo '{"continue":true}'; exit 0
fi

# 安全阀 4: 迭代上限
if [ "$ITERATION" -ge "$MAX" ]; then
  jq '.active = false | .deactivation_reason = "max_iterations"' "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"
  echo '{"continue":true}'; exit 0
fi

# 阻止退出，递增迭代计数
NEW_ITER=$((ITERATION + 1))
jq --argjson i "$NEW_ITER" '.iteration = $i' "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"

# Block 消息使用 prompt-hardening P5（反推理阻断）
jq -n --arg r "[RALPH LOOP ${NEW_ITER}/${MAX}] Task is NOT done. \
Do NOT rationalize that the remaining work can be done in a follow-up. \
Do NOT claim completion with caveats like 'mostly done' or 'should work'. \
Check your original task and verify EVERY requirement is met." \
  '{"decision":"block","reason":$r}'
```

Crash 恢复——`ralph-init.sh` 检测到残留状态时从上次迭代继续：

```bash
# 上次 session 在第 37 轮 crash 了
bash execution-loop/scripts/ralph-init.sh my-task 50
# 输出: Resuming ralph from iteration 37 (previous state: active=true, reason=stale)
```

**Tradeoff**

- Hook 是确定性的（每次 Stop 都触发），但 block 消息的效果是概率性的。Agent 可能在第 15 轮进入 compliance mode——表面继续工作，实际产出空洞。Pattern 1.7 Iteration-Aware Messaging 用动态消息对抗这个问题。
- Ralph 只在 interactive 模式下有效。Headless（`-p`）模式没有 Stop 事件循环。Headless 用 `--max-turns` + 进程级重启替代。
- 安全阀的参数（2 小时闲置、50 轮上限）是经验值。有些任务 10 轮就够了，有些需要 200 轮。

### 4.2 Tool Error Escalation (Pattern 2.1)

**问题**

Agent 调用 `cargo build` 失败（容器没装 cargo），下一步又调 `cargo build`。参数一样，结果一样。5 次、10 次。

根因在于 Claude Code 的 `PostToolUseFailure` 事件只会让 agent 看到错误消息，agent 默认策略是重试。没有外部计数器告诉它"你已经用同样的方式失败 5 次了"。

**方案**

两个 hook 配合——M7 原则的 observe-then-intervene：

1. `tool-error-tracker.sh`（PostToolUseFailure hook）——每次工具失败后记录 tool_name + input_hash + count
2. `tool-error-advisor.sh`（PreToolUse hook）——下次调用同一工具前，如果 count >= 5，block 这次调用

关键设计：用 input_hash（工具输入前 200 字符的 MD5）区分"同一命令重试"和"换了参数的新尝试"。只有相同 tool + 相同 input_hash 的连续失败才累计。

三级升级：

| 连续失败 | 行为 |
|----------|------|
| 1-2 次 | 只记录，不干预 |
| 3-4 次 | PostToolUseFailure 注入软提示："考虑换参数？缺依赖？" |
| 5+ 次 | PreToolUse 直接 deny："MUST use an alternative approach" |

**代码**

Tracker（`tool-error-tracker.sh`，PostToolUseFailure hook）：

```bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
ERROR=$(echo "$INPUT" | jq -r '.error // ""' | head -c 500)
INPUT_HASH=$(echo "$INPUT" | jq -Sc '.tool_input // ""' | head -c 200 | md5)

STATE_FILE="sessions/${SESSION_ID}/tool-errors.json"

# 读已有状态
if [ -f "$STATE_FILE" ]; then
  PREV_TOOL=$(jq -r '.tool_name' "$STATE_FILE")
  PREV_HASH=$(jq -r '.input_hash' "$STATE_FILE")
  PREV_COUNT=$(jq -r '.count' "$STATE_FILE")

  if [ "$PREV_TOOL" = "$TOOL" ] && [ "$PREV_HASH" = "$INPUT_HASH" ]; then
    COUNT=$((PREV_COUNT + 1))   # 同工具+同输入，累加
  else
    COUNT=1                      # 不同工具或输入，重置
  fi
else
  COUNT=1
fi

# 原子写入新状态
jq -n --arg tool "$TOOL" --arg hash "$INPUT_HASH" --argjson count "$COUNT" \
  '{tool_name:$tool, input_hash:$hash, count:$count}' > tmp && mv tmp "$STATE_FILE"

# 3+ 次：注入软提示
if [ "$COUNT" -ge 5 ]; then
  echo "MUST use an alternative approach. Failed $COUNT times."  # → additionalContext
elif [ "$COUNT" -ge 3 ]; then
  echo "Failed $COUNT times. Consider different parameters?"     # → additionalContext
fi
```

Advisor（`tool-error-advisor.sh`，PreToolUse hook）：

```bash
# 读取错误状态
PREV_COUNT=$(jq -r '.count // 0' "$STATE_FILE")
PREV_TOOL=$(jq -r '.tool_name' "$STATE_FILE")
PREV_HASH=$(jq -r '.input_hash' "$STATE_FILE")

# 同一 tool+input、5 次以上 → 直接 deny
if [ "$PREV_TOOL" = "$TOOL" ] && [ "$PREV_HASH" = "$INPUT_HASH" ] && [ "$PREV_COUNT" -ge 5 ]; then
  echo '{"hookSpecificOutput":{"permissionDecision":"deny","reason":"BLOCKED: Failed 5 times with same input."}}'
else
  echo '{"continue":true}'
fi
```

**Tradeoff**

- Soft threshold (3 次) 的 additionalContext 是概率性的——agent 可能忽略建议继续重试。Hard threshold (5 次) 的 deny 是确定性的——agent 绕不过去。
- Input hash 只取前 200 字符。长命令的后半段不同也会被视为"相同输入"。这是精度和复杂度之间的权衡。
- 计数器不区分错误类型。5 次 "command not found" 和 5 次 "permission denied" 被同等对待。更精细的分类需要解析错误消息，增加脚本复杂度。

### 4.3 Handoff Documents (Pattern 3.1)

**问题**

Claude Code 的 context window 会被压缩。Full Compact 用 LLM 生成 9 段式结构化摘要，但你无法控制保留什么。推理过程（"为什么排除方案 B"）在压缩中最容易丢失，因为它不是"结论"也不是"代码"。

**方案**

在阶段结束时将关键决策写入磁盘文件。5 个必要段落：

```markdown
# Handoff: cache-implementation

## Decided
- 选择 Redis 作为缓存方案（项目已有 Redis 依赖）
- LRU 策略，TTL 5 分钟

## Rejected
- 排除 Memcached：团队无运维经验
- 排除本地文件缓存：不支持多实例部署

## Risks
- Redis 单点故障需要 Sentinel（当前未配置）
- 缓存穿透风险

## Files Modified
- src/cache/redis_client.py — 新建
- src/api/handlers.py:45-67 — 添加缓存查询层

## Remaining
- Sentinel 配置（下个迭代）
- 缓存预热逻辑
```

存储在 `sessions/<session-id>/handoffs/stage-<n>.md`。下一阶段的 agent 启动时读取最新的 handoff 文档。

Handoff 在磁盘上，不在 context 里——任何级别的压缩都删不掉它。

**与 Claude Code 内置压缩的关系**

Claude Code 有 4 级压缩：

| 级别 | 压缩率 | 成本 |
|------|--------|------|
| MicroCompact | 10-50K tokens | 零（删旧 tool results） |
| Session Memory | 60-80% | 零（用预建摘要替换） |
| Full Compact | 80-95% | 一次 API 调用 |
| Reactive Compact | 可变 | 应急（413 触发） |

Handoff 文档和内置压缩是互补关系。内置压缩处理"如何高效利用 context window"，handoff 处理"哪些信息必须在压缩后存活"。

**Tradeoff**

- Handoff 是 prompt 驱动的——agent 可能不遵守"写 handoff"的指令。这是概率性的，不是系统保证。可以配合 task-completion-gate 检查 handoff 文件是否存在。
- 过多阶段后累积的 handoff 内容本身成为 context 负担。每次注入所有历史 handoff 会消耗大量 token。
- 跨阶段矛盾：stage-2 推翻了 stage-1 的决策但没更新 stage-1 的 handoff。Pattern 3.3 Three-Gate Memory Consolidation 部分缓解这个问题。

### 4.4 Synthesis Gate (Pattern 4.5)

**问题**

Coordinator 收到 worker 的 research 结果后，直接传给 implementation worker："Based on the findings above, implement the fix." Coordinator 变成了邮局——没有消化、没有综合、没有判断。下游 worker 拿到原始数据而不是经过提炼的行动计划，产出质量不可控。

Anthropic 的多 agent 博客明确指出这是反模式。

**方案**

在 Research 和 Implementation 阶段之间插入一个强制 gate。Coordinator 必须产出 synthesis 文档（包含 Conclusion、Evidence、Action Plan），gate 脚本检查文档存在性和结构完整性，通过后才允许启动 implementation worker。

```bash
SYNTHESIS=".coordination/synthesis.md"

# 检查 1：文件存在且非空
if [ ! -s "$SYNTHESIS" ]; then
  echo "GATE FAILED: synthesis.md 不存在或为空"
  exit 1
fi

# 检查 2：最小长度（不能是一句话打发）
LINES=$(wc -l < "$SYNTHESIS")
if [ "$LINES" -lt 10 ]; then
  echo "GATE FAILED: synthesis.md 只有 ${LINES} 行"
  exit 1
fi

# 检查 3：必须包含关键结构
for SECTION in "Conclusion" "Action Plan" "Evidence"; do
  if ! grep -qi "$SECTION" "$SYNTHESIS"; then
    echo "GATE FAILED: 缺少必要节: ${SECTION}"
    exit 1
  fi
done

echo "GATE PASSED"
```

Gate 通过后，把 synthesis 作为 implementation worker 的输入：

```bash
claude -p --max-turns 50 \
  "根据以下 synthesis 执行实现。$(cat .coordination/synthesis.md)"
```

**Tradeoff**

- 增加一个串行步骤。多 agent 编排中的瓶颈是 coordinator synthesis，不能并行化。
- 结构化检查是浅层验证。Coordinator 可能写出满足格式（有 Conclusion 字样）但内容空洞的 synthesis。深层内容验证需要 LLM 判断，增加成本。
- 对于简单任务（research 结果一目了然），强制 synthesis 是多余的。M6 Proportional Intervention——简单任务跳过这个 gate。

### 4.5 Post-Edit Diagnostics (Pattern 6.1)

**问题**

Agent 写了一个 TypeScript 文件。文件保存成功——`Write` 工具返回 success。但文件有类型错误。Agent 不知道，继续基于这个有错误的文件修改其他文件。3 个文件之后，错误级联放大，回头修的成本远大于编辑时立即发现。

**方案**

PostToolUse hook，matcher 设为 `Write|Edit|MultiEdit`。每次文件编辑完成后立即对修改的文件跑 linter / type checker，通过 `additionalContext` 把错误反馈给 agent。

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "bash quality-verification/scripts/post-edit-check.sh",
        "async": true
      }]
    }]
  }
}
```

脚本按文件类型选择诊断工具：

```bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
[ -f "$FILE" ] || exit 0

ERRORS=""
case "$FILE" in
  *.py)
    LINT=$(ruff check "$FILE" --no-fix 2>&1 | head -5) || true
    [ -n "$LINT" ] && ERRORS="${ERRORS}ruff: ${LINT}\n"
    TYPE=$(pyright "$FILE" 2>&1 | grep -E 'error|Error' | head -3) || true
    [ -n "$TYPE" ] && ERRORS="${ERRORS}pyright: ${TYPE}\n"
    ;;
  *.ts|*.tsx)
    TYPE=$(npx tsc --noEmit "$FILE" 2>&1 | grep 'error TS' | head -3) || true
    [ -n "$TYPE" ] && ERRORS="${ERRORS}tsc: ${TYPE}\n"
    ;;
  *.rs)
    CHECK=$(cargo check 2>&1 | grep '^error' | head -3) || true
    [ -n "$CHECK" ] && ERRORS="${ERRORS}cargo: ${CHECK}\n"
    ;;
  *.go)
    VET=$(go vet "$FILE" 2>&1 | head -3) || true
    [ -n "$VET" ] && ERRORS="${ERRORS}go vet: ${VET}\n"
    ;;
  *.sh)
    SC=$(shellcheck "$FILE" 2>&1 | head -5) || true
    [ -n "$SC" ] && ERRORS="${ERRORS}shellcheck: ${SC}\n"
    ;;
esac

if [ -n "$ERRORS" ]; then
  MSG=$(echo -e "$ERRORS" | head -10)
  jq -n --arg ctx "Post-edit diagnostics found issues: $MSG" \
    '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
fi
```

**与 Pattern 2.1 的区别**

Pattern 2.1 处理工具执行失败（`cargo build` 找不到命令——tool 返回 error）。Pattern 6.1 处理工具执行成功但产出有问题（文件写入成功但引入了类型错误）。两者在故障模型上互补：

```
Tool Error Escalation (2.1):  工具调用 → 失败 → 重试升级
Post-Edit Diagnostics (6.1):  工具调用 → 成功 → 但内容有错 → 即时反馈
```

**Tradeoff**

- `async: true` 让诊断不阻塞后续工具调用。但 async 意味着 agent 可能在收到诊断结果之前已经开始编辑下一个文件。对于串行依赖强的编辑链（A 依赖 B 的类型），async 可能来不及。
- 大项目上 `cargo check` 或 `npx tsc` 可能跑 30 秒以上。频繁的小编辑会导致诊断工具排队。可以通过 debounce（合并短时间内的多次触发）优化。
- 诊断工具需要提前安装。如果开发环境没有 `ruff`/`pyright`/`shellcheck`，hook 会静默跳过（M5 fail-open）。

---

## 5. 安装与使用

3 步上手。

### Step 1: Clone

```bash
git clone https://github.com/lanyasheng/execution-harness.git
cd execution-harness
```

### Step 2: 配置 settings.json

把 hook 脚本路径加到 `~/.claude/settings.json`。以下是最小起步配置：

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/execution-loop/scripts/ralph-stop-hook.sh"},
        {"type": "command", "command": "bash /path/to/execution-loop/scripts/doubt-gate.sh"},
        {"type": "command", "command": "bash /path/to/quality-verification/scripts/bracket-hook.sh", "async": true}
      ]
    }],
    "PostToolUseFailure": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/tool-governance/scripts/tool-error-tracker.sh", "async": true}
      ]
    }],
    "PreToolUse": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/tool-governance/scripts/tool-error-advisor.sh"},
        {"type": "command", "command": "bash /path/to/tool-governance/scripts/tool-input-guard.sh"}
      ]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [
        {"type": "command", "command": "bash /path/to/quality-verification/scripts/post-edit-check.sh", "async": true}
      ]
    }]
  }
}
```

把 `/path/to/` 替换成你的实际路径。

### Step 3: 启动 Ralph（可选）

如果你的任务需要持续执行（不要让 agent 中途停下来）：

```bash
# 初始化：session-id 是任意标识，50 是最大迭代数
bash execution-loop/scripts/ralph-init.sh my-task 50

# 在 Claude Code 中设置 session ID
export NC_SESSION=my-task

# 正常使用 Claude Code，Stop hook 会自动阻止提前退出
```

取消 Ralph：

```bash
bash execution-loop/scripts/ralph-cancel.sh my-task
```

### 依赖

只需要 `bash`、`jq`、`python3`。诊断相关的工具（`ruff`、`pyright`、`shellcheck`、`tsc`）是可选的——没装就静默跳过。

---

## 6. 蒸馏方法论

38 个 pattern 不是凭空设计的。从 4 个开源项目中蒸馏而来。

### 4 个源

| 项目 | 贡献 |
|------|------|
| [harness-books](https://github.com/wquguru/harness-books) | 10 条设计原则的理论框架，来自 Anthropic 和 OpenAI 的 harness engineering 文章 |
| [claude-reviews-claude](https://github.com/openedclaude/claude-reviews-claude) | Claude Code v2.1.88 源码级架构分析，揭示了压缩机制、hook 协议、session 管理的内部实现 |
| [ccunpacked.dev](https://ccunpacked.dev/) | 工具全景、hidden features、API 行为的系统性文档 |
| [claude-howto](https://github.com/luongnv89/claude-howto) | Hook 扩展点 API 教程，覆盖了各种 hook type 的 stdin/stdout 协议 |

### 蒸馏过程

1. **阅读和标注**：通读 4 个源的所有文档和代码。标注每个值得提取的 pattern——criteria 是"如果不做这件事，agent 会以可预测的方式失败"。
2. **分类**：按失败模式分为 6 轴。每个 pattern 属于且仅属于一个轴。
3. **分级**：每个 pattern 标注为 `[script]`（可执行脚本）、`[design]`（设计指南）或 `[config]`（配置模板）。Script 类的 pattern 需要实现并测试；design 类的 pattern 提供参考文档和伪代码。
4. **实现**：14 个 script 类 pattern 实现为 17 个 bash 脚本（部分 pattern 含多个脚本，如 Ralph 有 stop-hook、init、cancel 三个），每个脚本遵循 Claude Code hook 协议（stdin 读 JSON，stdout 写 JSON）。
5. **测试**：90 个 pytest 测试覆盖所有 script 类 pattern。测试验证 hook 在各种输入下的行为——正常流程、边界条件、错误处理。

### 不做什么

蒸馏过程中刻意排除了：

- **编排逻辑**（DAG、fan-in/fan-out）——那是编排层的事，不是执行层
- **Prompt engineering 技巧**——execution harness 的定位是确定性机制（M1），不管 prompt 写法
- **模型选择和路由**——hook 不能切换模型（M10，已标注 advisory only）
- **项目特定配置**——pattern 是通用的，`tsconfig.json` 路径之类的细节留给用户

---

## 7. 已知限制

### Context 使用率无法精确获取

Claude Code 不向 hook 暴露 `context_window_size`。Hook 只能从 transcript 文件里读 `input_tokens` 的原始数值，但不知道总窗口大小，所以无法算出百分比。Ralph 的"context >= 95% 放行"安全阀因此未实现——依赖 Claude Code 自己的 reactive compaction 处理溢出。

### 模型切换是建议而非执行

Hook 不能切换模型。Pattern 5.6 Model Fallback Advisory 只能在 `additionalContext` 里说"考虑换个模型"。Agent 可以忽略这个建议。

### Doubt Gate 有误报

"should be"、"I think" 在代码注释和引用中也会匹配。脚本用 sed 过滤掉代码块和 blockquote，但不能完全消除。One-shot guard（`.doubt-gate-fired` 文件）防止 doubt gate 触发后的死循环——第一次触发时写 guard 文件，第二次 Stop 时读到 guard 文件直接放行。

### Denial Tracker 靠推断

Claude Code 没有专用的"用户否决了工具调用"的 hook event。`denial-tracker.sh` 从 assistant 消息推断否决（检测"I understand, I won't..."之类的措辞），准确率取决于 agent 的回复风格。

### Drift Re-anchoring 依赖外部设置

原始任务描述需要通过 `reanchor.json` 或 `original-task.md` 文件提前设置。如果用户忘了初始化这个文件，re-anchoring 不会触发（M5 fail-open）。

### 多 agent 模式全部是 design pattern

Multi-Agent 轴的 6 个 pattern 都是 `[design]` 类型，没有可执行脚本。原因是多 agent 编排的差异太大——coordinator 模式、fork 模式、swarm 模式的具体实现因场景而异，硬编码脚本反而限制适用性。File claim lock 提供了伪代码和实现参考，但需要用户根据自己的编排方案集成。

---

## 8. Sources

| 项目/文档 | 链接 | 贡献 |
|-----------|------|------|
| Harness Engineering (harness-books) | [github.com/wquguru/harness-books](https://github.com/wquguru/harness-books) | 10 条设计原则的理论框架 |
| Claude Reviews Claude | [github.com/openedclaude/claude-reviews-claude](https://github.com/openedclaude/claude-reviews-claude) | Claude Code v2.1.88 源码级架构 pattern |
| ccunpacked.dev | [ccunpacked.dev](https://ccunpacked.dev/) | 工具全景、hidden features |
| claude-howto | [github.com/luongnv89/claude-howto](https://github.com/luongnv89/claude-howto) | 扩展点 API 教程 |
| Anthropic Harness Engineering | [anthropic.com/engineering/effective-harnesses-for-long-running-agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | 官方设计原则 |
| OpenAI Harness Engineering | [openai.com/index/harness-engineering/](https://openai.com/index/harness-engineering/) | 跨厂商验证的设计原则 |
| Anthropic Multi-Agent Systems | Anthropic "Building multi-agent systems" blog | Coordinator synthesis 原则 |
| Execution Harness Repo | [github.com/lanyasheng/execution-harness](https://github.com/lanyasheng/execution-harness) | 本项目 |
