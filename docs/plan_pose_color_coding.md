# Plan: Biomechanical Pose Color Coding

**Goal:** Color-code 9 key MediaPipe pose dots based on Gemini deep analysis feedback. Green = good to maintain, amber = attention area, red = injury risk. Only show top 3-5 high-confidence findings. The skeleton overlay becomes a visual X-ray of the bowler's action.

## Current State

- `AnalysisPhase` has `clipTimestamp` (time in clip) but no body part or severity
- `FramePoseLandmarks` has all 33 MediaPipe landmarks per frame with timestamps
- `SyncedSkeletonOverlayView` renders dots synced to video playback
- `SkeletonRenderer` draws all landmarks as uniform white dots
- Deep analysis prompt returns phases (run-up, bound, delivery stride, etc.) but not body-part-level assessments

## The 9 Key Dots

| Index | Landmark | MediaPipe ID |
|-------|----------|-------------|
| 1 | Head (nose) | 0 |
| 2 | Left shoulder | 11 |
| 3 | Right shoulder | 12 |
| 4 | Left hip | 23 |
| 5 | Right hip | 24 |
| 6 | Left knee | 25 |
| 7 | Right knee | 26 |
| 8 | Left ankle | 27 |
| 9 | Right ankle | 28 |

## Color Scheme

- **Green** (#20C997): Good technique, maintain this
- **Amber** (#F4A261): Attention area, room for improvement
- **Red** (#E63946): Injury risk, biomechanical concern

## How It Works

### 1. Gemini returns body-part annotations (new field in deep analysis)

Add to the deep analysis prompt: ask Gemini to return a `body_annotations` array alongside existing phases. Each annotation is:

```json
{
  "body_annotations": [
    {
      "body_part": "left_knee",
      "time": 2.1,
      "status": "attention",
      "reason": "Front knee collapsing inward at delivery stride"
    },
    {
      "body_part": "right_shoulder",
      "time": 1.8,
      "status": "good",
      "reason": "Excellent shoulder rotation through the crease"
    }
  ]
}
```

- `body_part`: one of `head`, `left_shoulder`, `right_shoulder`, `left_hip`, `right_hip`, `left_knee`, `right_knee`, `left_ankle`, `right_ankle`
- `time`: clip timestamp (seconds)
- `status`: `good` | `attention` | `injury_risk`
- `reason`: short explanation
- **Max 5 annotations, high confidence only** — instructed in prompt

### 2. New model: `BodyAnnotation`

```swift
struct BodyAnnotation: Codable, Equatable {
    let bodyPart: String    // e.g. "left_knee"
    let time: Double        // clip timestamp
    let status: String      // "good", "attention", "injury_risk"
    let reason: String

    var color: Color { ... } // green/amber/red based on status
    var landmarkIndex: Int { ... } // maps bodyPart string to MediaPipe landmark ID
}
```

### 3. Store annotations on `DeliveryDeepAnalysisArtifacts`

```swift
struct DeliveryDeepAnalysisArtifacts {
    var poseFrames: [FramePoseLandmarks] = []
    var poseFailureReason: String?
    var expertAnalysis: ExpertAnalysis?
    var chipReply: String?
    var bodyAnnotations: [BodyAnnotation] = []  // NEW
}
```

### 4. SkeletonRenderer uses annotations to color dots

- For each frame at time `t`, find annotations within ±0.3s
- If an annotation matches a landmark, color that dot accordingly
- Non-annotated dots stay white (neutral)
- Only render the 9 key dots (filter out fingers, toes, etc.)

## Changes

### GeminiAnalysisService.swift
- Add `body_annotations` to deep analysis prompt
- Parse `body_annotations` from response JSON
- Return alongside existing `DeliveryDeepAnalysisResult`

### DeepAnalysisModels.swift
- Add `struct BodyAnnotation`
- Add `bodyAnnotations` to `DeliveryDeepAnalysisArtifacts`

### Models.swift or DeepAnalysisModels.swift
- Add `DeliveryDeepAnalysisResult.bodyAnnotations: [BodyAnnotation]`

### SessionViewModel.swift
- Store parsed `bodyAnnotations` in `deepAnalysisArtifactsByDelivery`

### SkeletonRenderer.swift
- Accept `[BodyAnnotation]` as input
- When drawing dots, check if current landmark + timestamp has an annotation
- Color the dot green/amber/red accordingly
- Enlarge annotated dots slightly for visibility

### SkeletonSyncController.swift
- Pass `bodyAnnotations` through to renderer

## What This Achieves

- Visual biomechanical feedback overlaid on the delivery video
- Bowler immediately sees which body parts are good vs need attention
- Only top 3-5 high-confidence findings — no noise
- Injury risk areas highlighted in red — safety value
- Works with existing skeleton overlay infrastructure
