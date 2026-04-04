# Review Flow

## Purpose

`wellBowled_v2` uses a video-first review flow for marking bowling clips and estimating pace from frame timing.

Global settings:

- `Goal speed` is edited on the home screen and reused in review
- `Distance` is editable in review per clip, and the last chosen value becomes the default for the next clips

## First Pass

1. Set `Release`
2. Set `End`
3. Keep the default distance or edit it

Once both markers exist, the result panel appears automatically.

## Editable Fields

After the first pass, these can be adjusted independently at any time:

- `Release`
- `End`
- `Distance`

Rules:

- `End` cannot be set before `Release`
- moving `Release` past `End` clears `End`
- calculations refresh from the current markers and distance
- editing distance updates the global default used for subsequent videos

## Displayed Metrics

The result panel intentionally stays narrow:

- `Time diff` in seconds, formatted as `xx.xx s`
- `Estimated speed` in km/h
- `Frame-pick variance` as `± km/h`
- `Goal speed` from the home screen
- `Time delta vs goal` in seconds

The review screen does not show preview thumbnails. Navigation is handled through:

- swipe scrubbing on the video
- frame slider
- `±1` and `±10` seek buttons
- pinch to zoom the frame
- drag to pan while zoomed
- double-tap to reset zoom

The UI does not depend on the displayed rounded values for calculation. It calculates from:

- `releaseFrame`
- `arrivalFrame`
- `fps`
- `distanceMeters`

## Cached Metadata

The frame marker store keeps enough clip metadata for quick reuse:

- file name
- release frame
- end frame
- distance
- fps
- total frames
- duration
- saved timestamp

Current lookup key is the file name. Saved clips exported by the app already use UUID-based file names.
