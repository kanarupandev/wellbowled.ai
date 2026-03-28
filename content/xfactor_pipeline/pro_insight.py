"""Stage 7: Gemini Pro coaching insight (optional — falls back gracefully)."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
ANNOTATED_DIR = OUTPUT_DIR / "annotated"
XFACTOR_FILE = OUTPUT_DIR / "xfactor_data.json"
PLAN_FILE = OUTPUT_DIR / "flash_plan.json"
INSIGHT_FILE = OUTPUT_DIR / "pro_insight.json"


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


def fallback_insight(peak_angle: float) -> dict:
    if peak_angle > 40:
        return {
            "hook": "Elite separation — this is where express pace comes from.",
            "explanation": "The hips lead the shoulders by over 40°, storing elastic energy in the trunk.",
            "verdict": "World-class rotation. Keep it up.",
            "source": "fallback",
        }
    elif peak_angle > 25:
        return {
            "hook": "Good separation — there's pace potential here.",
            "explanation": f"At {peak_angle:.0f}°, the hips are doing their job. More delay in the shoulders would unlock extra speed.",
            "verdict": "Work on thoracic mobility and delayed shoulder rotation.",
            "source": "fallback",
        }
    else:
        return {
            "hook": "Limited separation — the hips and shoulders are moving together.",
            "explanation": f"Only {peak_angle:.0f}° of separation means the trunk isn't storing energy efficiently.",
            "verdict": "Focus on hip mobility drills and driving the front hip through earlier.",
            "source": "fallback",
        }


def run() -> dict:
    xfactor = json.loads(XFACTOR_FILE.read_text())
    peak_angle = xfactor["peak_separation_angle"]
    peak_frame_name = xfactor.get("peak_frame_name")

    plan = {}
    if PLAN_FILE.exists():
        plan = json.loads(PLAN_FILE.read_text())
    action_type = plan.get("action_type", "unknown")

    api_key = _load_api_key()

    if not api_key:
        print("  No GEMINI_API_KEY — using fallback insight")
        insight = fallback_insight(peak_angle)
    else:
        try:
            import google.generativeai as genai
            from PIL import Image

            genai.configure(api_key=api_key)
            model = genai.GenerativeModel("gemini-2.0-pro")

            peak_img_path = ANNOTATED_DIR / peak_frame_name
            img = Image.open(peak_img_path)

            prompt = f"""You are a cricket fast bowling biomechanics coach.

This frame shows a bowler at peak hip-shoulder separation.
- Action type: {action_type}
- Hip-shoulder separation angle: {peak_angle}°

Write exactly 3 lines for a video overlay:
1. One-line hook (what the viewer should notice)
2. One-line explanation (why this matters for pace)
3. One-line verdict (good/needs work + one actionable cue)

Return JSON only:
{{"hook": "...", "explanation": "...", "verdict": "..."}}

Keep it punchy. No jargon. A 16-year-old fast bowler should understand it."""

            response = model.generate_content([prompt, img])
            text = response.text.strip()
            json_match = re.search(r"\{[\s\S]*\}", text)
            if json_match:
                insight = json.loads(json_match.group())
                insight["source"] = "gemini-pro"
                print("  Gemini Pro insight received")
            else:
                print(f"  Gemini returned non-JSON. Using fallback.")
                insight = fallback_insight(peak_angle)
        except Exception as e:
            print(f"  Gemini Pro call failed: {e}. Using fallback.")
            insight = fallback_insight(peak_angle)

    with open(INSIGHT_FILE, "w") as f:
        json.dump(insight, f, indent=2)

    return insight


if __name__ == "__main__":
    result = run()
    print(json.dumps(result, indent=2))
