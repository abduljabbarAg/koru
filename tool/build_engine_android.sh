#!/usr/bin/env bash
#
# Cross-compiles the llama.cpp server for Android arm64.
#
# Replaces the Rust engine this app used to ship. Nothing about the app's
# architecture changed: the engine is still a standalone binary exec'd from
# nativeLibraryDir and still speaks the OpenAI-compatible HTTP API, so this is
# a different program in the same slot, not a new integration.
#
# Run on a Linux machine with the Android NDK installed. CI calls this.
#
# Usage:
#   NDK_ROOT=/path/to/ndk ./tool/build_engine_android.sh [output.so]
#
# Why jniLibs and not assets: since Android 10, an app targeting API 29+ may
# not exec a file it wrote itself. Files extracted from the APK into
# nativeLibraryDir remain executable, which is why this is bundled as a native
# library and copied from there at runtime.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${LLAMA_CPP_DIR:-$ROOT/third_party/llama.cpp}"
OUT="${1:-$ROOT/android/app/src/main/jniLibs/arm64-v8a/libllama-server.so}"

: "${NDK_ROOT:?set NDK_ROOT to your Android NDK}"
API="${ANDROID_API:-24}"
BUILD="${BUILD_DIR:-/tmp/llama-android-build}"

if [ ! -d "$SRC" ]; then
  echo "llama.cpp sources not found at $SRC." >&2
  echo "Clone a release there, or point LLAMA_CPP_DIR at one:" >&2
  echo "  git clone --depth 1 -b b11574 https://github.com/ggml-org/llama.cpp $SRC" >&2
  exit 1
fi

TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
  echo "No linux-x86_64 NDK toolchain at $TOOLCHAIN" >&2
  exit 1
fi

# The NDK's own toolchain file, not one inside llama.cpp: the script used to
# point at ggml/android-ndk.cmake, which existed in no release we build
# against, so the configure step could never have succeeded.
#
# Statically linked on purpose. An app that execs a shared-library binary from
# nativeLibraryDir needs the loader to find libllama.so and the ggml backends
# beside it, and the dynamic linker of a *separate exec'd process* does not
# search the app's library directory the way the app process itself does. One
# self-contained executable has no loader path to get wrong, which retires the
# risk the handover called "confirm the shared libraries travel".
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
  -DGGML_OPENMP=OFF -DBUILD_SHARED_LIBS=OFF >/dev/null

cmake --build "$BUILD" --target llama-server -j"$(nproc)" >/dev/null

mkdir -p "$(dirname "$OUT")"
cp "$BUILD/bin/llama-server" "$OUT"
# Shared libraries only if the build produced them; a static build is the
# normal case now, and an unmatched glob under `set -e` used to be fatal.
for so in "$BUILD"/bin/lib*.so; do
  [ -e "$so" ] || continue
  cp "$so" "$(dirname "$OUT")/"
done
# Strip. The unstripped binary is 187 MB of debug symbols that Android will
# never read and every install would carry; the same binary stripped is a
# fraction of that. `llvm-strip` because NDK r28 dropped the per-target strip
# names in favour of the LLVM one.
STRIP="$TOOLCHAIN/bin/llvm-strip"
if [ -x "$STRIP" ]; then
  "$STRIP" --strip-unneeded "$OUT"
  for so in "$(dirname "$OUT")"/*.so; do
    [ -e "$so" ] || continue
    "$STRIP" --strip-unneeded "$so"
  done
fi
chmod +x "$OUT"

echo "built $(wc -c < "$OUT") bytes -> $OUT"
