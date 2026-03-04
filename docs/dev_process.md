# Dev Process — wellBowled

**Read this first. Follow it always. No exceptions.**

---

## Philosophy

Slow is smooth. Smooth is fast. Code is the **last** thing we write — a translation of verified findings, not a guess.

**Simple.** One sentence or simplify it. **Modern.** Current tools and patterns. **Value-focused.** If it doesn't serve the user, cut it. **Steady → Agile.** Momentum through discipline, never quick and dirty. **Deadlines don't override process.** We work smart, not hard. If we miss a deadline, we make it next time. No hasty decisions — ever.

**Ground every decision.** "I think" is not a reason — "the experiment showed" is. **Ask, dispute, be honest.** Challenge every decision, your own first. **Be self-critical.** Review your work as if someone else wrote it. **Progress, don't be hasty.** Never trade correctness for speed. **Analyze, don't paralyze.** Timebox research, then decide and move. **Nobody gets a free pass.** Not the code, not the process, not the person giving instructions. If the guidance is poor, say so. If someone needs to step back and rest, say that too.

---

## Process Autonomy (Non-Negotiable)

- The process is already defined in docs. Do not ask the user how to run it.
- Resolve process uncertainty from docs, git history, source code, and runnable commands first.
- Ask the user only for real blockers outside the documented process:
  - missing product/priority decision
  - missing permission/credential/device access
  - unresolved contradiction between canonical docs after attempted reconciliation
- Any blocker escalation must include: what was attempted, exact evidence, and the next best options.

---

## Feedback Loop Quality (Non-Negotiable)

Fast feedback is mandatory. Quality is measured by how quickly we detect and fix the right problem.

### Timing SLAs

- **Code edit batch** (small logical change): compile or typecheck within **2 minutes**.
- **Touched-scope tests**: run focused tests within **5 minutes**.
- **Visible behavior changes** (UI/session/interaction): smoke check in simulator/device within **10 minutes**.
- **No blind waiting**: if a command is running without meaningful output for **more than 5 minutes**, stop, narrow scope, and rerun.

### Risk-Based Validation Depth

- **R0 Docs only**: markdown/doc consistency check + links/path sanity.
- **R1 Isolated logic/UI tweak**: focused unit tests + quick manual behavior check.
- **R2 Session/runtime flow change**: focused tests + end-to-end smoke of the affected path.
- **R3 Pipeline change** (`detect clip -> Gemini -> pose -> chips/control`): focused tests + smoke of happy path + at least one failure-path check.

### Mandatory Feedback Record (each iteration)

For every loop, record this in docs/notes before moving on:

- **Change**: what was modified.
- **Check**: exact command/test/manual step executed.
- **Result**: pass/fail with concrete evidence.
- **Next action**: keep, fix, or rollback direction.

### Tight Iteration Protocol

1. Write/adjust a failing test or explicit manual acceptance check.
2. Apply the minimum code change.
3. Run the shortest relevant test set first.
4. Run a quick end-to-end smoke if behavior is user-visible.
5. Sync docs with evidence before the next edit batch.

### Regression Discipline

- Do not stack multiple risky changes without an intermediate check.
- If a regression appears, isolate with `git diff` + smallest reproducer before further edits.
- Long suites are for confirmation, not first-line feedback. Start small, then expand.

### Pre-Install Gates (Hard Requirement)

- Any initializer/signature change in shared UI/service components must include a call-site sweep before tests:
  - run `rg -n "<SymbolName>\\("` in source-of-truth and ensure all call sites are updated.
- Source-of-truth edit first, always:
  - update `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/` only
  - then sync into Xcode build copy
  - never hot-fix only inside `/Users/kanarupan/workspace/xcodeProj/`
- Installation is blocked until tests pass:
  - run simulator test suite
  - only then build/install on device
- Camera preview specific guardrail:
  - canonical path is shared preview-layer ownership (`CameraPreview(previewLayer: ...)`)
  - reintroducing stale `CameraPreview(session: ...)` call sites is a release blocker.

---

## The Loop

Every piece of work. Every time. In order.

### 1. UNDERSTAND
Read the requirement completely. Restate it. If outcome/behavior is unclear, **stop and ask**. If only the process is unclear, do not ask — derive it from docs and continue. Write down what you don't know. → **Sync docs.**

### 2. RESEARCH
Prior art, constraints, known patterns. Form a **hypothesis** before touching anything. → **Sync docs** with the hypothesis.

### 3. EXPERIMENT
Validate with the real thing — `curl`, not hoping. Record **exact** inputs and outputs. → **Sync docs** with the verified result.

### 4. VERIFY
Does the result match the hypothesis? If not, update and re-run. Never proceed on broken assumptions. → **Sync docs**: VERIFIED or DISPROVED, with evidence.

### 5. PLAN
Design from **verified findings only**. Smallest slice that proves the approach. **Every estimate = code + tests + doc sync** — no exceptions. If the user did not request an approval gate, proceed autonomously and report progress.

### 6. TIDY FIRST
Tidy the code you're about to touch. Structural changes separate from behavioral changes. Commit tidying separately.

### 7. TEST FIRST
Failing test from verified findings. **Red.** Minimum code to pass. **Green.** Refactor. **Red → Green again.** Code is a translation of what you already proved.

### 8. IMPLEMENT
One thing at a time. Small commits. Readable by a stranger. No dead code, no commented-out code, no TODOs without a GitHub issue or `research/README.md` open question (Q1-Qn). If it's getting complex, go back to step 5. → **Sync docs.**

### 9. VERIFY AGAIN
Full test suite. Manual check against spec. If it doesn't match, fix it now.

### 10. DOCUMENT
Final sync. Docs describe **what is** — not what was, not what might be. Code changed → docs changed. No exceptions.

---

## The Experiment Pattern

```
Hypothesis → Experiment → Verify → Sync Docs → then Code
```

**Example — Gemini API integration:**
1. **Hypothesis**: Gemini 3 Flash accepts multimodal input via REST with base64 frames.
2. **Experiment**: `curl` the endpoint. Record exact request + response.
3. **Verify**: Response has expected data, latency within bounds.
4. **Sync docs**: Log the working command, formats, and latency.
5. **Code**: Translate the verified interaction into production code with tests.

Never write integration code from API docs alone. Prove it works first.

---

## Git as Project Journal

`git log` tells the story of why this project is the way it is.

- **Subject**: what changed.
- **Body**: why it changed, what was verified, what it connects to.
- **Read log before starting work.** `git log --oneline -15` for general context, `git log --oneline -10 -- <path>` when working on a specific area. Understand what was done and why before adding to it.
- Small commits. Each one self-contained and honest.

### Multi-Agent Conventions

Multiple agents (Claude Code, Codex) work on this repo concurrently.

- **Claude Code**: default commit prefix (e.g. `fix:`, `feat:`, `docs:`)
- **Codex**: commits prefixed with `codex:` (e.g. `codex: add session resumption handle`)
- **Before starting work**: always pull latest and read recent commits from all agents
- **Conflicts**: if your change touches a file another agent recently modified, re-read the file before editing
- **iOS source of truth**: `/Users/kanarupan/workspace/wellbowled.ai/ios/wellBowled/` — sync to Xcode project before building

---

## Keeping Docs Alive

- Sync at every step transition — not just at the end.
- Docs must never contradict each other. If updating one creates a conflict, fix both immediately.
- Stale docs are worse than no docs. If it's not current, it's a lie.
- Docs describe **what is**. Git log describes **how we got here**.

**Minimum doc sync per step:**
- UNDERSTAND: what the requirement is, what's unclear
- RESEARCH: hypothesis, prior art found, constraints identified
- EXPERIMENT: exact command/script, exact output, pass/fail
- VERIFY: VERIFIED or DISPROVED + evidence (link to result file)
- PLAN: approach, scope, what's deferred
- IMPLEMENT: what changed, why, what was tested

---

## For AI Agents

You are bound by this process.

1. **State your step.** UNDERSTAND / RESEARCH / EXPERIMENT / VERIFY / PLAN / TIDY / TEST / IMPLEMENT / DOCUMENT.
2. **Do not skip.** No understanding → no plan. No experiment → no code.
3. **No process questions to user.** If uncertainty is about workflow, resolve it from docs/tooling/history and continue.
4. **Show your work.** What you found, what you concluded, why.
5. **Sync docs at every transition.** Learn something → write it down → then move on.
6. **No contradictions.** Cross-check docs before and after changes.
7. **Challenge yourself.** "What could be wrong here?" If you can't answer, look harder.
8. **Be honest.** "I don't know" beats a confident guess.
9. **Read git log first.** Understand history before adding to it.
10. **Escalate only hard blockers.** Ask only for product-direction or access blockers after showing failed attempts and evidence.
11. **Push back.** If instructions are unclear, contradictory, or low quality — say so. If the user is making hasty decisions, flag it. If they need rest, tell them. You are a partner, not a yes-machine.
