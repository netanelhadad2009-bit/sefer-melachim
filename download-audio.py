#!/usr/bin/env python3
"""Download audio from existing NotebookLM notebooks.

Usage:
    python download-audio.py              # List all notebooks and their audio
    python download-audio.py --download   # Download all available audio
"""

import asyncio
import sys
from pathlib import Path

from notebooklm import NotebookLMClient

GENERATED_DIR = Path(__file__).parent / "generated" / "audio"


async def main():
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    do_download = "--download" in sys.argv

    async with await NotebookLMClient.from_storage() as client:
        notebooks = await client.notebooks.list()
        print(f"Found {len(notebooks)} notebooks\n")

        for nb in notebooks:
            print(f"Notebook: {nb.title} ({nb.id})")
            try:
                audio_list = await client.artifacts.list_audio(nb.id)
                if audio_list:
                    for art in audio_list:
                        print(f"  Audio: {art.id} — {art.title if hasattr(art, 'title') else 'untitled'}")
                        if do_download:
                            # Determine filename from notebook title
                            title = nb.title.lower()
                            if "יחידה 1" in title or "unit-1" in title:
                                fname = "unit-1.mp3"
                            elif "יחידה 2" in title or "unit-2" in title:
                                fname = "unit-2.mp3"
                            elif "יחידה 3" in title or "unit-3" in title:
                                fname = "unit-3.mp3"
                            elif "יחידה 4" in title or "unit-4" in title:
                                fname = "unit-4.mp3"
                            elif "יחידה 5" in title or "unit-5" in title:
                                fname = "unit-5.mp3"
                            elif "יחידה 6" in title or "unit-6" in title:
                                fname = "unit-6.mp3"
                            elif "מלא" in title or "full" in title:
                                fname = "full-tanach.mp3"
                            else:
                                fname = f"{nb.id}.mp3"

                            out = str(GENERATED_DIR / fname)
                            if Path(out).exists():
                                print(f"    [skip] {fname} already exists")
                                continue
                            try:
                                await client.artifacts.download_audio(nb.id, out, artifact_id=art.id)
                                print(f"    [done] Downloaded: {out}")
                            except Exception as e:
                                print(f"    [error] Download failed: {e}")
                else:
                    print("  No audio artifacts (may still be generating)")
            except Exception as e:
                print(f"  Error listing artifacts: {e}")
            print()


if __name__ == "__main__":
    asyncio.run(main())
