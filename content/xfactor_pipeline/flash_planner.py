"""Stage 2: Gemini Flash call for phase timing + bowler ROI, with fallback."""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
CONTACT_SHEET = OUTPUT_DIR / "contact_sheet.jpg"
PLAN_FILE = OUTPUT_DIR / "flash_plan.json"

FALLBACK_PLAN = {
    "bowler_roi": {"x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0},
    "phases": {
        "back_foot_contact": 0.3,
        "front_foot_contact": 0.7,
        "release": 1.0,
        "follow_through": 1.5,
    },
    "action_type": "semi-open",
    "insight_seed": "Standard bowling action with good rhythm through the crease.",
    "source": "fallback",
}

PROMPT = """You are a cricket bowling biomechanics analyst.

This contact sheet shows frames from a bowling delivery clip.
Frames are left-to-right, top-to-bottom, at ~3fps intervals.

Return JSON only:
{
  "bowler_roi": {"x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0},
  "phases": {
    "back_foot_contact": <seconds>,
    "front_foot_contact": <seconds>,
    "release": <seconds>,
    "follow_through": <seconds>
  },
  "action_type": "side-on" | "front-on" | "semi-open" | "mixed",
  "insight_seed": "<one sentence about what's notable in this action>"
}"""


def _load_api_key() -> str | None:
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                return line.split("=", 1)[1].strip()
    return None


def run() -> dict:
    api_key = _load_api_key()

    if not api_key:
        print("  No GEMINI_API_KEY found — using fallback plan")
        plan = FALLBACK_PLAN
    else:
        try:
            import google.generativeai as genai
            from PIL import Image

            genai.configure(api_key=api_key)
            model = genai.GenerativeModel("gemini-2.0-flash")

            img = Image.open(CONTACT_SHEET)
            response = model.generate_content([PROMPT, img])
            text = response.text.strip()

            # Extract JSON from response (may be wrapped in ```json ... ```)
            json_match = re.search(r"\{[\s\S]*\}", text)
            if json_match:
                plan = json.loads(json_match.group())
                plan["source"] = "gemini-flash"
                print("  Gemini Flash plan received")
            else:
                print(f"  Gemini returned non-JSON: {text[:200]}. Using fallback.")
                plan = FALLBACK_PLAN
        except Exception as e:
            print(f"  Gemini Flash call failed: {e}. Using fallback.")
            plan = FALLBACK_PLAN

    with open(PLAN_FILE, "w") as f:
        json.dump(plan, f, indent=2)

    return plan


if __name__ == "__main__":
    result = run()
    print(json.dumps(result, indent=2))
