# Demo Script — 3:00 (Recording, Not Live)

Video limit: 3 minutes. Only the first 3 minutes are evaluated.
Rule: Show product, not talking heads. Make Gemini role explicit.

---

## 0:00–0:10 — Hook (10s)

**Screen:** App on camera view, ready to bowl.
**Voiceover:**
> "A solo bowler at the nets has no expert watching. No feedback, no pressure, no direction.
> wellBowled changes that — Gemini Live becomes your bowling mate."

---

## 0:10–0:25 — Session Starts, Mate Greets (15s)

**Screen:** Tap start. Gemini Live connects. Mate speaks through earbuds.
**Show:**
- Connection indicator turns green
- Mate greets naturally, asks what to work on, asks how long
- Mate calls `set_session_duration` → timer appears on screen

**Voiceover:**
> "The mate sees your live video and hears you. It sets the session timer through a tool call — fully agentic."

---

## 0:25–0:55 — First Delivery + Feedback (30s)

**Screen:** Bowl a delivery. Count "1" flashes with glow animation.
**Show:**
- Delivery detected from video by Gemini Flash
- TTS announces count
- Mate gives one specific biomechanical cue (e.g. "Front knee collapsed — brace harder through the crease")

**Voiceover:**
> "Delivery detected automatically from the video stream. The mate already saw it live — gives one specific technical cue. Not a template. A real observation."

---

## 0:55–1:30 — Challenge Mode (35s)

**Screen:** Mate suggests challenge → calls `set_challenge_target` → banner: "Target: Yorker on off stump"
**Show:**
- Challenge banner appears with pulsing scope icon
- Bowl again. Count "2" flashes.
- Analysis evaluates hit/miss. Mate announces result.
- Score updates: "1/1 (100%)" or "0/1 (0%)"
- Next target auto-rotates. Bowl again.
- Score updates: e.g. "1/2 (50%)"

**Voiceover:**
> "The mate drives the session with challenges — sets targets through tool calls, evaluates each delivery with a separate Gemini API call, tracks your score. This is the coaching loop: target, bowl, evaluate, score, next."

---

## 1:30–2:00 — Deep Analysis Card + DNA (30s)

**Screen:** Tap into delivery result. Show the analysis view.
**Show:**
- 5-second clip playing
- Speed badge (e.g. "~118 ±4 kph")
- Phase breakdown: green (good) and red (needs work) bullets
- Swipe to DNA match: similarity ring (e.g. "54% — Mitchell Starc"), quality-dampened
- Quality rating visible

**Voiceover:**
> "Every delivery gets a 5-second clip analyzed by Gemini 3 Pro — biomechanical phases, pace estimate, execution quality, and bowling DNA. Matched against 100 international bowlers. Quality dampener ensures honest scores — a recreational bowler won't get 90% match with the greats."

---

## 2:00–2:30 — Review Agent + Voice Playback (30s)

**Screen:** Session ends. Review agent connects. Carousel of deliveries.
**Show:**
- Mate walks through delivery: "Your best ball was delivery 2 — let me show you the release"
- `control_playback` tool call: video seeks to release point
- "Slow mo" → playback slows to 0.25x
- `navigate_delivery` → swipes to next delivery

**Voiceover:**
> "After the session, a fresh review agent takes over with all analysis baked in. The bowler controls playback by voice — hands-free. Two separate Gemini agents with distinct lifecycles."

---

## 2:30–2:50 — Architecture (20s)

**Screen:** Architecture diagram overlay.
**Show:**
```
Phone → Gemini Live (voice + video stream)
     → Gemini Flash (delivery detection + challenge eval)
     → Gemini Pro (deep analysis + DNA + quality)
```

**Voiceover:**
> "3 Gemini models. The Live API mate uses 5 tool calls to operate the app — timer, challenges, session end, delivery navigation, and video playback. Delivery detection runs on 30-second rolling segments. Deep analysis runs on 5-second clips with execution quality rating."

---

## 2:50–3:00 — Close (10s)

**Screen:** Back to app showing session results.
**Voiceover:**
> "Real-time voice coaching, automatic delivery detection, expert biomechanical analysis, and challenge-driven training — all from one app, all powered by Gemini. Gemini isn't a feature. It is the product."

---

## Recording Tips
- Record on physical iPhone, screen capture via QuickTime or built-in recorder
- Use earbuds for mate audio — capture both screen + mate voice
- Do 3-4 takes, pick the one with best mate responses
- If mate says something great, keep it — authentic responses beat scripted ones
- Cut pauses between deliveries — judges don't need to watch you walk back to your mark
- Overlay voiceover in post-production if needed, or narrate live
