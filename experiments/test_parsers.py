"""
Tests for experiment utility functions: response parsing, speed computation, timestamp extraction.
Runs without API keys or video files.
"""

import sys
import os
import json
import unittest
import tempfile
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "delivery_detection"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "live_speed"))

from delivery_detection.detect import parse_response, extract_timestamps
from live_speed.speed_yolo import compute_speed
from live_speed import simulate_live, speed_gemini
import shared_config


class TestParseResponse(unittest.TestCase):

    def test_valid_response(self):
        resp = {
            "candidates": [{"content": {"parts": [
                {"text": '{"found": true, "deliveries_detected_at_time": [6.2, 18.5], "total_count": 2}'}
            ]}}],
            "usageMetadata": {"promptTokenCount": 100, "candidatesTokenCount": 50, "totalTokenCount": 150}
        }
        data, tokens = parse_response(resp)
        self.assertTrue(data["found"])
        self.assertEqual(data["total_count"], 2)
        self.assertEqual(tokens["total"], 150)

    def test_empty_candidates(self):
        resp = {"candidates": [{"content": {"parts": [
            {"text": '{"found": false, "deliveries_detected_at_time": [], "total_count": 0}'}
        ]}}]}
        data, tokens = parse_response(resp)
        self.assertFalse(data["found"])
        self.assertEqual(tokens["total"], 0)

    def test_malformed_json_raises(self):
        resp = {"candidates": [{"content": {"parts": [{"text": "not json"}]}}]}
        with self.assertRaises(Exception):
            parse_response(resp)

    def test_list_response_unwrapped(self):
        resp = {"candidates": [{"content": {"parts": [
            {"text": '[{"found": true, "total_count": 1}]'}
        ]}}]}
        data, _ = parse_response(resp)
        self.assertTrue(data["found"])


class TestExtractTimestamps(unittest.TestCase):

    def test_flat_timestamps(self):
        data = {"deliveries_detected_at_time": [6.2, 18.5]}
        self.assertEqual(extract_timestamps(data), [6.2, 18.5])

    def test_nested_deliveries(self):
        data = {"deliveries": [{"timestamp": 6.2}, {"timestamp": 18.5}]}
        self.assertEqual(extract_timestamps(data), [6.2, 18.5])

    def test_empty(self):
        self.assertEqual(extract_timestamps({}), [])


class TestComputeSpeed(unittest.TestCase):

    def test_too_few_detections(self):
        result = compute_speed([{"frame": 1, "cx": 0, "cy": 0}], 30.0, 100.0)
        self.assertEqual(result, [])

    def test_empty_detections(self):
        result = compute_speed([], 30.0, 100.0)
        self.assertEqual(result, [])

    def test_two_detections(self):
        dets = [
            {"frame": 0, "cx": 0.0, "cy": 0.0},
            {"frame": 1, "cx": 100.0, "cy": 0.0},
        ]
        result = compute_speed(dets, 30.0, 100.0)  # 100 px/m
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result[0]["speed_kph"], 108.0, delta=1.0)  # 1m in 1/30s = 30m/s = 108kph

    def test_skips_large_frame_gaps(self):
        dets = [
            {"frame": 0, "cx": 0.0, "cy": 0.0},
            {"frame": 10, "cx": 100.0, "cy": 0.0},  # gap > 5, should skip
        ]
        result = compute_speed(dets, 30.0, 100.0)
        self.assertEqual(result, [])


class TestSharedConfig(unittest.TestCase):

    def test_constants_are_defined(self):
        self.assertGreater(shared_config.DEFAULT_TEMPERATURE, 0.0)
        self.assertGreater(shared_config.DETECTION_HTTP_TIMEOUT_S, 0)
        self.assertGreater(shared_config.SPEED_HTTP_TIMEOUT_S, 0)
        self.assertGreater(shared_config.DEFAULT_JPEG_QUALITY, 0)
        self.assertGreater(shared_config.DETECTION_COOLDOWN_S, 0)
        self.assertGreater(shared_config.POLL_RATE_LIMIT_SLEEP_S, 0)

    def test_load_api_key_from_environment(self):
        with mock.patch("shared_config.os.path.exists", return_value=False):
            with mock.patch.dict(os.environ, {"GEMINI_API_KEY": "env_key_123"}, clear=False):
                self.assertEqual(shared_config.load_api_key(), "env_key_123")

    def test_load_api_key_from_env_file_precedence(self):
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            tmp.write("GEMINI_API_KEY=file_key_456\n")
            tmp_path = tmp.name

        original_path = shared_config.ENV_PATH
        try:
            shared_config.ENV_PATH = tmp_path
            with mock.patch.dict(os.environ, {"GEMINI_API_KEY": "env_key_123"}, clear=False):
                self.assertEqual(shared_config.load_api_key(), "file_key_456")
        finally:
            shared_config.ENV_PATH = original_path
            os.unlink(tmp_path)


class _FakeHTTPResponse:
    def __init__(self, payload: dict):
        self._payload = payload

    def read(self):
        import json
        return json.dumps(self._payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False


class TestApiCallConfigUsage(unittest.TestCase):

    def test_simulate_live_uses_config_temperature_and_timeout(self):
        captured = {}

        def fake_urlopen(request, timeout):
            captured["timeout"] = timeout
            captured["request"] = request
            return _FakeHTTPResponse({"candidates": [{"content": {"parts": [{"text": '{"delivery": false}'}]}}]})

        with mock.patch("live_speed.simulate_live.urllib.request.urlopen", side_effect=fake_urlopen):
            simulate_live.call_gemini(
                api_key="test_key",
                frames_b64=["abc"],
                timestamps=[1.0],
                interval=shared_config.POLL_INTERVAL_S,
            )

        self.assertEqual(captured["timeout"], shared_config.DETECTION_HTTP_TIMEOUT_S)
        payload = json.loads(captured["request"].data.decode("utf-8"))
        self.assertEqual(payload["generationConfig"]["temperature"], shared_config.DEFAULT_TEMPERATURE)

    def test_speed_gemini_uses_config_temperature_and_timeout(self):
        captured = {}

        def fake_urlopen(request, timeout):
            captured["timeout"] = timeout
            captured["request"] = request
            return _FakeHTTPResponse({"candidates": [{"content": {"parts": [{"text": '{"speed_kph": 95}'}]}}]})

        with mock.patch("live_speed.speed_gemini.urllib.request.urlopen", side_effect=fake_urlopen):
            speed_gemini.call_gemini(api_key="test_key", video_b64="abc")

        self.assertEqual(captured["timeout"], shared_config.SPEED_HTTP_TIMEOUT_S)
        payload = json.loads(captured["request"].data.decode("utf-8"))
        self.assertEqual(payload["generationConfig"]["temperature"], shared_config.DEFAULT_TEMPERATURE)


if __name__ == "__main__":
    unittest.main()
