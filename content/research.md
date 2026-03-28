# AI Content Pipeline — Deep Research Findings

Research conducted 2026-03-25 across pose estimation, video enhancement, content tools, and automation pipelines.

---

## 1. Pose Estimation (Skeleton Overlays)

### Best Options for Bowling Analysis on Mac

| Tool | Keypoints | Multi-person | macOS | Speed | Best For |
|------|-----------|-------------|-------|-------|----------|
| **MediaPipe Pose Landmarker** | 33 | No (single) | Yes (Python) | Very fast | Single bowler, real-time |
| **YOLO11-Pose (Ultralytics)** | 17 | Yes | Yes (pip) | Fast | Multiple people, robust |
| **Apple Vision (VNDetectHumanBodyPoseRequest)** | 19 (2D) / 17 (3D) | Yes | Native (PyObjC) | Fast | Mac-native, no deps |
| **MMPose / RTMPose** | 17-133 | Yes | Yes (pip) | Medium | Research-grade accuracy |
| **CoTracker (Meta)** | Any point | N/A | CPU/MPS | Slow | Custom point tracking |

### Recommendation: MediaPipe for daily pipeline
- 33 keypoints (more than YOLO's 17) — captures wrist, elbow, shoulder detail critical for bowling
- Runs on Mac Python with `pip install mediapipe`
- New Tasks API: `mediapipe.tasks.python.vision.PoseLandmarker`
- Draw with OpenCV: `mp.solutions.drawing_utils.draw_landmarks()`
- Fast enough for batch processing (>30fps on M-series)

### Cricket-Specific Research
- OpenCap (2025 study): validated pose estimation vs 3D motion capture for bowling
- YOLOv8x-Pose: used to track elbow angle, wrist speed, arm trajectory
- MediaPipe 33 landmarks used in cricket bowling phase detection research
- 17 key biomechanical parameters identified for bowling performance
- Phase detection accuracy >95% using delivery-phase data alone

---

## 2. AI Slow Motion (Frame Interpolation)

| Tool | Price | macOS | Quality | Setup |
|------|-------|-------|---------|-------|
| **RIFE-ncnn-vulkan** | Free | Yes (Vulkan) | Excellent | `brew install vulkan-loader molten-vk` + binary |
| **Topaz Video AI** | $299/yr | Yes | Best-in-class | GUI app |
| **Runway ML** | $15/mo+ | Web | Very good | Browser |
| **RIFE (Python/PyTorch)** | Free | Yes (MPS) | Excellent | `pip install` |
| **Media.io** | Free tier | Web | Good | Browser |

### Recommendation: RIFE-ncnn-vulkan (free, local, fast)
- Converts 30fps to 120/240fps locally
- Pre-built macOS binary with Vulkan support
- CLI: `./rife-ncnn-vulkan -i input_frames/ -o output_frames/`
- GitHub: github.com/nihui/rife-ncnn-vulkan

---

## 3. Ball Tracking & Trail Visualization

### Approaches
1. **Color-based (OpenCV)**: HSV detection + contour analysis. >32fps. Best for red cricket ball.
2. **YOLO ball detection**: Roboflow has cricket ball datasets (7452+ images). YOLOv8n for fast inference.
3. **CoTracker**: Click a point on the ball, tracks through frames. Good for trajectory trails.
4. **Fulltrack AI**: Commercial cricket ball tracking app ($10/mo), 3M+ users, 3D tracking.

### Glow Trail Effect (OpenCV)
- Store ball positions in a deque
- Draw circles at each historical position with decreasing alpha
- Use cv2.addWeighted() to blend glow overlay onto frame
- Gaussian blur on trail layer for glow effect

---

## 4. AI Voice-Over

| Tool | Price | Quality | Best Voice Style |
|------|-------|---------|-----------------|
| **ElevenLabs** | Free tier / $5/mo+ | Best | "Veteran Play-by-Play" — deep baritone, confident |
| **FineVoice** | Free tier | Good | Customizable sports announcer |
| **Podcastle** | Free tier | Good | Dynamic sports announcer |
| **Bark (open source)** | Free | Decent | Less control |

### Recommendation: ElevenLabs
- Sports announcer voices in Voice Library
- API for automation: generate voice-over from script text
- Deep, authoritative tone suits analysis content

---

## 5. Auto-Captions

| Tool | Price | Trending Styles | Automation |
|------|-------|----------------|------------|
| **CapCut Desktop** | Free | Word-by-word highlight, bold pop | Manual but fast |
| **Descript** | $24/mo | Clean, professional | Edit-by-transcript |
| **Creatomate** | $39/mo+ | API-driven, JSON templates | Fully automated |

### Recommendation: CapCut for manual, Creatomate for automated pipeline

---

## 6. Trending Cricket Content Formats (2026)

### What Works
- **Technique breakdowns**: Side-by-side pro vs amateur with skeleton overlay
- **"Why X is unplayable"**: Bold hook + biomechanical proof
- **Before/after**: User improvement with data overlay
- **Micro-influencer feel**: Personal, real, relatable > polished broadcast
- **Auto-captions mandatory**: 85% of Reels watched without sound

### Content Creators to Study
- CricViz (data-driven analysis graphics)
- The Grade Cricketer (humor + insight)
- Cricket-specific TikTok creators using match reactions + analysis overlay

---

## 7. Gemini Video Understanding (Your Secret Weapon)

- Gemini 2.5 Pro: state-of-the-art video understanding
- File API samples at 1fps (sufficient for bowling technique, not ball tracking)
- Can generate detailed biomechanical analysis text from video
- **Your app already does this** — repurpose analysis output as social media narration
- Community requesting higher FPS (5-10fps) for sports — may improve

---

## 8. Automated Pipeline Architecture

### Python Stack (All Free, Mac-native)

```
Raw Video (.mov)
    |
    v
[MediaPipe Pose] --> skeleton overlay frames
    |
    v
[YOLO Ball Detection] --> ball position tracking
    |
    v
[OpenCV Compositing] --> skeleton + trail + angle lines + phase labels
    |
    v
[RIFE] --> 30fps to 120fps slow motion
    |
    v
[Gemini API] --> generate analysis text from video
    |
    v
[ElevenLabs API] --> voice-over audio from analysis text
    |
    v
[FFmpeg] --> composite video + audio + captions --> final clip
```

### Key Python Packages
```
pip install mediapipe opencv-python ultralytics numpy ffmpeg-python
pip install pyobjc-framework-Vision  # optional: Apple native pose
```

---

## Sources

- [MediaPipe Pose Landmarker Python Guide](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker/python)
- [YOLO11 Pose Estimation](https://docs.ultralytics.com/tasks/pose/)
- [RIFE-ncnn-vulkan](https://github.com/nihui/rife-ncnn-vulkan)
- [CoTracker (Meta)](https://github.com/facebookresearch/co-tracker)
- [Cricket Bowling AI Analysis with YOLO](https://www.labellerr.com/blog/cricket-bowling-analysis-yolov8-pose/)
- [OpenCap Bowling Accuracy Study 2025](https://journals.sagepub.com/doi/10.1177/17479541251348081)
- [Fulltrack AI](https://www.fulltrack.ai/)
- [ElevenLabs Sports Voices](https://elevenlabs.io/voice-library/sports-announcer-voices)
- [Gemini 2.5 Video Understanding](https://developers.googleblog.com/en/gemini-2-5-video-understanding/)
- [Creatomate API](https://creatomate.com/)
- [TechniqueView AI Pose Detection](https://www.techniqueview.com/)
- [Apple Vision Body Pose](https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest)
- [Cricket Pose Estimation Research](https://www.mdpi.com/1424-8220/23/15/6839)
- [Ball Tracking with OpenCV](https://pyimagesearch.com/2015/09/14/ball-tracking-with-opencv/)
- [Topaz Video AI Pricing](https://www.topazlabs.com/pricing)
