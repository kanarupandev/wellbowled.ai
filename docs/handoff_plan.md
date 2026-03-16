# Handoff Plan — codex/dev 2026-03-16

## What Was Done (This Session)

### Speed Estimation Honesty (committed + pushed)
1. `speedErrorMarginKph` added to `Delivery` model (Codable, Equatable)
2. Frame-math margin ≥ 5 kph → speed suppressed entirely (not shown)
3. Gemini deep analyzer returns `speed_confidence` (0.0-1.0) — visual assessment of ball visibility, camera angle, stump alignment
4. If Gemini confidence < 0.4 → speed suppressed post-analysis
5. UI badge shows `120 ±3 kph` format (not exact)
6. All mate context messages say "estimated" and "video-based, not radar"
7. Mate uses pace brackets (60-80, 80-100, 100-120, 120-140) — never exact radar claims

### Earlier (same session)
- Live API keepalive (WebSocket ping every 15s)
- False disconnect fix (undecodable messages no longer trigger reconnect)
- Dynamic session timer (mate asks "how long?", sets via tool call)
- API timeouts (60s detection, 120s deep analysis)
- Failure notifications to live agent
- DNA string normalization
- Stump calibration: front-on positioning, dashed guide boxes
- Exponential backoff reconnect

## Pending / TODO for Next Agent

### P0 — Must Do
1. **MediaPipe broken** — user reported "I don't see the mediapipe". Pose overlay not displaying. Investigate `MediaPipePoseService` and the overlay rendering path. The simulator build fails with MediaPipe linker errors too.
2. **Commit `deploy.sh`** — script at repo root, already created, needs `git add deploy.sh && git commit`

### P1 — Should Do
3. **Speed badge in SessionResultsView** — check if the results/review screen also shows speed. If so, update to use `±X` format and suppress when nil.
4. **Test the Gemini `speed_confidence` field** — add a unit test that parses a deep analysis JSON response containing `speed_confidence` and verifies it's clamped 0-1.
5. **Review codex agent commit `4c3dcc3`** — "fix static analysis findings — retain cycle, force unwraps, lock safety, data race". Should be audited for correctness.

### P2 — Nice to Have
6. **Speed trend chart** — since speed is now bracket-level, a visual trend line across the session would be useful.
7. **Stump alignment confidence feedback** — the dashed guide boxes exist but there's no detector feedback ("stumps aligned" / "move left"). This requires the stump detection pipeline to be wired.

## Branch State
- Branch: `codex/dev`
- Latest commit: `63d5899` (claude: Gemini speed confidence + pace brackets)
- All changes pushed to origin
- Build: succeeds on physical device, simulator fails (MediaPipe linker — pre-existing)
