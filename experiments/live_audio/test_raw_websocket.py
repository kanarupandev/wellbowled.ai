"""
Test raw WebSocket connection to Gemini Live API.
Mimics exactly what the iOS app sends — camelCase JSON, same setup message.
This validates the wire protocol before debugging iOS.
"""
import asyncio
import json
import os
import sys
import websockets

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, ".."))
from shared_config import LIVE_AUDIO_MODEL as MODEL, load_api_key

ENDPOINT = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

# Exact same setup message as iOS app (camelCase keys)
SETUP_MESSAGE = {
    "setup": {
        "model": MODEL,
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": {
                        "voiceName": "Zephyr"
                    }
                }
            }
        },
        "systemInstruction": {
            "parts": [{"text": "You're an expert cricket mate watching a nets session. Keep responses short."}]
        },
        "outputAudioTranscription": {},
        "contextWindowCompression": {
            "triggerTokens": 25600,
            "slidingWindow": {
                "targetTokens": 12800
            }
        }
    }
}


async def test_connection():
    api_key = load_api_key()
    if not api_key:
        print("ERROR: No API key. Set GEMINI_API_KEY in .env")
        return

    url = f"{ENDPOINT}?key={api_key}"
    print(f"Model: {MODEL}")
    print(f"URL: {url[:80]}...")

    setup_json = json.dumps(SETUP_MESSAGE)
    print(f"\nSetup message ({len(setup_json)} chars):")
    print(json.dumps(SETUP_MESSAGE, indent=2)[:500])

    try:
        print("\nConnecting...")
        async with websockets.connect(url, max_size=10_000_000) as ws:
            print("WebSocket OPEN")

            # Send setup
            print("Sending setup...")
            await ws.send(setup_json)
            print("Setup sent, waiting for response...")

            # Wait for setupComplete
            response = await asyncio.wait_for(ws.recv(), timeout=10)
            print(f"\nResponse ({len(response)} chars):")
            parsed = json.loads(response)
            print(json.dumps(parsed, indent=2)[:500])

            if "setupComplete" in parsed:
                print("\n✓ SETUP COMPLETE — connection works!")

                # Send a text prompt to trigger audio response
                text_msg = {
                    "clientContent": {
                        "turns": [{
                            "role": "user",
                            "parts": [{"text": "Say hello mate in one sentence"}]
                        }],
                        "turnComplete": True
                    }
                }
                print("\nSending text prompt...")
                await ws.send(json.dumps(text_msg))

                # Read a few responses
                for i in range(10):
                    try:
                        resp = await asyncio.wait_for(ws.recv(), timeout=15)
                        msg = json.loads(resp)

                        # Summarize
                        if "serverContent" in msg:
                            sc = msg["serverContent"]
                            if sc.get("modelTurn"):
                                parts = sc["modelTurn"].get("parts", [])
                                audio_parts = [p for p in parts if "inlineData" in p]
                                text_parts = [p for p in parts if "text" in p]
                                print(f"  MSG #{i+1}: modelTurn ({len(audio_parts)} audio, {len(text_parts)} text)")
                            if sc.get("outputTranscription"):
                                print(f"  MSG #{i+1}: transcript: {sc['outputTranscription'].get('text', '')[:80]}")
                            if sc.get("turnComplete"):
                                print(f"  MSG #{i+1}: turnComplete")
                                break
                        elif "sessionResumptionUpdate" in msg:
                            print(f"  MSG #{i+1}: sessionResumptionUpdate")
                        else:
                            print(f"  MSG #{i+1}: {list(msg.keys())}")
                    except asyncio.TimeoutError:
                        print(f"  MSG #{i+1}: timeout")
                        break

                print("\n✓ Full round-trip successful!")
            else:
                print(f"\n✗ Unexpected response: {list(parsed.keys())}")

    except Exception as e:
        print(f"\n✗ ERROR: {type(e).__name__}: {e}")


if __name__ == "__main__":
    asyncio.run(test_connection())
