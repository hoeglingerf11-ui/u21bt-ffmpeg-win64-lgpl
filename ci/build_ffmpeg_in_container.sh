#!/usr/bin/env bash
set -euo pipefail

FFMPEG_COMMIT='46d899d7a02bc63237472cc4897258d5ddf274ac'
BTBN_COMMIT='63ac3265b0789ea16c7b1f8351cd2ad195a28722'
BTBN='/work/upstream/btbn'
OUT='/work/out'

git config --global --add safe.directory /work/upstream/ffmpeg
git config --global --add safe.directory /work/upstream/btbn

test "$(git rev-parse HEAD)" = "$FFMPEG_COMMIT"
test "$(git -C "$BTBN" rev-parse HEAD)" = "$BTBN_COMMIT"
test -f "$BTBN/variants/win64-lgpl-shared.sh"
test -f COPYING.LGPLv3

{
  echo '=== Pinned builder image ==='
  echo 'ghcr.io/btbn/ffmpeg-builds/base-win64@sha256:bb591a4a0357ff73c85fb0ef346ed135e11aff6d2c18dc17364b3a65ff540699'
  echo '=== Host compiler ==='
  "${HOST_CC:-cc}" --version | head -n 1
  echo '=== Cross compiler ==='
  "$CC" --version | head -n 1
  "$CC" -dumpmachine
  echo '=== Linker ==='
  "$LD" --version | head -n 1
  echo '=== Make ==='
  make --version | head -n 1
} > "$OUT/toolchain-versions.txt"

cd "$BTBN"
source util/vars.sh win64 lgpl-shared
source variants/win64-lgpl-shared.sh

cd /work/upstream/ffmpeg
SOURCE_DATE_EPOCH="$(git show -s --format=%ct "$FFMPEG_COMMIT")"
export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C
rm -rf "$OUT/prefix" "$OUT/runtime"
mkdir -p "$OUT/prefix" "$OUT/runtime/bin"
read -r -a TARGET_ARGS <<< "$FFBUILD_TARGET_FLAGS"
read -r -a BASE_CONFIG_ARGS <<< "$FF_CONFIGURE"
CONFIG_ARGS=("${TARGET_ARGS[@]}" "${BASE_CONFIG_ARGS[@]}" --disable-autodetect --enable-mediafoundation --enable-d3d11va)
for arg in "${CONFIG_ARGS[@]}"; do
  case "$arg" in
    --enable-gpl|--enable-nonfree|--enable-libx264) echo "Forbidden configure option: $arg" >&2; exit 20 ;;
  esac
done
{
  printf '%q ' ./configure --prefix=/work/out/prefix "${CONFIG_ARGS[@]}" \
    --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM"
  printf '\n'
} > "$OUT/configure.txt"

./configure --prefix="$OUT/prefix" "${CONFIG_ARGS[@]}" \
  --cc="$CC" --cxx="$CXX" --ar="$AR" --ranlib="$RANLIB" --nm="$NM" \
  --extra-cflags="$FF_CFLAGS" --extra-cxxflags="$FF_CXXFLAGS" \
  --extra-ldflags="$FF_LDFLAGS" --extra-libs="${FF_LIBS:-}" \
  --extra-version=u21bt 2>&1 | tee "$OUT/configure.log"
cp ffbuild/config.log "$OUT/config.log"

grep -Eq '^CONFIG_MEDIAFOUNDATION=yes$' ffbuild/config.mak
grep -Eq '^CONFIG_D3D11VA=yes$' ffbuild/config.mak
grep -Eq '^CONFIG_H264_MF_ENCODER=yes$' ffbuild/config.mak
grep -Eq '^CONFIG_FFV1_ENCODER=yes$' ffbuild/config.mak
grep -Eq '^CONFIG_AAC_ENCODER=yes$' ffbuild/config.mak
! grep -Eiq '^CONFIG_(GPL|NONFREE)=yes$|^CONFIG_LIBX264=yes$' ffbuild/config.mak

make -j2 V=1 2>&1 | tee "$OUT/make.log"
make install install-doc 2>&1 | tee "$OUT/install.log"
cp "$OUT/prefix/bin/ffmpeg.exe" "$OUT/runtime/bin/"
cp "$OUT/prefix/bin/ffprobe.exe" "$OUT/runtime/bin/"
find "$OUT/prefix/bin" -maxdepth 1 -type f -iname '*.dll' -exec cp {} "$OUT/runtime/bin/" \;
cp COPYING.LGPLv3 "$OUT/runtime/LICENSE.txt"
test -s "$OUT/runtime/bin/ffmpeg.exe"
test -s "$OUT/runtime/bin/ffprobe.exe"
test -n "$(find "$OUT/runtime/bin" -maxdepth 1 -type f -iname '*.dll' -print -quit)"
git diff --check
git diff --binary "$FFMPEG_COMMIT" > "$OUT/changes.diff"
