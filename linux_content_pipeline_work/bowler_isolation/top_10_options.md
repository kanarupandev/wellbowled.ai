# Bowler Isolation — Top 10 Options

## Goal
Given a bowling video with multiple people, isolate ONLY the bowler on black background.

---

## OPEN SOURCE / FREE

### 1. SAM 3 (Meta, Nov 2025) — TEXT-PROMPTED
- **What:** Latest Meta segmentation model. Say "the bowler" or "person in white bowling" → it finds and tracks them.
- **Why #1:** Text prompts mean no manual clicking. Just describe the bowler. 2x better than SAM 2 on benchmarks.
- **CPU:** Yes, slower but works.
- **License:** SAM License (free for research/non-commercial, check terms for commercial).
- **Repo:** https://github.com/facebookresearch/sam2 (SAM 3 will be similar)

### 2. SAM 2 / SAM 2.1 (Meta, 2024) — POINT-PROMPTED
- **What:** Click on the bowler in frame 1, it tracks and segments through all frames.
- **Why:** Proven, well-documented, works on video natively with temporal consistency.
- **CPU:** Yes, ~15 sec/frame.
- **License:** Apache 2.0 (fully open).
- **Repo:** https://github.com/facebookresearch/sam2

### 3. SAM2Long (ICCV 2025) — LONG VIDEO
- **What:** SAM 2 enhanced for long videos. Handles occlusion and reappearance.
- **Why:** If bowler goes behind umpire momentarily, SAM2Long handles it.
- **CPU:** Yes.
- **Repo:** https://github.com/Mark12Ding/SAM2Long

### 4. EfficientTAM (ICCV 2025) — FAST VARIANT
- **What:** 1.6x faster than SAM 2, 2.4x fewer parameters, same quality.
- **Why:** If CPU speed matters. Cuts 10-hour job to ~6 hours.
- **Repo:** https://openaccess.thecvf.com/content/ICCV2025/papers/Xiong_Efficient_Track_Anything_ICCV_2025_paper.pdf

### 5. MediaPipe Segmentation (Google) — ALREADY IN OUR STACK
- **What:** Built into MediaPipe. Outputs person segmentation mask alongside pose.
- **Why:** Zero new dependencies. Already working (the other agent got clean results).
- **CPU:** Yes, real-time fast.
- **Limitation:** Single-person optimized. Multiple people = picks the most prominent one.
- **Docs:** https://developers.google.com/ml-kit/vision/selfie-segmentation

### 6. RMBG-2.0 (BRIA AI) — BACKGROUND REMOVAL SPECIALIST
- **What:** Model specifically trained for removing backgrounds from images/video.
- **Why:** Optimized for the exact task. High quality edges.
- **CPU:** Yes, ~2-5 sec/frame.
- **License:** Open source.
- **Limitation:** Image-by-image (no temporal tracking). May flicker between frames.

---

## PAID / API

### 7. VideoBGRemover API — DEVELOPER API
- **What:** 4 AI models via API. `videobgremover-human` optimized for people.
- **Why:** No local setup. Send video, get result. Multiple quality tiers.
- **Pricing:** Pay per video/minute.
- **URL:** https://videobgremover.com/api

### 8. Runway ML — CREATIVE PLATFORM
- **What:** AI video editing platform with built-in segmentation and tracking.
- **Why:** Professional UI, real-time preview, drag-and-drop workflow.
- **Pricing:** From $12/month.
- **URL:** https://runwayml.com

### 9. Replicate SAM 2 API — CLOUD GPU
- **What:** SAM 2 running on cloud GPU via API.
- **Why:** Fast (GPU speed) without owning a GPU. Pay per run.
- **URL:** https://replicate.com/meta/sam-2-video

### 10. Gemini Pro Vision (Google) — ALREADY HAVE API KEY
- **What:** Send video to Gemini, ask for per-frame bowler bounding boxes.
- **Why:** Already integrated. No new dependencies. Gemini understands "bowler".
- **Limitation:** Returns bounding boxes, not pixel-precise masks. Need to combine with MediaPipe for mask.

---

## RECOMMENDATION MATRIX

| Option | Quality | Speed (CPU) | Setup | Cost | Best for |
|--------|---------|-------------|-------|------|----------|
| SAM 3 | Best | Slow | Medium | Free | Highest quality, text-prompted |
| SAM 2 | Very good | Slow | Medium | Free | Proven, well-documented |
| EfficientTAM | Very good | Medium | Medium | Free | Faster CPU processing |
| MediaPipe | Good | Fast | None (done) | Free | Quick iteration, already working |
| RMBG-2.0 | Good | Medium | Easy | Free | Simple background removal |
| Runway | Very good | Fast (cloud) | None | $12/mo | Non-technical workflow |
| Replicate API | Very good | Fast (cloud) | Easy | Pay/run | GPU without owning GPU |

## MY RECOMMENDATION

**For overnight batch processing (your use case):**
→ **SAM 3** if text-prompting works ("the bowler in white"). Best quality, free.
→ **SAM 2** if SAM 3 isn't released as standalone yet. Proven, Apache 2.0.

**For quick iteration during development:**
→ **MediaPipe** (already working, instant results).

**For production at scale (IPL season, many clips):**
→ **Replicate API** (cloud GPU, fast, pay per run).

The approach: use MediaPipe during development, switch to SAM 2/3 for final quality output.
