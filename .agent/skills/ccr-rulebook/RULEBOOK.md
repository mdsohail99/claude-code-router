# ⚖️ CCR Immutable Laws (HeliSync Edition)

These laws govern the "HeliSync Edition" fork. Violation of these laws constitutes an architectural failure.

---

## ⚡ Law #1: The Stealth Invariant
- **Rule**: CCR MUST NEVER send attribution headers or telemetry that identifies the user to the underlying AI provider.
- **Enforcement**: Verify that `packages/cli/src/utils/createEnvVariables.ts` hardcodes `CLAUDE_CODE_ATTRIBUTION_HEADER: "0"` and `DISABLE_TELEMETRY: "1"`.

## 🧠 Law #2: The Classifier Priority
- **Rule**: The "Smart Classifier" in `router.ts` MUST always prioritize specialized routing (code, image, think) over the default model.
- **Enforcement**: Verify the `getUseModel()` waterfall in `packages/core/src/utils/router.ts` still includes the detection logic for tools and images.

## 🔄 Law #3: The Triple-Sync Requirement
- **Rule**: Any change to the `default` model in CCR MUST optionally sync to Claude Code's native `settings.json`.
- **Enforcement**: Verify the existence and functionality of the "Apply & Restart" button in `packages/cli/src/utils/modelSelector.ts`.

## 🤖 Law #4: The Visibility & Placeholder Invariant
- **Rule**: Every model switch MUST be visible in the terminal, and images MUST be handled via [Image ID: X] placeholders for maximum model compatibility.
- **Enforcement**: 
    1. Verify `index.ts` injects `[CCR] 🤖 Switching to` at the start of the stream.
    2. Verify `image.agent.ts` uses the `[Image ID: X]` format to avoid "blind" models.

---

## 🛡️ Enforcement Gates (Pre-Completion)
Before finishing any task, run these checks:
1.  **Build Check**: Run `pnpm build` to ensure no syntax regressions.
2.  **Link Check**: Run `npm link` to verify CLI availability.
3.  **JSON Check**: Ensure all config parsing uses `JSON5` to avoid BOM crashes.
