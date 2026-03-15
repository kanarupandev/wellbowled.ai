# Plan: Single Agentic Loop Mode

**Goal:** Remove explicit free/challenge mode switching. The buddy operates as a single intelligent agent — it can suggest challenges, drills, free bowling, or anything else naturally through conversation. No mode toggle, no `switch_session_mode` tool.

## What stays
- `end_session` tool — buddy can end the session via tool call
- Challenge evaluation pipeline — when buddy sets a challenge via conversation + system detects delivery, analysis still evaluates it
- System prompt with challenge examples — buddy suggests challenges conversationally
- All pipeline events (`[CLIP READY]`, `[ANALYZING]`, `[ANALYSIS COMPLETE]`) fed to buddy
- Analysis feedback loop — results sent back for spoken debrief

## What gets removed

### 1. GeminiLiveService.swift
- Remove `switch_session_mode` from `mateTools` tool declarations (keep `end_session` only)
- Remove `case "switch_session_mode"` handler from `handleToolCall`
- Simplify `sendToolResponse` — remove `status` and `mode` params (only `end_session` uses it)
- Simplify `LiveFunctionResponsePayload` — remove `mode` field

### 2. Protocols.swift
- Remove `voiceMate(didRequestModeSwitch:)` from `VoiceMateDelegate`
- Remove its default extension implementation

### 3. SessionViewModel.swift
- Remove `switchSessionMode(to:)` method entirely
- Remove `voiceMate(didRequestModeSwitch:)` implementation
- Session always starts in `.freePlay` mode (single mode)
- Remove mode-conditional logic in `startSession` (no `if mode == .challenge` branch)
- Simplify `maybeSendProactiveGreetingIfNeeded` — remove mode/challenge context strings
- Keep challenge engine for when buddy conversationally sets targets (future wire-up)
- Remove `session.mode == .challenge` guards in delivery detection and deep analysis — challenges are tracked by `challengeTargetBySequence` regardless of mode

### 4. WBConfig.swift
- Remove `TOOLS` section referencing `switch_session_mode`
- Keep `end_session` tool reference
- System prompt already has challenge examples — no change needed there

### 5. UI (LiveSessionView or similar)
- Check if there are mode toggle buttons in the UI — remove them if present
- Session starts directly, no mode selection

## What this achieves
- Single conversation loop: buddy greets → observes → coaches → suggests challenges → debriefs → wraps up
- No explicit mode toggling breaks the conversational flow
- The buddy is the brain — it decides when to challenge, when to observe, when to coach
- Simpler codebase — fewer states, fewer tools, fewer edge cases
