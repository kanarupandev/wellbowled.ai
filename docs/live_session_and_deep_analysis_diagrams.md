# Live Session + Deep Analysis Diagrams

**Date**: 2026-03-03  
**Repo**: `/Users/kanarupan/workspace/wellbowled.ai`  
**Scope**: Current app flow (Home -> Live session), end-session results, per-delivery deep analysis, async execution.

## 1) End-to-End Demo Flow (4 minutes)

```mermaid
flowchart TD
    A["Home"] --> B["Open Live Session"]
    B --> C["Mate Greets Briefly"]
    C --> D["Ask Plan for Today"]
    D --> E["Setup Verification + Pilot Run"]
    E --> F["Session Started (3-minute timer)"]
    F --> G["Delivery Detection (on-device)"]
    G --> H["Live Feedback (brief)"]
    H --> J{"Session End Trigger"}
    J -->|"Timeout"| K["Auto-Navigate to Deliveries"]
    J -->|"End Button"| K
    J -->|"Voice: end session"| K
    K --> L["Horizontal Delivery Carousel (5s clips + release thumbnail)"]
    L --> M["Tap Deep Analysis (on demand per delivery)"]
    M --> N["Spinner + 2s telemetry bullets (20 steps max)"]
    N --> O["Deep Analysis Ready"]
    O --> P["Swipe Down: Phase-wise Good/Bad/Ugly + Injury Risk"]
    P --> Q["Swipe Down: DNA Match (Top 1-3 bowlers)"]
    Q --> R["Swipe Down: MediaPipe Overlay + Legend"]
    R --> S["Chips Panel: Focus/Pause/Slow-mo"]
    S --> T["Chip-driven Gemini control response updates playback focus"]
```

## 2) On-Demand Deep Analysis Async Pipeline

```mermaid
sequenceDiagram
    participant U as User
    participant V as LiveSessionView
    participant VM as SessionViewModel
    participant G as GeminiAnalysisService
    participant P as ClipPoseExtractor
    participant D as DNAMatcher

    U->>V: Tap "Deep Analysis"
    V->>VM: runDeepAnalysisIfNeeded(deliveryID)
    VM->>VM: Start telemetry loop (2s cadence)
    par Detailed Gemini analysis
        VM->>G: analyzeDeliveryDeep(clipURL)
        G-->>VM: summary + phases + expertAnalysis
    and DNA extraction/match
        VM->>G: extractBowlingDNA(clipURL + release metrics)
        G-->>VM: BowlingDNA
        VM->>D: match(userDNA, topN=3)
        D-->>VM: top matches
    and Local pose extraction
        VM->>P: extractFrames(clipURL, fixed FPS)
        P-->>VM: frame landmarks
    and Challenge scoring (challenge mode only)
        VM->>G: evaluateChallenge(clipURL, target)
        G-->>VM: hit/miss + reason
    end
    VM->>VM: Stop telemetry loop
    VM-->>V: Update status = ready, artifacts + report
    V-->>U: Enable downward swipe sections + chips controls
```

## 3) Per-Delivery Deep Analysis State Machine

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> running: Tap "Deep Analysis"
    running --> ready: Detailed result parsed
    running --> failed: Detailed analysis error
    failed --> running: Retry tap
    ready --> running: Re-run deep analysis
```

## 4) Results Navigation Model

```mermaid
flowchart LR
    A["Results Root"] --> B["Delivery Card (Horizontal swipe left/right)"]
    B --> C["Section 0: Clip + thumbnail + high-level summary"]
    C --> D["Section 1 (down): Phase insights"]
    D --> E["Section 2 (down): DNA matches (Top 1-3)"]
    E --> F["Section 3 (down): Pose overlay + legend"]
    F --> G["Section 4 (down): Chips panel + chat-style responses"]
```

