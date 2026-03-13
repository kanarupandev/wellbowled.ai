#!/usr/bin/env python3
"""
Config-driven 2-minute interactive Live API runner.

Primary mode is mock-safe (no API calls) for repeatable local verification.
Real API mode is blocked unless explicitly enabled in config.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
import wave
from typing import Any

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
EXPERIMENTS_DIR = os.path.join(SCRIPT_DIR, "..")
PROJECT_ROOT = os.path.join(SCRIPT_DIR, "../..")
sys.path.insert(0, EXPERIMENTS_DIR)

from shared_config import LIVE_AUDIO_MODEL as DEFAULT_MODEL, load_api_key

DEFAULT_VIDEO = os.path.join(PROJECT_ROOT, "resources/samples/whatsapp_nets_session.mp4")
DEFAULT_CONFIG_PATH = os.path.join(SCRIPT_DIR, "session_2min_config.json")
DEFAULT_REQUIRED_FIELDS = [
    "event",
    "delivery_count",
    "pace_band",
    "line",
    "length",
    "risk_level",
    "cue",
]


def _resolve_path(raw_path: str, base_dir: str) -> str:
    if os.path.isabs(raw_path):
        return raw_path
    return os.path.abspath(os.path.join(base_dir, raw_path))


def _load_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _default_output_paths(output_dir: str, output_basename: str) -> dict[str, str]:
    return {
        "result_json": os.path.join(output_dir, f"result_{output_basename}.json"),
        "transcript_txt": os.path.join(output_dir, f"transcript_{output_basename}.txt"),
        "audio_wav": os.path.join(output_dir, f"response_{output_basename}.wav"),
    }


def load_config(config_path: str) -> dict[str, Any]:
    raw = _load_json(config_path)
    config_dir = os.path.dirname(os.path.abspath(config_path))

    output_dir = _resolve_path(raw.get("output_dir", SCRIPT_DIR), config_dir)
    output_basename = raw.get("output_basename", "interactive_2min_run")

    cfg = {
        "config_path": os.path.abspath(config_path),
        "video_path": _resolve_path(raw.get("video_path", DEFAULT_VIDEO), config_dir),
        "model": raw.get("model", DEFAULT_MODEL),
        "max_session_seconds": int(raw.get("max_session_seconds", 120)),
        "mock_mode": bool(raw.get("mock_mode", True)),
        "allow_live_api_calls": bool(raw.get("allow_live_api_calls", False)),
        "json_contract_required_fields": raw.get(
            "json_contract_required_fields", DEFAULT_REQUIRED_FIELDS
        ),
        "mock_response_path": _resolve_path(
            raw.get("mock_response_path", "mock_live_responses.json"), config_dir
        ),
        "mock_default_audio_duration_s": float(raw.get("mock_default_audio_duration_s", 0.1)),
        "output_dir": output_dir,
        "output_basename": output_basename,
        "live_retry_max_attempts": int(raw.get("live_retry_max_attempts", 2)),
        "live_retry_backoff_seconds": float(raw.get("live_retry_backoff_seconds", 1.5)),
        "live_retry_backoff_multiplier": float(raw.get("live_retry_backoff_multiplier", 2.0)),
    }

    os.makedirs(output_dir, exist_ok=True)
    cfg["outputs"] = _default_output_paths(output_dir, output_basename)
    return cfg


def parse_json_update(
    transcript_text: str, required_fields: list[str]
) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    try:
        payload = json.loads(transcript_text)
    except json.JSONDecodeError as exc:
        return None, [f"invalid_json: {exc.msg}"]

    if not isinstance(payload, dict):
        return None, ["invalid_shape: expected JSON object"]

    missing = [key for key in required_fields if key not in payload]
    if missing:
        errors.append(f"missing_fields: {','.join(missing)}")
    return payload, errors


def _write_silence_wav(output_path: str, duration_s: float) -> float:
    sample_rate = 24000
    frame_count = max(1, int(duration_s * sample_rate))
    silence = b"\x00\x00" * frame_count
    with wave.open(output_path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(silence)
    return frame_count / sample_rate


def _write_text(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def run_mock_session(cfg: dict[str, Any]) -> dict[str, Any]:
    start = time.time()
    responses = _load_json(cfg["mock_response_path"])
    if not isinstance(responses, list):
        raise ValueError("mock_response_path must point to a JSON list")

    transcript_segments: list[str] = []
    parsed_updates: list[dict[str, Any]] = []
    json_validation_errors: list[str] = []
    events: list[dict[str, Any]] = []

    total_audio_duration = 0.0

    for idx, item in enumerate(responses):
        if not isinstance(item, dict):
            json_validation_errors.append(f"response[{idx}] invalid_shape: expected object")
            continue

        transcript = item.get("transcript", "")
        if transcript:
            transcript_segments.append(transcript)
            parsed, errors = parse_json_update(
                transcript, cfg["json_contract_required_fields"]
            )
            if parsed is not None:
                parsed_updates.append(parsed)
            for err in errors:
                json_validation_errors.append(f"response[{idx}] {err}")

        audio_dur = float(item.get("audio_duration_s", 0.0))
        total_audio_duration += max(0.0, audio_dur)

        event_type = item.get("event_type")
        if event_type:
            events.append({"type": event_type, "ts": time.time()})

        session_handle = item.get("session_handle")
        if session_handle:
            events.append({"type": "session_handle", "handle": session_handle})

    if total_audio_duration <= 0:
        total_audio_duration = cfg["mock_default_audio_duration_s"]

    audio_duration = _write_silence_wav(cfg["outputs"]["audio_wav"], total_audio_duration)
    transcript_text = "\n".join(transcript_segments)
    _write_text(cfg["outputs"]["transcript_txt"], transcript_text)

    result = {
        "video": cfg["video_path"],
        "config_path": cfg["config_path"],
        "model": cfg["model"],
        "elapsed_s": round(time.time() - start, 2),
        "max_session_seconds": cfg["max_session_seconds"],
        "audio_duration_s": round(audio_duration, 3),
        "audio_chunks": max(1, len(responses)),
        "transcript_segments": len(transcript_segments),
        "transcript": transcript_segments,
        "parsed_updates": parsed_updates,
        "json_validation_errors": json_validation_errors,
        "events": events,
        "outputs": cfg["outputs"],
    }
    _write_text(cfg["outputs"]["result_json"], json.dumps(result, indent=2))
    return result


def run_live_session(cfg: dict[str, Any]) -> dict[str, Any]:
    if not cfg["allow_live_api_calls"]:
        raise RuntimeError(
            "Live API calls are disabled by config. Set allow_live_api_calls=true to run live mode."
        )

    api_key = load_api_key()
    if not api_key:
        raise RuntimeError("No GEMINI_API_KEY found in .env/environment")

    from validate_audio import run_experiment, save_wav

    start = time.time()
    (
        audio_chunks,
        transcripts,
        events,
        elapsed,
        attempts_used,
    ) = execute_live_attempts(cfg, api_key, run_experiment)

    transcript_segments = [
        t.get("text", "") for t in transcripts if isinstance(t, dict) and t.get("text")
    ]
    parsed_updates: list[dict[str, Any]] = []
    json_validation_errors: list[str] = []

    for idx, text in enumerate(transcript_segments):
        parsed, errors = parse_json_update(text, cfg["json_contract_required_fields"])
        if parsed is not None:
            parsed_updates.append(parsed)
        for err in errors:
            json_validation_errors.append(f"transcript[{idx}] {err}")

    audio_duration = save_wav(audio_chunks, cfg["outputs"]["audio_wav"])
    transcript_text = "\n".join(transcript_segments)
    _write_text(cfg["outputs"]["transcript_txt"], transcript_text)

    result = {
        "video": cfg["video_path"],
        "config_path": cfg["config_path"],
        "model": cfg["model"],
        "elapsed_s": round(max(elapsed, time.time() - start), 2),
        "max_session_seconds": cfg["max_session_seconds"],
        "audio_duration_s": round(audio_duration, 3),
        "audio_chunks": len(audio_chunks),
        "transcript_segments": len(transcript_segments),
        "transcript": transcript_segments,
        "parsed_updates": parsed_updates,
        "json_validation_errors": json_validation_errors,
        "events": events,
        "retry_summary": {
            "attempts_used": attempts_used,
            "max_attempts": cfg["live_retry_max_attempts"],
        },
        "outputs": cfg["outputs"],
    }
    _write_text(cfg["outputs"]["result_json"], json.dumps(result, indent=2))
    return result


def execute_live_attempts(
    cfg: dict[str, Any],
    api_key: str,
    attempt_runner: Any,
) -> tuple[list[bytes], list[dict[str, Any]], list[dict[str, Any]], float, int]:
    events: list[dict[str, Any]] = []
    max_attempts = max(1, int(cfg["live_retry_max_attempts"]))
    base_backoff = max(0.0, float(cfg["live_retry_backoff_seconds"]))
    multiplier = max(1.0, float(cfg["live_retry_backoff_multiplier"]))

    for attempt in range(1, max_attempts + 1):
        events.append({"type": "attempt_start", "attempt": attempt, "ts": time.time()})
        try:
            result = attempt_runner(cfg["video_path"], api_key)
            if asyncio.iscoroutine(result):
                audio_chunks, transcripts, run_events, elapsed = asyncio.run(result)
            else:
                audio_chunks, transcripts, run_events, elapsed = result

            events.extend(run_events if isinstance(run_events, list) else [])
            events.append({"type": "attempt_success", "attempt": attempt, "ts": time.time()})
            return audio_chunks, transcripts, events, elapsed, attempt
        except Exception as exc:
            events.append(
                {
                    "type": "attempt_error",
                    "attempt": attempt,
                    "error": str(exc),
                    "ts": time.time(),
                }
            )
            if attempt >= max_attempts:
                raise

            delay = base_backoff * (multiplier ** (attempt - 1))
            events.append(
                {
                    "type": "retry_scheduled",
                    "attempt": attempt + 1,
                    "delay_s": round(delay, 3),
                    "ts": time.time(),
                }
            )
            if delay > 0:
                time.sleep(delay)

    raise RuntimeError("unreachable retry state")


def run_from_config(config_path: str) -> dict[str, Any]:
    cfg = load_config(config_path)
    if cfg["mock_mode"]:
        return run_mock_session(cfg)
    return run_live_session(cfg)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run config-driven interactive 2-minute session")
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG_PATH,
        help="Path to JSON config file",
    )
    args = parser.parse_args()

    result = run_from_config(args.config)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
