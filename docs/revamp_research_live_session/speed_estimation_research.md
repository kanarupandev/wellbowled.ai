# Real-Time Cricket Ball Speed Estimation on iOS

Research findings for on-device speed estimation with minimal Gemini API calls.

**Date:** 2026-03-25
**Target device:** iPhone 15 (A16 Bionic, 6-core GPU, 16-core Neural Engine)
**Constraint:** 1-3 Gemini calls at session start for calibration; everything else on-device, real-time.

---

## Table of Contents

1. [The Core Physics Problem](#1-the-core-physics-problem)
2. [Apple Vision Framework Capabilities](#2-apple-vision-framework-capabilities)
3. [Core ML Object Detection](#3-core-ml-object-detection)
4. [Frame Differencing (Current Approach)](#4-frame-differencing-current-approach)
5. [Gemini Setup Call Strategy](#5-gemini-setup-call-strategy)
6. [Speed Calculation Approaches](#6-speed-calculation-approaches)
7. [What Other Apps Do](#7-what-other-apps-do)
8. [Recommended Approach](#8-recommended-approach)
9. [Implementation Plan](#9-implementation-plan)

---

## 1. The Core Physics Problem

Before evaluating any approach, the fundamental constraints must be understood:

### Cricket Ball Apparent Size at Distance

iPhone 15 main camera: 26mm equivalent, f/1.6, ~73 degree horizontal FOV.

At 1080p (1920x1080) video recording:
- Horizontal FOV ~73 degrees => ~26.3 pixels per degree
- Cricket ball diameter: 7.3cm (0.073m)

| Distance | Ball angular size | Ball pixel diameter | Verdict |
|----------|------------------|--------------------| --------|
| 10m | 0.42 degrees | ~11 pixels | Marginal for detection |
| 15m | 0.28 degrees | ~7 pixels | Very small |
| 20m | 0.21 degrees | ~5.5 pixels | Barely visible |
| 25m | 0.17 degrees | ~4.5 pixels | Sub-pixel blur territory |
| 30m | 0.14 degrees | ~3.7 pixels | Essentially untrackable as a discrete object |

At 4K (3840x2160):
- ~52.6 pixels per degree
- Ball at 20m: ~11 pixels diameter (marginal)
- Ball at 30m: ~7.4 pixels (very small)

### Ball Motion Between Frames

| Speed (kph) | Speed (m/s) | Distance per frame @60fps | Distance per frame @120fps | Distance per frame @240fps |
|-------------|-------------|--------------------------|---------------------------|---------------------------|
| 80 | 22.2 | 0.37m | 0.19m | 0.09m |
| 100 | 27.8 | 0.46m | 0.23m | 0.12m |
| 120 | 33.3 | 0.56m | 0.28m | 0.14m |
| 140 | 38.9 | 0.65m | 0.32m | 0.16m |

At 60fps, a 120kph ball moves 0.56m per frame. Over 20m that is ~36 frames of flight time (~0.6s). At 240fps it is ~144 frames (~0.6s). More frames = better temporal resolution for transit time measurement.

### Motion Blur

At 60fps with typical outdoor exposure (1/500s shutter), the ball at 120kph moves ~6.7cm per exposure -- roughly its own diameter. This creates significant motion blur, making the ball appear as a streak rather than a circle. At 240fps with faster shutter speeds, blur is reduced but the image is darker and noisier.

### Key Takeaway

**Direct ball tracking (detecting and following the ball as a discrete object frame-by-frame) is extremely difficult with a single phone camera at 10-30m distance.** The ball is 4-11 pixels wide, moves fast, and motion-blurs. This is why Hawk-Eye uses 6-10 dedicated high-speed cameras with known positions for triangulation.

---

## 2. Apple Vision Framework Capabilities

### VNDetectTrajectoriesRequest (iOS 14+)

**What it does:** Detects objects moving along parabolic paths in video sequences. Uses frame differencing internally to find moving objects, then fits a parabolic trajectory to the detected points.

**Configuration:**
- `objectMinimumNormalizedRadius` / `objectMaximumNormalizedRadius`: Filter by apparent object size (normalized 0-1 relative to frame)
- `trajectoryLength`: Number of points to detect (minimum 5, recommended 10 for golf ball)
- `frameAnalysisSpacing`: Time interval between analyzed frames

**Designed for:** Golf balls, baseballs, soccer balls -- objects that are relatively large in frame and follow clear parabolic arcs.

**Cricket ball feasibility: POOR to MARGINAL**
- At 20m+, the cricket ball is 4-6 pixels. The trajectory detector relies on frame differencing and needs the object to be distinguishable from noise. At this pixel size, noise, compression artifacts, and background clutter are all comparable to the ball signal.
- The trajectory must be parabolic. Cricket balls do follow a roughly parabolic path, but the arc is very shallow (fast bowlers' balls barely deviate from a straight line over 20m). The algorithm may not detect such flat trajectories reliably.
- Apple's WWDC demos show this working for golf balls at close range (camera beside the tee) where the ball is 20-50+ pixels across. Not validated for small distant objects.
- **Known issue:** `objectMaximumNormalizedRadius` has been reported to not work correctly on Apple Developer Forums, with the setting not being reflected.
- **Performance:** Runs on Neural Engine, can process at 30-60fps on modern hardware. Latency is acceptable for real-time use.

**Verdict:** Worth trying as a supplement, but do not bet the product on it. It may work at close range (10-12m, behind the bowler's arm) but will likely fail at typical side-on distances of 15-30m.

### VNTrackObjectRequest (iOS 11+)

**What it does:** Tracks a previously identified object across video frames using correlation-based tracking.

**Cricket ball feasibility: POOR**
- Requires an initial bounding box (someone/something must first detect the ball).
- Correlation trackers lose small, fast-moving objects almost immediately.
- The ball changes appearance rapidly (rotation, blur, lighting) and the tracker template becomes stale within a few frames.
- Not designed for objects smaller than ~20x20 pixels.

**Verdict:** Not viable for cricket ball tracking at realistic distances.

### VNGenerateOpticalFlowRequest (iOS 14+)

**What it does:** Generates per-pixel optical flow vectors between two consecutive frames. Produces a dense flow field showing direction and magnitude of motion at every pixel.

**Cricket ball feasibility: INTERESTING BUT INDIRECT**
- Does not directly detect or track the ball.
- Could theoretically detect the "streak" of high-magnitude flow vectors caused by the ball's motion.
- At 20m+, the ball creates flow in only 4-6 pixels per frame -- indistinguishable from noise in many conditions.
- **Performance:** Uses Neural Engine. `VNGenerateOpticalFlowRequestRevision2` is ML-based. At full resolution, expect 15-30fps on iPhone 15. At reduced resolution (512x288), could hit 60fps.
- Memory-intensive: generates a full float2 image for every frame pair.

**Verdict:** Too expensive and too noisy for direct ball tracking. Could potentially be used for gross motion detection (bowler running in) but frame differencing in an ROI is simpler and faster for that purpose.

### VNDetectContoursRequest (iOS 14+)

**What it does:** Detects edges and contours in a single image.

**Cricket ball feasibility: VERY POOR**
- Static contour detection. Does not track across frames.
- Cricket stumps could theoretically be detected as vertical contours, but Gemini vision does this better and more reliably in a single call.
- The ball at 20m+ has no useful contour -- it is too small and blurred.

**Verdict:** Not useful for speed estimation. The existing Gemini stump detection approach is superior.

### VNDetectHumanBodyPoseRequest (iOS 14+)

**Already in use** via MediaPipe for delivery detection. Apple's built-in pose detection could replace MediaPipe dependency but does not directly help with speed estimation. The wrist velocity at release correlates loosely with ball speed but not accurately enough for speed estimation.

### Summary: Apple Vision Framework

| API | Ball Detection | Speed Estimation | Real-time | Practical? |
|-----|---------------|-----------------|-----------|------------|
| VNDetectTrajectoriesRequest | Marginal at distance | Via trajectory + time | Yes (30-60fps) | Maybe at <15m |
| VNTrackObjectRequest | Too small/fast | No | Yes | No |
| VNGenerateOpticalFlowRequest | Indirect (flow spike) | Indirect | Marginal (15-30fps) | No |
| VNDetectContoursRequest | No | No | Yes | No |

---

## 3. Core ML Object Detection

### YOLOv8/YOLO11 on CoreML

**Performance on iPhone 15 Neural Engine:**
- YOLOv8s: ~30-60fps at 640x640 input resolution
- YOLOv8n (nano): ~60-85fps at 640x640
- YOLO11n: ~60-85fps (successor to YOLOv8n, similar performance)
- Full YOLOv8 with 601 classes: ~10fps (too heavy)

**Cricket ball detection feasibility: POOR for real-time tracking**

The fundamental problem is not model speed but detection capability:
- YOLO models are trained on COCO which includes "sports ball" class, but at 32x32+ pixel minimum feature size.
- At 20-30m, the cricket ball is 4-7 pixels. This is **below the minimum detectable object size** for any standard object detector.
- Even tiny-YOLO variants designed for small objects expect the target to be at least ~16x16 pixels.
- Custom training on cricket ball data from Roboflow datasets (74-7452 images available) could improve detection at close range, but the physics of pixel size at distance remains the constraint.

**Where it could help:**
- Detecting stumps (large, static, high contrast) -- but Gemini already does this.
- Detecting the bowler (large, moving) -- but MediaPipe pose already does this.
- Detecting the ball near stumps (closer range, larger apparent size if camera is behind stumps).

### CreateML Custom Training

Apple's CreateML supports object detection training with YOLOv2-based architecture and transfer learning. You could:
1. Collect ~500+ images of cricket balls at various distances
2. Annotate bounding boxes
3. Train in CreateML
4. Export as CoreML model

**Practical issue:** The bottleneck is not the model architecture but the input data quality. If the ball is 5 pixels across in the training images, no model will reliably detect it.

### Roboflow Cricket Datasets

Available datasets:
- Cricket Ball Detection: 74 images (too small for training)
- Cricket Dataset: 7,452 images with ball + stumps + bowler annotations
- Ball Tracking Dataset: 573 images

The 7,452-image dataset is promising but would need validation that it includes frames at realistic phone-camera distances (most cricket vision datasets are from broadcast cameras with telephoto lenses).

### Verdict: CoreML Object Detection

Not viable for real-time ball tracking at 15-30m distance. The ball is simply too small in the frame. Could be useful for detecting stumps or the bowler, but those tasks are already handled.

---

## 4. Frame Differencing (Current Approach)

### What Already Exists

The app has a well-structured speed estimation pipeline:

1. **`StumpCalibration`** (`StumpCalibration.swift`): Stores normalized stump positions, computes `pixelsPerMetre` from stump separation, and converts transit time to speed via `speedKph(transitTimeSeconds:)`.

2. **`SpeedEstimationService`** (`SpeedEstimationService.swift`): Post-hoc analysis of recorded clips. Extracts Y-plane grayscale frames, computes motion energy in bowler/striker ROIs via frame differencing, finds spike peaks, measures transit time.

3. **`CliffDetector`** (`CliffDetector.swift`): Real-time stump-hit detection using energy cliff patterns. Already runs on live frames.

4. **`StumpDetectionService`** (`StumpDetectionService.swift`): Uses Gemini vision to detect stump positions from a single frame. Already works.

### Strengths of Frame Differencing

- **Extremely fast.** Computing |frame[n] - frame[n-1]| in an ROI is trivially cheap -- just integer subtraction on Y-plane bytes. No ML model, no Neural Engine needed.
- **Already built.** The ROI-based energy computation, noise floor calculation, and spike detection are all implemented and tested.
- **Works at any distance.** Frame differencing does not need to "see" the ball as a discrete object. It detects *any* motion in the ROI, including the blurry streak of a passing ball. This is fundamentally different from object detection.
- **Proven concept.** The CliffDetector already uses this for stump-hit detection in real-time.

### Weaknesses of Current Implementation

1. **Post-hoc only.** `SpeedEstimationService` processes recorded clips after the fact. It needs to be adapted for real-time frame processing.
2. **Bowler ROI spike is not just the ball.** The bowler's body, arm, and follow-through all create motion in the bowler-end ROI. Distinguishing ball release from bowler body motion is noisy.
3. **ROI size sensitivity.** Too large an ROI catches noise from people, wind, shadows. Too small and the ball's motion streak may not intersect the ROI.
4. **Single spike detection.** The current algorithm finds the first spike above threshold. In practice, there may be multiple motion events (bowler running through, batsman moving, other players).

### Can It Be Improved for Real-Time?

Yes. The core operations are cheap enough:
- Y-plane extraction: ~0 cost (already in the capture pipeline as YCbCr)
- Per-pixel difference in ROI: At 1080p with a 10% width x 30% height ROI, that is ~58,000 pixels. Integer subtraction + threshold comparison = ~0.1ms.
- Spike detection: Trivial comparison against rolling buffer.

**Total per-frame cost: <1ms.** This can easily run at 60fps or even 240fps.

### Error Analysis for Frame Differencing Speed Estimation

At 60fps with +-1 frame uncertainty on each gate:
- Transit time uncertainty: +-2 frames = +-33ms
- At 120kph (transit ~0.6s): speed range = 108-134 kph (+-13 kph) -- **outside +-5 kph target**
- At 120kph (transit ~0.6s) with +-0.5 frame: speed range = 115-125 kph (+-5 kph) -- **at target**

At 120fps with +-1 frame uncertainty:
- Transit time uncertainty: +-2 frames = +-17ms
- At 120kph (transit ~0.6s): speed range = 114-127 kph (+-6.5 kph) -- **close to target**

At 240fps with +-1 frame uncertainty:
- Transit time uncertainty: +-2 frames = +-8ms
- At 120kph (transit ~0.6s): speed range = 117-123 kph (+-3 kph) -- **within target**

**Key insight: To hit +-5 kph accuracy, you need either 120fps+ capture OR sub-frame spike timing via energy interpolation at 60fps.**

---

## 5. Gemini Setup Call Strategy

### Call 1: Scene Understanding + Stump Detection (Already Built)

Send one camera frame to Gemini. Ask it to:
1. Identify stump positions (bowler-end and striker-end) -- **already implemented in `StumpDetectionService`**
2. Identify the pitch boundaries (crease lines, pitch strip edges)
3. Estimate camera distance from the pitch (based on perspective cues)
4. Identify the camera angle relative to the pitch (side-on, behind-arm, end-on)

This gives:
- Stump positions (normalized) -> `StumpCalibration.pixelsPerMetre`
- Camera geometry context for choosing the best speed algorithm

### Call 2 (Optional): ROI Refinement

After the first few deliveries, send a frame with motion overlay showing where motion was detected. Ask Gemini to:
1. Confirm the motion ROIs are correctly placed
2. Suggest adjustments if the bowler's run-up path creates false triggers
3. Identify any scene elements that might cause systematic errors

### Call 3 (Optional): Speed Confidence Calibration

After 3-5 deliveries with speed estimates, send a summary to Gemini:
- "Ball transit times: 0.55s, 0.58s, 0.52s, 0.61s, 0.54s"
- Ask: "Given these transit times over a 20.12m pitch, are these speeds plausible for what you saw in the session? The bowler appeared to be [pace/medium-pace/spin]."
- This sanity-checks the calibration without requiring Gemini to do any speed calculation.

### Recommendation

**Call 1 is sufficient.** It is already built and provides the critical `pixelsPerMetre` calibration. Calls 2-3 are nice-to-haves that add complexity without fundamentally improving accuracy.

---

## 6. Speed Calculation Approaches

### Method A: Two-Gate Transit Time (Frame Differencing)

**How:** Define two ROIs (bowler-end near stumps, striker-end near stumps). Detect motion spike at gate 1 (bowler release), then motion spike at gate 2 (ball arriving at striker end). Transit time = spike2_time - spike1_time. Speed = 20.12m / transit_time.

**Accuracy:** +-5 kph at 120fps, +-3 kph at 240fps, +-13 kph at 60fps (with naive per-frame detection). Sub-frame interpolation (fitting a curve to energy values around the peak) could bring 60fps accuracy to +-5-7 kph.

**Latency:** <1ms per frame. Real-time.

**Reliability:**
- Gate 2 (striker end) is more reliable -- the ball arrives near the stumps, which is a well-defined spatial region.
- Gate 1 (bowler end) is noisier -- the bowler's body creates large motion signals. The ball release spike may be buried in bowler-body motion.
- **Improvement:** Use the delivery detection timestamp (from MediaPipe wrist velocity) as Gate 1 instead of bowler-end frame differencing. The wrist velocity spike occurs at ball release. Then only Gate 2 needs frame differencing.

**Verdict: BEST APPROACH. Already partially built. Needs adaptation from post-hoc to real-time, and Gate 1 should use MediaPipe release timestamp instead of frame differencing.**

### Method B: Optical Flow Magnitude

**How:** Compute optical flow in ball flight region. Sum flow magnitude vectors. Peak magnitude correlates with ball speed.

**Accuracy:** Poor. Flow magnitude depends on distance, angle, and apparent size. No absolute speed calibration possible without knowing exact ball size and distance at each point.

**Latency:** 15-50ms per frame (GPU optical flow). Not viable at 60fps.

**Verdict: NOT VIABLE. Too expensive, too inaccurate.**

### Method C: CliffDetector Energy Pattern

**How:** The CliffDetector already detects stump-hit events (energy cliff = ball hitting stumps). Use the cliff timestamp as Gate 2. Use delivery detection as Gate 1.

**Accuracy:** Good for Gate 2 (stump hits are sharp, high-energy events). But only works when the ball hits the stumps -- not for every delivery.

**Verdict: GOOD SUPPLEMENT for stump-hit deliveries. Not a general solution.**

### Method D: VNDetectTrajectoriesRequest

**How:** Let Apple's trajectory detector find the ball in flight. Extract trajectory points with timestamps. Compute speed from trajectory point spacing and known scale factor.

**Accuracy:** If it detects the ball reliably, accuracy could be excellent (multiple trajectory points give overdetermined speed estimate). But detection reliability at 20m+ is the unsolved problem.

**Latency:** 5-15ms per frame on Neural Engine.

**Verdict: EXPERIMENTAL. Try it. If it works at the user's camera distance, it would be the most elegant solution. But have a fallback.**

### Method E: Hybrid Wrist-Omega + Single-Gate

**How:** Use MediaPipe wrist angular velocity at release (already detected) as a coarse speed proxy. Then use a single striker-end motion gate to measure actual ball arrival time. Wrist omega gives ~+-15 kph pace bracket. Arrival time refines it.

The wrist angular velocity -> ball speed relationship is nonlinear and bowler-dependent, but within a session (same bowler), relative changes in omega correlate with relative changes in speed. Calibrate the relationship after the first few deliveries using full transit time measurements.

**Accuracy:** Initial estimate +-15 kph (pace bracket only). After calibration: potentially +-5-8 kph if the omega-speed relationship is stable for that bowler.

**Verdict: GOOD for pace bracket. Not accurate enough alone for +-5 kph. Useful as a fallback.**

---

## 7. What Other Apps Do

### Hawk-Eye (Professional Cricket)

- 6-10 high-speed cameras (340fps+), known positions, calibrated intrinsics
- Triangulation across cameras for 3D ball position
- Accuracy: +-2.6mm position, +-1 kph speed
- **Not applicable to single phone camera.**

### Fulltrack AI (Smartphone App -- Most Relevant Comparison)

- Single smartphone on tripod
- AI-based ball tracking from video
- Automated 3D trajectory reconstruction, speed, spin, line, length
- **Validation study (Shorter et al., 2025):**
  - 1081 deliveries tested against radar gun
  - Pace deliveries: ICC 0.87-0.90 (good agreement), CV 2.56-3.13%
  - **Overestimated speed by 0.72-0.77 m/s (2.6-2.8 kph) for pace**
  - Overestimated speed by 1.09-1.18 m/s (3.9-4.2 kph) for spin
  - Limits of agreement exceeded 3% -- not interchangeable with radar gun
- Proprietary, closed-source, subscription-based
- Key takeaway: **a well-resourced team with ML expertise achieved ~+-3 kph accuracy for pace with a single phone camera. This is roughly our target.**

### PitchVision (Hardware + Software)

- Dedicated hardware system with sensors + cameras
- Fits in 4 cases, 10-minute setup
- Measures pace, line, length, deviation, bounce
- **Not a phone-only solution.** Uses specialized sensor hardware alongside video.

### BowloMeter / Bowling Speed Meter (Simple Phone Apps)

- Manual frame-by-frame selection: user picks release frame and arrival frame
- Known pitch distance entered manually
- Speed = distance / time between selected frames
- **Not real-time, not automated.** But validates the fundamental transit-time approach.

### CricVision (AI Coaching App)

- AI-generated highlights and feedback
- Does not appear to do automated speed estimation
- Focus is on action replay and coaching, not speed measurement

### Key Insight from Competitors

**Fulltrack AI is the gold standard for phone-based cricket speed estimation.** They achieve ~+-3 kph for pace with ML-based ball tracking. They likely use a combination of:
1. Ball detection (probably YOLO or custom detector, trained on their own cricket data)
2. Trajectory fitting across detected positions
3. Known pitch geometry for scale calibration
4. Temporal interpolation for sub-frame accuracy

They process video **after recording**, not in real-time. Their approach is compute-intensive enough that real-time processing on-device seems unlikely for the ball tracking component. They likely do the heavy ML inference server-side or with significant on-device GPU time.

---

## 8. Recommended Approach

### The Honest Assessment

Achieving +-5 kph real-time speed estimation from a single phone camera is at the **frontier of what's possible**. Fulltrack AI achieves ~+-3 kph but likely with significant compute (not real-time) and a well-trained custom ML pipeline developed over years.

For wellBowled, the realistic achievable accuracy tiers are:

| Tier | Accuracy | Method | Effort |
|------|----------|--------|--------|
| **A: Pace bracket** | +-15 kph | Wrist omega from MediaPipe (already built) | Already done |
| **B: Rough speed** | +-8-10 kph | Two-gate frame differencing at 60fps | 2-3 days |
| **C: Good speed** | +-5-7 kph | Two-gate frame differencing at 120fps + sub-frame interpolation | 1 week |
| **D: Competitive** | +-3-5 kph | Custom ball detector + trajectory + transit time | 4-8 weeks |

### Recommended: Tier B Now, Tier C Soon

**Phase 1 (Ship Now): Hybrid Wrist-Release + Striker-Gate at 60fps**

1. **Gate 1 (Release):** Use the existing MediaPipe delivery detection timestamp as the release moment. This is already built, runs in real-time, and detects ball release via wrist angular velocity spike. Precision: +-1-2 frames at 30fps effective rate (MediaPipe runs on every 2nd frame at 60fps capture).

2. **Gate 2 (Arrival):** Add real-time frame differencing in the striker-end ROI (adapt the existing `SpeedEstimationService.computeMotionEnergy` to run on live frames). The CliffDetector pattern (energy buffer + spike detection) is already built -- just add a second ROI that is *above* the stumps to catch ball arrival *before* it hits.

3. **Transit time** = Gate 2 timestamp - Gate 1 timestamp.

4. **Speed** = 20.12m / transit_time * 3.6 (kph).

5. **Calibration:** Gemini stump detection (already built) provides the spatial reference. The pitch length is a known constant (20.12m).

6. **Sub-frame interpolation:** Fit a quadratic to the 3 energy values around the Gate 2 peak. The sub-frame peak gives ~+-0.5 frame precision, improving accuracy from +-13 kph to +-7-8 kph at 60fps.

**Expected accuracy: +-8-10 kph at 60fps. Latency: <5ms per frame.**

**Phase 2 (Next Sprint): 120fps Mode + Refined Gates**

1. Switch to 120fps capture when speed calibration is active. The iPhone 15 supports 1080p@120fps. The app already has `speedMode` flag in `CameraService` that targets 120fps.

2. At 120fps with sub-frame interpolation: +-4-6 kph accuracy.

3. Add a "bowler approach" gate upstream of the stumps to detect the bowler's run-up completion. This gives an additional timing signal.

4. Use the CliffDetector (stump-hit detection) as a third timing gate for deliveries that hit the stumps. Three gates give overdetermined transit time -> better accuracy.

**Expected accuracy: +-5-7 kph at 120fps. Latency: <3ms per frame.**

**Phase 3 (Optional): VNDetectTrajectoriesRequest Experiment**

1. Run `VNDetectTrajectoriesRequest` in parallel with frame differencing.
2. Configure: `objectMinimumNormalizedRadius = 0.002`, `objectMaximumNormalizedRadius = 0.02`, `trajectoryLength = 7`.
3. If it detects ball trajectories, use the trajectory points for much more precise speed estimation (multiple points along the flight path, not just two gates).
4. If it does not detect reliably, disable it with zero impact on the fallback frame differencing path.

---

## 9. Implementation Plan

### Phase 1: Real-Time Two-Gate Speed (2-3 days)

**Files to modify:**

1. **`BowlViewModel.swift`** (or equivalent session controller):
   - Create a `LiveSpeedEstimator` that receives: (a) delivery timestamps from `DeliveryDetector`, (b) live video frames from `CameraService`.
   - Wire up the live frame callback to feed frames into the speed estimator.

2. **New: `LiveSpeedEstimator.swift`**:
   ```
   Class responsibilities:
   - Receives live CMSampleBuffers
   - Maintains a rolling Y-plane buffer of the striker-end ROI
   - Computes motion energy per frame (reuse SpeedEstimationService.computeMotionEnergy logic)
   - On delivery detection: starts watching for striker-gate spike
   - On striker-gate spike: computes transit time, converts to speed
   - Sub-frame interpolation: quadratic fit around peak
   - Publishes SpeedEstimate for UI consumption
   ```

3. **`StumpCalibration.swift`**: No changes needed. Already computes `speedKph(transitTimeSeconds:)`.

4. **`CliffDetector.swift`**: Already detects stump hits. Wire its detection as a third gate input when available.

5. **UI**: Display speed estimate in the live session overlay. Already have `SpeedSetupOverlay.swift` and `CalibrationOverlayView.swift` for calibration flow.

### Phase 2: 120fps + Multi-Gate (1 week)

1. Enable `speedMode` in `CameraService` after calibration locks.
2. Validate that MediaPipe still works at 120fps (it processes every 2nd frame via `frameSkip`).
3. Add upstream "approach gate" ROI between bowler and halfway.
4. Implement multi-gate averaging for improved accuracy.

### Phase 3: Trajectory Detection Experiment (3-5 days)

1. Add `VNDetectTrajectoriesRequest` handler that runs in parallel on the video frame stream.
2. Filter trajectories by size and parabolic fit quality.
3. If viable trajectories detected, compute speed from trajectory point timestamps and calibrated pixel-to-metre conversion.
4. A/B compare with frame differencing results to validate.

---

## Appendix A: iPhone 15 Camera Capabilities Summary

| Mode | Resolution | FPS | Notes |
|------|-----------|-----|-------|
| Video | 4K (3840x2160) | 24/25/30/60 | Best resolution but no >60fps |
| Video | 1080p (1920x1080) | 25/30/60 | Default video mode |
| Slo-Mo | 1080p | 120 | Good for speed estimation |
| Slo-Mo | 1080p | 240 | Best temporal resolution, darker image |

Neural Engine: 16-core, ~17 TOPS. Can run YOLOv8n at 60-85fps alongside other tasks.

## Appendix B: Accuracy vs Frame Rate Table

For 120 kph ball over 20.12m pitch (transit ~0.604s):

| FPS | Frame uncertainty (+-1) | Transit time error | Speed range | Speed error |
|-----|------------------------|-------------------|-------------|-------------|
| 30 | +-33.3ms | +-66.7ms | 98-148 kph | +-25 kph |
| 60 | +-16.7ms | +-33.3ms | 108-134 kph | +-13 kph |
| 60 + interp | +-8ms | +-16ms | 114-127 kph | +-6.5 kph |
| 120 | +-8.3ms | +-16.7ms | 114-127 kph | +-6.5 kph |
| 120 + interp | +-4ms | +-8ms | 117-123 kph | +-3 kph |
| 240 | +-4.2ms | +-8.3ms | 117-123 kph | +-3 kph |
| 240 + interp | +-2ms | +-4ms | 119-122 kph | +-1.5 kph |

**Conclusion: 120fps with sub-frame interpolation is the sweet spot.** 60fps with interpolation is acceptable. 240fps is better but the darker image and potential compatibility issues may not be worth it.

## Appendix C: Sub-Frame Interpolation

Given energy values E[i-1], E[i], E[i+1] around a peak at frame i:

Fit quadratic: E(t) = at^2 + bt + c through the three points.
Sub-frame peak: t_peak = -b / (2a)

This gives approximately +-0.5 frame precision, effectively doubling the temporal resolution for free.

Implementation (Swift):
```swift
static func subframePeak(before: Double, peak: Double, after: Double) -> Double {
    // Returns offset from peak frame in range [-0.5, +0.5]
    let a = (before + after) / 2.0 - peak
    guard abs(a) > 1e-10 else { return 0.0 }
    let b = (after - before) / 2.0
    return -b / (2.0 * a)
}
```

## Appendix D: Sources and References

### Apple Developer Documentation
- [VNDetectTrajectoriesRequest](https://developer.apple.com/documentation/vision/vndetecttrajectoriesrequest)
- [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)
- [VNGenerateOpticalFlowRequest](https://developer.apple.com/documentation/vision/vngenerateopticalflowrequest)
- [Identifying Trajectories in Video](https://developer.apple.com/documentation/vision/identifying-trajectories-in-video)
- [Explore the Action & Vision App - WWDC20](https://developer.apple.com/videos/play/wwdc2020/10099/)
- [What's New in Vision - WWDC22](https://developer.apple.com/videos/play/wwdc2022/10024/)

### Validation Studies
- [Fulltrack AI vs Radar Gun - Shorter et al., 2025](https://journals.sagepub.com/doi/10.1177/17479541241284714) -- 1081 deliveries, ICC 0.87-0.90 for pace, overestimated by 0.72-0.77 m/s
- [Fulltrack AI Line and Length Validity](https://www.tandfonline.com/doi/full/10.1080/14763141.2024.2381108)

### Cricket Ball Tracking Research
- [Cricket Umpire Assistance and Ball Tracking Using Single Smartphone Camera](https://www.researchgate.net/publication/345691066_Cricket_umpire_assistance_and_ball_tracking_system_using_a_single_smartphone_camera)
- [Deep-Learning-Based Cricket Ball Segmentation and Tracking](https://www.researchgate.net/publication/365662574_Deep-Learning-Based_Computer_Vision_Approach_For_The_Segmentation_Of_Ball_Deliveries_And_Tracking_In_Cricket)
- [Computer Vision in IPL 2025](https://www.ultralytics.com/blog/how-computer-vision-in-ipl-2025-is-enabling-smarter-cricket)

### YOLO / CoreML
- [Best iOS Object Detection Models](https://blog.roboflow.com/best-ios-object-detection-models/)
- [Ultralytics iOS App](https://docs.ultralytics.com/hub/app/ios/)
- [ObjectDetection-CoreML (YOLOv8, YOLOv5)](https://github.com/tucan9389/ObjectDetection-CoreML)

### Cricket Ball Datasets
- [Cricket Ball Detection - Roboflow](https://universe.roboflow.com/cricket-2rxrt/cricket-ball-detection/dataset/1)
- [Cricket Ball and Stumps Detection - GitHub](https://github.com/sanjusabu/Cricket-Ball-and-Stumps-Detection)
- [Cricket Dataset (7452 images) - Roboflow](https://universe.roboflow.com/cricket-ball-tracking-dataset/cricket-dataset-z2wkt)

### Hawk-Eye and Professional Systems
- [Hawk-Eye - Wikipedia](https://en.wikipedia.org/wiki/Hawk-Eye)
- [Understanding Cricket Ball Tracking Technology: 2025](https://theword360.com/2025/06/10/how-ball-tracking-technology-improves-cricket-accuracy/)

### Competitor Apps
- [Fulltrack AI](https://www.fulltrack.ai/)
- [PitchVision](https://www.pitchvision.com/cricket-app)
- [CricVision](https://www.cricvision.ai/)

### Ball Trajectory Detection (Apple Ecosystem)
- [MIZUNO Ball Trajectory Detection](https://github.com/MIZUNO-CORPORATION/IdentifyingBallTrajectoriesinVideo)
- [VNDetectTrajectoriesRequest Forum Issues](https://developer.apple.com/forums/thread/670447)

### iPhone 15 Camera Specs
- [iPhone 15 Tech Specs - Apple](https://support.apple.com/en-us/111831)
- [iPhone 15 Imaging Tech Examined - DPReview](https://www.dpreview.com/articles/2668153890/apple-s-iphone-15-and-15-pro-imaging-tech-examined)
