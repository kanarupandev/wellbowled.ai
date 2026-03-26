# Speed Gradient Trail — Quality Gate

## MANDATORY: All must pass before ANY output is shown to user.

### A. BOWLER ISOLATION (instant fail if any check fails)
- [ ] A1. Skeleton overlay is on the BOWLER, not any other person, in EVERY frame
- [ ] A2. Zero frames where background person has any annotation
- [ ] A3. Wrist velocity badge is on the bowler's wrist, not anyone else's
- [ ] A4. If bowler can't be isolated, output NOTHING rather than wrong output

### B. ACCURACY (instant fail)
- [ ] B1. Wrist is the fastest joint at release (physics requirement)
- [ ] B2. Distal joints faster than proximal: Wrist > Forearm > Trunk > Hips
- [ ] B3. Peak velocities are within delivery window, not run-up or follow-through
- [ ] B4. Same clip produces identical output on 2 consecutive runs
- [ ] B5. Velocity numbers are plausible (no 0% wrist at release, no 100% hips at standstill)

### C. VISUAL CLARITY (must be obvious to a non-cricketer)
- [ ] C1. Color difference between fast and slow joints is OBVIOUS at phone size
- [ ] C2. The energy "flowing up the body" is visible during slo-mo playback
- [ ] C3. At peak frame, wrist/forearm should be visibly RED while hips are visibly BLUE
- [ ] C4. Skeleton is clean — no jitter, no jumping between people
- [ ] C5. Background is dimmed enough to make colors pop but video is still recognizable
- [ ] C6. Legend (slow→fast color bar) is readable
- [ ] C7. Wrist percentage badge is readable at phone size (28px+ font)

### D. VIDEO STRUCTURE
- [ ] D1. Title card explains what to watch for
- [ ] D2. Slo-mo shows the full delivery stride with colors changing
- [ ] D3. Pause at peak energy — dramatic moment, clearly labeled
- [ ] D4. Verdict card shows kinetic chain bar chart — each segment's contribution
- [ ] D5. Chain sequencing verdict is correct for this bowler
- [ ] D6. End card readable

### E. SELF-REVIEW PROCESS
- [ ] E1. Extract frames at 0%, 25%, 50%, 75% and VIEW each one
- [ ] E2. Confirm bowler (not background) has overlay in EVERY analysis frame
- [ ] E3. Confirm colors change visibly between frames (not all same color)
- [ ] E4. Confirm verdict matches the visual (if "ELITE CHAIN", the bars should show correct order)
- [ ] E5. Run ffprobe: 1080x1920, H.264, 30fps, >15s

## TOTAL: 27 checks. ALL must pass.
