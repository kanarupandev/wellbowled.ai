# Live Buddy Value Contract (Canonical)

**Date**: 2026-03-05  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Status**: Product decision record

---

## 1. Core Decision

Conversational hints are valuable only when they are **event-grounded**.

If live delivery detection is not reliable/low-latency, the buddy becomes generic chat and loses core value.

---

## 2. Real Value of Live Audio Buddy

The live buddy must deliver all three:
1. **Hands-free workflow control**:
   - greet, plan, setup verification, pilot run, mode switches, session control.
2. **Event-grounded next-ball cues**:
   - short actionable feedback after a detected delivery.
3. **Adherence and consistency loop**:
   - keeps bowler in a structured high-quality repetition flow.

Without event grounding, value drops to convenience/morale support only.

---

## 3. Guardrails

1. Do not present generic voice output as ball-specific coaching.
2. Ball-specific live hints require high detection confidence.
3. If confidence is low:
   - switch to non-ball-specific guidance
   - optionally request manual cue (`"ball done"` voice cue or tap).
4. Always keep claims honest:
   - no deterministic per-ball live precision claim unless validated by metrics.

---

## 4. Success Criteria for Event-Grounded Live Mode

Target operational metrics (real net sessions):
1. detection lag p95 `<= 2s`
2. delivery recall `>= 90%`
3. delivery precision `>= 90%`.

If these are not met, live mode should be positioned as:
1. session planning + control
2. motivational/coaching conversation
3. post-session analysis remains primary technical feedback channel.

---

## 5. Implementation Direction

Preferred architecture:
1. on-device live detector for immediate triggers
2. secondary post-session detector for recovery/correction
3. merged timestamp confidence model.

This keeps live UX responsive while preserving reliability.
