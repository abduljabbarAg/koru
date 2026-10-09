#!/usr/bin/env bash
#
# Cross-compiles glen for Android arm64.
#
# Run on a Linux machine with the Android NDK installed and the
# aarch64-linux-android Rust target available. CI calls this; it is a script so
# the same command works locally and there is exactly one description of how the
# binary is produced.
#
# Usage:
#   NDK_ROOT=/path/to/ndk ./tool/build_glen_android.sh [output.bin]
#
# Note on why the binary ends up in jniLibs rather than assets: since Android 10,
# an app targeting API 29 or newer may not exec a file it wrote itself. Files
# extracted from the APK into nativeLibraryDir remain executable, which is why
# this is bundled as a native library and copied from there at runtime.

set -euo pipefail

REPO="${GLEN_REPO:-https://github.com/AbduljabbarBXR/glen.git}"
REF="${GLEN_REF:-main}"
OUT="${1:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [[ -z "$OUT" ]]; then
  OUT="$ROOT/android/app/src/main/jniLibs/arm64-v8a/libglen.so"
fi
mkdir -p "$(dirname "$OUT")"

if [[ -z "${NDK_ROOT:-}" ]]; then
  echo "NDK_ROOT is not set. Install the NDK or set it in the environment." >&2
  exit 1
fi
if [[ ! -d "$NDK_ROOT" ]]; then
  echo "NDK_ROOT does not exist: $NDK_ROOT" >&2
  exit 1
fi

HOST_TAG="linux-x86_64"
case "$(uname -m)" in
  aarch64 | arm64) HOST_TAG="linux-aarch64" ;;
esac
TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG"

# minSdk is 24, so the oldest clang that matters is API 24.
LINKER="$TOOLCHAIN/bin/aarch64-linux-android24-clang"
if [[ ! -x "$LINKER" ]]; then
  echo "Cannot find the Android linker at $LINKER" >&2
  ls "$TOOLCHAIN/bin" 2>/dev/null | grep aarch64 | head -5 || true
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> fetching glen ($REF)"
git clone --depth 1 --branch "$REF" "$REPO" "$WORK/glen"

echo "==> building for aarch64-linux-android"
(
  cd "$WORK/glen"
  # The checked-in .cargo/config.toml turns on neon+dotprod for the host. On
  # Android those are baseline, not optional, so the flags are replaced rather
  # than appended.
  cat > .cargo/config.toml <<'EOF'
[target.aarch64-linux-android]
rustflags = ["-C", "target-feature=+neon"]
linker = "aarch64-linux-android24-clang"
EOF

  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$LINKER"
  export CC_aarch64_linux_android="$LINKER"
  export AR_aarch64_linux_android="$TOOLCHAIN/bin/llvm-ar"
  cargo build --release --target aarch64-linux-android
)

BUILT="$WORK/glen/target/aarch64-linux-android/release/Glen"
if [[ ! -f "$BUILT" ]]; then
  echo "glen did not produce a binary at $BUILT" >&2
  exit 1
fi

# Bundled as a .so so the Android packager treats it as a native library and
# extracts it to nativeLibraryDir, which is the only place an app can still exec
# from on a modern Android.
cp "$BUILT" "$OUT"
chmod 0755 "$OUT"

SIZE="$(wc -c <"$OUT")"
echo "==> wrote $OUT ($SIZE bytes)"
if ! grep -qa "Android" "$OUT" 2>/dev/null; then
  echo "note: could not confirm the binary is linked for bionic, continuing"
fi