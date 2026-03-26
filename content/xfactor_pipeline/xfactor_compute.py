"""X-factor computation: hip-shoulder separation with smoothing and noise rejection.

Features from the production linux pipeline:
- Median smoothing (window 5)
- Capping at 60 degrees
- Side-on noise rejection (MIN_LINE_SPREAD 0.03)
- Heuristic phase detection from separation curve
"""
from __future__ import annotations

import math

LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_HIP = 23
RIGHT_HIP = 24

# Visibility threshold for x-factor joints
XFACTOR_VISIBILITY_THRESHOLD = 0.5

# Max plausible x-factor angle
MAX_PLAUSIBLE_SEPARATION = 60.0

# Minimum horizontal spread to accept a hip/shoulder line
# Rejects side-on views where left/right collapse to same point
MIN_LINE_SPREAD = 0.03  # 3% of frame dimension

# Temporal median smoothing window
SMOOTH_WINDOW = 5


def _line_angle_deg(
    p1: tuple[float, float, float],
    p2: tuple[float, float, float],
) -> float | None:
    """Angle of line p1->p2 from horizontal, in degrees.

    Returns None if landmarks aren't visible or line is too short (side-on noise).
    """
    if p1[2] < XFACTOR_VISIBILITY_THRESHOLD or p2[2] < XFACTOR_VISIBILITY_THRESHOLD:
        return None
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

    Adds:
        hip_angle, shoulder_angle, separation_raw, separation (smoothed+capped)
    """
    # Pass 1: raw angles
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
            sep = min(sep, MAX_PLAUSIBLE_SEPARATION)
        else:
            sep = None

        frame["hip_angle"] = hip_angle
        frame["shoulder_angle"] = shoulder_angle
        frame["separation_raw"] = sep
        frame["separation"] = sep

    # Pass 2: temporal median smoothing
    raw_values = [f["separation_raw"] for f in frames]
    half_w = SMOOTH_WINDOW // 2
    smoothed = []
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
    """Frame with maximum smoothed hip-shoulder separation."""
    valid = [f for f in frames if f.get("separation") is not None]
    if not valid:
        return None
    return max(valid, key=lambda f: f["separation"])


def detect_phases_heuristic(frames: list[dict]) -> dict:
    """Heuristic phase detection from the separation curve.

    Returns dict with phase timestamps:
        back_foot_contact, front_foot_contact, release, follow_through
    """
    valid = [f for f in frames if f.get("separation") is not None]
    total_time = frames[-1]["time"] if frames else 1.0

    if not valid:
        return {
            "back_foot_contact": 0.0,
            "front_foot_contact": total_time * 0.35,
            "release": total_time * 0.5,
            "follow_through": total_time * 0.7,
        }

    peak = find_peak_separation(frames)
    peak_time = peak["time"]

    return {
        "back_foot_contact": max(0.0, peak_time - 0.4),
        "front_foot_contact": max(0.0, peak_time - 0.1),
        "release": peak_time,
        "follow_through": min(total_time, peak_time + 0.3),
    }
