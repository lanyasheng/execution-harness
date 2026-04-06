# Drift Re-anchoring

## Problem

Agent 在长会话中逐渐偏离原始任务。第 1 轮还在做需求分析，第 5 轮开始"顺手"重构不相关代码，第 10 轮已经在优化 CI 配置。这种 drift 在 Ralph 持续执行中更严重——因为 agent 不停，drift 没有天然的修正点。

## Solution

UserPromptSubmit hook 每 N 轮（默认 5 轮）将原始任务描述重新注入对话，作为"锚点"。注入的不是简单重复，而是带有当前进度对比的结构化 re-anchor 消息，让 agent 对照原始目标自查偏移。

## Implementation

1. 任务启动时将原始 prompt 存入 `sessions/<session-id>/original-task.md`
2. UserPromptSubmit hook 读取 ralph.json 获取当前迭代数
3. 当 `iteration % reanchor_interval == 0` 时触发 re-anchor
4. 注入结构化消息包含：原始任务、当前迭代数、已完成项（从 .harness-tasks.json 读取）
5. Hook 返回 `{"decision":"allow"}` 放行用户输入，re-anchor 作为附加 context

```bash
# UserPromptSubmit hook
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
RALPH="sessions/${SESSION_ID}/ralph.json"
[ -f "$RALPH" ] || exit 0

ITERATION=$(jq -r '.iteration // 0' "$RALPH")
INTERVAL=${REANCHOR_INTERVAL:-5}
[ $(( ITERATION % INTERVAL )) -eq 0 ] || exit 0
[ "$ITERATION" -gt 0 ] || exit 0

TASK=$(cat "sessions/${SESSION_ID}/original-task.md" 2>/dev/null)
[ -z "$TASK" ] && exit 0

cat <<EOF
{"decision":"allow","hookSpecificOutput":{"additionalContext":"[RE-ANCHOR iteration ${ITERATION}] 原始任务:\n${TASK}\n\n请对照原始任务检查：你当前的工作是否仍在为原始目标服务？如果偏离了，立即回到正轨。"}}
EOF
```

## Tradeoffs

- **Pro**: 低成本防 drift，不需要 LLM 判断
- **Pro**: 与 Ralph、Task Completion 正交——三者各管一个维度
- **Con**: 频率过高会浪费 context（N 太小），频率过低可能来不及纠偏（N 太大）
- **Con**: 对于合理的任务拆分变化（发现 A 前必须先做 B），re-anchor 可能产生误导

## Source

OMC 的多模式持续执行系统中的"任务重注入"机制。Anthropic 博客提到的 coordinator synthesis 原则——agent 需要定期对照原始目标。
