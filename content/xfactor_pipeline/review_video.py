"""Stage 9: Video review — extract key frames with FFmpeg for visual QA."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
REVIEW_DIR = OUTPUT_DIR / "review"
FINAL_VIDEO = OUTPUT_DIR / "final.mp4"


def run():
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    if not FINAL_VIDEO.exists():
        raise FileNotFoundError(f"Final video not found: {FINAL_VIDEO}")

    # Get video metadata
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", str(FINAL_VIDEO)],
        capture_output=True, text=True, check=True,
    )
    streams = json.loads(probe.stdout)["streams"]
    video_stream = next(s for s in streams if s["codec_type"] == "video")
    duration = float(video_stream["duration"])
    width = int(video_stream["width"])
    height = int(video_stream["height"])
    size_mb = FINAL_VIDEO.stat().st_size / (1024 * 1024)
    bitrate_kbps = int(video_stream["bit_rate"]) // 1000

    print(f"  Video: {width}x{height}, {duration:.1f}s, {size_mb:.1f}MB, {bitrate_kbps}kbps")

    # Extract frames at key timepoints
    checkpoints = [
        ("01_start", 0.1),
        ("02_intro_end", 1.4),
        ("03_slomo_early", duration * 0.2),
        ("04_quarter", duration * 0.25),
        ("05_half", duration * 0.5),
        ("06_three_quarter", duration * 0.75),
        ("07_verdict", duration * 0.85),
        ("08_end_card", duration * 0.95),
    ]

    for label, seek_time in checkpoints:
        out_path = REVIEW_DIR / f"{label}.jpg"
        subprocess.run(
            [
                "ffmpeg", "-y",
                "-ss", f"{seek_time:.2f}",
                "-i", str(FINAL_VIDEO),
                "-frames:v", "1",
                "-q:v", "2",
                str(out_path),
            ],
            capture_output=True, check=True,
        )
        print(f"  Frame: {label} @ {seek_time:.1f}s")

    # Contact sheet of the whole video (4x3 grid)
    contact_path = REVIEW_DIR / "contact_sheet.jpg"
    subprocess.run(
        [
            "ffmpeg", "-y",
            "-i", str(FINAL_VIDEO),
            "-vf", f"fps={12.0/duration},scale=360:-1,tile=4x3",
            "-frames:v", "1",
            "-q:v", "2",
            str(contact_path),
        ],
        capture_output=True, check=True,
    )
    print(f"  Contact sheet: {contact_path.name}")

    # QA checks
    issues = []
    if width != 1080 or height != 1920:
        issues.append(f"Resolution {width}x{height} — expected 1080x1920")
    if duration < 10 or duration > 60:
        issues.append(f"Duration {duration:.1f}s — should be 10-60s for IG")
    if size_mb > 100:
        issues.append(f"Size {size_mb:.1f}MB — too large")
    if bitrate_kbps < 1000:
        issues.append(f"Bitrate {bitrate_kbps}kbps — may be low quality")
    if video_stream["codec_name"] != "h264":
        issues.append(f"Codec {video_stream['codec_name']} — expected h264")

    print(f"\n  QA Results:")
    print(f"  Resolution: {width}x{height} {'OK' if width == 1080 and height == 1920 else 'WARN'}")
    print(f"  Duration:   {duration:.1f}s {'OK' if 10 <= duration <= 60 else 'WARN'}")
    print(f"  File size:  {size_mb:.1f} MB {'OK' if size_mb < 100 else 'WARN'}")
    print(f"  Bitrate:    {bitrate_kbps} kbps {'OK' if bitrate_kbps >= 1000 else 'WARN'}")
    print(f"  Codec:      {video_stream['codec_name']} {'OK' if video_stream['codec_name'] == 'h264' else 'WARN'}")

    if issues:
        print(f"\n  Issues found:")
        for issue in issues:
            print(f"    - {issue}")
    else:
        print(f"\n  All checks passed!")

    # Save report
    report = {
        "resolution": f"{width}x{height}",
        "duration_s": duration,
        "size_mb": round(size_mb, 1),
        "bitrate_kbps": bitrate_kbps,
        "codec": video_stream["codec_name"],
        "issues": issues,
        "screenshots": [f.name for f in sorted(REVIEW_DIR.glob("*.jpg"))],
    }
    with open(REVIEW_DIR / "qa_report.json", "w") as f:
        json.dump(report, f, indent=2)

    return report


if __name__ == "__main__":
    run()
