# 让 Agent 把活干完：从 Claude Code 512K 行源码蒸馏 21 个执行可靠性 Pattern

---

## 1. 你的 Agent 真的在干活吗

如果你在生产环境跑过 agent 超过一周，下面这些场景大概率见过：

你让 agent 重构一个横跨 7 个文件的模块。它改完前两个文件，发了一句"剩下的文件结构类似，按同样方式修改即可"，然后 `end_turn`。剩下五个文件原封不动。

容器里压根没装 cargo。`cargo build` 报 `command not found`。第二次同样参数同样报错。第三次还是。一共十二次。每次消耗 token，每次结果相同。

agent 改完代码说"这个修改应该是可以解决问题的，大概不会有副作用"。没跑测试，没看日志，没验证编译。你发现问题已经是两个小时以后的事了。

tmux 里的 agent 遇到 API 限速，卡在那里等你手动按回车。你在楼下吃饭这一小时，它就静静地等着。

这些不是模型能力问题——它知道怎么改代码。问题在 *harness*。

Harness 这个词在 agent 语境下指的是模型循环（query → tool_use → result → query...）周围的所有基础设施：何时启动、何时停止、出错怎么办、上下文不够了怎么办、多个 agent 怎么协调。模型是引擎，harness 是车架、刹车和安全带。引擎再好，没有刹车会翻车。

Anthropic 的 [harness engineering 博客](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) 和 OpenAI 的 [同名博客](https://openai.com/index/harness-engineering/) 都在说同一件事：模型能力在快速提升，但长任务可靠性的瓶颈不在模型，在 harness。你需要在模型循环之外建一层保障——检测提前停止、恢复 crash 状态、阻止无意义重试、保存关键上下文不被压缩丢掉。

execution-harness 做的就是补这层。21 个 pattern，8 个 bash 脚本，42 个测试。往 `settings.json` 里加几行 hook 配置就生效。没有框架，没有 runtime，没有 npm 全局包。

---

## 2. 蒸馏方法论：PCA 降维与品味注入

从 512K 行代码里提取 21 个 pattern——一个 agent 在单个 session 里读不完 51.2 万行 TypeScript。这件事本身就是个 harness engineering 问题。

### 2.1 PCA 类比

LastWhisperDev 在一篇关于 harness engineering 的技术文章中提出了一个类比：

> 代码是高维的，但有价值的设计模式是低秩的。蒸馏的本质是找到主成分。

问题是，"客观地"提取所有模式反而最没用。没有视角就没有优先级。最初几轮产出的东西就是这样：面面俱到地列出 Claude Code 有哪些子系统，但不说该用什么、为什么。

解法是注入 *基向量*：

1. 把 Anthropic 的 harness engineering 博客、OpenAI 的 Context Engineering 四轴框架（select / write / compress / isolate）、LastWhisperDev 对 "Do the simple thing that works" 的偏好作为投影方向。
2. 让 agent 沿这些方向从代码中提取主成分。不是什么都提取。
3. 诚实标注视角。execution-harness 不是 Claude Code 的客观映射，是经过"执行可靠性"这个视角过滤后的结果。

### 2.2 Review-Execution 分离

蒸馏流程的核心设计：*不让实现者审查自己的代码*。

用不同模型分别做 review 和 execution。Review agent 以全新视角对照源码查事实、判断抽象层级是否正确。Execution agent 读源码、写文档、协调子 agent 并行工作。两个 agent 互不可见对方的 session。

每轮 review-action 循环在全新 session 中进行。这一点很关键——如果在同一个 session 里连续做多轮 review + 修改，agent 的 context 会被前几轮的讨论填满，导致后面的 review 质量下降。新 session 拿到完整 token 预算，不被前几轮上下文污染。唯一协调媒介是磁盘上的 handoff 文档。

这个设计本身就是 Handoff 文档 (Pattern 2) 的一次实践。每一轮 review 的输出是一份结构化的审查报告（severity 分级、源码引用、修复建议），每一轮 execution 的输出是一份 handoff（做了什么、改了哪些文件、遗留什么问题）。新 session 的 agent 启动后第一件事是读最新的 handoff，然后继续工作。不需要看之前的对话历史。

本质上是 Coordinator 模式（Pattern 14）的人工版本：人做 coordinator，两个 agent 做 specialized worker。Anthropic 在 [Building multi-agent systems](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them) 中提到过同一个原则——verification subagent 应该专职，和主 agent 分开。

### 2.3 蒸馏过程中自身的 harness 问题

蒸馏过程本身遇到了蒸馏结果想要解决的问题。

读源码的 agent 经常在读完 3-4 个文件后就说"已经理解了整体架构"然后停下来。51.2 万行代码读 4 个文件就理解了？这就是 Pattern 1（Ralph）的使用场景。

多个 agent 并行写不同的 reference 文档时，偶尔两个 agent 对同一个概念给出了不同的描述。一个说 MicroCompact 移除 8 种工具类型的结果，另一个说 6 种。这需要 Pattern 14（三种委托模式）里 Coordinator 的"synthesis 不能委派"原则——coordinator（人）需要自己核实哪个是对的，而不是把两个矛盾的说法都保留。

跑了 4 轮 review 后，context 被压缩好几次。之前某一轮 review 指出的"Pattern 9 的阈值数字来源不明"在压缩后丢失了，后面的 agent 又写上了同样的未验证数字。这就是 Pattern 2（Handoff）和 Pattern 8（Compaction 提取）想要解决的问题。

如果这个蒸馏过程再做一次，我会从一开始就用 execution-harness 自己的 pattern 来保障蒸馏过程——用 Ralph 防止 agent 读几个文件就停下来，用 Handoff 保存每轮 review 的发现，用 Doubt Gate 阻止 agent 用"大概是这样"来交差。

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

12 个来源不是一开始就确定的。最初只有 4 个（Claude Code 源码、OMC、ccunpacked、claude-howto）。分析完这 4 个后发现只有 12 个 pattern——感觉还不够。然后并行启动 3 路搜索 agent，分别在 GitHub 仓库、ClaWHub 生态、和 agent reliability 研究方向搜索。搜回来的候选里，`plugin-doubt-gate` 贡献了投机检测（我们之前完全没有这个维度），`sdd-autopilot` 贡献了复杂度自适应（我们之前对所有任务一视同仁），`Continuous-Claude-v3` 贡献了编辑后即时诊断和 heartbeat 机制。

但不是所有搜到的 pattern 都采纳了。40+ 个候选经过去重和优先级排序后保留了 21 个。淘汰的标准是两个：一，和已有 pattern 语义重叠（比如"file-based working memory"和我们的 handoff 文档本质相同，只是命名不同）；二，不可在 hook 脚本中实现（比如"render cache stability with WeakMap"是 Node.js 应用层模式，bash 做不了）。

一个意外的发现：LastWhisperDev 也做了同样的蒸馏工作，产出了 [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill)。他的技术文章中的 PCA 降维类比——"代码是高维的，有价值的设计模式是低秩的"——比我们最初的"从源码提取 pattern"表述精确得多。这个类比被直接采纳到了蒸馏方法论文档中。

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

### 3.3 为什么用 bash + jq 而不是 Node.js 或 Python

Hook 脚本选 bash + jq 有三个理由。

第一，启动速度。Stop hook 在 agent 每次尝试停止时触发。如果脚本需要 100ms 的 Node.js 启动开销或 200ms 的 Python import 开销，agent 在高频 stop-block-continue 循环中会明显变慢。bash + jq 是 sub-10ms。

第二，零依赖。`bash` 和 `jq` 在任何开发者的 macOS/Linux 机器上都有。不需要 `npm install`，不需要 `pip install`，不需要管虚拟环境。复制脚本到任何路径，改一下 settings.json 里的路径，就能工作。

第三，可审计性。每个脚本不超过 100 行。一个中级工程师花 5 分钟能读完一个脚本并理解它做了什么。如果用 TypeScript 实现同样的逻辑，加上类型定义、import、错误处理、package.json，代码量至少翻 3 倍。

代价也有。bash 的 JSON 处理能力依赖 `jq`——没有 `jq` 就什么都做不了。错误处理比较粗糙——`set -euo pipefail` 是个好开始，但 bash 的错误传播远不如 try/catch 精确。日期解析需要三层 fallback（macOS `date -j` → GNU `date -d` → Python fallback）才能跨平台工作。

如果需要更复杂的 hook 逻辑（比如 Adaptive Complexity 的 LLM triage），bash 就不够了。那时候可以考虑 Node.js——Claude Code 本身就是 Node.js 实现的，hook 用 Node.js 不需要额外的运行时。但目前 8 个脚本的复杂度都在 bash 可以处理的范围内。

### 3.4 Hook 协议兼容性

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

### 4.5 Adaptive Complexity：不是所有任务都值得上全套

一个拼写修复和一个跨模块架构重构——两者需要相同强度的 harness 保障吗？

显然不。但如果 Ralph + Doubt Gate + Tool Error Escalation + Handoff + Post-Edit Diagnostics 全部打开，哪怕一个改 README 里一个错别字的任务也得经过这套流水线。overhead 不值得。

Adaptive Complexity (Pattern 16) 的思路：在任务开始前做一次 triage，根据复杂度自动选择执行模式。

| 等级 | 判断依据 | 启用什么 |
|------|---------|---------|
| Trivial | 单文件、纯文本改动 | 只有原子写入 |
| Low | 单文件、可能需要更新测试 | + 工具错误升级 |
| Medium | 2-5 个文件、跨模块 | + Ralph + Context 估算 |
| High | 5+ 文件、架构变更 | + Handoff + Hook Bracket + Post-Edit 诊断 |
| Critical | 安全修复、数据迁移、生产变更 | + Agent-type 验证门禁 + Scoped Hooks |

当前实现的 triage 是一个 regex，数 prompt 中提到的文件名数量。坦白说，这个启发式很粗糙——"Fix the auth bug"提到 0 个文件但可能涉及 10+ 文件。带连字符的文件名（`my-component.ts`）也匹配不到。

生产建议是用一次 Haiku 调用做 triage——成本 < $0.001，但精度比 regex 高一个量级。

有一条硬规则：**不确定时默认 Standard，NEVER 默认 Express。** Express 跳过验证。如果一个安全修复被误判为 Trivial，agent 会不经验证直接提交。这个误判的成本远高于多跑一次 Ralph 的 overhead。

Adaptive Complexity 和 Hook Runtime Profiles (Pattern 18) 可以组合。Profiles 是环境级控制（`HARNESS_PROFILE=strict`），Adaptive 是任务级控制。`strict` profile 下的 Adaptive 可以进一步微调——strict 不意味着所有任务都跑 Critical 模式，只意味着 Express 被禁用。

### 4.6 Checkpoint + Rollback：在破坏性命令前拍快照

Agent 执行 `rm -rf build/` 或 `git reset --hard`。这些操作不可逆。Claude Code 的内置 checkpoint 只追踪 Write/Edit 工具的文件变更，不覆盖 Bash 命令的副作用。

Pattern 19 的设计：PreToolUse hook 在 Bash 执行破坏性命令前创建 git 快照，PostToolUseFailure hook 在失败后自动回滚。

这里踩了一个很阴险的坑。

最初用 `git stash create --include-untracked` 来捕获包括新建文件在内的所有变更。看起来很合理。跑起来也不报错。但 `git stash create` 根本不支持 `--include-untracked`——这个 flag 只有 `push` 和 `save` 认。`create` 遇到它就静默忽略。意思是 agent 新建了一个文件然后 `rm -rf` 删了，你以为有快照其实没有。

这是一类特别阴险的 bug：工具不报错，exit code 0，你以为成功了。

绕过方式是三步：先 `git add -A`（把 untracked 文件加入 index），再 `git stash create`（现在 index 里有它们了），最后 `git reset HEAD`（恢复 index 到原始状态，不影响工作区）。实测验证：这样创建的 stash ref 确实包含 untracked 文件。

另一个问题是破坏性命令的检测。用 `grep -qE 'rm -rf|git reset --hard|docker rm|kubectl delete'` 匹配。但 `echo "don't run rm -rf /"` 和 `grep "rm -rf" audit.log` 也会命中。在 echo 或 grep 的参数里出现破坏性命令文本会触发不必要的 stash 操作。目前没有好的解法——要精确区分"执行"和"提到"需要解析 shell AST，bash 脚本里做不了。作为 tradeoff，多创建几个 stash 的成本（一次 I/O）比漏掉一个真正的破坏性命令低得多。

还有一个协议问题。PreToolUse hook 不支持 `additionalContext` 输出字段——这是 PostToolUse 和 PostToolUseFailure 才有的。最初想在创建快照后告诉 agent"已创建 checkpoint"，但 PreToolUse 只能用 `permissionDecision`（允许/拒绝/询问）和 `updatedInput`（改写工具输入）。所以 checkpoint 的创建对 agent 是静默的。

### 4.7 Post-Edit Diagnostics：编辑后立即知道出了问题

Agent 改了一个 Python 文件，引入了类型错误。然后它又基于这个有类型错误的文件改了另外两个文件。三个文件后你才从测试失败中发现第一个改动就有问题。

Post-Edit Diagnostics (Pattern 15) 的思路是 shift-left——在编辑发生后立即跑 linter/type checker，秒级反馈，不等到测试阶段。

PostToolUse hook 匹配 `Write|Edit`，根据文件扩展名选择诊断工具：

- `.py` → ruff + pyright
- `.ts/.tsx` → tsc --noEmit
- `.rs` → cargo check
- `.go` → go vet
- `.sh` → shellcheck

有几个实际考量。`tsc --noEmit` 在大项目上可以跑 30 秒以上——它 type-check 整个项目，不只是改了的文件。所以这个 hook 必须配 `async: true`，否则会阻塞 agent 的下一步操作。`cargo check` 同理。shellcheck 和 ruff 是秒级完成的，可以同步跑。

如果诊断工具没安装也没关系——`command -v ruff &>/dev/null` 检查存在性，不存在就跳过。hook 不会因为缺少 linter 而失败。

---

## 4.8 prompt-hardening 与 execution-harness：为什么不合并

两者解决的是不同层面的问题。

prompt-hardening 是概率层——改 prompt 的措辞让 LLM 更可能遵守指令。"把'请运行测试'改成'MUST 运行测试，NEVER 跳过'"。效果显著，但不是 100%。LLM 偶尔还是会忽略 MUST。

execution-harness 是确定层——不依赖 LLM 遵守，用系统机制强制执行。Stop hook 不管 agent 怎么想，`{"decision":"block"}` 就是不让它停。`permissionDecision: "deny"` 就是不让它执行那个命令。

两者的关系像是安全带和安全气囊。安全带（prompt-hardening）减少事故发生的概率。气囊（execution-harness）在事故发生时减少伤害。你不会因为有了气囊就不系安全带。

具体的接入点：

**P5（反推理阻断）→ Ralph block 消息。** 已经实现。Ralph 的 block 消息不只说"继续工作"，还预判 agent 的合理化——"不要合理化说剩下的可以后续处理，不要用'大致完成'来声称完成"。这是 P5 的直接应用。

**P13（代码级强制）= Hook 本身。** 概念等价。prompt-hardening 的 P13 原则是"关键约束必须有代码级强制作为备份"。每一个 hook 脚本就是一个 P13 实现。

**P9（漂移防护）→ Hook Pair Bracket。** 长对话中 agent 逐渐忘记规则（context drift）。P9 建议周期性重新注入关键约束。Hook Pair Bracket 的 UserPromptSubmit hook 就是注入点——每轮开始时注入提醒。

**P1（三重强化）→ Handoff 文档指令。** 让 agent 写 handoff 文档时用 P1 模式：`MUST write a handoff document. The handoff MUST contain all 5 sections. I REPEAT: do NOT skip the handoff document.`

**P4（条件触发）→ Adaptive Complexity。** 不同复杂度的任务触发不同强度的 prompt hardening。Critical 任务用 P1+P5+P9+P13 全套，Trivial 任务不加额外硬化。

---

## 4.9 端到端验证：从 init 到 cancel 的完整链路

42 个 pytest 测试都是单元级的——mock stdin JSON，验证 stdout JSON。它们证明脚本逻辑正确，但不证明脚本在真实 Claude Code session 中正确工作。

所以做了一次端到端验证，模拟完整的 hook 触发链路：

```
Step 1: ralph-init.sh e2e-test 5
  → 创建 sessions/e2e-test/ralph.json (active=true, iteration=0, max=5)

Step 2: Stop hook (正常消息 "I have completed the task.")
  → ralph-stop-hook.sh 输出 {"decision":"block","reason":"[RALPH LOOP 1/5]..."}
  → ralph.json 更新: iteration=1

Step 3: Stop hook (投机消息 "I think this should probably fix the issue.")
  → doubt-gate.sh 输出 {"decision":"block","reason":"...speculative language..."}
  → .doubt-gate-fired 守卫文件创建

Step 4: PostToolUseFailure (cargo build → command not found: cargo)
  → tool-error-tracker.sh 写入 tool-errors.json (count=1, hash=5472be1d...)

Step 5: ralph-cancel.sh e2e-test "test-complete"
  → 创建 sessions/e2e-test/cancel.json (30s TTL)

Step 6: Stop hook (cancel 后)
  → ralph-stop-hook.sh 检测到 cancel 信号 → {"continue":true}
  → ralph.json 更新: active=false, deactivation_reason="cancelled"
```

每一步的输入输出 JSON 都验证了。Ralph block → Doubt Gate block → Tool Error 追踪 → Cancel 放行，完整链路通过。

值得注意的是这个验证发现了一个重要限制：Ralph 仅在 interactive 模式下工作。Headless（`-p`）模式没有 Stop 事件循环——Claude Code 跑完就退出，不触发 Stop hook。Headless 模式用 `--max-turns` 控制执行轮数，不用 Ralph。

---

## 4.10 npx skills 发布

仓库兼容 `npx skills` 安装协议。每个 skill 目录下有 `metadata.json`：

```json
{
  "version": "1.0.0",
  "organization": "Community",
  "date": "April 2026",
  "abstract": "Drop-in Claude Code hook scripts for agent execution reliability...",
  "references": ["https://code.claude.com/docs/en/hooks", ...]
}
```

安装：
```bash
npx skills add github:lanyasheng/execution-harness
```

会列出 3 个 skill（agent-hooks / harness-design-patterns / agent-ops），交互选择要安装哪些。已验证通过。

和 LastWhisperDev 的 [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill) 用同样的 `npx skills add` 安装协议。区别是他的仓库只有设计原则（0 可执行代码），这个有 8 个可执行脚本和 42 个测试。

---

## 5. 工程质量：4 轮 review 和 5 个 P0 bug

### 5.1 四轮 multi-agent review

仓库经过 4 轮不同焦点的 review，每轮启动 3 个独立 agent 分别审查不同 skill。

**第一轮：功能正确性。** pattern 实现对不对、脚本按不按描述工作、测试覆盖够不够。这轮发现了 5 个安全阀只实现了 3 个的问题（P0），以及全部脚本的 JSON 注入漏洞。

**第二轮：协议合规。** hook 的 input/output JSON 是否符合 Claude Code 官方 schema。这轮发现 `tool-error-advisor.sh` 用了 PreToolUse 的废弃 output 格式（`decision: "block"` 应该是 `permissionDecision: "deny"`），以及 `ralph-stop-hook.sh` 读取不存在的 `stop_reason` 字段。

**第三轮：事实准确性。** reference 文档引用的 Claude Code 内部机制是否和源码一致。这轮发现 `context-usage.sh` 依赖的 `context_window` 字段在真实 transcript 中不存在。reviewer 实际检查了真实的 Claude Code transcript JSONL 文件来验证——不是靠文档推理，是靠 `grep` 和 `jq` 验尸。

**第四轮：最终审计。** 文件清单、交叉引用、数字一致性。这轮发现了根目录测试文件和子 skill 测试文件的 import 冲突，以及多处过时的测试数量引用。

4 轮累计 53 个问题，修了 30 个。但有 5 个被我们识别为 reviewer 的错误并拒绝了。这值得展开说。

### 5.1.1 Reviewer 也会犯错

一个 reviewer 声称 `PreCompact` hook 事件不存在于 Claude Code 中，判为 P0。我们去官方文档核实——Claude Code 有 26 个 hook 事件，`PreCompact` 是第 23 个。reviewer 用的是旧版 SDK 的 type definitions，里面确实没有 `PreCompact`，但它是后来加的。

另一个 reviewer 声称 `last_assistant_message` 不是 Stop hook 的输入字段，判为 P0。同样，官方文档明确列出了这个字段。reviewer 参考的是项目里已有的 Stop hook（只读 `stop_reason` 和 `session_id`），没去查官方文档。

第三个 reviewer 声称 `PostToolUseFailure` 事件不存在。这是 26 个事件中的第 6 个。

这说明了 multi-agent review 的一个关键 tradeoff：多个 reviewer 增加覆盖面，但也增加误报。当 reviewer 之间产生矛盾时（一个说存在一个说不存在），需要一个权威来源仲裁。在我们的场景里，权威来源是 Claude Code 官方文档。如果只有一个 reviewer，这些错误判定可能直接被采纳然后删掉了实际正确的代码。

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

前 5 个 commit 在加功能，后 7 个 commit 全在修 bug。这个比例本身就是一个教训——蒸馏知识容易，验证知识的正确性才是工作量的大头。一个 pattern 写出来可能只要 20 分钟，但验证它的 hook 协议是否和官方文档一致、状态文件的并发写入是否安全、日期解析在 macOS 和 Linux 上是否都正确，这些加起来是写的 3-5 倍时间。

### 5.4 improvement-learner 的新增维度

接入 improvement-learner（技能质量评估工具）时发现原有评分维度有盲区，新增了两个：

**leakage** —— 是否泄露不应暴露的内部实现细节（比如 Claude Code 的 source-mapped 变量名）。跨运行时可移植的 pattern 不应该依赖某个版本的内部命名。

**knowledge_density** —— 每百 token 的有效信息密度。防止 SKILL.md 或 reference 文件用套话填充篇幅。这个维度直接影响了 SKILL.md 的写法：能用一句话说清的不用两句。

这两个维度在第一个版本的 execution-harness SKILL.md 上就产生了效果。最初的版本 leakage 评分 0.0（到处是 `~/.openclaw/` 硬编码路径和 `nc-` 会话前缀），knowledge_density 0.4（每个 pattern 只有 3-5 行描述）。重写后 leakage 提升到 1.0，knowledge_density 到 0.96。这两个维度的加入暴露了一类自动评估器之前检测不到的质量问题：内容看起来结构完整（accuracy 1.0），但充斥着项目特定的硬编码引用，且每个 pattern 的深度不够——只说"做什么"不说"为什么"和"tradeoff 是什么"。

---

## 6. 已知局限

**context_window 安全阀无法实现。** Ralph 设计中的第 5 个安全阀，原意是 context >= 95% 时放行 stop，防止溢出崩溃。Claude Code 不在 hook 可访问的数据中暴露 `context_window_size`。只能拿到 `input_tokens` 原始数，不知道总 context window 是 200K 还是 1M。用硬编码阈值（160K tokens）做近似判断不够可靠，所以选择不做，而不是做一个不可靠的版本。

**model fallback 是建议性的。** hook 脚本无法切换 Claude Code 使用的模型。Pattern 21 的"自动模型降级/升级"只能在 `additionalContext` 中注入建议，agent 可能不遵守。确定性的 fallback 方式只有一种：在 subagent 定义中预先指定不同模型。

**doubt gate 有误报。** "这个 bug 可能影响了三个模块"中的"可能"是合理分析，但 doubt gate 只做关键词匹配。one-shot guard 防了无限循环，代价是第二次尝试永远放行。如果要做语义级消歧，需要 prompt-type hook 用 LLM 判断——每次 stop 多一次 API 调用。目前选择不做。

**Claude Code 内部名称可能过时。** `AutoDream`、`DenialTrackingState`、`buildExtractAutoOnlyPrompt` 来自 source-mapped v2.1.88 TypeScript。跨版本可能改名。reference 文档用了这些名字，主 SKILL.md 尽量不依赖。

**21 个 pattern 中 8 个有可执行脚本，13 个是设计参考。** 三种委托模式（Coordinator/Fork/Swarm）、三门控记忆合并、Adaptive Complexity 偏架构设计，不是一个 shell 脚本能覆盖的。

**Headless 模式不适用 Ralph。** `-p` 模式没有 Stop 事件循环。用 `--max-turns` 代替。Claude Code 的设计如此——headless 是单次批处理。

**所有 hook 都有性能开销。** 每个 Stop hook 都是一次 bash 进程启动 + jq 调用。单个 hook < 10ms，但如果配了 5 个 Stop hook，agent 每次尝试停止都有 ~50ms 的延迟。对于高频 stop-block 循环（Ralph + Doubt Gate 同时 block），这个延迟是累积的。目前没有观察到用户可感知的性能问题，但在极端场景（max_iterations=200，每次都被 block）下需要注意。

**Session state 目录需要手动清理。** `sessions/<session-id>/` 目录不会自动删除。跑了 100 个 session 后会有 100 个目录。每个几 KB，不影响磁盘。但如果需要调试某个 session，在 100 个目录里找对的那个不方便。建议定期 `find sessions/ -maxdepth 1 -mtime +7 -exec rm -rf {} \;` 清理 7 天以前的。

**tool-error-tracker 的 hash fallback。** 如果 `md5`、`md5sum`、`shasum` 都不存在（极端精简容器环境），hash 会 fallback 到 `"unknown"`。这意味着所有工具错误的 hash 相同，计数器永远不会重置。在这种环境下 tool error escalation 会过于激进。

---

## 7. 与同类项目的对比

**agentic-harness-patterns-skill。** LastWhisperDev 的原始蒸馏产物，纯知识库，0 可执行代码，6 个跨框架设计原则。execution-harness 在它基础上增加了 15 个 pattern 并将 8 个落地为脚本。抽象层级不同：前者是原则级（"agent 应该管理记忆"），后者是方案级（"用 handoff 文档写 5 段、存在 `sessions/<id>/handoffs/` 下"）。

**oh-my-claudecode (OMC)。** execution-harness 的多个 pattern 源自 OMC，但定位完全不同。OMC 是完整的 CLI wrapper + orchestration layer：npm 全局包，9 种持续执行模式，team runtime，rate limit daemon。execution-harness 只提取了和执行可靠性直接相关的几个机制（Ralph、Cancel TTL、Stale threshold），用 bash + jq 实现。想装全套用 OMC，只想加几个 hook 用 execution-harness。

**everything-claude-code (ECC)。** 38 个 agent、156 个 skill、插件市场。execution-harness 从中取了 Hook Runtime Profiles（环境变量控制 hook 强度）的概念。ECC 做所有事情，execution-harness 只做执行可靠性。

选哪个取决于你想要多重的依赖。

| | execution-harness | agentic-harness-patterns | OMC | ECC |
|---|---|---|---|---|
| 安装方式 | `npx skills add` 或 `git clone` + 改 settings.json | `npx skills add` | `npm i -g` + `/setup` | 插件市场 |
| 可执行代码 | 8 个 bash 脚本，42 个测试 | 0 | 完整 npm 包 | 完整插件包 |
| 运行时依赖 | bash + jq | 无 | Node.js + tmux | Node.js |
| 协议验证 | 对照官方 26 个 hook event 验证 | 不涉及 | 生产验证 | 生产验证 |
| 覆盖面 | 21 个执行可靠性 pattern | 6 个跨框架设计原则 | 9 种执行模式 + team runtime | 38 agent + 156 skill |
| 定位 | 只做执行可靠性 | 只做设计原则 | agent 全生命周期 | 一切 |

有个直觉性的判断方式：如果你的 agent 任务平均跑 5 分钟以内，大概率不需要这些东西。`--max-turns` 就够了。如果你的任务跑 30 分钟以上、涉及多文件修改、在不熟悉的环境中执行，那 Ralph + Doubt Gate + Tool Error Escalation 这三个 hook 能省掉大量的人工干预时间。

---

## 8. 开放问题

一些目前没有答案的问题。

**怎么测试一个 PreCompact hook 是否在正确时机触发？** 42 个测试都是单元级的——mock stdin 输入，验证 stdout 输出。但 Compaction Memory Extraction (Pattern 8) 需要 Claude Code 实际触发 auto-compact 才能验证 PreCompact hook 是否生效。你不能从外部可靠地触发 auto-compact——它取决于 context window 填充速度，而这取决于 agent 的行为。一种思路是故意构造一个会快速填满 context 的任务（比如让 agent 读 50 个大文件），但这更像集成测试而不是 CI 级别的自动化测试。

**怎么区分"合理推测"和"投机逃避"？** Doubt Gate 目前用关键词匹配，"可能"出现就 block。但"这个 bug 可能影响了三个模块"是合理分析，"这个修改可能修好了"是投机逃避。区分两者需要语义理解。一种方向是 prompt-type Stop hook——用 LLM 本身判断。代价是每次 stop 多一次 API 调用。另一种方向是检查上下文——如果 agent 刚跑了测试并且测试通过了，说"可能修好了"是有证据支撑的；如果它没跑任何验证就说"可能"，那就是投机。

**context_window 安全阀。** 设计中预期的第 5 个安全阀。Claude Code 不在 hook 可访问的数据中暴露 `context_window_size`——只通过 statusLine stdin pipe 给 HUD 插件。如果未来 hook 输入增加这个字段，或者通过 HUD plugin 的 IPC 间接获取，安全阀就能实现。在那之前，Claude Code 自身的 reactive compaction 独立处理溢出。不完美，但够用。

**agent 对 Ralph block 消息的适应性。** 一个有意思的观察：连续被 Ralph block 多次后，有些 agent 开始产出更短的回复——好像在"应付检查"而不是真正推进任务。这可能是因为 block 消息的措辞过于命令式，触发了 agent 的"服从模式"而不是"工作模式"。block 消息的措辞设计是一个开放的 prompt engineering 问题。当前用了 P5 反推理阻断，但也许需要根据迭代次数动态调整语气——前几次强硬，后面几次切换为"你做得很好，但检查一下还有没有遗漏"的鼓励式措辞。

**13 个纯设计参考 pattern 需要落地脚本。** 三种委托模式（Coordinator/Fork/Swarm）不是一个 shell 脚本能覆盖的，但 Denial Circuit Breaker、Hook Pair Bracket、Rate Limit Recovery 都可以实现为可执行脚本。难点在验证——怎么测试一个 rate limit recovery 脚本？你需要模拟 tmux pane 中的限速消息。

**doubt gate 和 Ralph 的叠加顺序问题。** 如果 settings.json 中 Ralph 在 Doubt Gate 前面，Ralph 先 block 了 stop，Doubt Gate 就不会触发。如果 Doubt Gate 在前面，它先 block 了投机语言，Ralph 的迭代计数没有递增。顺序影响行为。当前的建议是 Ralph 在前——确保迭代计数始终递增，即使 Doubt Gate 也会 block。但这意味着一次 stop 尝试可能同时消耗一次 Ralph 迭代和一次 Doubt Gate guard。在 max_iterations 较小（比如 5）的场景下，这可能导致 Ralph 比预期更早耗尽迭代次数。

仓库地址：[github.com/lanyasheng/execution-harness](https://github.com/lanyasheng/execution-harness)
