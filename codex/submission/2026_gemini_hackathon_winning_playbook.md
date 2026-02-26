# 2026 Gemini API Hackathon Winning Playbook

Last verified: 2026-02-26
Scope: Practical guidance for a winning submission to the Gemini 3 Hackathon on Devpost.

## 1) What judges score (optimize for this, not vibes)
Stage Two weighted criteria from official rules:
- Technical Execution: **40%**
- Innovation/Wow Factor: **30%**
- Potential Impact: **20%**
- Presentation/Demo: **10%**

Implication:
- If your app is beautiful but unstable, you lose.
- If your app is technically strong but boring/non-novel, you cap out.
- Demo quality matters, but it cannot rescue weak execution.

## 2) Baseline eligibility (Stage One) - must pass
You need all of these to avoid pass/fail rejection:
1. New app built during contest period, using Gemini 3 API centrally.
2. Public project/demo link (no paywall/login; if private, provide credentials).
3. Public code repo (or AI Studio app link as allowed).
4. English submission materials.
5. Demo video showing real product behavior, <= 3 minutes.
6. Submission text describing Gemini integration and features.

Judges may rely only on your text + images + video and may not run your app.

## 3) Winning criteria translated into action
### A) Technical Execution (40%)
Ship reliability first:
- No broken primary flow in demo.
- Handle error states visibly (network drop, rate limit, model timeout).
- Make Gemini usage central and non-superficial.
- Use structured output for deterministic UI rendering and parsing.
- Show real performance characteristics honestly (no fake “instant” cuts).

### B) Innovation/Wow Factor (30%)
Avoid generic wrappers:
- “Chatbot for X” is weak unless there is unique interaction/design.
- Prioritize one signature capability that feels unmistakably new.
- For your concept: live audio feedback + phase-aware jump chat + bowling DNA matching is a strong novelty stack.

### C) Potential Impact (20%)
Make impact quantifiable:
- Name exact user segment and pain point.
- Add measurable value metrics (time saved, error reduction, engagement).
- Include immediate real-world use case and adoption path.

### D) Presentation/Demo (10%)
Narrative must be surgical:
- First 10-15 seconds: problem and target user.
- Show the end-to-end “magic moment” early.
- Narrate what Gemini does vs what local/on-device logic does.
- Close with proof of functionality and why this can scale.

## 4) What judges usually expect to see in the demo
1. Clear before/after user pain.
2. Real product interaction (not slides only).
3. Gemini integration visibly central to product behavior.
4. Working loop, not just one isolated API call.
5. Reliability and fallback behavior.
6. Clear architecture explanation (simple diagram is enough).

## 5) Trendy modern UI that still scores
Use modern expression without hurting clarity:
- Follow Material 3 Expressive direction for motion/typography/visual hierarchy.
- Keep high contrast and readable information density.
- Use motion to reduce perceived latency (progressive disclosure, skeleton states).
- Keep interaction “alive” at all times: progress ring, live cue chips, haptics, immediate placeholders.

Anti-patterns:
- Over-animated hero screens with slow task completion.
- Neon gradients with poor readability.
- Hidden state changes (user wonders if system is working).

## 6) Submission package that wins
Your Devpost package should be judge-friendly:
1. 200-word concise summary (problem, users, Gemini role, outcome).
2. 3-minute demo video with real app footage.
3. Public repo with quickstart and architecture diagram.
4. Public prototype link (or test credentials).
5. Explicit section: “How Gemini is central to this app.”
6. Explicit section: “Known limitations and next steps.”

## 7) High-probability reasons teams lose
- Gemini used as an afterthought.
- Demo shows concept but not working product.
- Video spends too long on intro branding.
- No fallback path; one runtime issue kills trust.
- Submission missing public access details.
- Claims exceed what is shown.

## 8) Recommended scoring target before submission
Internal pre-judge target:
- Technical Execution: >= 4.5/5
- Innovation/Wow: >= 4.3/5
- Potential Impact: >= 4.0/5
- Presentation/Demo: >= 4.5/5

If any criterion < 4, fix that before polish work.

## 9) Final advice for your specific project
For your bowling assistant concept, winning angle is:
- Live API-first experience (audio coaching loop) as the headline.
- 5s rich-clip deep analysis for actionable insights.
- Phase timeline + jump-chat for explainability.
- Signature matching as “advanced differentiator,” not core dependency.

If time-constrained, cut in this order:
1. Keep: live loop + clip + one great analysis card.
2. Keep: phase jump-chat if stable.
3. Optional: DNA vector matching if quality is high; otherwise ship as roadmap.
