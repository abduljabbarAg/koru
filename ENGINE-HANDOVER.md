# Engine swap handover — llama.cpp

Status as of `925a019` (pushed to `main`). This file covers **only** the
engine swap. Everything else lives in `HANDOFF.md`.

**Partly verified, and the distinction matters.** Verified on this machine: the
engine cross-compiles from llama.cpp b11574 into a static AArch64 binary with
no glibc references, and the APK carrying both it and the model builds. Not yet
verified: the app starting the engine *on the phone*. That check is the whole
game and nothing below pretends it has been passed.

---

## What changed

The bundled inference engine is llama.cpp instead of glen. Measured on the
target phone, all three candidates on the same 231 MB
`Bonsai-1.7B-Q1_0.gguf`:

| Engine | Reads Q1_0 | Output | Generation |
| --- | --- | --- | --- |
| **llama.cpp b11574** | yes | correct | **4.65 t/s** |
| PortLLM | yes | wrong (`pepepepe`) | 0.30 t/s |
| glen | no — `unknown dtype 41` | — | — |

llama.cpp answered *"The capital of France is"* with *Paris*, fluently, at
roughly 15x the speed of the engine it replaced.

`GGML_TYPE_Q1_0 = 41` is in stock ggml since before this tag — glen's
"unknown dtype 41" was a missing case in glen, not an exotic format.

**No new integration was needed.** Koru has never had an FFI surface. It execs
a binary out of `nativeLibraryDir` via `ProcessBuilder` and talks to it over
loopback HTTP/SSE. `lib/local/local_model_client.dart` already documented the
engine as swappable — *"glen, llama.cpp's server, or anything else that speaks
the API"*. llama.cpp ships `llama-server`, which speaks exactly that.

Files touched:

- `android/app/src/main/kotlin/com/abduljabbar/koru/MainActivity.kt` — execs
  `libllama-server.so --model … --port … --host 127.0.0.1 --threads 2
  --no-warmup`. All `Glen_*` environment variables removed.
- `tool/build_engine_android.sh` — was `build_glen_android.sh`, rewritten for
  llama.cpp + CMake + NDK. Uses the NDK's own `android.toolchain.cmake`, not
  the `ggml/android-ndk.cmake` that exists in no release, and builds
  `BUILD_SHARED_LIBS=OFF`: one self-contained executable has no loader path
  to get wrong. Stripped with `llvm-strip`: 187 MB unstripped → 13.8 MB.
- `.github/workflows/apk.yml` — the `glen` job is now `engine`, clones
  llama.cpp at b11574, and fetches the Bonsai model (sha256
  `3d7c6c90…f7e3`) instead of Qwen.
- `third_party/glen` and `third_party/portllm` — deleted.

---

## Build and install, from this machine

```bash
# engine (~3 min): NDK 28.2 at ~/Android/Sdk/ndk/28.2.13676358
NDK_ROOT=~/Android/Sdk/ndk/28.2.13676358 \
LLAMA_CPP_DIR=/tmp/opencode/llama.cpp \
  ./tool/build_engine_android.sh
# -> android/app/src/main/jniLibs/arm64-v8a/libllama-server.so (13.8 MB)

# APK: the model must be at assets/models/Bonsai-1.7B-Q1_0.gguf first
export JAVA_HOME=~/jdk21 ANDROID_HOME=~/Android/Sdk
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk (~265 MB, model included)

~/Android/Sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The engine and the `.gguf` are gitignored. A fresh clone has to rebuild and
redownload both, which is why both steps are scripted rather than remembered.

---

## Do these next

### 1. ~~Build the engine~~ Done. See above.

### 2. ~~Turn bundling on and build the APK~~ Done. `BUNDLE_LOCAL_ENGINE` is
`"true"` in `.github/workflows/apk.yml`, so CI fetches the engine binary and
Bonsai and every APK carries both. A local build still has to put the same two
files in the same places first.

### 3. ~~Confirm `llama-server` survives extraction and execs~~ **Still open.**
This was the one risk the previous handover named and it has not been retired
by anything done on this machine. What *has* been checked: the binary is
AArch64, statically linked apart from `libm`/`libdl`/`libc`, and carries no
glibc symbols — the failure modes that would stop an exec outright. The
remaining unknown is Android's own refusal to exec, and only a phone can
answer it. See "Build and install" above; the engine log lands in
`filesDir/llama-server.log` and the Settings screen surfaces its tail.

### 4. ~~Check the shared libraries travel~~ Moot.
The build is static (`BUILD_SHARED_LIBS=OFF`): only `libm`, `libdl`, `libc`
in NEEDED, no `libggml-*` to lose. readelf confirms AArch64 and zero glibc
references.

### 5. Re-measure on device

Through the app, not the CLI. Confirm roughly 4.6 t/s and that the answer is
sensible. If generation is ~0.1 t/s, check `--threads 2` actually survived.

### 6. ~~Model choice~~ Made.

`Bonsai-1.7B-Q1_0.gguf` (231 MB) ships, not `qwen2.5-0.5b-instruct-q4_k_m.gguf`
(491 MB). Same resident size, sharper answers, half the download. The Qwen
filename is still accepted by `modelFile()` so an install that already unpacked
the old file keeps working; it is no longer bundled.

---

## Threading — do not "fix" this

Decoding one token of the 1.7B:

```
1 thread   3.87 t/s
2 threads  4.65 t/s   <- best
4 threads  0.13 t/s   <- collapses
```

Past two threads this CPU does not benefit; they contend for cores the model is
already using. The old glen settings said four threads, on measurements from a
different model. `--threads 2` is deliberate. Do not raise it to core count.

---

## Anything to bring back

Nothing was actually destroyed — both engines were vendored as **plain tracked
files**, not submodules, with their commits recorded:

```bash
git show 925a019^:third_party/glen
git show 925a019^:third_party/portllm
```

PortLLM's work is worth keeping regardless of whether it ships:

- A **fused Q1_0 kernel** — Q1_0 weights are exactly ±scale, so
  `dot = scale · (2·Σ{bit set} x − Σ(all) x)`, with the second sum hoisted out
  of the row loop. Verified against exact f32 arithmetic to **3.6e-5** on
  Bonsai's real attention weights.
- The finding that **Qwen3 needs per-head QK-norm before RoPE**. PortLLM had no
  support for those tensors at all, and glen — which *did* — was where that
  gap was found. Anything else built on Qwen3 will hit it.

---

## Known blockers carried in

- **GitHub Actions quota is exhausted** (5898 minutes used; jobs fail with zero
  steps). Any CI plan depends on quota resetting, or on building locally.
- **PortLLM's accuracy bug was never root-caused.** Logits are finite and
  well-ranged and hidden-state RMS is healthy, so it is subtle, not NaN or
  memory. It reproduced on PortLLM's own reference model
  (`qwen2.5-0.5B-Q4_K`), so it is engine-wide rather than Q1_0-specific. Do not
  assume Q1_0 caused it.
