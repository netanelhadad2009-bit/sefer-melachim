#!/usr/bin/env python3
"""Generate NotebookLM content (audio podcasts, mind maps, summaries) for each unit PDF."""

import asyncio
import json
import sys
from pathlib import Path

from notebooklm import NotebookLMClient
from notebooklm.rpc.types import AudioFormat, AudioLength

PROJECT_DIR = Path(__file__).parent
GENERATED_DIR = PROJECT_DIR / "generated"

UNIT_PDFS = {
    1: PROJECT_DIR / "יחידה1.pdf",
    2: PROJECT_DIR / "יחידה2.pdf",
    3: PROJECT_DIR / "יחידה3.pdf",
    4: PROJECT_DIR / "יחידה4.pdf",
    5: PROJECT_DIR / "יחידה5.pdf",
    6: PROJECT_DIR / "יחידה6.pdf",
}

FULL_TANACH_PDF = PROJECT_DIR / "tanachwithpsukim.pdf"

UNIT_TITLES = {
    1: "מלכות שלמה",
    2: "פילוג הממלכה",
    3: "אליהו ואחאב",
    4: "מהפכות ותמורות",
    5: "חזקיהו ושנחריב",
    6: "יאשיהו וחורבן",
}

SUMMARY_PROMPT = (
    "תן סיכום מקיף בעברית של החומר הזה. "
    "כלול את הנקודות המרכזיות, הדמויות החשובות, "
    "האירועים המרכזיים והמסרים העיקריים. "
    "כתוב בצורה ברורה ותמציתית, מתאימה לתלמידי בגרות."
)

AUDIO_INSTRUCTIONS = (
    "Create a deep-dive discussion in Hebrew about this Tanach unit. "
    "Cover the key events, characters, and theological themes. "
    "Make it engaging and educational for high school students studying for the Bagrut exam."
)


def ensure_dirs():
    for subdir in ["audio", "mindmaps", "summaries"]:
        (GENERATED_DIR / subdir).mkdir(parents=True, exist_ok=True)


def file_exists(path: Path) -> bool:
    return path.exists() and path.stat().st_size > 0


async def setup_notebook(client, title, pdf_path, wait_timeout=180):
    """Create notebook and upload PDF, return (notebook_id, source_id)."""
    notebook = await client.notebooks.create(title)
    nb_id = notebook.id
    print(f"    Notebook: {nb_id}")
    source = await client.sources.add_file(nb_id, str(pdf_path), wait=True, wait_timeout=wait_timeout)
    print(f"    Source: {source.id}")
    return nb_id


async def generate_mindmap(client, nb_id, unit_id):
    mm_path = GENERATED_DIR / "mindmaps" / f"unit-{unit_id}.json"
    if file_exists(mm_path):
        print(f"  [skip] Mind map unit-{unit_id} exists")
        return
    print(f"  Generating mind map for unit {unit_id}...")
    mind_map = await client.artifacts.generate_mind_map(nb_id)
    with open(mm_path, "w", encoding="utf-8") as f:
        json.dump(mind_map, f, ensure_ascii=False, indent=2)
    print(f"  [done] Mind map: {mm_path}")


async def generate_summary(client, nb_id, unit_id):
    sum_path = GENERATED_DIR / "summaries" / f"unit-{unit_id}.txt"
    if file_exists(sum_path):
        print(f"  [skip] Summary unit-{unit_id} exists")
        return
    print(f"  Generating summary for unit {unit_id}...")
    result = await client.chat.ask(nb_id, SUMMARY_PROMPT)
    with open(sum_path, "w", encoding="utf-8") as f:
        f.write(result.answer)
    print(f"  [done] Summary: {sum_path}")


async def generate_audio(client, nb_id, unit_id, instructions=None, length=AudioLength.DEFAULT, filename=None):
    fname = filename or f"unit-{unit_id}.mp3"
    audio_path = GENERATED_DIR / "audio" / fname
    if file_exists(audio_path):
        print(f"  [skip] Audio {fname} exists")
        return
    print(f"  Generating audio {fname}...")
    instr = instructions or AUDIO_INSTRUCTIONS
    status = await client.artifacts.generate_audio(
        nb_id, language="he", instructions=instr,
        audio_format=AudioFormat.DEEP_DIVE, audio_length=length,
    )
    print(f"    Task: {status.task_id} — waiting (up to 15 min)...")
    await client.artifacts.wait_for_completion(nb_id, status.task_id, timeout=900)
    await client.artifacts.download_audio(nb_id, str(audio_path))
    print(f"  [done] Audio: {audio_path}")


async def process_unit(client, unit_id, pdf_path, skip_audio=False):
    title = UNIT_TITLES.get(unit_id, f"יחידה {unit_id}")
    print(f"\n--- Unit {unit_id}: {title} ---")

    print(f"  Setting up notebook...")
    nb_id = await setup_notebook(client, f"ספר מלכים - יחידה {unit_id}: {title}", pdf_path)

    # Mind map + summary first (fast)
    for gen_fn in [generate_mindmap, generate_summary]:
        try:
            await gen_fn(client, nb_id, unit_id)
        except Exception as e:
            print(f"  [error] {gen_fn.__name__}: {e}")

    # Audio last (slow)
    if not skip_audio:
        try:
            await generate_audio(client, nb_id, unit_id)
        except Exception as e:
            print(f"  [error] Audio: {e}")

    return nb_id


async def process_full_tanach(client):
    print(f"\n--- Full Tanach ---")
    print(f"  Setting up notebook...")
    nb_id = await setup_notebook(
        client, 'ספר מלכים - תנ"ך מלא עם פסוקים', FULL_TANACH_PDF, wait_timeout=300
    )
    try:
        await generate_audio(
            client, nb_id, "full",
            instructions=(
                "Create a comprehensive Hebrew deep-dive discussion covering "
                "the entire Book of Kings (Sefer Melachim). Cover the major themes, "
                "key figures from Solomon to the destruction of the Temple."
            ),
            length=AudioLength.LONG,
            filename="full-tanach.mp3",
        )
    except Exception as e:
        print(f"  [error] Full Tanach audio: {e}")


async def main():
    ensure_dirs()

    units_to_process = list(range(1, 7))
    skip_audio = "--no-audio" in sys.argv
    skip_full = "--no-full" in sys.argv
    if any(a.isdigit() for a in sys.argv[1:]):
        units_to_process = [int(x) for x in sys.argv[1:] if x.isdigit()]

    print(f"Units: {units_to_process} | Audio: {not skip_audio} | Full Tanach: {not skip_full}")

    async with await NotebookLMClient.from_storage() as client:
        for unit_id in units_to_process:
            pdf_path = UNIT_PDFS.get(unit_id)
            if not pdf_path or not pdf_path.exists():
                print(f"  Skipping unit {unit_id}: PDF not found")
                continue
            await process_unit(client, unit_id, pdf_path, skip_audio=skip_audio)

        if not skip_full and FULL_TANACH_PDF.exists():
            await process_full_tanach(client)

    print("\nDone! Content in:", GENERATED_DIR)


if __name__ == "__main__":
    asyncio.run(main())
