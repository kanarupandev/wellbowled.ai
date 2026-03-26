"""Stage 4: Compute hip-shoulder separation (X-Factor) per frame."""
from __future__ import annotations

import json
import math
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
POSE_FILE = OUTPUT_DIR / "pose_data.json"
PLAN_FILE = OUTPUT_DIR / "flash_plan.json"
XFACTOR_FILE = OUTPUT_DIR / "xfactor_data.json"

# Landmark indices
L_HIP, R_HIP = 23, 24
L_SHOULDER, R_SHOULDER = 11, 12

# Reasonable X-Factor range for cricket bowling
MAX_REASONABLE_SEPARATION = 80.0  # degrees
MIN_VISIBILITY = 0.5  # landmark confidence threshold


def compute_angle(p1: dict, p2: dict) -> float:
    """Angle of line p1→p2 from horizontal, in degrees."""
    return math.degrees(math.atan2(p2["y"] - p1["y"], p2["x"] - p1["x"]))


def landmarks_visible(lm: list[dict], indices: list[int], threshold: float = MIN_VISIBILITY) -> bool:
    """Check all specified landmarks meet visibility threshold."""
    return all(lm[i]["visibility"] >= threshold for i in indices)


def run() -> dict:
    pose_data = json.loads(POSE_FILE.read_text())

    # Load phases for labelling
    plan = {}
    if PLAN_FILE.exists():
        plan = json.loads(PLAN_FILE.read_text())
    phases = plan.get("phases", {})

    frames = []
    peak_sep = 0.0
    peak_idx = 0

    for i, fd in enumerate(pose_data):
        lm = fd.get("landmarks")
        entry = {
            "frame": fd["frame"],
            "frame_index": i,
            "time_s": round(i / 10.0, 2),  # 10fps extraction
            "hip_angle": None,
            "shoulder_angle": None,
            "separation": None,
            "phase": None,
            "reliable": False,
        }

        if lm and landmarks_visible(lm, [L_HIP, R_HIP, L_SHOULDER, R_SHOULDER]):
            lh, rh = lm[L_HIP], lm[R_HIP]
            ls, rs = lm[L_SHOULDER], lm[R_SHOULDER]

            hip_angle = compute_angle(lh, rh)
            shoulder_angle = compute_angle(ls, rs)

            # Handle angle wrapping
            raw_sep = abs(hip_angle - shoulder_angle)
            if raw_sep > 180:
                raw_sep = 360 - raw_sep

            entry["hip_angle"] = round(hip_angle, 1)
            entry["shoulder_angle"] = round(shoulder_angle, 1)
            entry["separation"] = round(raw_sep, 1)
            entry["reliable"] = raw_sep <= MAX_REASONABLE_SEPARATION

            # Only consider reliable frames during delivery for peak
            # X-Factor peaks between back_foot_contact and follow_through
            if entry["reliable"] and raw_sep > peak_sep:
                t_bfc = phases.get("back_foot_contact", 0.0)
                t_ft = phases.get("follow_through", 999)
                if t_bfc <= entry["time_s"] <= t_ft:
                    peak_sep = raw_sep
                    peak_idx = i

        # Determine current phase
        t = entry["time_s"]
        if phases:
            if t < phases.get("back_foot_contact", 999):
                entry["phase"] = "RUN_UP"
            elif t < phases.get("front_foot_contact", 999):
                entry["phase"] = "BACK_FOOT_CONTACT"
            elif t < phases.get("front_foot_contact", 999) + 0.3:
                entry["phase"] = "FRONT_FOOT_CONTACT"
            elif t < phases.get("release", 999):
                entry["phase"] = "FRONT_FOOT_CONTACT"
            elif t < phases.get("follow_through", 999):
                entry["phase"] = "RELEASE"
            else:
                entry["phase"] = "FOLLOW_THROUGH"

        frames.append(entry)

    result = {
        "frames": frames,
        "peak_separation_frame": peak_idx,
        "peak_separation_angle": round(peak_sep, 1),
        "peak_frame_name": frames[peak_idx]["frame"] if frames else None,
        "peak_time_s": frames[peak_idx]["time_s"] if frames else None,
        "peak_phase": frames[peak_idx]["phase"] if frames else None,
        "reliable_frames": sum(1 for f in frames if f["reliable"]),
        "total_frames": len(frames),
    }

    print(f"  Peak X-Factor: {peak_sep:.1f}° at frame {peak_idx} ({result['peak_time_s']}s)")
    print(f"  Phase at peak: {result['peak_phase']}")
    print(f"  Reliable frames: {result['reliable_frames']}/{result['total_frames']}")

    with open(XFACTOR_FILE, "w") as f:
        json.dump(result, f, indent=2)

    return result


if __name__ == "__main__":
    result = run()
    for f in result["frames"]:
        sep = f["separation"]
        if sep is not None:
            marker = ""
            if f["frame_index"] == result["peak_separation_frame"]:
                marker = " ◄ PEAK"
            elif not f["reliable"]:
                marker = " (noisy)"
            bar = "█" * min(int(sep), 60)
            print(f"  {f['time_s']:5.2f}s  {sep:5.1f}°  {bar}{marker}")
