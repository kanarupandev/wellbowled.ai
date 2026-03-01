# Interactive 2-Minute Runner

## Purpose
Run a config-driven 2-minute interactive session with:
- mock mode (default for safe/local verification)
- optional live mode (explicitly opt-in to avoid credit usage)

## Files
- `run_interactive_2min.py`
- `session_2min_config.json` (live template, live calls disabled by default)
- `session_2min_mock_config.json` (safe mock run)
- `mock_live_responses.json` (mock transcript/events fixture)

## Commands
Mock-safe run:
```bash
python3 run_interactive_2min.py --config session_2min_mock_config.json
```

Live run (requires `allow_live_api_calls: true` + API key):
```bash
python3 run_interactive_2min.py --config session_2min_config.json
```

## Outputs
- `result_<basename>.json`
- `transcript_<basename>.txt`
- `response_<basename>.wav`
