"""
Experiment 003: MediaPipe Ground Truth Release Point
====================================================
Get the actual release timestamp from pose data.
Validates which Gemini thinkingLevel is more accurate.
"""

import cv2
import mediapipe as mp
import math
import os
import json

VIDEO_PATH = os.path.join(os.path.dirname(__file__), "../../resources/samples/3_sec_1_delivery_nets.mp4")
MODEL_PATH = os.path.join(os.path.dirname(__file__), "../../resources/pose_landmarker_heavy.task")

PoseLandmarker = mp.tasks.vision.PoseLandmarker
PoseLandmarkerOptions = mp.tasks.vision.PoseLandmarkerOptions
BaseOptions = mp.tasks.BaseOptions
VisionRunningMode = mp.tasks.vision.RunningMode


def main():
    cap = cv2.VideoCapture(VIDEO_PATH)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps

    print(f"Video: {os.path.basename(VIDEO_PATH)}")
    print(f"FPS: {fps}, Frames: {total_frames}, Duration: {duration:.2f}s")

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=VisionRunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    frames_data = []

    with PoseLandmarker.create_from_options(options) as landmarker:
        frame_idx = 0
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            ts_ms = int(frame_idx * 1000 / fps)
            ts_s = frame_idx / fps
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            result = landmarker.detect_for_video(mp_image, ts_ms)

            entry = {"frame": frame_idx, "ts": round(ts_s, 4)}

            if result.pose_landmarks and len(result.pose_landmarks) > 0:
                lm = result.pose_landmarks[0]

                # Right arm
                r_sh = lm[12]
                r_wr = lm[16]
                dx_r = r_wr.x - r_sh.x
                dy_r = r_wr.y - r_sh.y
                entry["r_theta"] = round(math.atan2(dx_r, dy_r), 4)
                entry["r_wrist_vis"] = round(r_wr.visibility, 3)
                entry["r_wrist_y"] = round(r_wr.y, 4)
                entry["r_sh_y"] = round(r_sh.y, 4)
                entry["r_above"] = r_wr.y < r_sh.y

                # Left arm
                l_sh = lm[11]
                l_wr = lm[15]
                dx_l = l_wr.x - l_sh.x
                dy_l = l_wr.y - l_sh.y
                entry["l_theta"] = round(math.atan2(dx_l, dy_l), 4)
                entry["l_wrist_vis"] = round(l_wr.visibility, 3)
            else:
                entry["no_pose"] = True

            frames_data.append(entry)
            frame_idx += 1

    cap.release()

    # Unwrap + angular velocity for both arms
    for arm in ["r", "l"]:
        thetas = [f.get(f"{arm}_theta") for f in frames_data]

        unwrapped = [thetas[0] if thetas[0] is not None else 0]
        for i in range(1, len(thetas)):
            if thetas[i] is None or thetas[i-1] is None:
                unwrapped.append(unwrapped[-1])
                continue
            delta = thetas[i] - thetas[i-1]
            if delta > math.pi: delta -= 2 * math.pi
            elif delta < -math.pi: delta += 2 * math.pi
            unwrapped.append(unwrapped[-1] + delta)

        dt = 1.0 / fps
        omega = [0.0]
        for i in range(1, len(unwrapped) - 1):
            omega.append((unwrapped[i+1] - unwrapped[i-1]) / (2 * dt))
        omega.append(0.0)

        for i, f in enumerate(frames_data):
            f[f"{arm}_omega"] = round(omega[i], 2)

    # Find peaks
    r_peak = max(frames_data, key=lambda f: abs(f.get("r_omega", 0)))
    l_peak = max(frames_data, key=lambda f: abs(f.get("l_omega", 0)))

    # Print timeline
    print(f"\n{'Time':>6} {'R_ω':>8} {'L_ω':>8} {'R_vis':>6} {'Above':>6}")
    print("-" * 40)
    for f in frames_data:
        mark = ""
        if f is r_peak: mark = " <-R"
        if f is l_peak: mark += " <-L"
        print(f"{f['ts']:>6.3f} {f.get('r_omega',0):>8.1f} {f.get('l_omega',0):>8.1f} "
              f"{f.get('r_wrist_vis',0):>6.3f} {str(f.get('r_above','')):>6}{mark}")

    bowling_arm = "right" if abs(r_peak.get("r_omega", 0)) > abs(l_peak.get("l_omega", 0)) else "left"
    peak_ts = r_peak["ts"] if bowling_arm == "right" else l_peak["ts"]
    peak_omega = abs(r_peak.get("r_omega", 0)) if bowling_arm == "right" else abs(l_peak.get("l_omega", 0))

    print(f"\n=== RESULT ===")
    print(f"Bowling arm: {bowling_arm}")
    print(f"Release: {peak_ts:.3f}s (ω={peak_omega:.1f} rad/s)")
    print(f"\nGemini default: 1.38s  (Δ={abs(1.38 - peak_ts):.3f}s)")
    print(f"Gemini low:     0.86s  (Δ={abs(0.86 - peak_ts):.3f}s)")

    out_path = os.path.join(os.path.dirname(__file__), "003_results.json")
    with open(out_path, "w") as f:
        json.dump({"bowling_arm": bowling_arm, "release_ts": peak_ts, "peak_omega": round(peak_omega, 1),
                    "fps": fps, "frames": total_frames, "duration": round(duration, 2)}, f, indent=2)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
