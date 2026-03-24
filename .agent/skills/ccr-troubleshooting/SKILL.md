---
name: ccr-troubleshooting
description: Enforce 1:1 Mapping between CLI fixes and documentation.
---

# CCR Troubleshooting Protocol

Use this skill at the end of every bug fix or issue resolution in the CCR repository.

## Core Mandate
Every identified issue and its subsequent fix MUST be recorded as a new guide in `docs/Troubleshooting/`.

## Workflow
1.  **Identify Root Cause**: Determine if the issue was due to encoding (BOM), pathing, or routing logic.
2.  **Create/Update Guide**:
    - Path: `docs/Troubleshooting/[Issue-Name].md`
    - Content: Describe the problem, the root cause (e.g., hidden BOM characters), the fix (e.g., switching to `JSON5`), and how to verify it.
3.  **Cross-Reference**: Link the troubleshooting doc in the `v0.1` Changelog or equivalent.

## Final Verification
Before finishing a task, confirm that the relevant troubleshooting doc exists and is accurate.
