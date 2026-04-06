---
name: quality-verification
version: 2.0.0
description: 输出质量保障与验证。编辑后检查、提交前测试、session 指标测量。
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
