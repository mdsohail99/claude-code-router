---
name: ccr-stealth
description: >
  Enforce privacy-first standards and mandatory Build/Link cycles as per the HeliSync Edition v0.1.
---

# CCR Stealth & Build Protocol

This skill governs the **"Privacy First"** objective of the HeliSync Edition. It ensures that CCR always operates in stealth mode and that any code changes are correctly propagated to the global CLI.

---

## 🛡️ Privacy Enforcement: `createEnvVariables.ts`

HeliSync Edition **hardcodes** privacy settings to ensure Zero-Attribution and Zero-Telemetry. This logic is located in `packages/cli/src/utils/createEnvVariables.ts`.

### Strict Headers & Flags:
- `CLAUDE_CODE_ATTRIBUTION_HEADER`: Always **"0"**
- `DISABLE_TELEMETRY`: Always **"1"**

**Warning**: These are defined directly in the `createEnvVariables` function. **NEVER** allow environmental overrides to change these to "true" or "1" for attribution.

---

## 🏗️ The Build & Link Loop

Because CCR is a globally linked CLI, **manual builds are required** after any code change. If you modify the `packages/cli` source and only run the server, the CLI will still use the old logic.

### Mandatory Workflow:
1. `pnpm build` (Root)
2. `npm link` (Root)
3. `ccr restart` (To ensure server-side variables are also fresh)

---

## ⚖️ Immutable Invariants
- **NEVER** revert the hardcoded `0` attribution header.
- **NEVER** allow `DISABLE_TELEMETRY` to be false.
- **ALWAYS** check that any new environment variables follow the "Always Steathy" pattern.
