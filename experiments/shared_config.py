"""
Shared configuration for all experiment scripts.
Single source of truth for model IDs, thresholds, and paths.
"""

import os

PROJECT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ENV_PATH = os.path.join(PROJECT_ROOT, ".env")

# Model IDs
SCOUT_MODEL = "gemini-3-flash-preview"
COACH_MODEL = "gemini-3-pro-preview"
LIVE_AUDIO_MODEL = "models/gemini-2.5-flash-native-audio-preview-12-2025"

# Thresholds
FILE_SIZE_THRESHOLD_MB = 5.0
DETECTION_PASS_THRESHOLD_S = 0.3
DETECTION_COOLDOWN_S = 3.0
POLL_INTERVAL_S = 3
POLL_RATE_LIMIT_SLEEP_S = 0.5

# Video defaults
DEFAULT_JPEG_QUALITY = 70
DEFAULT_CONF_THRESHOLD = 0.15

# API defaults
DEFAULT_TEMPERATURE = 0.1
DETECTION_HTTP_TIMEOUT_S = 30
SPEED_HTTP_TIMEOUT_S = 120


def load_api_key():
    """Load Gemini API key from .env or environment."""
    if os.path.exists(ENV_PATH):
        with open(ENV_PATH) as f:
            for line in f:
                if line.startswith("GEMINI_API_KEY="):
                    return line.strip().split("=", 1)[1]
    return os.environ.get("GEMINI_API_KEY")
