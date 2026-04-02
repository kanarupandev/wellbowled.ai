# Content Pipeline — End to End

## The System

```
INPUT                    PROCESSING                         OUTPUT
-----                    ----------                         ------

[Raw Footage]  -->  [1. Source]  -->  [2. Script]  -->  [3. Visuals]  -->  [4. Audio]  -->  [5. Assembly]  -->  [Final Clip]
                         |                |                  |                |                  |
                     Where do I       What story         What does        What does         How does it
                     get footage?     am I telling?      it look like?    it sound like?    come together?
```

---

## The 5 Nodes

### Node 1: SOURCE — Getting the footage

**V1 (now):** YouTube clips of Dale Steyn bowling (fair use for analysis/education)
**V2:** Screen record from official cricket boards' free highlights
**V3:** Film your own sessions + intercut with pro footage for comparison
**Future:** Partnerships with cricket boards, licensed footage

Key question: What footage gives the most analytical value per second?

---

### Node 2: SCRIPT — The analysis thinking

**V1 (now):** You write 5-7 sentences manually. What's the ONE insight?
**V2:** Feed clip to Gemini API -> get biomechanical breakdown -> edit into script
**V3:** Script templates per content type (technique breakdown, comparison, drill)
**Future:** Fully automated: footage in -> Gemini writes script -> you approve

This is the MOST IMPORTANT node. A bad script with great visuals = forgettable.
A great script with basic visuals = shareable.

The script IS the analysis. Everything else is packaging.

---

### Node 3: VISUALS — What the viewer sees

**V1 (now):** CapCut speed ramps + text overlays + freeze frames. Manual, 15 min.
**V2:** Python skeleton overlay + angle lines on key frames. Semi-automated.
**V3:** Full pipeline: pose estimation + ball tracking + trails + phase labels. Automated.
**Future:** Real-time rendering, interactive web viewer

Sub-nodes (each independently improvable):

```
3a. Skeleton overlay     [none] -> [MediaPipe basic] -> [styled/colored by phase]
3b. Angle measurements   [none] -> [manual lines]    -> [auto elbow/shoulder/hip angles]
3c. Slow motion          [none] -> [iPhone 240fps]   -> [RIFE AI interpolation]
3d. Ball tracking        [none] -> [manual highlight] -> [YOLO + glow trail]
3e. Side-by-side compare [none] -> [manual split]    -> [synced dual skeleton]
3f. Text overlays        [CapCut manual] -> [templated] -> [auto-generated from script]
3g. Transitions          [hard cuts] -> [phase labels] -> [animated phase transitions]
```

---

### Node 4: AUDIO — What the viewer hears

**V1 (now):** Your own voice narrating over the clip. Authentic. 5 min to record.
**V2:** ElevenLabs AI voice from script text. Consistent quality. 1 min to generate.
**V3:** Your voice + ambient net session sounds + subtle music bed
**Future:** Choose voice style per content type (hype vs analytical vs coaching)

Sub-nodes:

```
4a. Voice-over      [your voice] -> [AI voice] -> [branded voice clone]
4b. Music bed       [none] -> [CapCut library] -> [curated per mood]
4c. Sound effects   [none] -> [ball hitting bat/pad] -> [timed to video]
4d. Captions        [none] -> [CapCut auto] -> [styled word-by-word]
```

---

### Node 5: ASSEMBLY — Putting it all together

**V1 (now):** CapCut. Import video, add text, add voice, export. 10 min.
**V2:** DaVinci Resolve template. Drag in assets, adjust timing. 8 min.
**V3:** FFmpeg script. Takes processed video + audio + captions -> renders final. 2 min.
**Future:** Fully automated. Script approved -> clip rendered -> scheduled to post.

Sub-nodes:

```
5a. Editing         [CapCut manual] -> [DaVinci template] -> [FFmpeg automated]
5b. Format export   [one format]    -> [9:16 + 16:9]      -> [per-platform optimized]
5c. Thumbnails      [auto frame]    -> [designed]          -> [AI-generated options]
5d. Publishing      [manual post]   -> [scheduled]         -> [multi-platform automated]
```

---

## Time Budget: 30 Minutes Per Clip

| Node | V1 Time | Target | How to Get There |
|------|---------|--------|-----------------|
| 1. Source | 5 min | 2 min | Maintain a footage library, pre-downloaded |
| 2. Script | 10 min | 10 min | This stays manual. It's your value-add. |
| 3. Visuals | 10 min | 8 min | Templates + one Python enhancement |
| 4. Audio | 5 min | 5 min | Record voice OR generate AI |
| 5. Assembly | 10 min | 5 min | Template-based editing |
| **Total** | **40 min** | **30 min** | |

Script stays manual because YOUR analysis insight is the differentiator.
Everything else gets automated over time.

---

## V1 Daily Workflow (Start Tomorrow)

```
Morning (or night before):
  1. Pick ONE insight about a bowler           (2 min)
  2. Find/download a clip showing it           (5 min)
  3. Write 5-7 sentences: hook, insight, CTA   (10 min)

Production:
  4. Import to CapCut, trim to key moments     (3 min)
  5. Add speed ramps (slo-mo on release)       (2 min)
  6. Add text overlays (bold insight text)     (3 min)
  7. Record voice-over on phone/Mac            (3 min)
  8. Add captions (CapCut auto)                (2 min)
  9. Export 9:16                               (1 min)

Publish:
  10. Post to Reels + TikTok + Shorts          (2 min)
```

Total: ~33 min. No code. No AI pipeline. Just start.

---

## Node Upgrade Path (Priority Order)

| Priority | Node | Upgrade | Impact | Effort |
|----------|------|---------|--------|--------|
| 1 | 2. Script | Gemini generates first draft from clip | Saves 5 min, better consistency | Low |
| 2 | 3f. Text overlays | Branded templates in CapCut | Visual consistency, saves 2 min | Low |
| 3 | 4d. Captions | Styled word-by-word captions | Massive reach boost (85% watch muted) | Low |
| 4 | 3c. Slow motion | RIFE AI interpolation script | Cinematic release point shots | Medium |
| 5 | 3a. Skeleton overlay | MediaPipe + OpenCV Python script | THE differentiator — broadcast quality | Medium |
| 6 | 4a. Voice-over | ElevenLabs from script | Consistent, no recording needed | Low |
| 7 | 3b. Angle measurements | Auto joint angle calculation | "40 degrees of separation" with proof | Medium |
| 8 | 3d. Ball tracking | YOLO + glow trail | Hawk-Eye lite — massive wow factor | High |
| 9 | 5a. Editing | FFmpeg automated assembly | Under 5 min total production | High |
| 10 | 3e. Side-by-side | Synced dual skeleton compare | Pro vs amateur is the killer format | High |

---

## The Content Moat

What makes this defensible over time:

1. **Your cricket knowledge** — AI can't replace genuine bowling insight
2. **The wellBowled.ai 23-parameter DNA model** — no one else has this framework
3. **Compound library** — 100 clips = a searchable technique encyclopedia
4. **Pipeline automation** — as nodes improve, you produce MORE with LESS time
5. **Audience trust** — consistent daily posting builds authority

The pipeline is a machine. Each node is a lever. Improve one lever at a time.
