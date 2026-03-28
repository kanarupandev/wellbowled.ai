# Next Potential TODO — Wow Strategy for Gemini Live Hackathon

Date: 2026-03-13
Branch context: `codex/dev`

## 1) Core Product Doctrine (Non-negotiable)
Gemini audio is **GUIDE LAYER**, not measurement layer.

- Gemini audio: onboarding, coaching, motivation, navigation, commentary, drill planning.
- Deterministic CV pipeline (MediaPipe/YOLO/OpenCV/rule engine): detection, localization, scoring, confidence.
- Never present LLM speech as measured fact unless backed by deterministic signals.
- UI and voice must clearly separate:
  - measured facts
  - coaching suggestions

## 2) Hackathon-Winning Hypothesis
The winning story is not "we detect everything perfectly live." 
The winning story is: **"The first real-time bowling expert buddy that makes training feel human, immediate, and trustworthy."**

What judges should feel in <60 seconds:
- "This is alive" (natural proactive voice companion).
- "This is useful" (actionable setup and execution guidance).
- "This is credible" (confidence-aware, no fake certainty).
- "This is sticky" (post-session debrief and next-ball plan).

## 3) Wow-Factor Pillars

### Pillar A: Live Field Buddy (Gemini Live Audio)
- Greets and asks plan in natural speech.
- Guides setup in short, event-driven prompts.
- Runs a waterfall interaction:
  - greet
  - plan
  - setup check
  - pilot run
  - session start

### Pillar B: Confidence-Aware Coaching
- Voice only says "ready" when detector confidence is truly ready.
- If uncertain: specific correction only (distance, angle, framing, lighting).
- System says "unscorable" when quality is insufficient instead of pretending.

### Pillar C: Challenge Theater (High Demo Impact)
- Buddy gives challenge target with cricket language.
- Challenge is attached to next delivery deterministically.
- After ball: expectation vs actual + confidence + short spoken debrief.

### Pillar D: Multi-Layer Insight Experience
- Fast delivery clips first (instant gratification).
- Deep analysis on demand (no forced wait).
- Spoken expert wrap-up and next 3-ball drill plan.

### Pillar E: Trust by Design
- Show confidence/reason codes.
- Preserve full-session replay.
- Transparent fallback states (not detected, low confidence, retry guidance).

## 4) 4-Minute Demo Choreography (3 min live + 1 min results)

### 0:00-0:20 — Cold Open
- App opens with energetic bowling whizz + clear mode label.
- Buddy: "What are we working on today?"

### 0:20-1:00 — Setup Intelligence
- Buddy asks to show stumps and stance area.
- Overlays appear (stump boxes/dots/guide lines).
- Buddy confirms readiness only after stable confidence.

### 1:00-2:40 — Live Session
- Buddy gives challenge (example line/length target).
- User bowls.
- Buddy gives concise in-session prompts between deliveries only.
- Session end by button or voice command.

### 2:40-3:20 — Delivery Results Transition
- Auto-navigate to full replay + real telemetry for detection/clipping progress.
- Auto-transition to side-swipe delivery carousel when ready.

### 3:20-4:00 — Deep Insight + Voice Debrief
- Select a delivery.
- Run deep analysis.
- Show phase insights + DNA match + (when available) pose overlay.
- Buddy summarizes: strengths, top fix, next 3-ball drill.

## 5) Guide-Layer Features by Stage

### Before Recording
- Intent capture: "pace, line/length, or action rhythm today?"
- Camera readiness checklist via voice + visual status.
- Stump visibility gating for challenge mode.
- Pilot run confirmation.

### During Recording
- Event-only prompts (no chatter).
- Focus prompts: wrist, landing foot, follow-through.
- Safety reminders for repeated unstable patterns.
- Natural reprompt if user silent after key question.

### Clip Page (Post Session)
- Voice triage: "Analyze best 3 first?"
- Voice commands: `analyze this`, `next clip`, `repeat summary`.
- Explain why certain clips are low confidence.

### During Deep Analysis
- Real processing telemetry only.
- Keep user engaged with meaningful progress bullets.
- If delayed: steady "Analyzing..." state, no fake milestones.

### After Analysis
- 20-30s spoken debrief.
- Priority fixes only (max 2-3).
- Next 3-ball plan with explicit goal.
- Optional mode switch suggestion (`challenge` <-> `free`).

## 6) Challenge Mode Implementation Blueprint (Deterministic Core)

### Stage 1: Stump Calibration + Overlay
- Add calibration stage before challenge session.
- Detect both stumps with YOLO/CoreML/OpenCV.
- Render:
  - stump boxes
  - centerline and reference dots
  - readiness/confidence badge
- Gemini audio reads detector state and instructs camera adjustments.

### Stage 2: Pitch-Plane Mapping
- Compute homography from stump landmarks to pitch coordinates.
- Encode challenge targets into coordinate zones:
  - handedness
  - line (for example 5th/6th stump proxy zones)
  - length (yorker/good/back of length)

### Stage 3: Challenge Binding
- Spoken challenge creates `pendingChallenge`.
- `pendingChallenge` binds to next detected `delivery_id`.
- Persist in delivery metadata.

### Stage 4: Expectation vs Actual Scoring
- Detect ball path/impact with deterministic CV.
- Compute line/length error + tolerance window.
- Output:
  - score
  - confidence
  - reason codes
- If uncertain: mark `unscorable`, give retry coaching.

## 7) "Wow" UX Details That Matter
- Very short voice responses (human, not robotic).
- Fine-print but clear mode indicator top-left.
- One-tap save full session to Photos.
- Zero dead-end pages: always clear next action.
- No abrupt nav jumps while swiping/reading.
- Keep portrait-first behavior stable.

## 8) Judging-Oriented Priorities (What to maximize)

### A) Gemini Live API Showcase
- Continuous, context-aware voice buddy across session lifecycle.
- Tool-call based mode switch + navigation actions.

### B) Practical Value
- Setup quality improvement before first ball.
- Concrete next-ball fixes after analysis.

### C) Technical Rigor
- Deterministic scoring with confidence.
- Transparent failure handling.

### D) Product Polish
- Smooth transitions.
- Fast feedback.
- Clear visual hierarchy.

## 9) Prioritized Build Backlog (Impact First)

### P0 (Must ship for strong demo)
1. Stump calibration state + overlays + readiness gate.
2. Pending challenge binding to next delivery.
3. Deterministic challenge scoring skeleton with `unscorable` fallback.
4. Voice debrief template (strengths + top fix + 3-ball plan).
5. Real telemetry transition page (full replay while detection finalizes).

### P1 (High-value enhancer)
1. Multi-angle ingestion and fused deep analysis prompt.
2. Confidence-aware spoken explanations.
3. Better voice command grammar for clip navigation.

### P2 (Stretch / post-hackathon)
1. Advanced ball trajectory and speed confidence model.
2. Full wicket/crease calibration automation.
3. Longer-term skill progression coaching memory.

## 10) Test and Reliability Gates
- Unit tests for:
  - challenge binding logic
  - scoring math and tolerances
  - confidence gating
  - unscorable transitions
- Guardrails:
  - if calibration unstable -> block challenge scoring
  - if ball not visible -> no fake score
- Regression checks before install:
  - camera preview path
  - navigation state
  - mode switching

## 11) Acceptance Criteria for "Wow + Trust"
- Buddy feels proactive and helpful in first 20 seconds.
- Setup guidance measurably improves framing readiness.
- Challenge target is traceably attached to specific delivery.
- Score output always includes confidence and reason.
- Deep analysis produces actionable spoken fixes.
- System never hallucinates measurement certainty.

## 12) Notes from Discussion (Preserved)
- Multi-angle clips can be sent together for richer analysis.
- Gemini audio can provide commentary and fixes after analysis.
- Challenge prompts are valid.
- Challenge judging must remain deterministic.
- Guide layer, not measurement layer, remains core principle.
