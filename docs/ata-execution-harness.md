# 让 Agent 把活干完：从 Claude Code 512K 行源码蒸馏 21 个执行可靠性 Pattern

---

## 1. 你的 Agent 真的在干活吗

如果你在生产环境跑过 agent 超过一周，下面这些场景大概率见过：

你让 agent 重构一个横跨 7 个文件的模块。它改完前两个文件，发了一句"剩下的文件结构类似，按同样方式修改即可"，然后 `end_turn`。剩下五个文件原封不动。

容器里压根没装 cargo。`cargo build` 报 `command not found`。第二次同样参数同样报错。第三次还是。一共十二次。每次消耗 token，每次结果相同。

agent 改完代码说"这个修改应该是可以解决问题的，大概不会有副作用"。没跑测试，没看日志，没验证编译。你发现问题已经是两个小时以后的事了。

tmux 里的 agent 遇到 API 限速，卡在那里等你手动按回车。你在楼下吃饭这一小时，它就静静地等着。

这些不是模型能力问题——它知道怎么改代码。问题在 *harness*：agent 周围那层保障执行可靠性的基础设施是空的。模型在进步，但长任务可靠性的瓶颈在 harness 层。

execution-harness 做的就是补这层。21 个 pattern，8 个 bash 脚本，42 个测试。往 `settings.json` 里加几行 hook 配置就生效。没有框架，没有 runtime，没有 npm 全局包。

---

## 2. 蒸馏方法论：PCA 降维与品味注入

从 512K 行代码里提取 21 个 pattern——一个 agent 在单个 session 里读不完 51.2 万行 TypeScript。这件事本身就是个 harness engineering 问题。

### 2.1 PCA 类比

LastWhisperDev 在他的微信公众号文章中提出了一个类比：

> 代码是高维的，但有价值的设计模式是低秩的。蒸馏的本质是找到主成分。

问题是，"客观地"提取所有模式反而最没用。没有视角就没有优先级。最初几轮产出的东西就是这样：面面俱到地列出 Claude Code 有哪些子系统，但不说该用什么、为什么。

解法是注入 *基向量*：

1. 把 Anthropic 的 harness engineering 博客、OpenAI 的 Context Engineering 四轴框架（select / write / compress / isolate）、LastWhisperDev 对 "Do the simple thing that works" 的偏好作为投影方向。
2. 让 agent 沿这些方向从代码中提取主成分。不是什么都提取。
3. 诚实标注视角。execution-harness 不是 Claude Code 的客观映射，是经过"执行可靠性"这个视角过滤后的结果。

### 2.2 Review-Execution 分离

蒸馏流程的核心设计：*不让实现者审查自己的代码*。

Codex（GPT 5.4 xhigh）做 review——以全新视角对照源码查事实、判抽象层级。Claude Code（Opus 4.6 max）做 execution——读源码、写文档、协调子 agent 并行。两个 agent 互不可见对方的 session。每轮 review-action 循环在全新 session 中进行——拿到完整 token 预算，不被前几轮上下文污染。唯一协调媒介是磁盘上的 handoff 文档。

本质上是 Coordinator 模式的人工版本：人做 coordinator，两个 agent 做 specialized worker。Anthropic 在多 agent 系统博客里说过同一个原则——verification subagent 应该专职，和主 agent 分开。

### 2.3 信息来源全景

21 个 pattern 来自 12+ 个来源，每个贡献不同：

| 来源 | 贡献了什么 |
|------|-----------|
| Claude Code v2.1.88 源码 | Query Engine loop、Permission Pipeline、Context Management、Session Persistence。约一半 pattern 的内部实现参考 |
| oh-my-claudecode (OMC) | Ralph 持续执行模式（名字来自 OMC）、Cancel TTL 30 秒、Stale threshold 2 小时、状态文件读取的 4 级 fallback |
| ccunpacked.dev | DenialTrackingState 的逆向、AutoDream 记忆合并、MCP auto-healing |
| claude-howto | Prompt-type / Agent-type hook 的区分、Hook pair bracket、Component-scoped hooks 的 `once: true` |
| Claude Code 官方文档 | 26 个 hook 事件的 JSON schema、permission 协议。验证所有 hook 实现的基准 |
| LastWhisperDev | 蒸馏方法论——PCA 类比、Review-Execution 分离、品味注入 |
| agentic-harness-patterns-skill | 6 个跨框架设计原则（Memory, Skills, Tools, Context, Multi-agent, Lifecycle）|
| plugin-doubt-gate | Speculation detection 通过 hedging word scan |
| Continuous-Claude-v3 | Post-edit diagnostics、stale session daemon、heartbeat 机制 |
| everything-claude-code (ECC) | Hook runtime profiles、instinct evolution 概念 |
| sdd-autopilot | 8 阶段 pipeline 复杂度分级 → Adaptive complexity scoring |
| Anthropic / OpenAI 博客 | Harness engineering 设计原则、filesystem-as-context |

---

## 3. 架构设计：三个 Skill，三类读者

### 3.1 为什么拆成三个 Skill

最初版本是 12 个 pattern 全塞一个 SKILL.md。问题立刻暴露：需要 hook 脚本的开发者被迫读完 10 页设计原则才能找到配置方法；做架构设计的人不需要知道 `ralph-stop-hook.sh` 里怎么 parse JSON；SRE 只想知道怎么检测限速和恢复死 session。

拆了：

```
execution-harness/
├── skills/
│   ├── agent-hooks/               ← 开发者：装 hook，配 settings.json，走人
│   ├── harness-design-patterns/   ← 架构师：设计多 agent 系统时的参考
│   └── agent-ops/                 ← SRE：监控、恢复、保护运行中的 agent
└── shared/                        ← Session state layout（三者共用）
```

reference 文件名保留原始编号（01/03/07/13/15...），不连续。monorepo 拆分的历史痕迹，也方便跨 skill 引用不产生歧义。

### 3.2 Session-Scoped State Layout

所有运行时状态统一在一个 session 目录下：

```
sessions/<session-id>/
  ralph.json              ← 持续执行状态
  cancel.json             ← 30 秒 TTL 取消信号
  handoffs/               ← 阶段间 handoff 文档
  tool-errors.json        ← 工具连续失败追踪
  denials.json            ← 权限否决追踪
  bracket.json            ← 每轮测量数据
  .doubt-gate-fired       ← 投机检测守卫标志
```

一个 session 的所有状态就是一个目录。清理靠 `rm -rf`。没有散落在不同路径的碎片。

不做跨 session 读取。OMC 有 4 级 fallback 去扫描其他 session 的状态文件，我们选择严格 session-scoped，不做 fallback。理由是简单：跨 session 状态泄漏是一类很难调试的 bug，不值得为向后兼容冒这个险。

Crash 恢复靠目录检查。`ralph-init.sh` 初始化时先看有没有残留 `ralph.json`。发现 `active: true` 或 `deactivation_reason: "stale"`，不重置迭代计数器，从上次位置恢复。这解决了"agent 在第 37 轮 crash 后重启从 0 开始"的问题。

### 3.3 Hook 协议兼容性

所有脚本对照 Claude Code 官方文档验证过 26 个 hook event。我们用了 5 种：

| Hook Event | 用途 | 脚本 |
|------------|------|------|
| Stop | 阻止提前停止 / 检测投机语言 | `ralph-stop-hook.sh`, `doubt-gate.sh` |
| PostToolUseFailure | 追踪工具连续失败 | `tool-error-tracker.sh` |
| PreToolUse | 阻止已失败 5 次的工具重试 | `tool-error-advisor.sh` |
| PostToolUse | 编辑后即时诊断 | `post-edit-check.sh` |
| （CLI 调用） | 初始化 / 取消 | `ralph-init.sh`, `ralph-cancel.sh` |

输入输出遵循同一协议——stdin 接 JSON（含 `session_id`, `tool_name`, `tool_input` 等），stdout 输出 JSON 决策：

```json
{"continue": true}                                    // 放行
{"decision": "block", "reason": "..."}                 // 阻止
{"hookSpecificOutput": {"additionalContext": "..."}}   // 注入上下文
```

---

## 4. 核心 Pattern 深度解析

### 4.1 Ralph 持续执行

Claude Code 在复杂任务中经常"觉得自己做完了"就发 `end_turn`。多文件修改尤其常见——改完第一个文件就停，剩下的被遗忘。

Ralph 的名字来自 OMC 的 `persistent-mode.mjs`，是 OMC 里九种持续执行模式中优先级最高的。核心逻辑：

```
Agent 尝试停止
  → Stop hook 触发
    → 读 sessions/<session-id>/ralph.json
      → active=true 且 iteration < max?
        → 是: {"decision":"block","reason":"继续干活"}，iteration++
        → 否: {"continue":true}
```

简单的"继续工作"消息效果不好。agent 会合理化——"剩下的工作可以在后续 session 中完成"。所以 block 消息需要预判这种倾向：

```
[RALPH LOOP 5/50] Task is NOT done.
Do NOT rationalize that "the remaining work can be done in a follow-up."
Do NOT claim completion with caveats.
Check your original task description and verify EVERY requirement is met.
Continue working on the original task.
```

这条消息的设计参考了 prompt-hardening 的反推理阻断原则：不只告诉 agent "继续"，还要堵住它最可能的逃逸路径。

**4 个安全阀。** 无论 ralph 状态如何，遇到以下情况直接放行：

认证失败（401/403）——token 过期了继续执行没有意义。Cancel 信号——带 30 秒 TTL 的取消文件，过期自动忽略。OMC 选 30 秒是因为足够覆盖 Stop hook 的检查周期（通常 1-5 秒内触发），又不会长到影响后续 session。闲置超时 > 2 小时——防止 zombie 状态永远占用资源，阈值来自 OMC 的 `STALE_STATE_THRESHOLD_MS = 7200000`。达到 max_iterations——防止无限循环，默认 50 轮。

缺了一个：context_window >= 95%。设计中预期的第 5 个安全阀，但无法实现——Claude Code 的 transcript JSONL 不包含 `context_window_size` 字段，这个数据只通过 statusLine stdin pipe 提供给 HUD 插件，hook 脚本拿不到。Claude Code 自身的 reactive compaction 独立处理 context 溢出，实践中这个缺失可以接受，但不完美。后面"已知局限"一节会展开。

**Crash recovery。** `ralph-init.sh` 初始化时先检查有没有残留状态文件。发现 `active: true`，说明上次 session 非正常退出，不重置 `iteration`，从上次的值继续。测试代码做了端到端验证：初始化 → 手动改 iteration 到 5（模拟 crash）→ 再次初始化 → 确认 iteration 保持 5 且输出包含 "Resuming"。

注意 Ralph 仅适用于 interactive 模式。Headless（`-p`）没有 Stop 事件循环，用 `--max-turns` 代替。

### 4.2 Doubt Gate：你说"可能"我就不让你停

Ralph 基于迭代计数阻止 agent 过早停止。Doubt Gate 基于内容分析阻止 agent 以不确定的方式停止。两者正交。

Stop hook 触发时，先 strip 代码块和引用块（否则 `// I think this might need review` 这种注释会误触发），然后扫描剩余文本中的投机性关键词：

英文：`likely`, `maybe`, `might`, `probably`, `not sure`, `I think`, `I believe`, `should be`, `could be`, `possibly`
中文：`可能`, `大概`, `也许`, `应该是`, `我认为`, `我猜`, `不太确定`, `估计是`

命中任何一个就 block，要求 agent 提供证据——跑测试、看日志、读文件验证。

这里有个死循环风险：如果 agent 的性格就是喜欢用"可能"，它重新回答时还是会说"可能"，然后再被 block，无穷无尽。所以引入了 one-shot guard：第一次触发时写一个 `.doubt-gate-fired` 标志文件，第二次 stop 时看到这个文件就无条件放行，然后删掉文件。

代价很明确：第二次尝试即使仍然投机也会放行。但没有这个 guard，agent 可能永远无法停止。

误报是已知问题。"这个 bug 可能影响了三个模块"中的"可能"是合理分析，不是投机。但 doubt gate 只做关键词匹配，没有语义消歧能力。

### 4.3 Tool Error Escalation：连续 5 次相同失败，强制换路

`cargo build` 在没装 cargo 的容器里执行了 5 次，每次相同输入、相同 `command not found: cargo`。

两个脚本配合：PostToolUseFailure hook (`tool-error-tracker.sh`) 追踪，PreToolUse hook (`tool-error-advisor.sh`) 干预。

| 连续失败次数 | 行为 |
|-------------|------|
| 1-2 | 只记录，不干预 |
| 3-4 | 注入软提示："已失败 3 次，考虑换参数/路径/依赖？" |
| 5+ | 注入强制切换："MUST use an alternative approach" |

一个容易忽略的细节是 `input_hash` 的确定性。用 `jq -Sc` 对 tool_input 做 compact sorted JSON，取前 200 字符做 md5。这区分了"同一个命令反复失败"和"不同命令分别失败"。agent 换了参数重试（哪怕换一个字符），hash 变化，计数器重置。只有完全相同的输入连续失败才会升级。这个设计在 P0-4 bug 中被修过一次——最初没排序 JSON key，导致 `{"a":1,"b":2}` 和 `{"b":2,"a":1}` 被判定为不同输入。

第 5 次失败后，`tool-error-advisor.sh` 在 PreToolUse 阶段返回 `permissionDecision: "deny"`，直接阻止执行。和 `additionalContext`（建议性，LLM 可能忽略）不同，`permissionDecision` 是确定性的。

### 4.4 Handoff 文档：内置压缩不够用

Claude Code 有 4 级压缩（MicroCompact → Session Memory → Full Compact → Reactive Compact），长任务中自动触发。压缩后，关键的设计决策、排除过的方案、已识别的风险会丢。

为什么不能只靠内置压缩？两个原因。

第一，摘要内容由 LLM 决定，你控制不了保留什么。"排除 Memcached 的原因"在 LLM 看来可能不重要，就被丢了。三天后你需要回顾这个决策时，信息不在了。

第二，Full Compact 用 `<analysis>` scratchpad 提高摘要质量，但 scratchpad 内容 strip 后不进入压缩后的 context。推理过程丢失。

Handoff 文档的做法：阶段结束时把关键信息写入磁盘文件。5 个段落——Decided / Rejected / Risks / Files Modified / Remaining。压缩后的 agent 读磁盘恢复上下文。Handoff 在磁盘上，任何级别的 context 压缩都碰不到它。

和内置压缩互补。你控制保留什么，内置压缩处理剩下的。

还有一个配套机制：Compaction Memory Extraction (Pattern 8)。在 PreCompact hook 中注入 prompt，让 agent 在压缩发生前把当前未保存的发现写入 handoff。Handoff 是计划内的上下文传递，compaction extraction 是被动的知识抢救。

---

## 5. 工程质量：3 轮 review 和 5 个 P0 bug

### 5.1 三轮 multi-agent review

仓库经过 3 轮不同焦点的 review。第一轮查功能正确性——pattern 实现对不对、脚本按不按描述工作、测试覆盖够不够。第二轮查协议合规——hook 的 input/output JSON 是否符合 Claude Code 官方 schema、字段名对不对。第三轮查事实准确性——reference 文档引用的 Claude Code 内部机制是否和源码一致、OMC 的阈值和字段名对不对。

53 个问题，修了 30 个。5 个 reviewer 错误被识别并拒绝——reviewer 也会犯错，这正是 multi-agent review 的意义。

### 5.2 五个 P0 bug

**`context_window_size` 不在 transcript 里。** 最初假设能从 transcript JSONL 读 `context_window_size` 算百分比。transcript 里根本没有这个字段——只通过 statusLine stdin pipe 给 HUD 插件。`context-usage.sh` 只能报原始 `input_tokens`，算不了百分比。Ralph 的 context >= 95% 安全阀因此实现不了。修复方式不是找到正确字段，是诚实标注限制——README、SKILL.md、reference、脚本注释里全部声明这个局限。

**`git stash create --include-untracked` 静默失败。** Checkpoint/Rollback (Pattern 19) 最初用这个命令捕获 untracked 文件。但 `git stash create` 不支持 `--include-untracked`，只有 `push`/`save` 支持。`create` 加这个 flag 不报错，静默忽略，untracked 文件不被包含在快照中。最后改成先 `git add -A`、再 `git stash create`、最后 `git reset HEAD` 恢复 index。这类静默失败的 bug 特别阴险——工具不报错，你以为它成功了。

**JSON 注入。** 最初 tool-error-tracker 用 bash 字符串拼接构造 JSON。错误消息里有引号或换行就把 JSON 搞坏了。修复后所有 JSON 输出通过 `jq -n --arg` 构造，`jq` 自动处理转义。8 个脚本统一了这个模式。

**`input_hash` 不确定性。** 上面 4.3 节提到的：最初没排序 JSON key，相同语义的输入算出不同 hash。`jq -Sc` 修复。

**协议字段名错误。** `tool-error-advisor.sh` 最初输出 `{"decision":"deny"}`。PreToolUse hook 的官方协议要求 `hookSpecificOutput.permissionDecision`。字段名不对，Claude Code 直接忽略整个输出。靠逐个对照官方文档 26 个 hook event 的 schema 才发现。

### 5.3 从 12 到 21，从一个文件到三个 Skill

git log 看演进：

```
421b5a9  初始版本：12 个 pattern，全塞一个 SKILL.md
3e7fe0f  session-scoped state 隔离 + crash recovery
dceda34  全面重写：去掉所有 Claude Code 内部路径引用
ffa8db7  扩展到 18 个 pattern + 蒸馏方法论文档
e58c21c  扩展到 21 个 pattern，checkpoint/rollback, token budget, model fallback
94f76f4  拆成 3 个 skill（agent-hooks / harness-design-patterns / agent-ops）
c8f3913  修复 session_id 来源：用 stdin JSON 而非依赖环境变量
e78ccad  P0 修复：JSON 注入、确定性 hash、安全阀实现
f99ecce  协议合规：5 个字段名/schema 错误
c2e12e2  agent-ops review 的 3 个 P0
29ddf3f  ops factcheck 的 2 个 CRITICAL
b26fe0e  质量审计：7 个事实错误、phantom 引用、过时数字
```

前 5 个 commit 在加功能，后 7 个 commit 全在修 bug。pattern 数量在增长，但后半段主要精力花在质量密度上。

### 5.4 improvement-learner 的新增维度

接入 improvement-learner（技能质量评估工具）时发现原有评分维度有盲区，新增了两个：

**leakage** —— 是否泄露不应暴露的内部实现细节（比如 Claude Code 的 source-mapped 变量名）。跨运行时可移植的 pattern 不应该依赖某个版本的内部命名。

**knowledge_density** —— 每百 token 的有效信息密度。防止 SKILL.md 或 reference 文件用套话填充篇幅。这个维度直接影响了 SKILL.md 的写法：能用一句话说清的不用两句。

---

## 6. 已知局限

**context_window 安全阀无法实现。** Ralph 设计中的第 5 个安全阀，原意是 context >= 95% 时放行 stop，防止溢出崩溃。Claude Code 不在 hook 可访问的数据中暴露 `context_window_size`。只能拿到 `input_tokens` 原始数，不知道总 context window 是 200K 还是 1M。用硬编码阈值（160K tokens）做近似判断不够可靠，所以选择不做，而不是做一个不可靠的版本。

**model fallback 是建议性的。** hook 脚本无法切换 Claude Code 使用的模型。Pattern 21 的"自动模型降级/升级"只能在 `additionalContext` 中注入建议，agent 可能不遵守。确定性的 fallback 方式只有一种：在 subagent 定义中预先指定不同模型。

**doubt gate 有误报。** "这个 bug 可能影响了三个模块"中的"可能"是合理分析，但 doubt gate 只做关键词匹配。one-shot guard 防了无限循环，代价是第二次尝试永远放行。如果要做语义级消歧，需要 prompt-type hook 用 LLM 判断——每次 stop 多一次 API 调用。目前选择不做。

**Claude Code 内部名称可能过时。** `AutoDream`、`DenialTrackingState`、`buildExtractAutoOnlyPrompt` 来自 source-mapped v2.1.88 TypeScript。跨版本可能改名。reference 文档用了这些名字，主 SKILL.md 尽量不依赖。

**21 个 pattern 中 8 个有可执行脚本，13 个是设计参考。** 三种委托模式（Coordinator/Fork/Swarm）、三门控记忆合并、Adaptive Complexity 偏架构设计，不是一个 shell 脚本能覆盖的。

**Headless 模式不适用 Ralph。** `-p` 模式没有 Stop 事件循环。用 `--max-turns` 代替。Claude Code 的设计如此——headless 是单次批处理。

---

## 7. 与同类项目的对比

**agentic-harness-patterns-skill。** LastWhisperDev 的原始蒸馏产物，纯知识库，0 可执行代码，6 个跨框架设计原则。execution-harness 在它基础上增加了 15 个 pattern 并将 8 个落地为脚本。抽象层级不同：前者是原则级（"agent 应该管理记忆"），后者是方案级（"用 handoff 文档写 5 段、存在 `sessions/<id>/handoffs/` 下"）。

**oh-my-claudecode (OMC)。** execution-harness 的多个 pattern 源自 OMC，但定位完全不同。OMC 是完整的 CLI wrapper + orchestration layer：npm 全局包，9 种持续执行模式，team runtime，rate limit daemon。execution-harness 只提取了和执行可靠性直接相关的几个机制（Ralph、Cancel TTL、Stale threshold），用 bash + jq 实现。想装全套用 OMC，只想加几个 hook 用 execution-harness。

**everything-claude-code (ECC)。** 38 个 agent、156 个 skill、插件市场。execution-harness 从中取了 Hook Runtime Profiles（环境变量控制 hook 强度）的概念。ECC 做所有事情，execution-harness 只做执行可靠性。

一句话说就是：agentic-harness-patterns 告诉你原则，execution-harness 给你能跑的脚本，OMC 和 ECC 给你全套基础设施。选哪个取决于你想要多重的依赖。

---

## 8. 下一步

13 个只有设计参考的 pattern 需要落地脚本。Compaction Memory Extraction (Pattern 8) 有 PreCompact hook 配置示例但没独立脚本。Adaptive Complexity (Pattern 16) 的 triage 逻辑有伪代码但没可直接用的 `triage.sh`。这些脚本的难度不在实现——bash + jq 能搞定——而在验证：怎么测试一个 PreCompact hook 是否在正确时机触发？

42 个测试都是单元级的：mock stdin 输入，验证 stdout 输出。缺集成级验证——把所有 hook 配到真实 Claude Code session 里，跑一个多文件修改任务，观察 Ralph 是否正确 block、doubt gate 是否触发、tool error 是否升级。这需要和 improvement-evaluator 的 task suite 结合，但 evaluator 本身的 task suite 格式还在迭代。

仓库中的 `quality-pipeline-integration.md` 描述了 5 个和 improvement-* skill family 的接入点（evaluator + Ralph、autoloop + handoff、gate + agent-type hook、learner + compaction extraction、forge + pattern-aware test gen），全是方案级的，没有代码。

context_window 安全阀的补救得等 Claude Code 一侧的变化——如果未来 hook 输入中暴露 context window 数据，或者通过 HUD plugin 的 IPC 间接获取，第 5 个安全阀就能实现。在那之前，用硬编码阈值做近似判断精度不够，宁可不做。

还有一个方向值得探索：doubt gate 的语义升级。目前的关键词匹配可以升级为 prompt-type hook——用 LLM 判断"这句话是合理推测还是投机逃避"。代价是每次 stop 多一次 API 调用。对高价值任务（安全修复、数据迁移），这个成本可以接受。
