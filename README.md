# Execution Harness

Claude Code agent 执行可靠性工具集。解决 agent 在长任务中的常见失败：提前停止、上下文丢失、重试死循环、限速挂死、crash 后状态丢失。

蒸馏自 Claude Code v2.1.88 内部架构（Query Engine、Tool System、Permission Pipeline、Context Management、Session Persistence）和 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (OMC) 的生产实践。参考了 [Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) 和 [OpenAI](https://openai.com/index/harness-engineering/) 的 harness engineering 博客。

## 仓库结构

```
execution-harness/
├── skills/
│   ├── agent-hooks/          ← 可执行 hook 脚本（给系统集成者）
│   │   ├── SKILL.md
│   │   ├── scripts/          ← 8 个 bash 脚本
│   │   ├── tests/            ← 32 个 pytest 测试
│   │   └── references/       ← 5 个 pattern 详解
│   ├── harness-design-patterns/  ← 设计模式知识库（给架构师）
│   │   ├── SKILL.md
│   │   └── references/       ← 10 个 pattern + 方法论 + 质量管道集成
│   └── agent-ops/            ← 运维工具（给 SRE）
│       ├── SKILL.md
│       ├── scripts/          ← 1 个工具脚本
│       ├── tests/            ← 5 个 pytest 测试
│       └── references/       ← 6 个 pattern 详解
└── shared/
    └── session-state-layout.md   ← 跨 skill 共享的状态目录规范
```

## 三个 Skill

### agent-hooks — 即插即用的 Hook 脚本

**受众**：需要配置 Claude Code settings.json 的系统集成者。

提供 8 个 bash 脚本，配到 Claude Code 的 hooks 里即可生效：

| 脚本 | Hook 类型 | 功能 |
|------|----------|------|
| `ralph-init.sh` | CLI | 初始化持续执行（支持 crash 恢复） |
| `ralph-stop-hook.sh` | Stop | 阻止 agent 提前停止，4 个安全阀保底 |
| `ralph-cancel.sh` | CLI | 发送 30s TTL 取消信号 |
| `tool-error-tracker.sh` | PostToolUseFailure | 追踪连续失败，3/5 次阈值升级 |
| `tool-error-advisor.sh` | PreToolUse | 5 次失败后 deny 同一命令 |
| `doubt-gate.sh` | Stop | 检测投机语言，强制提供证据 |
| `post-edit-check.sh` | PostToolUse | 编辑后即时跑 linter/type checker |
| `context-usage.sh` | CLI | 从 transcript 提取 input token 计数 |

### harness-design-patterns — 设计模式参考

**受众**：设计 agent 系统架构的工程师。

10 个设计模式，每个包含：问题 → 原理 → tradeoff → 来源 → Claude Code 实证：

| 模式 | 解决什么 |
|------|---------|
| Handoff 文档 | 跨阶段/跨压缩的上下文传递 |
| 原子文件写入 | 并发状态文件安全 |
| Compaction 记忆提取 | 压缩前被动抢救知识 |
| 权限否决追踪 | 防止 agent 换表述绕过拒绝 |
| 三门控记忆合并 | 跨 session 记忆碎片化 |
| Hook Pair Bracket | 每轮 context/时间测量 |
| Component-Scoped Hooks | 任务级别的 hook 控制 |
| 三种委托模式 | Coordinator/Fork/Swarm 选型 |
| Adaptive Complexity | 任务复杂度自适应执行强度 |
| Hook Runtime Profiles | 环境级 hook 强度控制 |

附带：[蒸馏方法论](skills/harness-design-patterns/references/distillation-methodology.md)（PCA 降维、Review-Execution 分离）和[质量管道集成指南](skills/harness-design-patterns/references/quality-pipeline-integration.md)。

### agent-ops — 运维工具

**受众**：维护运行中 agent 的 SRE。

6 个运维 pattern（1 个有脚本，5 个为设计参考）：

| 工具 | 状态 | 功能 |
|------|------|------|
| Context 估算 | **脚本** | 从 transcript 提取 token 使用量 |
| Rate Limit 恢复 | 设计参考 | 扫描 tmux pane 检测限速，安全恢复 |
| Stale Session Daemon | 设计参考 | Heartbeat + 死 session 知识回收 |
| Checkpoint + Rollback | 设计参考 | 破坏性 Bash 前快照，失败后回滚 |
| Token Budget | 设计参考 | 按 context 使用率注入预算指令 |
| Auto Model Fallback | 设计参考 | 连续失败后建议升级模型 |

## 安装

### 前提条件

- Claude Code CLI
- `jq`（所有脚本依赖）
- `bash`
- 可选：`ruff`/`pyright`/`tsc`/`cargo`/`shellcheck`（post-edit-check 使用）

### 配置 Hook

将需要的脚本加入 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/ralph-stop-hook.sh"},
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/doubt-gate.sh"}
      ]
    }],
    "PostToolUseFailure": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/tool-error-tracker.sh", "async": true}
      ]
    }],
    "PreToolUse": [{
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/tool-error-advisor.sh"}
      ]
    }],
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [
        {"type": "command", "command": "bash /path/to/skills/agent-hooks/scripts/post-edit-check.sh", "async": true}
      ]
    }]
  }
}
```

### 启用 Ralph 持续执行

```bash
# 初始化（session-id, max-iterations）
bash skills/agent-hooks/scripts/ralph-init.sh my-task-001 50

# 取消
bash skills/agent-hooks/scripts/ralph-cancel.sh my-task-001
```

## 测试

```bash
# agent-hooks（27 tests）
cd skills/agent-hooks && python3 -m pytest tests/ -v

# agent-ops（5 tests）
cd skills/agent-ops && python3 -m pytest tests/ -v
```

## 架构设计

### Session-Scoped State

所有运行时状态统一在 `sessions/<session-id>/` 下：

```
sessions/<session-id>/
  ralph.json              ← 持续执行状态
  cancel.json             ← 取消信号（30s TTL）
  handoffs/               ← 阶段间上下文传递
  tool-errors.json        ← 工具错误追踪
  denials.json            ← 权限否决追踪
```

清理只需 `rm -rf sessions/<session-id>/`。Crash 恢复只需检查目录是否存在。

### Hook 协议

所有脚本遵循 Claude Code hook 协议：

- **输入**：stdin 接收 JSON（包含 `session_id`, `transcript_path`, `tool_name` 等）
- **输出**：stdout 输出 JSON（`{"decision":"block","reason":"..."}` 或无输出表示允许）
- **安全**：所有 JSON 输出通过 `jq -n` 构造（防止注入）
- **原子**：所有状态文件通过 write-then-rename 写入（防止并发损坏）

### Ralph 安全阀

Ralph stop hook 在以下条件下 **MUST 放行**，防止 agent 被永久阻塞：

1. 认证失败（401/403，从 `last_assistant_message` 检测）
2. Cancel 信号存在且未过期
3. 闲置超时 > 2 小时
4. 达到 max_iterations

> Context usage >= 95% 安全阀**未实现**——Claude Code 不在 hook 输入或 transcript 中暴露 `context_window_size`（该数据仅通过 statusLine stdin pipe 提供给 HUD 插件）。Claude Code 自身的 reactive compaction 机制独立处理 context 溢出。

## 信息来源

| 来源 | 提供了什么 |
|------|-----------|
| [Claude Code 源码 v2.1.88](https://github.com/openedclaude/claude-reviews-claude) | Query Engine 循环、Tool System、Permission Pipeline、Context Management、Session Persistence 内部架构 |
| [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | Ralph persistent-mode、Stop hook 机制、Cancel TTL、Stale 阈值、Team runtime |
| [ccunpacked.dev](https://ccunpacked.dev/) | yoloClassifier、DenialTracking、AutoDream、MCP auto-healing、Memory extraction |
| [claude-howto](https://github.com/luongnv89/claude-howto) | Prompt-type hooks、Agent-type hooks、Hook pair bracket、Component-scoped hooks |
| [Claude Code 官方文档](https://code.claude.com/docs/en/hooks) | 26 个 hook 事件、输入/输出 schema、permission 协议 |
| [LastWhisperDev](https://mp.weixin.qq.com/s/R9EgZlx1RnXK4L12OBQn-w) + [agentic-harness-patterns-skill](https://github.com/keli-wen/agentic-harness-patterns-skill) | 蒸馏方法论、PCA 降维类比、Review-Execution 分离 |
| [Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) / [OpenAI](https://openai.com/index/harness-engineering/) | Harness engineering 设计原则 |
| GitHub 社区 | [plugin-doubt-gate](https://github.com/johnlindquist/plugin-doubt-gate)、[Continuous-Claude-v3](https://github.com/parcadei/Continuous-Claude-v3)、[everything-claude-code](https://github.com/affaan-m/everything-claude-code)、[sdd-autopilot](https://github.com/rubenzarroca/sdd-autopilot) |

## 蒸馏方法论

本仓库的 21 个 pattern 不是 Claude Code 的客观映射，而是经过特定视角投影后的产物。蒸馏过程借鉴了 LastWhisperDev 的 PCA 类比：

> 代码是高维的，但有价值的设计模式是低秩的。蒸馏的本质是找到主成分。

三个关键方法论选择：

1. **品味注入**：以 Anthropic/OpenAI 的 harness engineering 博客和 Context Engineering 四轴框架（select/write/compress/isolate）作为基向量
2. **Review-Execution 分离**：用不同的 agent 做 review 和 execution，互不可见对方的 session
3. **每轮新 session**：每轮 review-action 在全新 session 中执行，通过 handoff 文件传递上下文

详见 [distillation-methodology.md](skills/harness-design-patterns/references/distillation-methodology.md)。

## 已知局限

- **Context usage 安全阀无法在 hook 中实现** — `context_window_size` 仅通过 statusLine stdin pipe 暴露
- **Auto Model Fallback 是建议性的，不是自动的** — hook 无法控制 Claude Code 使用哪个模型
- **Claude Code 内部 API 名称来自 source-mapped 源码 (v2.1.88)** — minified bundle 中被混淆，可能随版本变化
- **Post-edit diagnostics 速度取决于 linter** — TypeScript 的 `tsc --noEmit` 在大项目上可能需要 30 秒+，建议 `async: true`
- **Doubt gate 的 hedging 词匹配有误报风险** — "should be"、"could be" 在非投机语境中也会触发

## License

MIT
