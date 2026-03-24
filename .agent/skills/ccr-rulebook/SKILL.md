---
name: ccr-rulebook
description: Central enforcement for the 3 Immutable Laws of CCR architecture.
---

# CCR Rulebook Skill

This skill provides the mandatory enforcement layer for all CCR development in the HeliSync Edition.

## Usage
ALWAYS load this skill alongside `ccr-context`. You MUST verify every law in `RULEBOOK.md` that is relevant to your current task.

## Closing Requirement
Before calling `notify_user` or claiming a task is done, you MUST:
1. Open `RULEBOOK.md`.
2. Perform the "Enforcement Gates" relevant to your work.
3. If any law is violated, you MUST report the violation and stop the task until it is fixed.
