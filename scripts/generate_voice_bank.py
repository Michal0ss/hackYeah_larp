"""Generates the live-set coach's voice bank with ElevenLabs.

Reads Packages/Core/Sources/LiveSet/Resources/voice_manifest.json (one entry per phrase, each with
one or more recorded variants) and writes one mp3 per variant next to it. BankedCoachVoice (Swift)
plays these at runtime instead of calling any TTS live, so a workout never waits on a network call
and the same ~20 fixed phrases aren't paid for on every rep.

Needs ELEVENLABS_API_KEY in the environment (never commit it, never paste it in chat):

    export ELEVENLABS_API_KEY=...
    python scripts/generate_voice_bank.py                  # generate files that are still missing
    python scripts/generate_voice_bank.py --force           # regenerate everything
    python scripts/generate_voice_bank.py --voice-id XXXX    # override voice_manifest.json's voiceId for this run

Pick a voiceId from https://elevenlabs.io/app/voice-library or `GET /v1/voices` on your account, and
set it as "voiceId" in voice_manifest.json so later runs don't need --voice-id. The generated mp3s
are committed to the repo (like any other app asset) so teammates don't need their own API key.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Packages/Core/Sources/LiveSet/Resources"
MANIFEST_PATH = RESOURCES / "voice_manifest.json"
API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def variants(manifest: dict):
    for phrase, items in manifest["phrases"].items():
        for item in items:
            yield phrase, item["text"], item["file"]


def generate_one(voice_id: str, model_id: str, api_key: str, text: str) -> bytes:
    body = json.dumps(
        {
            "text": text,
            "model_id": model_id,
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        API_URL.format(voice_id=voice_id),
        data=body,
        method="POST",
        headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="regenerate files that already exist")
    parser.add_argument("--voice-id", help="override the manifest's voiceId for this run")
    args = parser.parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        print("ELEVENLABS_API_KEY is not set", file=sys.stderr)
        return 1

    manifest = load_manifest()
    voice_id = args.voice_id or manifest.get("voiceId")
    if not voice_id or voice_id.startswith("REPLACE_"):
        print("set \"voiceId\" in voice_manifest.json, or pass --voice-id", file=sys.stderr)
        return 1
    model_id = manifest.get("modelId", "eleven_multilingual_v2")

    generated, skipped = 0, 0
    for phrase, text, file in variants(manifest):
        destination = RESOURCES / f"{file}.mp3"
        if destination.exists() and not args.force:
            skipped += 1
            continue
        try:
            audio = generate_one(voice_id, model_id, api_key, text)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            print(f"failed: {phrase!r} -> {text!r}: HTTP {exc.code} {detail}", file=sys.stderr)
            return 1
        destination.write_bytes(audio)
        generated += 1
        print(f"wrote {destination.relative_to(ROOT)}  ({phrase!r} -> {text!r})")

    print(f"done: {generated} generated, {skipped} already present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
