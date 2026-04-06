# 让 Agent 把活干完：从 Claude Code 512K 行源码蒸馏 21 个执行可靠性 Pattern

---

> **TL;DR**
>
> - Agent 提前停止、重试死循环、上下文丢失——瓶颈在 harness，不在模型。Anthropic 和 OpenAI 的博客都在说同一件事。
> - Stop hook 返回 `{"decision":"block"}` 就能强制阻止 agent 停下来。prompt 里写"请继续"靠 LLM 自觉，hook 走系统机制。
> - 工具连续失败 5 次，用 `permissionDecision: "deny"` 硬拦截。`additionalContext` 是建议，LLM 会忽略。
> - Handoff 文档写到磁盘上，context 压缩碰不到它。你控制保留什么，内置压缩处理剩下的。
> - 21 个 pattern 里 8 个有可执行脚本，13 个是设计参考——不是所有问题都值得写 hook。
> - 蒸馏知识容易，验证知识的正确性才是工作量的大头。写一个 pattern 20 分钟，验证 hook 协议、并发写入、跨平台兼容是写的 3-5 倍时间。

---

## 1. 你的 Agent 真的在干活吗

跑过一周就懂。生产环境的 agent 超过一周，下面这些场景你大概率见过：

七个文件的重构。agent 改完前两个，发了一句"剩下的文件结构类似，按同样方式修改即可"，然后 `end_turn`。剩下五个文件原封不动。

容器没装 cargo。`cargo build` 报 `command not found`。第二次同样参数同样报错。第三次还是。一共十二次。每次消耗 token，每次结果相同。你看着日志刷屏的感觉像看一个人往同一面墙上撞了十二次。

改完代码不验证。agent 说"这个修改应该是可以解决问题的，大概不会有副作用"。没跑测试，没看日志，没验证编译。你发现问题已经是两个小时以后的事了。

tmux 里卡住了。agent 遇到 API 限速，需要你手动按回车。你下楼吃了顿饭，回来一看——它等了你整整一小时。

问题不在模型。它知道怎么改代码。问题在 *harness*。

什么是 harness？模型循环（query → tool_use → result → query...）周围的所有基础设施：何时启动、何时停止、出错怎么办、上下文不够了怎么办、多个 agent 怎么协调。模型是引擎，harness 是刹车。引擎马力再大，没有刹车迟早翻车。

两家都在说这事。Anthropic 的 [harness engineering 博客](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) 和 OpenAI 的 [同名博客](https://openai.com/index/harness-engineering/) 讲的是同一件事：模型能力在快速提升，但长任务可靠性的瓶颈不在模型，在 harness。你需要在模型循环之外建一层保障——检测提前停止、恢复 crash 状态、阻止无意义重试、保存关键上下文不被压缩丢掉。

execution-harness 补这层。21 个 pattern，8 个 bash 脚本，42 个测试。往 `settings.json` 里加几行 hook 配置就生效。没有框架，没有 runtime，没有 npm 全局包。

<div style="display:flex;gap:16px;margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px">
<div style="flex:1;border-radius:12px;padding:20px;background:#fef2f2;border:1px solid #fca5a5">
<div style="font-size:12px;font-weight:700;color:#dc2626;letter-spacing:1px;margin-bottom:14px">❌ 没有 Harness</div>
<div style="background:#fff;border:1px solid #fecaca;border-radius:8px;padding:12px;margin-bottom:8px"><b>Agent 改完 2/7 个文件</b><br/><span style="color:#666">"剩下的结构类似"</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓ end_turn</div>
<div style="background:#fff;border:1px solid #fecaca;border-radius:8px;padding:12px;margin-bottom:8px"><b>cargo build × 12</b><br/><span style="color:#666">每次 command not found</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓</div>
<div style="background:#fff;border:1px solid #fecaca;border-radius:8px;padding:12px;margin-bottom:8px"><b>"应该是可以解决的"</b><br/><span style="color:#666">没跑测试、没看日志</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓</div>
<div style="background:#fef2f2;border:1px solid #f87171;border-radius:8px;padding:12px"><b style="color:#dc2626">两小时后才发现问题</b></div>
</div>
<div style="flex:1;border-radius:12px;padding:20px;background:#f0fdf4;border:1px solid #86efac">
<div style="font-size:12px;font-weight:700;color:#16a34a;letter-spacing:1px;margin-bottom:14px">✅ 有 Execution Harness</div>
<div style="background:#fff;border:1px solid #bbf7d0;border-radius:8px;padding:12px;margin-bottom:8px"><b>Agent 尝试在 2/7 处停止</b><br/><span style="color:#666">Stop hook 触发</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓ <span style="font-size:11px">Ralph block</span></div>
<div style="background:#fff;border:1px solid #bbf7d0;border-radius:8px;padding:12px;margin-bottom:8px"><b>被阻止，继续修改</b><br/><span style="color:#666">[RALPH LOOP 1/50]</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓</div>
<div style="background:#fff;border:1px solid #bbf7d0;border-radius:8px;padding:12px;margin-bottom:8px"><b>cargo build 第 5 次</b><br/><span style="color:#666">tool-error-advisor: DENY</span></div>
<div style="text-align:center;color:#999;margin:4px 0">↓ <span style="font-size:11px">强制换方案</span></div>
<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:8px;padding:12px"><b style="color:#16a34a">7/7 文件完成，测试通过</b></div>
</div>
</div>

### 21 个 Pattern 全览

这 21 个 pattern 分三层——执行层（agent-hooks，给开发者）、设计层（harness-design-patterns，给架构师）、运维层（agent-ops，给 SRE）。8 个有可执行的 bash 脚本，13 个是设计参考。后面的章节会挑核心的几个深入讲，这里先列完整清单：

| # | Pattern | 解决什么 | 机制 |
|---|---------|---------|------|
| 1 | **Ralph 持续执行** | Agent 提前停止 | Stop hook 阻止终止，注入续航指令 |
| 2 | **Handoff 文档** | Context 压缩丢信息 | 阶段结束时写 Decided/Rejected/Risks 到磁盘 |
| 3 | **工具错误升级** | 同一工具重试死循环 | PostToolUseFailure 追踪，5 次后强制换方案 |
| 4 | **Rate Limit 恢复** | 限速后 session 挂死 | 扫描 tmux pane 关键词，限速解除后发 Enter 恢复 |
| 5 | **Context 估算** | 不知道 context 用了多少 | 读 transcript 最后 4KB 提取 input_tokens/context_window |
| 6 | **原子文件写入** | 并发读写状态文件损坏 | write-then-rename（POSIX 原子操作） |
| 7 | **Cancel TTL** | 旧取消信号影响新 session | 取消信号带 30s 过期时间 |
| 8 | **Compaction 记忆提取** | 压缩时丢失重要发现 | PreCompact hook 在压缩前写 handoff |
| 9 | **权限否决追踪** | Agent 换表述绕过拒绝 | 追踪否决模式，3 次后降级，5 次后 session 级禁止 |
| 10 | **三门控记忆合并** | 跨 session 记忆碎片化 | Time/Session/Lock 三道门控后批量合并 |
| 11 | **Hook Pair Bracket** | 不知道每轮消耗多少 | UserPromptSubmit + Stop 配对测量 |
| 12 | **Component-Scoped Hooks** | 全局 hooks 太粗粒度 | 在 SKILL.md frontmatter 中声明局部 hooks |
| 13 | **Doubt Gate** | Agent 以投机语言"完成"任务 | Stop hook 扫描 hedging 词，强制提供证据 |
| 14 | **三种委托模式** | 多 agent 协调方式选错 | Coordinator/Fork/Swarm 选型指南 |
| 15 | **Post-Edit Diagnostics** | 编辑引入错误后才发现 | PostToolUse hook 即时跑 linter/type checker |
| 16 | **Adaptive Complexity** | 简单任务 overhead 太高 | Triage 评估复杂度，自动选执行模式 |
| 17 | **Stale Session Daemon** | Session 静默死亡丢失知识 | Heartbeat + 死 session 知识回收 |
| 18 | **Hook Runtime Profiles** | 不同场景需要不同 hook 强度 | 环境变量控制 minimal/standard/strict |
| 19 | **Checkpoint + Rollback** | Bash 破坏性操作不可逆 | PreToolUse git stash + PostToolUseFailure 自动回滚 |
| 20 | **Token Budget Per Subtask** | Context 前半段用完后半段不够 | UserPromptSubmit hook 注入预算感知指令 |
| 21 | **Auto Model Fallback** | 模型反复失败无切换机制 | 3 次连续失败后自动升级 Haiku→Sonnet→Opus |

### 常见场景选型

不需要每次都上全套。按场景选组合：

| 场景 | 推荐组合 |
|------|---------|
| 多文件 bugfix，怕 agent 半途停 | Ralph + Context 估算（做安全阀） |
| 多阶段任务（plan → implement → verify） | Handoff 文档 + Compaction 提取 |
| Agent 在陌生环境跑（依赖可能缺失） | 工具错误升级 + 权限否决追踪 |
| 批量 dispatch 多个 agent 到 tmux | Rate Limit 恢复 + Hook Pair Bracket（监控） |
| 高价值任务（安全修复、生产热修） | Ralph（Agent-type 验证）+ Scoped Hooks + Doubt Gate |
| 多 agent 并行开发 | 三种委托模式选型 + Handoff + Hook Bracket |
| 快速实验，最小 overhead | Hook Profile = minimal + Adaptive Complexity = trivial |
| Session 可能长时间运行或 crash | Stale Session Daemon + Ralph（crash recovery） |

---

## 2. 蒸馏方法论：PCA 降维与品味注入

规模先讲清楚。512K 行 TypeScript——一个 agent 在单个 session 里读不完。这件事本身就是个 harness engineering 问题。

### 2.1 PCA 类比：注入基向量

先说个类比：

> 代码是高维的，但有价值的设计模式是低秩的。蒸馏的本质是找到主成分。

但我发现一个问题。"客观地"提取所有模式反而最没用。没有视角就没有优先级。最初几轮产出的东西面面俱到地列出 Claude Code 有哪些子系统，但不说该用什么、为什么。很无聊，也没法落地。

解法是注入 *基向量*：

1. 把 Anthropic 的 harness engineering 博客、OpenAI 的 Context Engineering 四轴框架（select / write / compress / isolate）、"Do the simple thing that works" 的设计偏好作为投影方向。
2. 让 agent 沿这些方向从代码中提取主成分。不是什么都提取。
3. 诚实标注视角。execution-harness 不是 Claude Code 的客观映射，是经过"执行可靠性"这个视角过滤后的结果。

我觉得第三条最重要。承认偏见比假装客观有用。

### 2.2 Review-Execution 分离

核心设计一句话：*不让实现者审查自己的代码*。

用不同模型分别做 review 和 execution。Review agent 以全新视角对照源码查事实、判断抽象层级是否正确。Execution agent 读源码、写文档、协调子 agent 并行工作。两个 agent 互不可见对方的 session。

每轮在新 session 中做。这一点很关键——如果在同一个 session 里连续做多轮 review + 修改，agent 的 context 会被前几轮的讨论填满，后面的 review 质量下降。新 session 拿到完整 token 预算，不被前几轮上下文污染。唯一协调媒介是磁盘上的 handoff 文档。

这个设计本身就是 Handoff 文档 (Pattern 2) 的实践。每一轮 review 的输出是一份结构化的审查报告（severity 分级、源码引用、修复建议），每一轮 execution 的输出是一份 handoff（做了什么、改了哪些文件、遗留什么问题）。新 session 的 agent 启动后第一件事是读最新的 handoff，然后继续工作。不需要看之前的对话历史。

换个角度看。这是 Coordinator 模式（Pattern 14）的人工版本：人做 coordinator，两个 agent 做 specialized worker。Anthropic 在 [Building multi-agent systems](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them) 中提到过同一个原则——verification subagent 应该专职，和主 agent 分开。

### 2.3 蒸馏过程本身踩的坑

挺讽刺的——蒸馏过程踩的坑，恰好是蒸馏结果想要解决的那些。

读源码的 agent 经常在读完 3-4 个文件后就说"已经理解了整体架构"然后停下来。51.2 万行代码读 4 个文件就理解了？这让我意外——不是因为 agent 能力不够，是因为它太"自信"了。这就是 Pattern 1（Ralph）的场景。

并行踩坑更烦。多个 agent 同时写不同的 reference 文档时，偶尔两个 agent 对同一个概念给出了不同的描述。一个说 MicroCompact 移除 8 种工具类型的结果，另一个说 6 种。到底几种？这需要 Pattern 14（三种委托模式）里 Coordinator 的"synthesis 不能委派"原则——coordinator（人）需要自己核实哪个是对的，而不是把两个矛盾的说法都保留。

context 压缩也出事了。跑了 4 轮 review 后，context 被压缩好几次。之前某一轮 review 指出的"Pattern 9 的阈值数字来源不明"在压缩后丢失了，后面的 agent 又写上了同样的未验证数字。这就是 Pattern 2（Handoff）和 Pattern 8（Compaction 提取）想要解决的问题。

回头看这段经历。如果蒸馏过程再做一次，我会从一开始就用 execution-harness 自己的 pattern 来保障蒸馏过程——用 Ralph 防止 agent 读几个文件就停下来，用 Handoff 保存每轮 review 的发现，用 Doubt Gate 阻止 agent 用"大概是这样"来交差。

### 2.4 来源归因

12+ 个来源。每个贡献不同：

<div style="margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:12px;max-width:650px">
<div style="text-align:center;margin-bottom:12px">
<div style="display:inline-flex;flex-wrap:wrap;gap:6px;justify-content:center">
<span style="background:#dbeafe;border:1px solid #93c5fd;border-radius:8px;padding:4px 10px">Claude Code 源码</span>
<span style="background:#dcfce7;border:1px solid #86efac;border-radius:8px;padding:4px 10px">OMC</span>
<span style="background:#fef9c3;border:1px solid #fde68a;border-radius:8px;padding:4px 10px">ccunpacked</span>
<span style="background:#fce7f3;border:1px solid #f9a8d4;border-radius:8px;padding:4px 10px">claude-howto</span>
<span style="background:#e0e7ff;border:1px solid #a5b4fc;border-radius:8px;padding:4px 10px">官方文档</span>
<span style="background:#f3e8ff;border:1px solid #c4b5fd;border-radius:8px;padding:4px 10px">GitHub 社区 × 6</span>
<span style="background:#fff7ed;border:1px solid #fdba74;border-radius:8px;padding:4px 10px">Anthropic/OpenAI 博客</span>
</div>
</div>
<div style="text-align:center;color:#999;margin:4px 0">↓ 40+ 候选 pattern</div>
<div style="text-align:center;margin:8px 0">
<span style="background:#f3f4f6;border:1px solid #d1d5db;border-radius:8px;padding:6px 16px">去重 + 优先级排序 + 可实现性筛选</span>
</div>
<div style="text-align:center;color:#999;margin:4px 0">↓</div>
<div style="text-align:center">
<span style="background:#eff6ff;border:2px solid #3b82f6;border-radius:8px;padding:8px 20px;font-weight:700;color:#1d4ed8">21 个 pattern → 3 个 skill</span>
</div>
</div>

| 来源 | 贡献了什么 |
|------|-----------|
| Claude Code v2.1.88 源码（蒸馏基线版本，当前最新 v2.1.92+） | Query Engine loop、Permission Pipeline、Context Management、Session Persistence。约一半 pattern 的内部实现参考 |
| oh-my-claudecode (OMC) | Ralph 持续执行模式（名字来自 OMC）、Cancel TTL 30 秒、Stale threshold 2 小时、状态文件读取的 4 级 fallback |
| ccunpacked.dev | DenialTrackingState 的逆向、AutoDream 记忆合并、MCP auto-healing |
| claude-howto | Prompt-type / Agent-type hook 的区分、Hook pair bracket、Component-scoped hooks 的 `once: true` |
| Claude Code 官方文档 | 27 个 hook 事件的 JSON schema、permission 协议。验证所有 hook 实现的基准 |
| 社区技术文章 | 蒸馏方法论——PCA 类比、Review-Execution 分离、品味注入 |
| plugin-doubt-gate | Speculation detection 通过 hedging word scan |
| Continuous-Claude-v3 | Post-edit diagnostics、stale session daemon、heartbeat 机制 |
| everything-claude-code (ECC) | Hook runtime profiles、instinct evolution 概念 |
| sdd-autopilot | 8 阶段 pipeline 复杂度分级 → Adaptive complexity scoring |
| Anthropic / OpenAI 博客 | Harness engineering 设计原则、filesystem-as-context |

不是一开始就有 12 个来源。最初只有 4 个（Claude Code 源码、OMC、ccunpacked、claude-howto）。分析完这 4 个后只提取出 12 个 pattern——感觉不够。然后并行启动 3 路搜索 agent，分别在 GitHub 仓库、ClaWHub 生态、和 agent reliability 研究方向搜索。搜回来的候选里，`plugin-doubt-gate` 贡献了投机检测（我们之前完全没有这个维度），`sdd-autopilot` 贡献了复杂度自适应（我们之前对所有任务一视同仁），`Continuous-Claude-v3` 贡献了编辑后即时诊断和 heartbeat 机制。

也有不采纳的。40+ 个候选经过去重和优先级排序后保留了 21 个。淘汰标准两个：一，和已有 pattern 语义重叠（比如"file-based working memory"和我们的 handoff 文档本质相同，只是命名不同）；二，在 hook 脚本中做不了（比如"render cache stability with WeakMap"是 Node.js 应用层模式，bash 搞不定）。

---

## 3. 架构设计：三个 Skill，三类读者

### 3.1 拆分原因

先说失败经历。最初版本是 12 个 pattern 全塞一个 SKILL.md。问题立刻暴露：需要 hook 脚本的开发者被迫读完 10 页设计原则才能找到配置方法；做架构设计的人不需要知道 `ralph-stop-hook.sh` 里怎么 parse JSON；SRE 只想知道怎么检测限速和恢复死 session。

所以拆了：

```
execution-harness/
├── skills/
│   ├── agent-hooks/               ← 开发者：装 hook，配 settings.json，走人
│   ├── harness-design-patterns/   ← 架构师：设计多 agent 系统时的参考
│   └── agent-ops/                 ← SRE：监控、恢复、保护运行中的 agent
└── shared/                        ← Session state layout（三者共用）
```

还有一个容易被问到的事：reference 文件名保留原始编号（01/03/07/13/15...），不连续。monorepo 拆分的历史痕迹，也方便跨 skill 引用不产生歧义。

<div style="display:flex;gap:12px;margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px">
<div style="flex:1;border-radius:12px;padding:16px;background:#eff6ff;border:1px solid #93c5fd">
<div style="font-size:12px;font-weight:700;color:#1d4ed8;letter-spacing:1px;margin-bottom:10px">🔧 agent-hooks</div>
<div style="font-size:12px;color:#666;margin-bottom:8px">给<b>开发者</b>——装 hook，配 settings.json</div>
<div style="display:flex;flex-wrap:wrap;gap:4px">
<span style="background:#dbeafe;border-radius:6px;padding:2px 8px;font-size:11px">ralph-stop-hook</span>
<span style="background:#dbeafe;border-radius:6px;padding:2px 8px;font-size:11px">doubt-gate</span>
<span style="background:#dbeafe;border-radius:6px;padding:2px 8px;font-size:11px">tool-error-tracker</span>
<span style="background:#dbeafe;border-radius:6px;padding:2px 8px;font-size:11px">post-edit-check</span>
</div>
<div style="margin-top:8px;font-size:11px;color:#1d4ed8">8 scripts · 42 tests</div>
</div>
<div style="flex:1;border-radius:12px;padding:16px;background:#f0fdf4;border:1px solid #86efac">
<div style="font-size:12px;font-weight:700;color:#16a34a;letter-spacing:1px;margin-bottom:10px">📐 harness-design-patterns</div>
<div style="font-size:12px;color:#666;margin-bottom:8px">给<b>架构师</b>——设计参考，无可执行代码</div>
<div style="display:flex;flex-wrap:wrap;gap:4px">
<span style="background:#dcfce7;border-radius:6px;padding:2px 8px;font-size:11px">handoff</span>
<span style="background:#dcfce7;border-radius:6px;padding:2px 8px;font-size:11px">delegation</span>
<span style="background:#dcfce7;border-radius:6px;padding:2px 8px;font-size:11px">adaptive</span>
<span style="background:#dcfce7;border-radius:6px;padding:2px 8px;font-size:11px">hook-profiles</span>
</div>
<div style="margin-top:8px;font-size:11px;color:#16a34a">10 patterns · 12 references</div>
</div>
<div style="flex:1;border-radius:12px;padding:16px;background:#fefce8;border:1px solid #fde68a">
<div style="font-size:12px;font-weight:700;color:#a16207;letter-spacing:1px;margin-bottom:10px">📡 agent-ops</div>
<div style="font-size:12px;color:#666;margin-bottom:8px">给 <b>SRE</b>——监控、恢复、保护</div>
<div style="display:flex;flex-wrap:wrap;gap:4px">
<span style="background:#fef9c3;border-radius:6px;padding:2px 8px;font-size:11px">rate-limit</span>
<span style="background:#fef9c3;border-radius:6px;padding:2px 8px;font-size:11px">checkpoint</span>
<span style="background:#fef9c3;border-radius:6px;padding:2px 8px;font-size:11px">token-budget</span>
<span style="background:#fef9c3;border-radius:6px;padding:2px 8px;font-size:11px">model-fallback</span>
</div>
<div style="margin-top:8px;font-size:11px;color:#a16207">1 script · 5 tests · 5 design refs</div>
</div>
</div>

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

一个目录就是一个 session。清理靠 `rm -rf`。没有散落在不同路径的碎片。

跨 session 读取？不做。OMC 有 4 级 fallback 去扫描其他 session 的状态文件，我们选择严格 session-scoped，不做 fallback。理由很简单：跨 session 状态泄漏是一类很难调试的 bug，不值得为向后兼容冒这个险。

crash 恢复靠目录检查。`ralph-init.sh` 初始化时先看有没有残留 `ralph.json`。发现 `active: true` 或 `deactivation_reason: "stale"`，不重置迭代计数器，从上次位置恢复。这解决了"agent 在第 37 轮 crash 后重启从 0 开始"的问题。我可能过于谨慎了，但丢失 37 轮的进度比多写几行检查代码痛苦得多。

### 3.3 bash + jq 的取舍

三个理由。

第一，快。Stop hook 在 agent 每次尝试停止时触发。如果脚本需要 100ms 的 Node.js 启动开销或 200ms 的 Python import 开销，agent 在高频 stop-block-continue 循环中会明显变慢。bash + jq 是 sub-10ms。

第二，零依赖。`bash` 和 `jq` 在任何开发者的 macOS/Linux 机器上都有。不需要 `npm install`，不需要 `pip install`，不需要管虚拟环境。复制脚本到任何路径，改一下 settings.json 里的路径，就能工作。

第三，好审计。每个脚本不超过 100 行。一个中级工程师花 5 分钟能读完一个脚本并理解它做了什么。如果用 TypeScript 实现同样的逻辑，加上类型定义、import、错误处理、package.json，代码量至少翻 3 倍。

代价也有。bash 的 JSON 处理能力依赖 `jq`——没有 `jq` 就什么都做不了。错误处理比较粗糙——`set -euo pipefail` 是个好开始，但 bash 的错误传播远不如 try/catch 精确。日期解析需要三层 fallback（macOS `date -j` → GNU `date -d` → Python fallback）才能跨平台工作。这三层 fallback 写起来挺丑的。

bash 有天花板。如果需要更复杂的 hook 逻辑（比如 Adaptive Complexity 的 LLM triage），bash 就不够了。那时候可以考虑 Node.js——Claude Code 本身就是 Node.js 实现的，hook 用 Node.js 不需要额外的运行时。但目前 8 个脚本的复杂度都在 bash 能处理的范围内。

### 3.4 Hook 协议兼容性

对照官方文档验证。所有脚本对照 Claude Code 官方文档验证过 27 个 hook event。我们用了 5 种：

| Hook Event | 用途 | 脚本 |
|------------|------|------|
| Stop | 阻止提前停止 / 检测投机语言 | `ralph-stop-hook.sh`, `doubt-gate.sh` |
| PostToolUseFailure | 追踪工具连续失败 | `tool-error-tracker.sh` |
| PreToolUse | 阻止已失败 5 次的工具重试 | `tool-error-advisor.sh` |
| PostToolUse | 编辑后即时诊断 | `post-edit-check.sh` |
| （CLI 调用） | 初始化 / 取消 | `ralph-init.sh`, `ralph-cancel.sh` |

协议很统一。输入输出遵循同一规范——stdin 接 JSON（含 `session_id`, `tool_name`, `tool_input` 等），stdout 输出 JSON 决策：

```json
{"continue": true}                                    // 放行
{"decision": "block", "reason": "..."}                 // 阻止
{"hookSpecificOutput": {"additionalContext": "..."}}   // 注入上下文
```

### 3.5 安装

兼容 `npx skills` 安装协议。每个 skill 目录下有 `metadata.json`：

```json
{
  "version": "1.0.0",
  "organization": "Community",
  "date": "April 2026",
  "abstract": "Drop-in Claude Code hook scripts for agent execution reliability...",
  "references": ["https://code.claude.com/docs/en/hooks", ...]
}
```

安装一行搞定：
```bash
npx skills add github:lanyasheng/execution-harness
```

会列出 3 个 skill（agent-hooks / harness-design-patterns / agent-ops），交互选择要装哪些。

和 [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill) 用同一套 `npx skills add` 协议。区别在于那个仓库只有设计原则（0 可执行代码），这个有 8 个可执行脚本和 42 个测试。

---

## 4. 核心 Pattern 深度解析

### 4.1 Ralph 持续执行

开头第 1 节的场景——7 个文件改了 2 个就停——Ralph 就是为这件事做的。名字来自 OMC 的 `persistent-mode.mjs`，是九种持续执行模式里优先级最高的一个。逻辑不复杂：agent 每次尝试停止，Stop hook 触发，去读 `sessions/<id>/ralph.json`——如果 `active=true` 且迭代次数没超限，就 block 掉这次 stop，迭代计数加一。

<div style="margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;max-width:500px">
<div style="background:#eff6ff;border:1px solid #93c5fd;border-radius:8px;padding:12px;text-align:center"><b>Agent 尝试停止</b></div>
<div style="text-align:center;color:#999;margin:4px 0">↓ <span style="font-size:11px">Stop hook 触发</span></div>
<div style="background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:12px;text-align:center">读取 <code>sessions/&lt;id&gt;/ralph.json</code></div>
<div style="text-align:center;color:#999;margin:4px 0">↓</div>
<div style="display:flex;gap:8px">
<div style="flex:1;text-align:center">
<div style="background:#fef2f2;border:1px solid #fca5a5;border-radius:8px;padding:10px"><b style="color:#dc2626">active=false<br/>或 iteration ≥ max</b><br/><span style="font-size:11px;color:#666">→ 放行 stop</span></div>
</div>
<div style="flex:1;text-align:center">
<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:8px;padding:10px"><b style="color:#16a34a">active=true<br/>且 iteration &lt; max</b><br/><span style="font-size:11px;color:#666">→ block + iteration++</span></div>
</div>
</div>
<div style="text-align:center;margin-top:8px">
<div style="display:inline-flex;gap:6px;flex-wrap:wrap;justify-content:center">
<span style="background:#fef2f2;border:1px solid #fca5a5;border-radius:10px;padding:2px 8px;font-size:11px">🛑 401/403</span>
<span style="background:#fef2f2;border:1px solid #fca5a5;border-radius:10px;padding:2px 8px;font-size:11px">🛑 cancel 信号</span>
<span style="background:#fef2f2;border:1px solid #fca5a5;border-radius:10px;padding:2px 8px;font-size:11px">🛑 2h 闲置</span>
<span style="background:#fef2f2;border:1px solid #fca5a5;border-radius:10px;padding:2px 8px;font-size:11px">🛑 max 迭代</span>
</div>
<div style="font-size:11px;color:#999;margin-top:4px">4 个安全阀：命中任一 → 无条件放行</div>
</div>
</div>

光说"继续"没用。试过。agent 会合理化——"剩下的工作可以在后续 session 中完成"，然后带着这句话心安理得地停下来。所以 block 消息得预判它的逃逸路径：

```
[RALPH LOOP 5/50] Task is NOT done.
Do NOT rationalize that "the remaining work can be done in a follow-up."
Do NOT claim completion with caveats.
Check your original task description and verify EVERY requirement is met.
Continue working on the original task.
```

这条消息借鉴了 prompt-hardening 的反推理阻断原则——不只告诉 agent 继续，还堵住它最常走的几条退路。

**4 个安全阀。** 不管 ralph 状态如何，碰到这四种情况直接放行：

- **认证失败（401/403）**——token 过期了，继续执行白费 token。
- **Cancel 信号**——带 30 秒 TTL 的取消文件，过期自动忽略。OMC 选 30 秒是因为刚好覆盖 Stop hook 的检查周期（通常 1-5 秒内触发），又不会长到影响下一个 session。
- **闲置超过 2 小时**——防止 zombie 状态占着资源不放。阈值来自 OMC 的 `STALE_STATE_THRESHOLD_MS = 7200000`。
- **达到 max_iterations**——防止死循环，默认 50 轮。

少了一个。设计里本来还有第 5 个安全阀：context_window >= 95%。做不了——Claude Code 的 transcript JSONL 不包含 `context_window_size` 字段，这个数据只通过 statusLine stdin pipe 给 HUD 插件，hook 脚本拿不到。Claude Code 自身的 reactive compaction 会独立处理 context 溢出，实际用下来没出过问题，但总觉得差点意思。后面"已知局限"那节会具体说。

**crash 了怎么办？** `ralph-init.sh` 初始化时先检查有没有残留状态文件。发现 `active: true`，说明上次 session 非正常退出。处理方式是不重置 `iteration`，从上次的值接着来。测试代码做了端到端验证：初始化 → 手动把 iteration 改到 5（模拟 crash）→ 再次初始化 → 确认 iteration 保持 5 且输出包含 "Resuming"。

一个限制。Ralph 只在 interactive 模式下工作。Headless（`-p`）没有 Stop 事件循环，用 `--max-turns` 代替。

### 4.2 Doubt Gate：投机语言检测

Ralph 看迭代数。Doubt Gate 看内容。两者正交。

Stop hook 触发时，先 strip 代码块和引用块——否则 `// I think this might need review` 这种注释会误触发——然后扫描剩余文本中的投机性关键词：

英文：`likely`, `maybe`, `might`, `probably`, `not sure`, `I think`, `I believe`, `should be`, `could be`, `possibly`
中文：`可能`, `大概`, `也许`, `应该是`, `我认为`, `我猜`, `不太确定`, `估计是`

命中就 block。要求 agent 拿出证据——跑测试、看日志、读文件验证。

有个陷阱。如果 agent 天生爱说"可能"呢？它被 block 后重新回答，还是说"可能"，再被 block，没完没了。所以引入了 one-shot guard：第一次触发时写一个 `.doubt-gate-fired` 标志文件，第二次 stop 时看到这个文件就无条件放行，然后删文件。

代价清楚得很：第二次尝试即使还在投机也会放行。但没有这个 guard，agent 可能永远停不下来。两害相权，我选了能停。

误报是明摆着的。"这个 bug 可能影响了三个模块"里的"可能"是合理分析，不是投机。Doubt Gate 做关键词匹配，没有语义消歧。我不确定这个 tradeoff 长期来看是不是最优的，但现阶段没有更好的方案不引入额外 API 调用。

### 4.3 Tool Error Escalation：连续 5 次失败，强制换路

真事。`cargo build` 在没装 cargo 的容器里跑了 5 次。每次输入相同，每次 `command not found: cargo`。

两个脚本配合。PostToolUseFailure hook (`tool-error-tracker.sh`) 负责追踪，PreToolUse hook (`tool-error-advisor.sh`) 负责干预。

| 连续失败次数 | 行为 |
|-------------|------|
| 1-2 | 只记录，不干预 |
| 3-4 | 注入软提示："已失败 3 次，考虑换参数/路径/依赖？" |
| 5+ | 注入强制切换："MUST use an alternative approach" |

关键细节。`input_hash` 必须是确定性的。做法是用 `jq -Sc` 对 tool_input 做 compact sorted JSON，取前 200 字符做 md5。这区分了"同一个命令反复失败"和"不同命令分别失败"。agent 换了参数重试——哪怕换一个字符——hash 变化，计数器重置。只有完全相同的输入连续失败才升级。P0-4 bug 就栽在这里——最初没排序 JSON key，`{"a":1,"b":2}` 和 `{"b":2,"a":1}` 算出不同 hash。

第 5 次失败后怎样？`tool-error-advisor.sh` 在 PreToolUse 阶段返回 `permissionDecision: "deny"`，直接阻止执行。这和 `additionalContext`（建议性，LLM 可以无视）不一样，`permissionDecision` 是硬的，没有商量余地。

### 4.4 Handoff 文档：你控制保留什么

Claude Code 有 4 级压缩（MicroCompact → Session Memory → Full Compact → Reactive Compact）。长任务中自动触发。压缩后，关键的设计决策、排除过的方案、已识别的风险——丢了。

为什么靠不住？两个原因。

第一个。摘要内容由 LLM 决定，你控制不了保留什么。"排除 Memcached 的原因"在 LLM 眼里可能不重要，顺手就丢了。三天后你需要回顾这个决策，信息已经不在了。

第二个。Full Compact 用 `<analysis>` scratchpad 提高摘要质量，但 scratchpad 内容 strip 后不进入压缩后的 context。推理过程没了。

Handoff 文档的做法很直接：阶段结束时把关键信息写入磁盘文件。5 个段落——Decided / Rejected / Risks / Files Modified / Remaining。压缩后的 agent 读磁盘恢复上下文。文件在磁盘上，任何级别的 context 压缩都碰不到它。

和内置压缩互补。你选要保留什么，内置压缩处理剩下的。

还有配套。Compaction Memory Extraction (Pattern 8) 在 PreCompact hook 中注入 prompt，让 agent 在压缩发生前把当前未保存的发现写入 handoff。Handoff 是计划内的上下文传递，compaction extraction 是被动抢救——压缩要来了，赶紧把没存的东西先存一下。

### 4.5 Adaptive Complexity：按任务复杂度选 harness 强度

一个拼写修复和一个跨模块重构，需要同等强度的保障吗？

当然不。但 Ralph + Doubt Gate + Tool Error Escalation + Handoff + Post-Edit Diagnostics 全开的话，改 README 里一个错别字也得过这套流水线。不值得。

Adaptive Complexity (Pattern 16) 的想法：任务开始前做一次 triage，按复杂度选执行模式。

| 等级 | 判断依据 | 启用什么 |
|------|---------|---------| 
| Trivial | 单文件、纯文本改动 | 只有原子写入 |
| Low | 单文件、可能需要更新测试 | + 工具错误升级 |
| Medium | 2-5 个文件、跨模块 | + Ralph + Context 估算 |
| High | 5+ 文件、架构变更 | + Handoff + Hook Bracket + Post-Edit 诊断 |
| Critical | 安全修复、数据迁移、生产变更 | + Agent-type 验证门禁 + Scoped Hooks |

说实话吧。当前的 triage 实现是一个 regex，数 prompt 中提到的文件名数量。很粗糙——"Fix the auth bug"提到 0 个文件但可能涉及 10+ 文件，带连字符的文件名（`my-component.ts`）匹配不到。

更好的做法是用一次 Haiku 调用做 triage。成本 < $0.001，精度比 regex 高一个量级。

有一条硬规则。**不确定时默认 Standard，永远不默认 Express。** Express 跳过验证。如果一个安全修复被误判为 Trivial，agent 会不经验证直接提交。这种误判的成本远高于多跑一次 Ralph。

Adaptive Complexity 和 Hook Runtime Profiles (Pattern 18) 可以叠加。Profiles 是环境级控制（`HARNESS_PROFILE=strict`），Adaptive 是任务级控制。`strict` profile 下的 Adaptive 可以进一步微调——strict 不是说所有任务都跑 Critical 模式，只是 Express 被禁了。

### 4.6 Checkpoint + Rollback：破坏性命令前拍快照

agent 执行 `rm -rf build/` 或 `git reset --hard`。不可逆。Claude Code 内置 checkpoint 只追踪 Write/Edit 工具的文件变更，Bash 命令的副作用不在覆盖范围内。

Pattern 19 的做法：PreToolUse hook 在 Bash 执行破坏性命令前创建 git 快照，PostToolUseFailure hook 在失败后自动回滚。

踩了个坑。说实话挺阴的。

最初用 `git stash create --include-untracked` 捕获包括新建文件在内的所有变更。看起来合理，跑起来也不报错。但 `git stash create` 根本不认 `--include-untracked`——这个 flag 只有 `push` 和 `save` 支持。`create` 遇到它直接无视。结果是：agent 新建了一个文件然后 `rm -rf` 删了，你以为有快照，其实没有。

工具不报错，exit code 0，你以为成功了。这类 bug 最难发现。

绕过方式三步走：先 `git add -A`（把 untracked 文件加入 index），再 `git stash create`（现在 index 里有它们了），最后 `git reset HEAD`（恢复 index，不影响工作区）。实测下来，这样创建的 stash ref 确实包含 untracked 文件。

还有个问题。破坏性命令怎么检测？用 `grep -qE 'rm -rf|git reset --hard|docker rm|kubectl delete'` 匹配。但 `echo "don't run rm -rf /"` 和 `grep "rm -rf" audit.log` 也会命中——在 echo 或 grep 的参数里提到破坏性命令文本就会触发不必要的 stash。精确区分"执行"和"提到"需要解析 shell AST，bash 脚本里做不了。作为 tradeoff，多创建几个 stash 的成本（一次 I/O）比漏掉一个真正的破坏性命令低很多。我能接受。

实现细节。PreToolUse hook 支持 `additionalContext`，但我们最终选择不在 checkpoint 创建后通知 agent——通知只会让 agent 多一次决策（"要不要回滚？"），而自动回滚应该是无感的。所以 checkpoint 的创建对 agent 是静默的。

### 4.7 Post-Edit Diagnostics：编辑后即时检查

举个例子。agent 改了一个 Python 文件，引入了类型错误。然后基于这个有错的文件又改了两个。三个文件改完，你才从测试失败里发现第一个改动就有问题。错误在第一秒就存在了，你花了二十分钟才知道。

Post-Edit Diagnostics (Pattern 15) 的思路是 shift-left——编辑发生后立刻跑 linter/type checker，秒级反馈，不等到测试阶段。

PostToolUse hook 匹配 `Write|Edit`，按文件扩展名选诊断工具：

- `.py` → ruff + pyright
- `.ts/.tsx` → tsc --noEmit
- `.rs` → cargo check
- `.go` → go vet
- `.sh` → shellcheck

实际跑起来有讲究。`tsc --noEmit` 在大项目上能跑 30 秒以上——它 type-check 整个项目，不只改了的文件。所以这个 hook 必须配 `async: true`，否则阻塞 agent 的下一步。`cargo check` 同理。shellcheck 和 ruff 秒级完成，同步跑没问题。

诊断工具没装也没事。`command -v ruff &>/dev/null` 检查存在性，不存在就跳过。hook 不会因为缺 linter 而失败。

---

### 4.8 prompt-hardening 与 execution-harness 的关系

层次不同。

prompt-hardening 是概率层——改 prompt 措辞让 LLM 更可能遵守指令。"把'请运行测试'改成'MUST 运行测试，NEVER 跳过'"。效果明显，但不是 100%。LLM 偶尔还是会无视 MUST。

execution-harness 是确定层——不靠 LLM 配合，用系统机制强制执行。Stop hook 不管 agent 怎么想，`{"decision":"block"}` 就是不让停。`permissionDecision: "deny"` 就是不让跑那个命令。

<div style="margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;max-width:600px">
<div style="background:#fefce8;border:1px solid #fde68a;border-radius:12px;padding:16px;margin-bottom:8px">
<div style="font-size:12px;font-weight:700;color:#a16207;margin-bottom:8px">Layer 1: prompt-hardening（概率层）</div>
<div style="display:flex;gap:6px;flex-wrap:wrap">
<span style="background:#fef9c3;border-radius:6px;padding:3px 8px;font-size:11px">P1 三重强化</span>
<span style="background:#fef9c3;border-radius:6px;padding:3px 8px;font-size:11px">P5 反推理阻断</span>
<span style="background:#fef9c3;border-radius:6px;padding:3px 8px;font-size:11px">P9 漂移防护</span>
<span style="background:#fef9c3;border-radius:6px;padding:3px 8px;font-size:11px">P13 代码级强制</span>
</div>
<div style="font-size:11px;color:#92400e;margin-top:6px">改 prompt 措辞让 LLM <b>更可能</b>遵守 → 但不是 100%</div>
</div>
<div style="text-align:center;color:#999;font-size:11px;margin:4px 0">↓ LLM 仍可能不遵守</div>
<div style="background:#eff6ff;border:1px solid #93c5fd;border-radius:12px;padding:16px">
<div style="font-size:12px;font-weight:700;color:#1d4ed8;margin-bottom:8px">Layer 2: execution-harness（确定层）</div>
<div style="display:flex;gap:6px;flex-wrap:wrap">
<span style="background:#dbeafe;border-radius:6px;padding:3px 8px;font-size:11px">Ralph Stop hook</span>
<span style="background:#dbeafe;border-radius:6px;padding:3px 8px;font-size:11px">Doubt Gate</span>
<span style="background:#dbeafe;border-radius:6px;padding:3px 8px;font-size:11px">Tool Error Deny</span>
<span style="background:#dbeafe;border-radius:6px;padding:3px 8px;font-size:11px">Post-Edit Check</span>
</div>
<div style="font-size:11px;color:#1e40af;margin-top:6px">系统机制<b>强制执行</b> → 不依赖 LLM 的配合</div>
</div>
</div>

两层一起用。prompt-hardening 减少 agent 犯错的概率，execution-harness 在它犯错时拦住。具体的接入点：

**P5（反推理阻断）→ Ralph block 消息。** 已经在用。Ralph 的 block 消息不只说"继续工作"，还堵 agent 的合理化——"不要合理化说剩下的可以后续处理，不要用'大致完成'来声称完成"。P5 的直接应用。

**P13（代码级强制）= Hook 本身。** 概念等价。prompt-hardening 的 P13 原则是"关键约束必须有代码级强制作为备份"。每一个 hook 脚本就是一个 P13 实现。

**P9（漂移防护）→ Hook Pair Bracket。** 长对话中 agent 逐渐忘记规则（context drift）。P9 建议周期性重新注入关键约束。Hook Pair Bracket 的 UserPromptSubmit hook 就是注入点——每轮开始时注入提醒。

**P1（三重强化）→ Handoff 文档指令。** 让 agent 写 handoff 文档时用 P1 模式：`MUST write a handoff document. The handoff MUST contain all 5 sections. I REPEAT: do NOT skip the handoff document.`

**P4（条件触发）→ Adaptive Complexity。** 不同复杂度的任务触发不同强度的 prompt hardening。Critical 任务用 P1+P5+P9+P13 全套，Trivial 任务不加额外硬化。

---

### 4.9 端到端验证：从 init 到 cancel 的完整链路

不够。42 个 pytest 测试都是单元级——mock stdin JSON，验证 stdout JSON。它们证明脚本逻辑正确，但不能证明脚本在真实 Claude Code session 中也正确。

所以做了一次端到端验证，模拟完整的 hook 触发链路：

<div style="margin:24px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:13px;max-width:550px">
<div style="background:#eff6ff;border:1px solid #93c5fd;border-radius:8px;padding:10px;margin-bottom:6px">
<b>Step 1</b> <code>ralph-init.sh e2e-test 5</code>
<div style="font-size:11px;color:#666">→ 创建 ralph.json (active=true, iteration=0)</div>
</div>
<div style="text-align:center;color:#16a34a;font-size:11px;margin:2px 0">↓ Stop hook</div>
<div style="background:#fef2f2;border:1px solid #fca5a5;border-radius:8px;padding:10px;margin-bottom:6px">
<b>Step 2</b> 正常消息 → <b style="color:#dc2626">Ralph BLOCK</b>
<div style="font-size:11px;color:#666">{"decision":"block","reason":"[RALPH LOOP 1/5]..."}</div>
</div>
<div style="text-align:center;color:#16a34a;font-size:11px;margin:2px 0">↓ Stop hook</div>
<div style="background:#fef2f2;border:1px solid #fca5a5;border-radius:8px;padding:10px;margin-bottom:6px">
<b>Step 3</b> "I think this should probably..." → <b style="color:#dc2626">Doubt Gate BLOCK</b>
<div style="font-size:11px;color:#666">检测到 hedging 词，要求提供证据</div>
</div>
<div style="text-align:center;color:#a16207;font-size:11px;margin:2px 0">↓ PostToolUseFailure</div>
<div style="background:#fefce8;border:1px solid #fde68a;border-radius:8px;padding:10px;margin-bottom:6px">
<b>Step 4</b> cargo build → command not found → <b style="color:#a16207">追踪 count=1</b>
<div style="font-size:11px;color:#666">tool-errors.json (hash=5472be1d...)</div>
</div>
<div style="text-align:center;color:#16a34a;font-size:11px;margin:2px 0">↓ ralph-cancel.sh</div>
<div style="background:#f0fdf4;border:1px solid #86efac;border-radius:8px;padding:10px">
<b>Step 5-6</b> Cancel → Stop hook → <b style="color:#16a34a">ALLOW</b>
<div style="font-size:11px;color:#666">deactivation_reason="cancelled"</div>
</div>
</div>

每一步的输入输出 JSON 都验了。Ralph block → Doubt Gate block → Tool Error 追踪 → Cancel 放行，完整链路跑通。

---

---

## 5. 工程质量：4 轮 review

### 5.1 四轮 multi-agent review

仓库经过 4 轮不同焦点的 review。每轮启动 3 个独立 agent，分别审查不同 skill。

**第一轮看功能**——pattern 实现对不对、脚本按不按描述工作、测试覆盖够不够。上来就炸了两个 P0：5 个安全阀只实现了 3 个，以及全部脚本的 JSON 注入漏洞。

**第二轮对协议。** 逐个比对 hook 的 input/output JSON 和 Claude Code 官方 schema。`tool-error-advisor.sh` 用了 PreToolUse 的废弃 output 格式（`decision: "block"` 应该是 `permissionDecision: "deny"`），`ralph-stop-hook.sh` 在读一个根本不存在的 `stop_reason` 字段。字段名错一个字母，Claude Code 直接无视你的输出，不报错——这种 bug 光看代码逻辑永远发现不了。

**第三轮验事实。** reference 文档引用的 Claude Code 内部机制和源码一致吗？reviewer 不是对着文档推理，是拿 `grep` 和 `jq` 去翻真实的 transcript JSONL 文件。结果发现 `context-usage.sh` 依赖的 `context_window` 字段在真实 transcript 中根本不存在。

**第四轮收尾审计。** 文件清单、交叉引用、数字一致性。发现根目录测试文件和子 skill 测试文件的 import 冲突，以及多处过时的测试数量引用。这轮新发现明显比前三轮少——信号衰减了。

4 轮累计 53 个问题，修了 30 个。但有 5 个是 reviewer 自己搞错了，我们拒绝修。这值得说说。

### 5.1.1 Reviewer 也会犯错

举三个例子。

一个 reviewer 说 `PreCompact` hook 事件不存在于 Claude Code 中，判 P0。我们去官方文档核实——Claude Code 有 27 个 hook 事件，`PreCompact` 是第 23 个。reviewer 参考的是旧版 SDK 的 type definitions，里面确实没有 `PreCompact`，但那是后来加的。

另一个 reviewer 说 `last_assistant_message` 不是 Stop hook 的输入字段，判 P0。官方文档明确列了这个字段。reviewer 看的是项目里已有的 Stop hook（只读 `stop_reason` 和 `session_id`），没查官方文档。

第三个 reviewer 说 `PostToolUseFailure` 事件不存在。这是 27 个事件中的第 6 个。

教训很具体。多个 reviewer 增加覆盖面，但也增加误报。reviewer 之间矛盾时（一个说存在，一个说不存在），需要权威来源仲裁。我们的权威来源是 Claude Code 官方文档。如果只有一个 reviewer，这些错误判定可能直接被采纳，然后正确的代码被删了。

multi-agent review 不是越多 agent 越好。有个拐点。过了拐点，噪声增长快过信号。我没有找到这个拐点在哪，但 4 轮 × 3 agent 的配置在我们的场景里感觉接近了——第四轮发现的新问题明显少于前三轮。

### 5.2 从 12 到 21，从一个文件到三个 Skill

TL;DR 里说过：蒸馏知识容易，验证正确性才是大头。具体多大？从 12 个 pattern 扩展到 21 个，用了大约一个周末。从一个 SKILL.md 拆到三个独立 skill 加 4 轮 review 修完 30 个 bug，用了剩下的工作日。写一个 pattern 20 分钟，验证 hook 协议对不对、状态文件并发写会不会撞、macOS 和 Linux 的 `date` 命令解析行为一不一样——加起来是写的 3-5 倍时间。回过头看，如果只写不验，这个仓库现在大概是个漂亮的废品。

### 5.3 质量评估的两个盲区：leakage 和 knowledge_density

接入 improvement-learner（技能质量评估工具）时发现原有评分维度有盲区。新增了两个。

**leakage** —— 是否泄露不应暴露的内部实现细节（比如 Claude Code 的 source-mapped 变量名）。可移植的 pattern 不应该依赖某个版本的内部命名。

**knowledge_density** —— 每百 token 的有效信息密度。防止 SKILL.md 或 reference 文件用套话填充篇幅。这个维度直接影响了 SKILL.md 的写法：能用一句话说清的不用两句。

效果很直接。第一个版本的 execution-harness SKILL.md 上，leakage 评分 0.0（到处是 `~/.openclaw/` 硬编码路径和 `nc-` 会话前缀），knowledge_density 0.4（每个 pattern 只有 3-5 行描述）。重写后 leakage 到 1.0，knowledge_density 到 0.96。

这两个维度暴露了一类之前检测不到的质量问题：内容看起来结构完整（accuracy 1.0），但充斥着项目特定的硬编码引用，且每个 pattern 深度不够——只说"做什么"不说"为什么"和"tradeoff 是什么"。我觉得这个发现本身比评分工具更有价值。

---

## 6. 已知局限

**context_window 安全阀做不了。** 4.1 节讲过——Claude Code 不在 hook 输入中暴露 `context_window_size`，硬编码阈值不靠谱，所以选了不做。

**model fallback 是建议性的。** hook 脚本没法切换 Claude Code 使用的模型。Pattern 21 的"自动模型降级/升级"只能在 `additionalContext` 中注入建议，agent 可以无视。确定性的 fallback 只有一种：在 subagent 定义中预先指定不同模型。

**doubt gate 有误报。** 4.2 节讲过——关键词匹配没法区分合理分析和投机逃避。one-shot guard 防了死循环，代价是第二次永远放行。

**Claude Code 内部名称可能过时。** `AutoDream`、`DenialTrackingState`、`buildExtractAutoOnlyPrompt` 来自 source-mapped v2.1.88 TypeScript。跨版本可能改名。reference 文档用了这些名字，主 SKILL.md 尽量不依赖。

**21 个 pattern 中 8 个有可执行脚本，13 个是设计参考。** 三种委托模式（Coordinator/Fork/Swarm）、三门控记忆合并、Adaptive Complexity 偏架构设计，不是一个 shell 脚本能覆盖的。

**所有 hook 都有性能开销。** 每个 Stop hook 是一次 bash 进程启动 + jq 调用。单个 hook < 10ms，但配了 5 个 Stop hook，agent 每次尝试停止就有约 50ms 延迟。高频 stop-block 循环（Ralph + Doubt Gate 同时 block）下延迟会累积。目前没观察到用户可感知的性能问题，但极端场景（max_iterations=200，每次都被 block）下需要注意。

**session state 目录要手动清。** `sessions/<session-id>/` 目录不会自动删除。跑了 100 个 session 就有 100 个目录，每个几 KB，不影响磁盘。但要调试某个 session 时在 100 个目录里翻不方便。建议定期 `find sessions/ -maxdepth 1 -mtime +7 -exec rm -rf {} \;` 清理 7 天前的。

**tool-error-tracker 的 hash fallback。** 如果 `md5`、`md5sum`、`shasum` 都不存在（极端精简容器环境），hash 会 fallback 到 `"unknown"`。所有工具错误的 hash 相同，计数器永远不重置。这种环境下 tool error escalation 会过于激进。

---

## 7. 开放问题

**怎么测 PreCompact hook 的触发时机？** 42 个测试都是单元级——mock stdin，验 stdout。但 Compaction Memory Extraction (Pattern 8) 需要 Claude Code 实际触发 auto-compact 才能验证 PreCompact hook 有没有生效。你没法从外部可靠地触发 auto-compact——它取决于 context window 填充速度，而那取决于 agent 的行为。一种想法是故意构造会快速填满 context 的任务（比如让 agent 读 50 个大文件），但这更像集成测试，不是 CI 级别的自动化测试。我暂时没有好方案。

**"合理推测"和"投机逃避"怎么分？** Doubt Gate 用关键词匹配，"可能"出现就 block。但"这个 bug 可能影响了三个模块"是合理分析，"这个修改可能修好了"是投机逃避。区分两者需要语义理解。一个方向是 prompt-type Stop hook——用 LLM 本身判断，代价是每次 stop 多一次 API 调用。另一个方向是检查上下文——如果 agent 刚跑了测试且测试通过了，说"可能修好了"有证据支撑；如果没跑任何验证就说"可能"，那就是投机。两条路我都没走通。

**context_window 安全阀。** 4.1 节和第 6 节都提到了这个缺口。如果未来 hook 输入增加 `context_window_size` 字段，或者通过 HUD plugin 的 IPC 间接获取，就能做。在那之前靠 reactive compaction 兜底。

**agent 被 Ralph block 太多次会怎样？** 一个有意思的观察：连续被 block 多次后，有些 agent 开始产出更短的回复——像在应付检查，不是真的在推进任务。我猜是因为 block 消息措辞太命令式，触发了 agent 的"服从模式"而不是"工作模式"。block 消息的措辞设计是一个开放的 prompt engineering 问题。当前用了 P5 反推理阻断，但也许需要根据迭代次数动态调整语气——前几次强硬，后面切换为"你做得不错，但检查一下还有没有遗漏"的鼓励式措辞。这只是直觉，没有验证过。

**13 个纯设计参考 pattern 要不要落地？** 三种委托模式（Coordinator/Fork/Swarm）不是一个 shell 脚本能覆盖的，但 Denial Circuit Breaker、Hook Pair Bracket、Rate Limit Recovery 都可以写成可执行脚本。难点在验证——怎么测试一个 rate limit recovery 脚本？你需要模拟 tmux pane 中的限速消息。没想好怎么做。

**doubt gate 和 Ralph 的叠加顺序怎么定？** 如果 settings.json 中 Ralph 排在 Doubt Gate 前面，Ralph 先 block 了 stop，Doubt Gate 就不触发。反过来，Doubt Gate 先 block 了投机语言，Ralph 的迭代计数没递增。顺序影响行为。当前建议 Ralph 在前——确保迭代计数始终递增，即使 Doubt Gate 也会 block。但这意味着一次 stop 尝试可能同时消耗一次 Ralph 迭代和一次 Doubt Gate guard。max_iterations 比较小（比如 5）的场景下，Ralph 可能比预期更早耗尽。这个 tradeoff 我还没有满意的解法。

这些问题留着。harness 不是写完就不动的东西——模型在变，hook 协议在变，你对"可靠"的定义也在变。

仓库地址：[github.com/lanyasheng/execution-harness](https://github.com/lanyasheng/execution-harness)
