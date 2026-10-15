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

# NEON only. This phone is ARMv8.0 with no SDOT, and ggml's runtime CPU
# detection picks the right variant from the shared libs we ship anyway.
cmake -S "$SRC" -B "$BUILD" -DCMAKE_TOOLCHAIN_FILE="$SRC/ggml/android-ndk.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_CURL=OFF -DGGML_OPENMP=OFF -DLLAMA_BUILD_SHARED=ON >/dev/null

cmake --build "$BUILD" --target llama-server -j"$(nproc)" >/dev/null

mkdir -p "$(dirname "$OUT")"
# The server links against libllama and the ggml backends, so those have to
# travel in the APK too. Copying them beside it is what keeps the exec working;
# nativeLibraryDir is already on the loader path for anything unpacked there.
cp "$BUILD/bin/llama-server" "$OUT"
for so in "$BUILD"/bin/lib*.so; do
  cp "$so" "$(dirname "$OUT")/"
done
chmod +x "$OUT"

echo "built $(wc -c < "$OUT") bytes -> $OUT"
