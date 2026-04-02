"""Extract and verify pose angles from Bumrah and Steyn clips."""
import sys
import math
from pathlib import Path

import cv2
import numpy as np

# Add src to path
SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

from pose_extractor import extract_poses

REPO = Path(__file__).resolve().parents[2]
BUMRAH = str(REPO / "resources" / "samples" / "bumrah_side_on_3sec.mp4")
STEYN = str(REPO / "resources" / "samples" / "steyn_side_on_3sec.mp4")

# Landmark indices
LEFT_SHOULDER, RIGHT_SHOULDER = 11, 12
LEFT_HIP, RIGHT_HIP = 23, 24
LEFT_KNEE, LEFT_ANKLE = 25, 27
RIGHT_KNEE, RIGHT_ANKLE = 26, 28
LEFT_ELBOW, LEFT_WRIST = 13, 15
RIGHT_ELBOW, RIGHT_WRIST = 14, 16


def angle_3pt(a, b, c):
    """Angle at point b formed by points a-b-c, in degrees."""
    if any(p[2] < 0.4 for p in [a, b, c]):
        return None
    ba = (a[0] - b[0], a[1] - b[1])
    bc = (c[0] - b[0], c[1] - b[1])
    dot = ba[0] * bc[0] + ba[1] * bc[1]
    mag_ba = math.sqrt(ba[0]**2 + ba[1]**2)
    mag_bc = math.sqrt(bc[0]**2 + bc[1]**2)
    if mag_ba < 1e-6 or mag_bc < 1e-6:
        return None
    cos_angle = max(-1, min(1, dot / (mag_ba * mag_bc)))
    return math.degrees(math.acos(cos_angle))


def line_angle_deg(p1, p2):
    """Angle of line p1->p2 from horizontal, in degrees."""
    if p1[2] < 0.4 or p2[2] < 0.4:
        return None
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    if abs(dx) < 0.02 and abs(dy) < 0.02:
        return None
    return math.degrees(math.atan2(dy, dx))


def hip_shoulder_sep(pts):
    """Hip-shoulder separation (X-Factor)."""
    hip_a = line_angle_deg(pts[LEFT_HIP], pts[RIGHT_HIP])
    sho_a = line_angle_deg(pts[LEFT_SHOULDER], pts[RIGHT_SHOULDER])
    if hip_a is None or sho_a is None:
        return None, hip_a, sho_a
    sep = abs(hip_a - sho_a)
    if sep > 180:
        sep = 360 - sep
    return round(sep, 1), round(hip_a, 1), round(sho_a, 1)


def front_knee_angle(pts):
    """Front knee angle. For right-arm bowlers, front leg is LEFT leg.
    For side-on view, use whichever knee is more forward (lower x in normalized coords
    for a bowler bowling left-to-right, or higher x for right-to-left).
    We compute both and return both."""
    left_knee = angle_3pt(pts[LEFT_HIP], pts[LEFT_KNEE], pts[LEFT_ANKLE])
    right_knee = angle_3pt(pts[RIGHT_HIP], pts[RIGHT_KNEE], pts[RIGHT_ANKLE])
    return left_knee, right_knee


def analyze_clip(name, path):
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"  {path}")
    print(f"{'='*60}")

    data = extract_poses(path)
    fps = data["fps"]
    frames = data["frames"]
    print(f"  Frames: {len(frames)}, FPS: {fps}, Resolution: {data['width']}x{data['height']}")

    print(f"\n  {'Frame':>5} {'Time':>6} {'X-Factor':>8} {'HipAng':>7} {'ShoAng':>7} {'LKnee':>6} {'RKnee':>6} {'Vis':>4}")
    print(f"  {'-'*5} {'-'*6} {'-'*8} {'-'*7} {'-'*7} {'-'*6} {'-'*6} {'-'*4}")

    best_xf_frame = None
    best_xf_val = 0

    for f in frames:
        pts = f.get("landmarks")
        if pts is None:
            print(f"  {f['index']:>5} {f['time']:>6.2f}   no pose")
            continue

        sep, hip_a, sho_a = hip_shoulder_sep(pts)
        lk, rk = front_knee_angle(pts)

        # Mean visibility of key joints
        key_joints = [LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP,
                      LEFT_KNEE, RIGHT_KNEE, LEFT_ANKLE, RIGHT_ANKLE]
        vis = sum(pts[j][2] for j in key_joints) / len(key_joints)

        sep_s = f"{sep:>6.1f}°" if sep is not None else "   N/A "
        hip_s = f"{hip_a:>6.1f}" if hip_a is not None else "   N/A"
        sho_s = f"{sho_a:>6.1f}" if sho_a is not None else "   N/A"
        lk_s = f"{lk:>5.0f}°" if lk is not None else "  N/A "
        rk_s = f"{rk:>5.0f}°" if rk is not None else "  N/A "

        print(f"  {f['index']:>5} {f['time']:>6.2f} {sep_s} {hip_s} {sho_s} {lk_s} {rk_s} {vis:>.2f}")

        if sep is not None and sep > best_xf_val:
            best_xf_val = sep
            best_xf_frame = f['index']

    print(f"\n  Peak X-Factor: {best_xf_val:.1f}° at frame {best_xf_frame}")
    return data


if __name__ == "__main__":
    print("Bumrah vs Steyn — Angle Extraction & Verification")
    bumrah_data = analyze_clip("BUMRAH (MI Nets)", BUMRAH)
    steyn_data = analyze_clip("STEYN (SA Nets)", STEYN)
