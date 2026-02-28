"""
Audio Live API Validation — Expert Mate Hypothesis
====================================================
Streams video frames to gemini-2.5-flash-native-audio and captures
spoken audio response + transcription.

The hypothesis: native-audio model can watch bowling video and speak
delivery feedback like an expert mate.

Usage:
  python validate_audio.py [video_path]

Default: uses whatsapp_nets_session.mp4 (68s, 4 deliveries)
"""

import asyncio
import base64
import io
import json
import os
import sys
import time
import wave

import cv2
import PIL.Image

from google import genai
from google.genai import types

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, ".."))
from shared_config import LIVE_AUDIO_MODEL as MODEL, load_api_key

PROJECT_ROOT = os.path.join(SCRIPT_DIR, "../..")
DEFAULT_VIDEO = os.path.join(PROJECT_ROOT, "resources/samples/whatsapp_nets_session.mp4")
OUTPUT_DIR = SCRIPT_DIR

SYSTEM_INSTRUCTION = """You're an expert cricket mate watching a live nets session through a camera.

When you see a bowling delivery, call it out naturally and concisely:
- Count it ("That's three")
- Estimate the pace ("medium pace" / "quick" / "slow")
- One brief observation if notable ("good follow-through" / "dropped your arm a bit")

Keep it short — like a mate standing behind the stumps. Don't narrate everything you see.
Only speak when you spot a delivery."""

# Ground truth for whatsapp_nets_session.mp4
GT_DELIVERIES = {
    "whatsapp_nets_session.mp4": [6.77, 18.83, 37.57, 59.00],
}


def frame_to_jpeg_blob(frame, max_dim=1024, quality=70):
    """Convert OpenCV BGR frame to JPEG blob dict for Live API."""
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    img = PIL.Image.fromarray(frame_rgb)
    img.thumbnail([max_dim, max_dim])

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    buf.seek(0)

    return {
        "mime_type": "image/jpeg",
        "data": base64.b64encode(buf.read()).decode(),
    }


def save_wav(audio_chunks, output_path):
    """Save PCM audio chunks to WAV file (1ch, 16-bit, 24kHz)."""
    if not audio_chunks:
        print("No audio data received.")
        return 0

    with wave.open(output_path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(24000)  # Gemini outputs at 24kHz
        for chunk in audio_chunks:
            wf.writeframes(chunk)

    total_bytes = sum(len(c) for c in audio_chunks)
    duration = total_bytes / (24000 * 2)
    print(f"Saved {duration:.1f}s of audio to {output_path} ({total_bytes} bytes)")
    return duration


def generate_silence(duration_s=1.0, sample_rate=16000):
    """Generate PCM silence (16-bit, 16kHz mono) for keepalive."""
    num_samples = int(duration_s * sample_rate)
    return b'\x00\x00' * num_samples


def extract_audio_from_video(video_path, target_rate=16000):
    """Extract audio from video using moviepy, resample to 16kHz mono PCM."""
    try:
        from moviepy.editor import VideoFileClip
        import numpy as np

        clip = VideoFileClip(video_path)
        if clip.audio is None:
            print("Video has no audio track")
            return None, 0

        # Get audio as numpy array at target sample rate
        audio_arr = clip.audio.to_soundarray(fps=target_rate)

        # Convert to mono if stereo
        if len(audio_arr.shape) > 1 and audio_arr.shape[1] > 1:
            audio_arr = audio_arr.mean(axis=1)

        # Convert float [-1, 1] to 16-bit PCM
        audio_arr = np.clip(audio_arr, -1.0, 1.0)
        pcm_data = (audio_arr * 32767).astype(np.int16).tobytes()

        duration = len(pcm_data) / (target_rate * 2)
        print(f"Extracted {duration:.1f}s of audio ({len(pcm_data)} bytes, {target_rate}Hz)")
        clip.close()
        return pcm_data, duration
    except ImportError:
        # Fallback: use cv2 (no audio support) — generate silence
        print("moviepy not available, using silence as audio")
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        dur = total / fps if fps else 0
        cap.release()
        silence = b'\x00\x00' * int(dur * target_rate)
        return silence, dur


async def send_video_frames(session, video_path, stop_event):
    """Stream video frames + video's own audio to the Live API."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"ERROR: Cannot open {video_path}")
        stop_event.set()
        return

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps if fps > 0 else 0
    frame_skip = max(1, int(fps))  # 1 frame per second

    # Extract audio from video
    audio_data, audio_duration = extract_audio_from_video(video_path)
    audio_sample_rate = 16000
    audio_bytes_per_second = audio_sample_rate * 2  # 16-bit

    print(f"Video: {os.path.basename(video_path)} ({total_frames} frames, {fps:.0f}fps, {duration:.1f}s)")
    print(f"Strategy: stream 1 frame/sec + real audio from video")

    frame_idx = 0
    frames_sent = 0
    t_start = time.time()

    try:
        while cap.isOpened() and not stop_event.is_set():
            ret, frame = cap.read()
            if not ret:
                print(f"\nVideo complete — sent {frames_sent} frames in {time.time()-t_start:.1f}s", flush=True)
                break

            if frame_idx % frame_skip == 0:
                elapsed = frame_idx / fps if fps > 0 else 0

                # Send video frame
                blob = frame_to_jpeg_blob(frame)
                await session.send_realtime_input(media=blob)

                # Send corresponding 1s of audio from the video
                if audio_data:
                    audio_start = int(elapsed * audio_bytes_per_second)
                    audio_end = audio_start + audio_bytes_per_second
                    chunk = audio_data[audio_start:audio_end]
                    if chunk:
                        await session.send_realtime_input(
                            audio={
                                "data": base64.b64encode(chunk).decode(),
                                "mime_type": "audio/pcm",
                            }
                        )

                frames_sent += 1
                print(f"  Sent frame {frame_idx} (t={elapsed:.1f}s)", end="\r", flush=True)
                await asyncio.sleep(1.0)  # Real-time pacing

            frame_idx += 1

    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"\nSender error: {e}", flush=True)
    finally:
        cap.release()
        await asyncio.sleep(15.0)
        stop_event.set()


async def receive_responses(session, stop_event, audio_chunks, transcripts, events):
    """Receive audio + transcription from model."""
    turn_count = 0
    try:
        async for response in session.receive():
            if stop_event.is_set():
                break

            # Debug: log raw response type
            has_data = response.data is not None
            has_text = response.text is not None
            has_sc = response.server_content is not None

            # Audio data
            if has_data:
                audio_chunks.append(response.data)

            # Text response (TEXT mode)
            if has_text:
                transcripts.append({"time": time.time(), "text": response.text})
                print(f"\n[Mate]: {response.text}", end="", flush=True)

            # Server content (audio transcription, turn signals)
            if has_sc:
                sc = response.server_content

                if sc.output_transcription and sc.output_transcription.text:
                    t = time.time()
                    transcripts.append({"time": t, "text": sc.output_transcription.text})
                    print(f"\n[Mate]: {sc.output_transcription.text}", end="", flush=True)

                if sc.turn_complete:
                    turn_count += 1
                    total_audio = sum(len(c) for c in audio_chunks) / (24000 * 2)
                    print(f"\n--- turn {turn_count} complete (audio: {total_audio:.1f}s, transcripts: {len(transcripts)}) ---", flush=True)

                # Log model turns with parts for debugging
                if sc.model_turn and sc.model_turn.parts:
                    for part in sc.model_turn.parts:
                        if hasattr(part, 'thought') and part.thought:
                            print(f"\n[Thought]: {part.text[:100] if part.text else '(no text)'}...", flush=True)

            # Session resumption handle
            if response.session_resumption_update:
                update = response.session_resumption_update
                if update.resumable and update.new_handle:
                    events.append({"type": "session_handle", "handle": update.new_handle[:30]})

            # GoAway warning
            if response.go_away is not None:
                tl = getattr(response.go_away, 'time_left', 'unknown')
                print(f"\n[WARNING] Server disconnecting in: {tl}", flush=True)
                events.append({"type": "go_away", "time_left": str(tl)})

    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"\nReceive error: {type(e).__name__}: {e}", flush=True)
        events.append({"type": "error", "error": str(e)})


async def run_experiment(video_path, api_key):
    """Main experiment: stream video → get audio response."""
    client = genai.Client(
        api_key=api_key,
        http_options={"api_version": "v1beta"},
    )

    config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction=types.Content(
            parts=[types.Part(text=SYSTEM_INSTRUCTION)]
        ),
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Zephyr")
            )
        ),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        media_resolution=types.MediaResolution.MEDIA_RESOLUTION_LOW,
        context_window_compression=types.ContextWindowCompressionConfig(
            trigger_tokens=25600,
            sliding_window=types.SlidingWindow(target_tokens=12800),
        ),
        session_resumption=types.SessionResumptionConfig(handle=None),
    )

    audio_chunks = []
    transcripts = []
    events = []
    stop_event = asyncio.Event()

    print(f"\nConnecting to {MODEL}...")
    t_start = time.time()

    try:
        async with client.aio.live.connect(model=MODEL, config=config) as session:
            print("Connected!")
            connect_time = time.time() - t_start
            print(f"Connection established in {connect_time:.1f}s")

            # Send initial text prompt to prime the model
            print("Sending initial prompt...")
            await session.send_client_content(
                turns=types.Content(
                    role="user",
                    parts=[types.Part(text=(
                        "I'm about to show you a cricket nets session. "
                        "Watch for bowling deliveries and call them out as you see them. "
                        "Count each delivery, estimate the pace, and make brief observations. "
                        "Speak naturally like a mate watching cricket."
                    ))],
                ),
                turn_complete=True,
            )
            # Brief pause to let model acknowledge
            await asyncio.sleep(1.0)

            sender = asyncio.create_task(
                send_video_frames(session, video_path, stop_event)
            )
            receiver = asyncio.create_task(
                receive_responses(session, stop_event, audio_chunks, transcripts, events)
            )

            # Wait for sender to finish (video complete)
            await sender
            # Give receiver a bit more time after sender is done
            try:
                await asyncio.wait_for(receiver, timeout=5.0)
            except asyncio.TimeoutError:
                receiver.cancel()

    except Exception as e:
        print(f"\nSession error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        events.append({"type": "session_error", "error": str(e)})

    elapsed = time.time() - t_start
    return audio_chunks, transcripts, events, elapsed


def main():
    video_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VIDEO
    video_path = os.path.abspath(video_path)
    video_name = os.path.basename(video_path)

    api_key = load_api_key()
    if not api_key:
        print("ERROR: Set GEMINI_API_KEY in .env or environment")
        sys.exit(1)

    print("=" * 60)
    print("AUDIO LIVE API VALIDATION — Expert Mate Hypothesis")
    print("=" * 60)
    print(f"Model: {MODEL}")
    print(f"Video: {video_name}")

    # Run experiment
    audio_chunks, transcripts, events, elapsed = asyncio.run(
        run_experiment(video_path, api_key)
    )

    # Save audio
    wav_path = os.path.join(OUTPUT_DIR, "response_audio.wav")
    audio_duration = save_wav(audio_chunks, wav_path)

    # Save transcript
    full_transcript = "".join(t["text"] for t in transcripts)
    transcript_path = os.path.join(OUTPUT_DIR, "transcript.txt")
    with open(transcript_path, "w") as f:
        f.write(full_transcript)
    print(f"Saved transcript to {transcript_path}")

    # Results summary
    print(f"\n{'='*60}")
    print("RESULTS")
    print(f"{'='*60}")
    print(f"Session duration: {elapsed:.1f}s")
    print(f"Audio received: {audio_duration:.1f}s ({len(audio_chunks)} chunks)")
    print(f"Transcript segments: {len(transcripts)}")
    print(f"Events: {len(events)}")

    if full_transcript:
        print(f"\n--- Full Transcript ---")
        print(full_transcript)
    else:
        print("\nNo transcript received.")

    if events:
        print(f"\n--- Events ---")
        for e in events:
            print(f"  {e}")

    # Ground truth comparison (if available)
    gt = GT_DELIVERIES.get(video_name, [])
    if gt:
        print(f"\nGround truth deliveries: {gt}")
        print("(Manual review needed: listen to audio and check if deliveries were called out)")

    # Save result JSON
    result = {
        "video": video_name,
        "model": MODEL,
        "elapsed_s": round(elapsed, 1),
        "audio_duration_s": round(audio_duration, 1),
        "audio_chunks": len(audio_chunks),
        "transcript_segments": len(transcripts),
        "transcript_texts": [t["text"] for t in transcripts],
        "full_transcript": full_transcript,
        "events": events,
        "ground_truth": gt,
    }
    result_path = os.path.join(OUTPUT_DIR, "result_audio_validation.json")
    with open(result_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nSaved: {result_path}")


if __name__ == "__main__":
    main()
