---
name: quality-verification
version: 2.0.0
description: 输出质量保障与验证。编辑后检查、提交前测试、session 指标测量。不适用于工具重试（用 tool-governance）或 agent 提前停止（用 execution-loop）。参见 tool-governance（错误追踪）。
license: MIT
triggers:
  - post edit check
  - lint after edit
  - test before commit
  - hook bracket
  - session metrics
  - quality gate
  - hook profile
---

# Quality & Verification

输出质量保障：编辑后即时检查、提交前自动测试、per-turn 指标测量。

## When to Use

- 编辑后即时检查 → Post-edit diagnostics
- 提交前跑测试 → Test-before-commit gate
- 测量 per-turn 指标 → Hook pair bracket
- 按环境切换 hook 强度 → Hook runtime profiles

## When NOT to Use

- Agent 提前停止 → 用 `execution-loop`
- 工具安全 → 用 `tool-governance`

---

## Patterns

| # | Pattern | Type | Description |
|---|---------|------|-------------|
| 6.1 | Post-edit diagnostics | [script] | 编辑后跑 linter/type checker |
| 6.2 | Hook runtime profiles | [config] | 环境级 profile 切换 |
| 6.3 | Session turn metrics | [script] | per-turn 时间/turn 计数测量 |
| 6.4 | Test-before-commit gate | [script] | git commit 前跑测试 |
| 6.5 | Atomic state writes | [design] | write-to-temp-then-rename |
| 6.6 | Session state hygiene | [design] | 定期清理 stale state |

## Scripts

| 脚本 | Hook 类型 | 功能 |
|------|----------|------|
| `post-edit-check.sh` | PostToolUse (Write\|Edit\|MultiEdit) | 编辑后 linter |
| `bracket-hook.sh` | Stop | 记录 per-turn 指标 |
| `test-before-commit.sh` | PreToolUse (Bash) | commit 前跑测试 |


## Quick Start

```bash
# TODO: Add usage examples
```

## Workflow

1. Agent 编辑文件 → PostToolUse hook 触发（Write/Edit/MultiEdit）
2. `post-edit-check.sh` 检测文件类型（`.ts`/`.tsx` → tsc, `.py` → ruff, `.sh` → shellcheck）
3. 跑对应 linter/type checker，将错误通过 `additionalContext` 注入上下文
4. Agent 立即看到诊断错误，当场修复

提交时：

1. Agent 执行 `git commit` → PreToolUse (Bash) hook 拦截
2. `test-before-commit.sh` 识别到 git commit 命令，跑测试套件
3. 测试失败 → block commit，agent 看到失败输出后修复再提交

MUST 在编辑后立即跑诊断并注入错误上下文，否则 agent 会带着类型错误继续往下写，越积越多。

不要等到 commit 时才跑 linter——而是每次编辑后即时检查，commit 前跑完整测试套件。

如果不确定某个文件类型是否需要 post-edit 检查，看 `post-edit-check.sh` 里的扩展名映射表。没有对应 linter 的文件类型直接跳过，不要硬跑。

<example>
场景: agent 编辑 handlers.ts，引入了类型错误
1. agent 调用 Edit 修改 handlers.ts
2. PostToolUse hook 触发 post-edit-check.sh
3. 脚本检测 .ts 扩展名 → 跑 tsc --noEmit
4. tsc 输出 "error TS2345: Argument of type 'string' is not assignable to parameter of type 'number'"
5. 错误通过 additionalContext 注入 agent 上下文
6. agent 立即看到 TS2345，当场修复类型不匹配
结果: 类型错误在产生的同一个 turn 内被修复，不会传播到后续代码
</example>

<anti-example>
错误用法: 对每次 README.md 编辑都跑 post-edit diagnostics
README 不是代码文件，没有 linter 可跑，每次编辑后空跑一次检查白白浪费时间。
这是 M6 (Proportional Intervention) 违规——非代码文件不需要诊断 hook。
post-edit-check.sh 应按扩展名过滤，非代码文件直接 exit 0。
</anti-example>

## Output

| 产出物 | 来源 | 说明 |
|--------|------|------|
| 诊断结果 | `additionalContext` | linter/type checker 错误注入 agent 上下文，agent 当场可见 |
| session 指标 | `bracket.json` | per-turn 时间、turn 计数、hook 执行耗时 |
| 测试结果 | commit 前 | 测试套件输出，失败时 block commit 并展示失败用例 |

## Related

- `tool-governance` — 错误追踪器记录诊断失败（tool-error-tracker 追踪连续 linter 失败）
- `execution-loop` — doubt gate 检测未验证声明（agent 说"应该没问题"但没跑检查时拦截）
- `context-memory` — 诊断结果写入 handoff document，跨 session 传递未修复的已知问题
