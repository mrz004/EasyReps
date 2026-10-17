"""One-off: build the bundled exercise assets from yuhonas/free-exercise-db.

Outputs:
  assets/exercises/exercises.json   (id, name, primary_muscle, secondary_muscles,
                                     equipment, instructions, has_image)
  assets/exercises/img/<id>.webp    (first image only, max width 400 px, WebP q60)

Usage (from the repository root):
  python -m pip install Pillow
  python tools/prepare_exercises.py [--source <local clone of free-exercise-db>]

Without --source, the JSON and images are downloaded from GitHub (raw files).
Review a sample of the converted images before committing them.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

RAW_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main"
MAX_WIDTH = 400
WEBP_QUALITY = 60
BUDGET_BYTES = 10 * 1000 * 1000
USER_AGENT = "CountMySweat-asset-prep/0.1"

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "exercises"
IMG_DIR = OUT_DIR / "img"


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def read_source(source: Path | None, relative: str) -> bytes:
    if source is not None:
        return (source / relative).read_bytes()
    return fetch(f"{RAW_BASE}/{relative}")


def trim(item: dict) -> dict:
    primary = item.get("primaryMuscles") or ["other"]
    return {
        "id": item["id"],
        "name": item["name"].strip(),
        "primary_muscle": primary[0],
        "secondary_muscles": item.get("secondaryMuscles") or [],
        "equipment": item.get("equipment"),
        "instructions": item.get("instructions") or [],
        "has_image": bool(item.get("images")),
    }


def convert(source: Path | None, item: dict) -> tuple[str, int, str | None]:
    exercise_id = item["id"]
    images = item.get("images") or []
    if not images:
        return exercise_id, 0, None  # Shown with a placeholder in the app.
    try:
        data = read_source(source, f"exercises/{images[0]}")
        image = Image.open(io.BytesIO(data)).convert("RGB")
        if image.width > MAX_WIDTH:
            height = round(image.height * MAX_WIDTH / image.width)
            image = image.resize((MAX_WIDTH, height), Image.LANCZOS)
        target = IMG_DIR / f"{exercise_id}.webp"
        image.save(target, "WEBP", quality=WEBP_QUALITY, method=6)
        return exercise_id, target.stat().st_size, None
    except Exception as error:  # noqa: BLE001 - report and continue
        return exercise_id, 0, str(error)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, help="local clone of free-exercise-db")
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    items = json.loads(read_source(args.source, "dist/exercises.json"))
    print(f"{len(items)} exercises in dataset")

    IMG_DIR.mkdir(parents=True, exist_ok=True)
    trimmed = sorted((trim(i) for i in items), key=lambda i: i["id"])
    json_path = OUT_DIR / "exercises.json"
    json_path.write_text(
        json.dumps(trimmed, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda i: convert(args.source, i), items))

    failures = [(i, e) for i, _, e in results if e]
    image_bytes = sum(size for _, size, _ in results)
    total = image_bytes + json_path.stat().st_size
    written = sum(1 for _, size, _ in results if size)
    print(f"images: {written} written, {image_bytes / 1e6:.1f} MB")
    print(f"total assets: {total / 1e6:.1f} MB (budget {BUDGET_BYTES / 1e6:.1f} MB)")
    for exercise_id, error in failures:
        print(f"  failed {exercise_id}: {error}", file=sys.stderr)
    if total > BUDGET_BYTES:
        print("WARNING: asset budget exceeded", file=sys.stderr)
        return 1
    return 0 if not failures else 2


if __name__ == "__main__":
    sys.exit(main())
