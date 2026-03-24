# 🔄 Syncing with Official Upstream

To keep your fork updated with the official Claude Code Router repository without breaking your custom features (`CodeAgent`, `Selector Fixes`, etc.), follow this **Rebase Workflow**.

## Pre-requisites
You already have the `official` remote configured:
- `official`: `https://github.com/musistudio/claude-code-router.git`
- `origin`: `https://github.com/mdsohail99/claude-code-router.git` (Your Fork)

## The Sync Process

### 1. Fetch Latest Changes
Pull the latest tracking information from the official repository:
```bash
git fetch official
```

### 2. Rebase your changes onto Upstream
Instead of a "Merge" (which creates a messy commit history), use a "Rebase". This takes your custom commits and places them **on top** of the latest official code.
```bash
git rebase official/main
```

### 3. Handle Conflicts (If Any)
If the official repo changed a file we also modified (like `modelSelector.ts`), Git will pause.
1.  Open the file and resolve the markers (`<<<<<<<` and `>>>>>>>`).
2.  Stage the resolved file: `git add <filename>`
3.  Continue the rebase: `git rebase --continue`

### 4. Push to your Fork
Since rebasing rewrites history, you will need to "force push" to your fork:
```bash
git push origin main --force
```

---

## 🔍 Selective Merging: How to Choose?

If the official repository has improved a feature that competes with your custom changes, follow these steps to compare and decide.

### 1. Compare Before Syncing
Check exactly what changed in the official repo since your last sync:
```bash
git diff main official/main
```
Or to see changes in a specific file:
```bash
git diff main official/main -- packages/cli/src/utils/modelSelector.ts
```

### 2. Selective Rebase (Interactive)
If you want to **discard** some of your custom commits because the official repo now handles it better:
```bash
git rebase -i official/main
```
This opens a list of your commits. You can change `pick` to `drop` for any custom feature you no longer want.

### 3. Choosing "Theirs" during Conflicts
When you rebase and a conflict occurs, you can choose to discard your logic and take the official logic instead:
```bash
git checkout --theirs <filename>
git add <filename>
git rebase --continue
```
*(Note: In a rebase, `--theirs` refers to the official upstream code).*

## 🛡️ Strategic Rule: Keep "Core" logic, Accept "UI" updates
- **Keep**: Your `CodeAgent` and `Router` logic (it's unique to CCR).
- **Accept**: Official UI styling, CLI colors, or utility improvements.

## ⚠️ Warning
Always run `npx pnpm build` after a sync to ensure the official changes didn't introduce any build errors with your custom logic.
