# Cricket Bowling AI Resources

**Last updated**: 2025-02-25

---

## Datasets

### Bowling-Specific

| Name | What | Free? | Link |
|------|------|-------|------|
| **Cricket Ball Dataset (YOLO)** | 1068 labeled ball images for YOLO training | Free | [Kaggle](https://www.kaggle.com/datasets/kushagra3204/cricket-ball-dataset-for-yolo) |
| **No-Ball Detection Dataset** | Foot no-ball images for transfer learning | OSS | [GitHub](https://github.com/TanjimKIT/No-Ball-Detection-Dataset) |
| **RAIE Transformer Dataset** | 212 annotated deliveries with ball trajectory data | OSS | [GitHub](https://github.com/HiteshDereddy/RAIE-Transformer) |
| **Cricket Wide Balls** | Wide vs not-wide images with calibration data | Free | [Kaggle](https://www.kaggle.com/datasets/vaarunkamath/cricket-wide-balls-dataset) |
| **FPVShotDetection** | Front pitch view ball tracking annotations | OSS | [GitHub](https://github.com/KumailAbb/FPVShotDetection) |
| **Cricsheet** | Ball-by-ball data for all international cricket (YAML/JSON/CSV) | Free | [cricsheet.org](https://cricsheet.org) |

### Action Recognition (includes bowling classes)

| Name | What | Free? | Link |
|------|------|-------|------|
| **UCF101** | 101 action classes including "Cricket Bowling" | Free | [Kaggle](https://www.kaggle.com/datasets/matthewjansen/ucf101-action-recognition) |
| **Kinetics-400/600** | Large-scale video actions including "bowling (cricket)" | Free | [DeepMind](https://www.deepmind.com/open-source/kinetics) |
| **CricShot10** | 10 cricket shot classes from YouTube (batting-focused) | OSS | [GitHub](https://github.com/ascuet/CricShot10) |

---

## Pre-Trained Models

### Cricket-Specific

| Name | What | Link |
|------|------|------|
| **VideoMAE cricket classification** | Video classifier fine-tuned on cricket actions | [HuggingFace](https://huggingface.co/tahawarsi360/videomae-base-finetuned-cricket-classification) |
| **Suspected Bowling Action Recognition** | VGG16 legal/illegal bowling classifier | [GitHub](https://github.com/adnanfazal01/Suspected-Bowling-Action-Recognition) |
| **RAIE Transformer** | Cricket ball trajectory prediction (MSE 3.95) | [GitHub](https://github.com/HiteshDereddy/RAIE-Transformer) |

### General (highly applicable)

| Name | What | Link |
|------|------|------|
| **TimeSformer (Meta)** | Video classification, Kinetics-400 (includes bowling), 85K downloads | [HuggingFace](https://huggingface.co/facebook/timesformer-base-finetuned-k400) |
| **VideoMAE base** | Self-supervised video pre-training, fine-tunable for bowling | [HuggingFace](https://huggingface.co/MCG-NJU/videomae-base) |
| **MediaPipe Pose** | 33 body landmarks, on-device, iOS/Android/Python | [Google](https://developers.google.com/mediapipe/solutions/vision/pose_landmarker) |
| **MoveNet** | Fast pose detection, Lightning/Thunder variants | [TFHub](https://tfhub.dev/google/movenet/singlepose/thunder) |

### Pose Estimation Frameworks

| Name | What | Stars | Link |
|------|------|-------|------|
| **AlphaPose** | Multi-person real-time pose estimation | 8.5K | [GitHub](https://github.com/MVIG-SJTU/AlphaPose) |
| **MMPose** | OpenMMLab pose toolbox (RTMPose) | 7.4K | [GitHub](https://github.com/open-mmlab/mmpose) |
| **ViTPose** | Vision Transformer SOTA pose estimation | 1.9K | [GitHub](https://github.com/ViTAE-Transformer/ViTPose) |
| **rtmlib** | Lightweight RTMPose without heavy deps | 507 | [GitHub](https://github.com/Tau-J/rtmlib) |
| **Pose2Sim** | 2D pose → 3D OpenSim biomechanics | 573 | [GitHub](https://github.com/perfanalytics/pose2sim) |

### Ball Tracking

| Name | What | Stars | Link |
|------|------|-------|------|
| **TrackNetV3** | Small fast-moving ball tracking (shuttlecock→cricket) | 179 | [GitHub](https://github.com/qaz812345/TrackNetV3) |
| **TrackNetV4** | Latest generation ball tracking | 32 | [GitHub](https://github.com/TrackNetV4/TrackNetV4) |

---

## Open Source Bowling Analysis Projects

| Name | What | Link |
|------|------|------|
| **BowlForm AI** | MediaPipe + DeepSeek for bowling form feedback | [GitHub](https://github.com/Faizanras00l/cricket-bowling-analyzer) |
| **AI Fast Bowling Analysis** | YOLOv8 pose + ball tracking + injury risk | [GitHub](https://github.com/Skalya-23/ai-fastbowling-analysis) |
| **Bowling Analysis** | CV biomechanics: lean angle, head position, release speed | [GitHub](https://github.com/GOWTHAM-2709/Bowling-Analysis) |
| **Bowling Action Validation** | Elbow extension vs ICC 15° limit via Streamlit | [GitHub](https://github.com/shazhani/validating-bowling-action-using-DL) |
| **Illegal Bowling Classifier** | LSTM + pose for bowling phase prediction + legality | [GitHub](https://github.com/mick-riley/cv-illegal-bowling-classifier) |
| **Cricket Bowling Biomechanics** | Wrist/elbow trajectories + DTW motion alignment | [GitHub](https://github.com/Dhruvkulshrestha018/Cricket-Bowling-Biomechanics) |
| **SpinVision** | Ball trajectory + spin effect estimation | [GitHub](https://github.com/abhijitshukla/SpinVision) |
| **CrickNova-AI** | Speed, swing, spin tracking + AI coaching | [GitHub](https://github.com/Prasad72-max/CrickNova-AI) |
| **Cricket 3D Motion Biomechanics** | 3D analysis + coach feedback for batting/bowling/fielding | [GitHub](https://github.com/amruthadevops/Cricket-AI-Motion-Biomechanics-Corrective-Feedback) |

---

## Commercial (No Public Access)

| Name | What | Access |
|------|------|--------|
| **Hawk-Eye** | Gold standard ball tracking, DRS, speed — used by ICC | Licensed to boards/broadcasters only |
| **CricViz** | Expected Wickets, control %, seam/swing metrics | B2B platform only |
| **PitchVision** | Camera + sensor system for club coaching | Paid hardware + subscription |
| **Bola Cricket** | Smartphone bowling/batting analysis app | Paid app |

---

## Key Gaps (Opportunities for wellBowled)

1. **No public bowling video dataset with pose + ball + phase annotations** — biggest gap
2. **No bowling phase segmentation model** (run-up → gather → delivery stride → release → follow-through)
3. **No public speed estimation from single-camera model**
4. **No cricket-specific embedding/vector store** for action similarity search
5. **No mobile-optimized bowling analysis models** — most projects are desktop Python
6. **No TrackNet fine-tuned on cricket ball** with released weights

---

## Most Relevant for wellBowled Right Now

| Priority | Resource | Why |
|----------|----------|-----|
| 1 | **MediaPipe Pose** | Already using. On-device, 33 landmarks, iOS ready |
| 2 | **Cricket Ball YOLO Dataset** | Fine-tune YOLOv8-nano for ball detection (future speed estimation) |
| 3 | **RAIE Transformer** | Ball trajectory prediction with 212 delivery dataset |
| 4 | **Cricsheet** | Ball-by-ball data for bowling analytics features |
| 5 | **VideoMAE (Kinetics-400)** | Already has "bowling (cricket)" class — fine-tune for action detection |
| 6 | **Pose2Sim** | 2D → 3D biomechanics for Expert analysis |
| 7 | **TrackNetV3/V4** | Ball tracking architecture to adapt for cricket |
