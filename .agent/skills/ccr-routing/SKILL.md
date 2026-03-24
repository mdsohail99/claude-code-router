---
name: ccr-routing
description: >
  Enforce Smart Classifier logic and routing matrix rules as per the HeliSync Edition v0.1 standard.
---

# CCR Smart Routing Protocol

This skill governs the **"Smart Classifier"**, which is the primary architectural enhancement of the HeliSync Edition. It allows CCR to automatically switch models based on the task type (code, image, etc.).

---

## 🧠 The Decision Engine: `router.ts`

The core logic is located in `packages/core/src/utils/router.ts` within the `getUseModel()` function. It follows a strict **priority waterfall**:

1.  **Manual Model Override**: Explicit `provider,model` in the request body (line 134).
2.  **Code Task Detection**: Bash/str_replace tools found in request → `Router.code` (line 148).
3.  **Image Task Detection**: Raw images or placeholders `[Image ID: X]` found → `Router.image` (line 159).
4.  **Long Context Threshold**: Token count exceeds `longContextThreshold` (line 168).
5.  **Sub-Agent Tags**: `<CCR-SUBAGENT-MODEL>` tags found in system prompt (line 181).
6.  **Haiku Fallback**: Claude Haiku variants routed to `background` model (line 198).
7.  **Web Search Detection**: `web_search` type tools found → `Router.webSearch` (line 207).
8.  **Thinking Detection**: `thinking` block is present → `Router.think` (line 215).
9.  **Default Global Model**: Fallback to `Router.default` (line 219).

---

## 🗺️ The Routing Matrix: `ccr-route-matrix.json`

Located at `scripts/ccr/ccr-route-matrix.json`. This file maps the **Scenarios** defined in `router.ts` to actual model strings for the server.

### Example Mapping:
```json
{
  "code": "openrouter,minimax/minimax-m2.5:free",
  "image": "openrouter,nvidia/nemotron-nano-12b-v2-vl:free",
  "think": "openrouter,arcee-ai/trinity-large-preview:free"
}
```

---

## 🛠️ Performance & Tuning

- **Threshold**: The default long-context threshold is set to **60,000 tokens**.
- **Agent Sovereignty**: If a request contains a specific sub-agent model tag, the classifier **MUST** respect it and bypass general categorization.

---

## 📏 Invariants — Never Violate
- **NEVER** remove the `code` category check. This was the primary fix for the "Dead Code" issue in the original repo.
- **NEVER** change the order of the waterfall without a full impact analysis on token usage and cost.
- **ALWAYS** update the fallback settings in `packages/shared/src/types.ts` if adding a new `RouterScenarioType`.
