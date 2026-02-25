# Phase 2: Configuration Optimization Results

## Winner: Config E (Default Thinking)

```
Model:       gemini-3-flash-preview
Temperature: 0.1
Thinking:    Default (no thinkingConfig — let Gemini decide reasoning depth)
File API:    Videos > 5MB
Prompt:      Simple Scout prompt (see configs.py PROMPT_CURRENT)
```

## Smoke Test Gate (3-sec nets clip, GT: 1.0s, threshold: 0.3s)

| Config | Change | Delta | Tokens | Latency | Consistent | Gate |
|--------|--------|-------|--------|---------|------------|------|
| A | temp=0.1, MINIMAL | 0.167s | 736 | 4.0s | Yes | PASS |
| B | temp=1.0, MINIMAL | 0.267s | 738 | 3.8s | No (phantoms!) | **FAIL** |
| C | schema+metadata | 0.000s | 727 | 3.8s | Yes | PASS* |
| D | downscale 480p | 0.400s | 634 | 4.2s | Yes | **FAIL** |
| E | default thinking | 0.150s | 1712 | 11.1s | Yes | PASS |

*Config C passed smoke test but failed on real videos (overfitting to short clip).

## Full Suite (5 runs each)

### Config A (MINIMAL thinking) — 4/7 PASS

| Video | Threshold | Score | Avg Delta | Tokens | Latency |
|-------|-----------|-------|-----------|--------|---------|
| Umran (broadcast) | 0.2s | 1/1 PASS | 0.163s | 1,189 | 4.8s |
| Kapil D1 (broadcast) | 0.2s | FAIL | 0.760s | — | — |
| Kapil D2 (broadcast) | 0.2s | PASS | 0.080s | 2,243 | 5.5s |
| WhatsApp D1 (nets) | 0.3s | FAIL | 0.331s | — | — |
| WhatsApp D2 (nets) | 0.3s | FAIL | 0.460s | 6,531 | 3.7s |
| WhatsApp D3 (nets) | 0.3s | PASS | 0.241s | — | — |
| WhatsApp D4 (nets) | 0.3s | PASS | 0.280s | — | — |

### Config E (Default thinking) — 6/7 PASS

| Video | Threshold | Score | Avg Delta | Tokens | Latency |
|-------|-----------|-------|-----------|--------|---------|
| Umran (broadcast) | 0.2s | 1/1 PASS | **0.057s** | 1,889 | 9.2s |
| Kapil D1 (broadcast) | 0.2s | FAIL (=0.200s) | 0.200s | — | — |
| Kapil D2 (broadcast) | 0.2s | PASS | **0.020s** | 3,210 | 11.5s |
| WhatsApp D1 (nets) | 0.3s | **PASS** | **0.051s** | — | — |
| WhatsApp D2 (nets) | 0.3s | **PASS** | **0.140s** | 7,393 | 9.6s |
| WhatsApp D3 (nets) | 0.3s | PASS | 0.221s | — | — |
| WhatsApp D4 (nets) | 0.3s | **PASS** | **0.040s** | — | — |

### Bumrah (broadcast montage — nice-to-have)

| Config | Score | Count consistency | Notes |
|--------|-------|-------------------|-------|
| A (MINIMAL) | 1/7 | [6,7,6,7] inconsistent | 0.3-0.5s early |
| E (Default) | 3/7 | [5,8,6] inconsistent | Quick cuts confuse model |

Documented as known limitation — broadcast montage with rapid scene cuts.

## Key Findings

### What helps accuracy:
1. **File API** for videos >5MB (turned WhatsApp from 0/4 → 4/4)
2. **Default thinking** (no thinkingConfig) — model reasons deeper, better timestamps on real videos
3. **Low temperature (0.1)** — prevents phantom hallucinations

### What hurts accuracy:
1. **Temperature 1.0** — causes phantom deliveries (2-3x in a 3-sec clip)
2. **Response schema + metadata** — confused model on Umran Malik (returned frame/fps as timestamp)
3. **Downscaling to 480p** — loses release-point detail, model lands on follow-through
4. **MINIMAL thinking** — fast but undershoots on longer videos

### Critical insight:
**Smoke tests can overfit.** Config C won the 3-sec smoke test (0.000s delta!) but performed worst on real videos (0/1, 0/2, 2/4). Always validate on diverse clips.

## Cost Comparison

| Config | Avg tokens/call | Avg latency | Cost estimate (per call) |
|--------|----------------|-------------|--------------------------|
| A (MINIMAL) | 736-6,531 | 3.7-5.5s | ~$0.0005 |
| E (Default) | 1,712-7,393 | 9.2-11.5s | ~$0.0010 |

At $0.001/call, 1,000 calls/day = **$1/day**. Cost is negligible for either config.

## Production Recommendation

Use **Config E** with adaptive File API:
- Videos < 5MB: inline base64
- Videos > 5MB: File API (upload once, query multiple times)
- Temperature: 0.1 (never higher)
- Thinking: Default (do NOT set thinkingConfig)
- Prompt: Simple, clip-agnostic Scout prompt
