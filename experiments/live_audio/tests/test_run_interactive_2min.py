import json
import os
import sys
import tempfile
import unittest

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(TEST_DIR, "../../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from experiments.live_audio.run_interactive_2min import (
    parse_json_update,
    run_from_config,
)


class RunInteractive2MinTests(unittest.TestCase):
    def test_parse_json_update_valid(self):
        required = [
            "event",
            "delivery_count",
            "pace_band",
            "line",
            "length",
            "risk_level",
            "cue",
        ]
        payload = (
            '{"event":"update","delivery_count":1,"pace_band":"medium-slow",'
            '"line":"off","length":"good","risk_level":"low","cue":"steady"}'
        )
        parsed, errors = parse_json_update(payload, required)
        self.assertIsNotNone(parsed)
        self.assertEqual(errors, [])
        self.assertEqual(parsed["event"], "update")

    def test_parse_json_update_missing_fields(self):
        required = ["event", "delivery_count", "cue"]
        parsed, errors = parse_json_update('{"event":"update"}', required)
        self.assertIsNotNone(parsed)
        self.assertTrue(any("missing_fields" in err for err in errors))

    def test_mock_run_writes_outputs_and_parses_updates(self):
        with tempfile.TemporaryDirectory() as tmp:
            mock_path = os.path.join(tmp, "mock_live_responses.json")
            with open(mock_path, "w", encoding="utf-8") as f:
                json.dump(
                    [
                        {
                            "event_type": "turn_complete",
                            "transcript": (
                                '{"event":"update","delivery_count":2,'
                                '"pace_band":"medium","line":"off","length":"good",'
                                '"risk_level":"low","cue":"keep wrist high"}'
                            ),
                            "audio_duration_s": 0.12,
                            "session_handle": "mock-handle-1",
                        }
                    ],
                    f,
                    indent=2,
                )

            config_path = os.path.join(tmp, "config.json")
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "video_path": "../../resources/samples/whatsapp_nets_session.mp4",
                        "mock_mode": True,
                        "allow_live_api_calls": False,
                        "mock_response_path": mock_path,
                        "output_dir": tmp,
                        "output_basename": "unit_mock",
                    },
                    f,
                    indent=2,
                )

            result = run_from_config(config_path)
            self.assertEqual(result["json_validation_errors"], [])
            self.assertEqual(len(result["parsed_updates"]), 1)
            self.assertEqual(result["parsed_updates"][0]["delivery_count"], 2)

            outputs = result["outputs"]
            self.assertTrue(os.path.exists(outputs["result_json"]))
            self.assertTrue(os.path.exists(outputs["transcript_txt"]))
            self.assertTrue(os.path.exists(outputs["audio_wav"]))


if __name__ == "__main__":
    unittest.main()
