# Engine swap handover — llama.cpp

Status as of `925a019` (pushed to `main`). This file covers **only** the
engine swap. Everything else lives in `HANDOFF.md`.

**Nothing here has been run end to end.** The code is written and committed; no
APK has been built and the app has not been launched. Treat this as
"ready to build", not "verified".

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
  llama.cpp + CMake + NDK.
- `.github/workflows/apk.yml` — the `glen` job is now `engine`.
- `third_party/glen` and `third_party/portllm` — deleted.

---

## Do these next

### 1. Build the engine

```bash
NDK_ROOT=/path/to/ndk ./tool/build_engine_android.sh
```

Expects llama.cpp sources at `third_party/llama.cpp`, or set `LLAMA_CPP_DIR`.
See the script's header — it is explicit about what it wants and why.

### 2. Turn bundling on and build the APK

`BUNDLE_LOCAL_ENGINE` is `"false"` in `.github/workflows/apk.yml:23`. It gates
downloading the engine into `jniLibs/arm64-v8a` and the model into
`assets/models/`. Set it `"true"` for a local-engine build.

### 3. The one thing I could not verify

**Confirm `llama-server` survives extraction from `jniLibs` and execs.**
Everything else is mechanical, but this is the actual risk:

- Since Android 10 an app targeting API 29+ may not exec a file it wrote
  itself. Files extracted from the APK into `nativeLibraryDir` remain
  executable — that is the whole reason the engine ships as a native library.
- `build.gradle.kts:75-79` already sets `useLegacyPackaging = true` for exactly
  this, so the mechanism is in place. It has just never been exercised with
  llama.cpp's binary.
- Failure looks like `exec failed for …` in the engine log, which the Dart side
  reports as "no bundled engine".

I would bet on this working. I have not seen it work.

### 4. Check the shared libraries travel

The build script copies `libllama.so` and the ggml backends beside
`libllama-server.so`. Verify the loader finds them at runtime; a missing
`libggml-cpu-android_armv8.0_1.so` is the most likely silent failure.

### 5. Re-measure on device

Through the app, not the CLI. Confirm roughly 4.6 t/s and that the answer is
sensible. If generation is ~0.1 t/s, check `--threads 2` actually survived.

### 6. Model choice

The shipped model is `qwen2.5-0.5b-instruct-q4_k_m.gguf` (491 MB). The
benchmark above used Bonsai-1.7B-Q1_0 (231 MB). Decide which ships — the
smaller Q1_0 is roughly half the size and was the reason for this work.

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
