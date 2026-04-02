"""Stage 4: Compute hip-shoulder separation (X-factor) per frame."""
from __future__ import annotations

import math
from collections import deque

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24

# Higher threshold for x-factor joints — they must be clearly visible
XFACTOR_VISIBILITY_THRESHOLD = 0.5

# Maximum plausible x-factor angle (anything above is noise)
MAX_PLAUSIBLE_SEPARATION = 60.0

# Minimum horizontal spread for a hip/shoulder line to be meaningful
# (rejects side-on views where left/right collapse to same point)
MIN_LINE_SPREAD = 0.03  # 3% of frame width

# Smoothing window for temporal stability
SMOOTH_WINDOW = 5


def _line_angle_deg(p1: tuple[float, float, float], p2: tuple[float, float, float]) -> float | None:
    """Angle of line p1->p2 from horizontal, in degrees.
    Returns None if landmarks aren't visible or line is too short (side-on noise).
    """
    if p1[2] < XFACTOR_VISIBILITY_THRESHOLD or p2[2] < XFACTOR_VISIBILITY_THRESHOLD:
        return None
    # Reject if the two points are too close horizontally (side-on view = noise)
    if abs(p2[0] - p1[0]) < MIN_LINE_SPREAD and abs(p2[1] - p1[1]) < MIN_LINE_SPREAD:
        return None
    return math.degrees(math.atan2(p2[1] - p1[1], p2[0] - p1[0]))


def _median(values: list[float]) -> float:
    s = sorted(values)
    n = len(s)
    if n % 2 == 1:
        return s[n // 2]
    return (s[n // 2 - 1] + s[n // 2]) / 2


def compute_xfactor(frames: list[dict]) -> list[dict]:
    """Add x-factor data to each frame dict.

    Adds to each frame:
      - hip_angle: degrees (or None)
      - shoulder_angle: degrees (or None)
      - separation_raw: raw absolute difference (or None)
      - separation: smoothed + capped separation (or None)
    """
    # First pass: compute raw angles
    for frame in frames:
        pts = frame.get("landmarks")
        if pts is None:
            frame["hip_angle"] = None
            frame["shoulder_angle"] = None
            frame["separation_raw"] = None
            frame["separation"] = None
            continue

        hip_angle = _line_angle_deg(pts[LEFT_HIP], pts[RIGHT_HIP])
        shoulder_angle = _line_angle_deg(pts[LEFT_SHOULDER], pts[RIGHT_SHOULDER])

        if hip_angle is not None and shoulder_angle is not None:
            sep = abs(hip_angle - shoulder_angle)
            if sep > 180:
                sep = 360 - sep
            # Cap at plausible max
            sep = min(sep, MAX_PLAUSIBLE_SEPARATION)
        else:
            sep = None

        frame["hip_angle"] = hip_angle
        frame["shoulder_angle"] = shoulder_angle
        frame["separation_raw"] = sep
        frame["separation"] = sep

    # Second pass: temporal median smoothing
    raw_values = [f["separation_raw"] for f in frames]
    smoothed = []
    half_w = SMOOTH_WINDOW // 2
    for i in range(len(frames)):
        window = []
        for j in range(max(0, i - half_w), min(len(frames), i + half_w + 1)):
            if raw_values[j] is not None:
                window.append(raw_values[j])
        if window:
            smoothed.append(_median(window))
        else:
            smoothed.append(None)

    for i, frame in enumerate(frames):
        frame["separation"] = smoothed[i]

    return frames


def find_peak_separation(frames: list[dict]) -> dict | None:
    """Find the frame with maximum hip-shoulder separation."""
    valid = [f for f in frames if f.get("separation") is not None]
    if not valid:
        return None
    return max(valid, key=lambda f: f["separation"])


def detect_phases_heuristic(frames: list[dict]) -> dict:
    """Simple heuristic phase detection based on separation curve.

    Returns dict with phase timestamps:
      - back_foot_contact: separation starts rising
      - front_foot_contact: near peak separation
      - release: peak separation
      - follow_through: after peak, separation collapsing
    """
    valid = [f for f in frames if f.get("separation") is not None]
    if not valid:
        total_time = frames[-1]["time"] if frames else 1.0
        return {
            "back_foot_contact": 0.0,
            "front_foot_contact": total_time * 0.35,
            "release": total_time * 0.5,
            "follow_through": total_time * 0.7,
        }

    peak = find_peak_separation(frames)
    peak_time = peak["time"]
    total_time = frames[-1]["time"]

    return {
        "back_foot_contact": max(0.0, peak_time - 0.4),
        "front_foot_contact": max(0.0, peak_time - 0.1),
        "release": peak_time,
        "follow_through": min(total_time, peak_time + 0.3),
    }
