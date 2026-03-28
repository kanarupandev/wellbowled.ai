# Full Pipeline — Best Tools at Each Stage

## The Pipeline Stages

```
Raw clip → [1. Isolate bowler] → [2. Upscale/enhance] → [3. Slow-motion interpolation]
→ [4. Pose estimation] → [5. Analysis (velocity/angles)] → [6. Visualization] → [7. Encode] → Output
```

---

## Stage 1: Bowler Isolation

**Winner: SAM 2 Large (on Mac with MPS)**
Already decided. See bowler_isolation/ docs.

---

## Stage 2: Video Super-Resolution / Upscale

Broadcast footage is often 360p-720p. The bowler might be 50-100px tall. Upscaling before pose estimation improves landmark accuracy.

| Tool | Quality | Speed | Runs on | Notes |
|------|---------|-------|---------|-------|
| **Real-ESRGAN** | Best for real-world | ~1-3 sec/frame (GPU), slower CPU | Mac/Linux | Gold standard. Open source. Restores fine details. |
| **Video2X** | Same (wraps Real-ESRGAN) | Same | Windows/Linux | Friendly wrapper with batch processing |
| **Topaz Video AI** | Best commercial | Fast | Mac/Windows | $299 one-time. Professional grade. |
| **BSRGAN** | Good | Similar to ESRGAN | Any | Alternative to Real-ESRGAN |

**Recommendation:** Real-ESRGAN. Free, open source, proven on sports footage. 2x or 4x upscale before pose estimation.

**Rationale:** A 360p bowler upscaled to 720p gives MediaPipe 4x more pixels to work with. Landmark accuracy improves significantly on low-res broadcast crops.

---

## Stage 3: Frame Interpolation / Slow Motion

Source is 25-30fps. We want ultra-slow-motion (0.1x). That means 250-300fps equivalent. Frame interpolation generates the in-between frames smoothly.

| Tool | Quality | Speed | Notes |
|------|---------|-------|-------|
| **RIFE** | Best for sports motion | ~30ms/frame (GPU) | Handles fast bowling arm motion well |
| **FILM (Google)** | Very good | Slower | Better for static→smooth transitions |
| **IFRNet** | Good | Fast | Lighter alternative to RIFE |
| **DAIN** | Good | Slow | Older, depth-aware interpolation |

**Recommendation:** RIFE. Specifically designed for fluid motion interpolation. Combined with Real-ESRGAN via Video2X for one-step upscale+interpolation.

**Rationale:** A 30fps clip at 0.1x speed without interpolation = 3fps (choppy). RIFE generates smooth 8x interpolated frames = 240fps feel at 0.1x = silky smooth slow motion. The bowling arm arc becomes visible as a continuous flow, not frame jumps.

---

## Stage 4: Pose Estimation

| Model | Accuracy (MPJPE) | Speed | Multi-person | 3D | Notes |
|-------|-------------------|-------|-------------|-------|-------|
| **ViTPose** | Best (0.192m) | Slow | Yes | No | State of the art. Transformer-based. |
| **MediaPipe Heavy** | Good | Fast | Limited | Yes (noisy z) | Already in our stack. 33 landmarks. |
| **YOLO11 Pose** | Very good (89.4% mAP) | Real-time | Yes | No | Fast + accurate. Good balance. |
| **MoveNet Thunder** | Good | Fast | Single | No | Google, optimized for mobile |
| **MeTRAbs** | Best for biomechanics | Slow | Yes | Yes (real 3D) | Academic, validated for sports |
| **OpenPose** | Good | Medium | Yes | No | Older but proven |

**Recommendation:** MediaPipe Heavy for now (already working, deterministic, 33 landmarks). Upgrade to ViTPose if accuracy becomes the bottleneck.

**Rationale:** After SAM 2 isolation, MediaPipe only sees one person — its main weakness (multi-person confusion) is eliminated. Its 33 landmarks at fast speed is sufficient for velocity computation. ViTPose is better but adds complexity for marginal gain in our use case.

**Future upgrade path:** ViTPose + SAM 2 isolated input = best possible accuracy.

---

## Stage 5: Analysis (Velocity / Angles / Energy)

No external tools needed. Pure computation:
- Velocity: frame-to-frame position change × fps / torso_length
- Angles: atan2 on landmark pairs
- Transfer ratios: peak velocity ratios between segments
- Calibrated against Ferdinands 2011 data

---

## Stage 6: Visualization / Rendering

| Tool | What for | Notes |
|------|----------|-------|
| **Pillow (PIL)** | Anti-aliased text, pills, badges | Already using |
| **OpenCV** | Skeleton lines, circles, video I/O | Already using |
| **Cairo / Pycairo** | Higher quality 2D graphics | Alternative to Pillow for smoother gradients |
| **FFmpeg** | Final encode, H.264+AAC | Already using |

**Recommendation:** Keep Pillow + OpenCV. Sufficient for our needs.

---

## Stage 7: Final Encoding

**FFmpeg** — already using. H.264, CRF 17, yuv420p, faststart, AAC audio.

---

## The Optimal Pipeline (with all tools)

```
[Raw broadcast clip]
    ↓
[SAM 2 Large on Mac] → isolated bowler on black (MPS, ~30 min/1-min clip)
    ↓
[Real-ESRGAN 2x] → upscaled to higher resolution (optional, for low-res source)
    ↓
[RIFE 8x interpolation] → smooth ultra-slo-mo frames (optional, for fluid motion)
    ↓
[MediaPipe Heavy] → 33 landmarks per frame, deterministic
    ↓
[Velocity + transfer ratio computation] → calibrated against research data
    ↓
[Pillow + OpenCV rendering] → energy flow visualization
    ↓
[FFmpeg H.264] → upload-ready 9:16 MP4
```

**The game changers:**
1. SAM 2 eliminates multi-person confusion permanently
2. Real-ESRGAN makes low-res broadcast usable for pose estimation
3. RIFE makes the energy flow visible as smooth motion, not frame jumps

---

## Cost Summary

| Tool | Cost | Where it runs |
|------|------|---------------|
| SAM 2 Large | Free (Apache 2.0) | Mac |
| Real-ESRGAN | Free | Mac or Linux |
| RIFE | Free | Mac or Linux |
| MediaPipe | Free | Linux |
| Pillow/OpenCV/FFmpeg | Free | Linux |
| Gemini Flash (1 call/clip) | ~$0.001/clip | API |
| **Total** | **~Free** | |
