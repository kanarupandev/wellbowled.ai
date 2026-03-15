# Plan: Single Agentic Loop Mode

**Goal:** Remove explicit free/challenge mode switching. The buddy operates as a single intelligent agent — it can suggest challenges, drills, free bowling, or anything else naturally through conversation. No mode toggle, no `switch_session_mode` tool.

**Status: COMPLETE** — all items implemented and deployed to device.

## What stays
- [x] `end_session` tool — buddy can end the session via tool call
- [x] Challenge evaluation pipeline — when buddy sets a challenge via conversation + system detects delivery, analysis still evaluates it
- [x] System prompt with challenge examples (10 action-only + 5 ball-tracking) — buddy suggests challenges conversationally
- [x] All pipeline events (`[CLIP READY]`, `[ANALYZING]`, `[ANALYSIS COMPLETE]`) fed to buddy
- [x] Analysis feedback loop — results sent back for spoken debrief

## What gets removed

### 1. GeminiLiveService.swift — DONE
- [x] Remove `switch_session_mode` from `mateTools` tool declarations (keep `end_session` only)
- [x] Remove `case "switch_session_mode"` handler from `handleToolCall`
- [x] Simplify `sendToolResponse` — remove `status` and `mode` params
- [x] Simplify `LiveFunctionResponsePayload` — remove `mode` and `status` fields

### 2. Protocols.swift — DONE
- [x] Remove `voiceMate(didRequestModeSwitch:)` from `VoiceMateDelegate`
- [x] Remove its default extension implementation

### 3. SessionViewModel.swift — DONE
- [x] Remove `switchSessionMode(to:)` method entirely
- [x] Remove `voiceMate(didRequestModeSwitch:)` implementation
- [x] Session always starts in `.freePlay` mode (single mode)
- [x] Remove mode-conditional logic in `startSession` (no `if mode == .challenge` branch)
- [x] Remove `mode` parameter from `startSession()`
- [x] Simplify `maybeSendProactiveGreetingIfNeeded` — remove mode/challenge context strings
- [x] Remove waterfall phases (greeting/planning/pilotRun) — only `.starting` and `.active`
- [x] Remove `hasPilotRun`, `hasBowlerPlanResponse`, `proactiveRepromptTask`
- [x] Add analysis feedback loop — send structured results to buddy via `sendContext()`
- [x] Add pipeline events: `[CLIP READY]`, `[ANALYZING]`, `[ANALYSIS COMPLETE]`
- [x] Implement `voiceMate(didRequestEndSession:)`
- [x] Clean up `didTranscribeUser` — remove waterfall checks
- [ ] Future: wire buddy's conversational challenge targets into `challengeTargetBySequence`

### 4. WBConfig.swift — DONE
- [x] Remove `switch_session_mode` from TOOLS section
- [x] Keep `end_session` tool reference
- [x] System prompt rewritten: autonomous coach, no waterfall, no scripted phases
- [x] Challenge examples added (10 action-only + 5 ball-tracking with setup guidance)
- [x] Persona styles simplified (Aussie, English, Tamil, Tanglish)

### 5. HomeView.swift — DONE
- [x] Remove mode picker (Free Play / Challenge cards)
- [x] Remove `selectedMode` state
- [x] Remove `ModeOptionCard` struct
- [x] Single "Start Live Session" button
- [x] Simplified session description text

### 6. LiveSessionView.swift — DONE
- [x] Remove `initialMode` parameter and init
- [x] Remove mode-conditional auto-start logic
- [x] Simplify `isChallengeSession` computed property

### 7. BowlingDNAMatcher.swift — DONE (simplify)
- [x] Cache pre-encoded bowler vectors as lazy static (103 bowlers encoded once)
- [x] Remove duplicate `BowlingDNAMatcher.match` call in analysis feedback loop

### 8. FamousBowlerDatabase.swift — DONE
- [x] Expanded from 12 to 103 bowler profiles with researched DNA

## What this achieves
- Single conversation loop: buddy greets → observes → coaches → suggests challenges → debriefs → wraps up
- No explicit mode toggling breaks the conversational flow
- The buddy is the brain — it decides when to challenge, when to observe, when to coach
- Simpler codebase — fewer states, fewer tools, fewer edge cases (-182 lines net)
- Closed feedback loop: analysis results → buddy → natural spoken debrief
