"""
Configuration definitions for delivery detection experiments.

Prompt techniques applied (research-backed):
1. Count-first-then-locate: Forces model to enumerate before pinpointing (reduces missed detections)
2. Visual landmark anchoring: Describes release in terms of observable body landmarks
3. Negative examples: Explicitly lists what is NOT a delivery (reduces phantoms)
4. Temporal precision cueing: Tells model about video temporal resolution
5. Ascending order constraint: Catches timestamp ordering errors
6. Minimal output format: Fewer output tokens = lower latency + cost
"""

# --- PROMPT A/B: Current production prompt ---
PROMPT_CURRENT = """Scan this video for cricket bowling deliveries.

A bowling delivery is: a person performing a bowling action — arm swings over and releases (or would release) the ball. This includes ALL bowling styles:
- Overarm (standard pace/fast bowling)
- Round-arm and side-arm deliveries
- Spin bowling (off-spin, leg-spin, wrist spin)
- Shadow bowling (no ball present — arm still swings over)

For EACH delivery, note the timestamp when the ball is released (bowling arm at highest point before release).

BROADCAST VIDEO RULES:
- This video may contain quick cuts, replays, graphics, or montage edits
- IGNORE slow-motion replays — only count real-time live-action deliveries
- IGNORE graphic overlays, scorecard transitions, and crowd shots
- Focus ONLY on the bowler's body and arm action at real-time speed
- Each cut/scene showing a new delivery from a consistent camera angle = one delivery

OUTPUT FORMAT (JSON only):
{"found": true, "deliveries_detected_at_time": [6.2, 18.5], "total_count": 2}

If no deliveries found:
{"found": false, "deliveries_detected_at_time": [], "total_count": 0}

IMPORTANT:
- Look for ANY bowling-like arm action at real-time speed
- Include deliveries even if partially visible
- Timestamps in seconds, ascending order, as precise as possible (to 0.1s)
- Return ALL real-time deliveries found in the video"""


# --- PROMPT C: Research-optimized with video metadata ---
# Techniques: count-first, visual anchoring, negative examples, metadata, frame numbers
def prompt_with_metadata(fps, duration, frame_count):
    return f"""You are analyzing a cricket video for bowling delivery detection.

VIDEO: {fps:.0f} fps, {duration:.1f} seconds, {frame_count} frames total.

TASK — find every bowling delivery in this video.

WHAT IS A DELIVERY:
A delivery occurs when the bowler's arm rotates over the shoulder and the ball is released (or would be released in shadow bowling). The release point is when the bowling arm reaches its highest vertical position and the hand opens.

This applies to ALL bowling styles: overarm, round-arm, side-arm, fast, medium, spin, and shadow bowling.

WHAT IS NOT A DELIVERY:
- Slow-motion replays (different speed, zoomed camera, repeated action)
- Fielding throws (no run-up, different arm action)
- Batting strokes
- Walking, stretching, or practice swings without full arm rotation
- Graphics, scorecard overlays, or crowd shots

INSTRUCTIONS:
Step 1: Watch the full video. Count how many real-time bowling deliveries occur.
Step 2: For each delivery, identify the precise moment of ball release.
Step 3: Convert to timestamp (seconds) and frame number (frame = timestamp × {fps:.0f}).

OUTPUT (JSON only):
{{"found": true, "deliveries": [{{"timestamp": 6.2, "frame": 186}}], "total_count": 1}}

If none found:
{{"found": false, "deliveries": [], "total_count": 0}}

PRECISION: Timestamps must be in ascending order, accurate to 0.1 seconds."""


# --- Response schemas ---
RESPONSE_SCHEMA_SIMPLE = {
    "type": "OBJECT",
    "properties": {
        "found": {"type": "BOOLEAN"},
        "deliveries_detected_at_time": {
            "type": "ARRAY",
            "items": {"type": "NUMBER"}
        },
        "total_count": {"type": "INTEGER"}
    },
    "required": ["found", "deliveries_detected_at_time", "total_count"]
}

RESPONSE_SCHEMA_WITH_FRAMES = {
    "type": "OBJECT",
    "properties": {
        "found": {"type": "BOOLEAN"},
        "deliveries": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "timestamp": {"type": "NUMBER"},
                    "frame": {"type": "INTEGER"}
                },
                "required": ["timestamp", "frame"]
            }
        },
        "total_count": {"type": "INTEGER"}
    },
    "required": ["found", "deliveries", "total_count"]
}


# --- Configuration matrix ---
CONFIGS = {
    "A": {
        "name": "Baseline (temp=0.1)",
        "description": "Current production setup",
        "temperature": 0.1,
        "thinking": "MINIMAL",
        "prompt": PROMPT_CURRENT,
        "response_schema": None,
        "downscale": None,
    },
    "B": {
        "name": "Temp 1.0",
        "description": "Gemini 3 recommended default temperature — may improve reasoning stability",
        "temperature": 1.0,
        "thinking": "MINIMAL",
        "prompt": PROMPT_CURRENT,
        "response_schema": None,
        "downscale": None,
    },
    "C": {
        "name": "Schema + Metadata + Frames",
        "description": "Response schema constraint + video metadata + frame numbers + research-optimized prompt",
        "temperature": 0.1,  # from Config A winner
        "thinking": "MINIMAL",
        "prompt": "METADATA",  # sentinel — use prompt_with_metadata()
        "response_schema": RESPONSE_SCHEMA_WITH_FRAMES,
        "downscale": None,
    },
    "D": {
        "name": "Downscale 480p + Schema + Metadata",
        "description": "Config C + video preprocessed to 480p — token reduction test",
        "temperature": 0.1,  # from Config A winner
        "thinking": "MINIMAL",
        "prompt": "METADATA",  # sentinel — use prompt_with_metadata()
        "response_schema": RESPONSE_SCHEMA_WITH_FRAMES,
        "downscale": 480,
    },
    "E": {
        "name": "Default Thinking",
        "description": "Same as A but no thinkingConfig — let Gemini use default reasoning depth",
        "temperature": 0.1,
        "thinking": None,  # no thinkingConfig sent
        "prompt": PROMPT_CURRENT,
        "response_schema": None,
        "downscale": None,
    },
}
