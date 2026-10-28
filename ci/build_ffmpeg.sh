#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
IMAGE='ghcr.io/btbn/ffmpeg-builds/base-win64@sha256:284c22c72ffe8f2ff2f6676a60482a9ca0ee7e093c9938a801bc1a4d83b0e9c1'
EXPECTED_FFMPEG='46d899d7a02bc63237472cc4897258d5ddf274ac'
EXPECTED_BTBn='63ac3265b0789ea16c7b1f8351cd2ad195a28722'

test "$(git -C "$ROOT/upstream/ffmpeg" rev-parse HEAD)" = "$EXPECTED_FFMPEG"
test "$(git -C "$ROOT/upstream/btbn" rev-parse HEAD)" = "$EXPECTED_BTBn"
mkdir -p "$ROOT/out"

docker pull "$IMAGE"
docker image inspect "$IMAGE" --format '{{json .}}' > "$ROOT/out/builder-image-inspect.json"
free_kb_after_pull="$(df -Pk "$GITHUB_WORKSPACE" | awk 'NR==2 {print $4}')"
test "$free_kb_after_pull" -ge 8388608 || { echo "Refusing compile: less than 8 GiB free after pulling the pinned toolchain image." >&2; exit 1; }
echo "Pinned toolchain image pulled; free disk ${free_kb_after_pull} KiB remains before compilation."
docker run --rm --network none \
  -v "$ROOT:/work" \
  -w /work/upstream/ffmpeg \
  "$IMAGE" bash /work/ci/build_ffmpeg_in_container.sh

python "$ROOT/ci/pe_imports.py" "$ROOT/out/runtime/bin" > "$ROOT/out/pe-imports.json"
python - "$ROOT/out/pe-imports.json" <<'PY'
import json, sys
inventory = json.load(open(sys.argv[1], encoding="utf-8"))
if not inventory.get("files") or any(item.get("machine") != "AMD64" for item in inventory["files"]):
    raise SystemExit("Runtime PE inventory is empty or contains a non-AMD64 file.")
names = {item["file"].lower() for item in inventory["files"]}
if not {"ffmpeg.exe", "ffprobe.exe"}.issubset(names):
    raise SystemExit("Runtime PE inventory is missing ffmpeg.exe or ffprobe.exe.")
PY
