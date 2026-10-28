#!/usr/bin/env bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
FFMPEG_COMMIT='46d899d7a02bc63237472cc4897258d5ddf274ac'
BTBN_COMMIT='63ac3265b0789ea16c7b1f8351cd2ad195a28722'
ART="$ROOT/out/artifacts"
SRC="$ART/source-build"
mkdir -p "$ART" "$SRC"
cp -R "$ROOT/out/runtime/." "$ART/runtime/"
cp "$ROOT/out/builder-image-inspect.json" "$ROOT/out/toolchain-versions.txt" \
  "$ROOT/out/configure.txt" "$ROOT/out/configure.log" "$ROOT/out/config.log" \
  "$ROOT/out/make.log" "$ROOT/out/install.log" "$ROOT/out/changes.diff" \
  "$ROOT/out/pe-imports.json" "$ROOT/sources.lock.json" "$SRC/"
cp "$ROOT/ci/"*.sh "$ROOT/ci/"*.py "$ROOT/ci/"*.ps1 "$SRC/"
cp "$ROOT/.github/workflows/build-ffmpeg-lgpl-win64.yml" "$SRC/"
cp "$ROOT/U21BT_BUILD_PLAN.md" "$SRC/"

git -C "$ROOT/upstream/ffmpeg" archive --format=tar.gz --prefix=FFmpeg/ "$FFMPEG_COMMIT" > "$SRC/FFmpeg-${FFMPEG_COMMIT}.tar.gz"
git -C "$ROOT/upstream/btbn" archive --format=tar.gz --prefix=BtbN-FFmpeg-Builds/ "$BTBN_COMMIT" \
  LICENSE util/vars.sh variants/win64-lgpl-shared.sh variants/windows-install-shared.sh \
  variants/defaults-lgpl-shared.sh variants/defaults-lgpl.sh \
  images/base-win64/ct-ng-config images/base-win64/Dockerfile \
  images/base-win64/toolchain.cmake images/base-win64/cross.meson > "$SRC/BtbN-recipe-${BTBN_COMMIT}.tar.gz"
cp "$ART/runtime/LICENSE.txt" "$SRC/FFmpeg-COPYING.LGPLv3.txt"
cat > "$ART/runtime/THIRD_PARTY_NOTICES.txt" <<'EOF'
FFmpeg is distributed as dynamically linked shared libraries built from FFmpeg commit 46d899d7a02bc63237472cc4897258d5ddf274ac with the LGPL version 3 option enabled.
The corresponding FFmpeg source, exact build configuration, build scripts, changes.diff, and LGPL license text are provided in ffmpeg-win64-lgpl-source-build-u21bt.zip.
The source/build bundle includes the selected BtbN recipe files under the MIT License; its LICENSE file is included in that bundle.
This notice is generated for the U21BT technical candidate. It does not by itself establish final product-level LGPL compliance or a working customer replacement mechanism.
EOF
(cd "$ART/runtime" && zip -X -q -r "$ART/ffmpeg-win64-lgpl-shared-u21bt.zip" .)
(cd "$SRC" && zip -X -q -r "$ART/ffmpeg-win64-lgpl-source-build-u21bt.zip" .)

python - "$ART" "$FFMPEG_COMMIT" "$BTBN_COMMIT" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(p for p in root.iterdir() if p.is_file() and p.name not in ("build-manifest.json", "SHA256SUMS.txt"))
manifest = {"schema":"u21bt-build-artifact-manifest-v1", "ffmpeg_commit":sys.argv[2], "btbn_recipe_commit":sys.argv[3],
            "artifacts":[{"name":p.name,"bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
(root/"build-manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
with (root/"SHA256SUMS.txt").open("w", encoding="ascii", newline="\n") as out:
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.name != "SHA256SUMS.txt":
            out.write(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root).as_posix()}\n")
PY
