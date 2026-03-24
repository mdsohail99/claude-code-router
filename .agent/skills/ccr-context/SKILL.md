---
name: ccr-context
description: >
  Load CCR project context before working on ANY code, architecture, CLI, or server task in this
  codebase. ALWAYS use this skill when the user mentions HeliSync Edition, Smart Classifier,
  or Stealth Mode.
---

# CCR HeliSync Edition Context

This repository is a **highly customized fork** of the Claude Code Router (CCR), tailored for the HeliSync ecosystem. It includes advanced task classification, global settings synchronization, and hardened privacy enforcement.

---

## 🚀 Fork Identity: HeliSync Edition v0.1

Unlike the upstream repository, this version prioritizes **Smart Routing** and **Privacy Stealth**. Before modifying any core files, understand these three pillars:

### 1. Smart Classifier (The Brain)
- **Logic**: Located in `packages/core/src/utils/router.ts`.
- **Function**: Automatically detects `code` vs `image` vs `longContext` tasks.
- **Matrix**: Uses `scripts/ccr/ccr-route-matrix.json` to map scenarios to specific models.

### 2. Global Sync (The Bridge)
- **Logic**: Located in `packages/cli/src/utils/modelSelector.ts`.
- **Function**: When you use `ccr model`, the "Apply & Restart" button synchronizes your CCR `default` model directly into Claude Code's native `~/.claude/settings.json`.

### 3. Stealth Mode (The Law)
- **Logic**: Located in `packages/cli/src/utils/createEnvVariables.ts`.
- **Function**: Hardcodes `CLAUDE_CODE_ATTRIBUTION_HEADER: "0"` and `DISABLE_TELEMETRY: "1"` for every request.

---

## 🔨 Development Workflow

Because this is a CLI tool that lives globally, any changes require a full build/link cycle:

1.  **Modify code** in `packages/cli/src` or `packages/core/src`.
2.  **Run Build**: `pnpm build` in the CCR root.
3.  **Run Link**: `npm link` in the CCR root to update your global `ccr` command.
4.  **Restart Service**: `ccr restart` to apply server-side changes.

---

## 📂 Key File Map

| Path | Purpose |
|---|---|
| `packages/core/src/utils/router.ts` | The core "Smart Classifier" waterfall logic. |
| `packages/cli/src/utils/modelSelector.ts` | The interactive model selector and Claude sync logic. |
| `packages/cli/src/utils/createEnvVariables.ts` | Stealth Mode enforcement (Attribution/Telemetry). |
| `scripts/ccr/ccr-route-matrix.json` | The model routing matrix (used by the Classifier). |
| `docs/Changelog/` | Definitive record of all HeliSync Edition modifications. |

---

## ⚖️ Immutable Invariants
- **NEVER** revert the `JSON5` parsing. It is required to handle invisible BOM characters in Windows config files.
- **NEVER** re-enable telemetry or attribution headers.
- **ALWAYS** ensure the `ccr model` selector loops to allow changing multiple slots in one session.
