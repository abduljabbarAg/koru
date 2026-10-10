# Koru — engineering handoff

Read this before touching anything. Most of what is here is **not** derivable from the
code, and it is the expensive part to rediscover.

Last verified: CI green at `ff1170d8`, 237 tests, both jobs passing.

---

## The device, and why it dictates everything

The phone has **~1.6 GB available RAM** (5.6 GB total, ~4 GB in use) and 28 GB storage.
The bundled model is **491 MB**.

That single fact explains the most-reported symptom: **loading the bundled model takes
up to ~30 minutes.** It is memory starvation and cold storage I/O, not slow code.
Freeing RAM and storage on the device is the first thing to try, before optimising
anything.

It also explains the second reported symptom: **"2 tok/s first, then 4 tok/s."** The
first request pays to stream the whole checkpoint off storage; later requests hit page
cache. This is now mitigated by a warm-up pass at server start (see below).

**Build in GitHub Actions only.** Never build or test locally. Flutter is not installed
on the device and the environment cannot run it.

---

## glen: what is measured, and what is not

glen is vendored at `third_party/glen`, pinned in `third_party/GLEN_COMMIT`. It is
**pure Rust with exactly one dependency (`memmap2`)** — no llama.cpp, no CUDA.

### Established by measurement

| fact | evidence |
|---|---|
| **glen is compute-bound, not bandwidth-bound** | Qwen3-0.6B is 19% *smaller* on disk (397 MB vs 491 MB) and **2.4x slower**. More layers (28 vs 24) plus per-head `qk_norm` outweigh the smaller file. |
| **Qwen2.5-0.5B-Instruct-Q4_K_M stays bundled** | Qwen3-0.6B is clearly smarter (it reasoned correctly on a test prompt) but far too slow to be the default. Keep it as a possible cloud/quality mode only. |
| **4 threads beats 8** | 1 thread 412 ms/token, 2: 397 ms, **4: 255–259 ms**, 8: anywhere 213–511 ms. 8 threads is glen's default (`available_parallelism().min(8)`) and was the *cause* of the erratic first/last-request behaviour, not a warmup effect. |
| **Current baseline: 4.03–4.08 tok/s** | Stable within 1%. This is the number to beat. |
| **The KU cache is a large win** | `Glen_NOKU=1` drops to 3.07 then 1.33 tok/s and becomes erratic. The pre-unpacked Q4_K path is on by default and must stay on. |
| **Prefill is I/O-bound cold, compute-bound warm** | Cold 44-token prefill took 5.30 s (8.3 tok/s) against a 1.59 tok/s decode rate. Different problems, do not conflate them. |

### Live in the app now

- `Glen_THREADS=4`, set in `MainActivity.startEngine`.
- Warm-up prefill before the server binds (`serve.rs::warm`), using **scratch KV caches**
  so live conversation state is never touched.
- `--bench` reads tensor shapes from the loaded checkpoint instead of hardcoded
  Qwen2.5-0.5B literals. It previously *panicked* on any other model.
- The cloud context packet is no longer prefilled into the local model — it duplicated
  facts already in `LocalEngineFacts`.

### The next optimisation, and where NOT to put it

**NEON/SIMD is unfinished.** The trap: `gemv_range` dispatches to NEON only for
**dtype 6 (Q5_0) and 8 (Q8_0)**. It is tempting to add Q4_K (dtype 12) NEON there, but
that path is **rarely reached**, because Q4_K goes through the pre-unpacked
`gemv_ku_mt` / `gemm_ku_batch_mt` kernels instead.

**The correct target is `gemv_ku_mt` / `gemm_ku_batch_mt`.**

### A failure worth remembering

Lowering the `rows < 256` threading gate in `Pool::run` to let the 128-row K/V
projections use all threads **made things worse**: 3.90 → 2.99 tok/s mean, with a
1.65 outlier. Sync overhead exceeded the parallelism gained on small matrices. The
change was reverted (`f27a63e`). The reasoning sounded right and was wrong — measure
before believing it.

### How to measure (this is the reusable asset)

Do not benchmark through CI; it is a ~32 minute loop. Instead:

1. `kaggle`-free: the glen artifact is only ~450 KB —
   `https://api.github.com/repos/AbduljabbarBXR/koru/actions/runs/<run>/artifacts/<glen-artifact-id>/zip`
   gives a static AArch64 `libglen.so` that **runs directly in Termux**.
2. The 491 MB model can be extracted from the APK already on device rather than
   re-downloaded:
   `assets/flutter_assets/assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf`
3. `Glen_MODEL=/tmp/gbz/model.gguf Glen_THREADS=4 ./libglen.so "prompt" 60` — prints
   `generated N tokens in Xs = Y tok/s`.
4. Three runs each, old binary vs new, same prompt. One run tells you nothing.

**Env vars are case-sensitive and the prefix is `Glen_`, not `GLEN_`** — this cost real
time. `Glen_MODEL`, `Glen_THREADS`, `Glen_CTX`, `Glen_TOOLS`, `Glen_NOKU`, `Glen_VERBOSE`.

---

## Android specifics that were expensive to learn

- **Native libs are not extracted by default.** Since Android 6 the default maps
  `jniLibs` straight out of the APK, so `File(nativeLibraryDir, "libglen.so")` does not
  exist and the exec path has nothing to run. Fixed with
  `packagingOptions { jniLibs { useLegacyPackaging = true } }` in
  `android/app/build.gradle.kts`. Symptom: the app said "no bundled model".
- **Flutter assets are under `assets/flutter_assets/`.** A model at
  `assets/flutter_assets/assets/models/x.gguf` is opened as
  `flutter_assets/assets/models/x.gguf`. Getting this wrong returns null silently and
  the engine "fails to start". Symptom: a 30-minute wait and then a bare error.
- **Every launch failure must write its reason.** `startEngine` returning a bare
  `false` made four distinct failures indistinguishable. It now logs the exec
  exception, or the exit code plus stderr when glen starts and dies immediately.
- The engine is launched from `nativeLibraryDir` because Android 10+ blocks exec from
  the app's writable data directory.

---

## Product direction

**Koru is becoming a tool for freelancers.** It was a broad life companion
(fitness, knowledge, business, chat) and that breadth produced shallow features: the
`knowledge` table and the `drafts` screen both exist with **zero writers**.

**Decided:** drop the learning module and fitness. Keep the mascot and the chat.

The intended loop: **clients → work done and pending → money received → balance →
deadlines**, with AI brainstorming on top.

**Still deliberately not wired:** AI tool calls that reach GitHub. `Glen_TOOLS=0` is
on purpose. Tool calls would mean network access from the engine, a GitHub token on
device, and a direct contradiction of the "nothing leaves this phone" promise. If it is
ever done it must be opt-in, read-only, allowlisted, confirmed per action, and logged.

**AED is hardcoded in 8 places** across `business.dart`, `local_assistant.dart`,
`engine.dart` and `guide.dart`. There is no currency setting. Amounts are stored as
bare doubles, so fixing it is display-layer only — no migration.

---

## Data model state

`schemaVersion = 3`. Tables `payments` and `deadlines` are **additive**, so existing
installs migrate without data loss.

- `payments(client_id, amount, date, note)` — a ledger, because "paid 500 of 2000
  today" cannot be expressed by the old single `amount` plus a binary status.
- `deadlines(client_id?, title, due, done)` — own table so they can be sorted by
  urgency across all clients.
- `balanceFor(client)` = invoiced − received, **floored at zero**. The floor was
  documented before it was implemented and a test caught the gap: overpaying returned
  −500, which reads as money owed to the freelancer.

**There is no UI for any of this yet.** The ledger is real data the app cannot show.

---

## Build and credentials

- CI: `.github/workflows/apk.yml`. Flutter 3.24.0, JDK 17, NDK 27.0.12077973.
- Artifacts: `koru-apk-arm64` (~486 MB, per-ABI, the one to use), `koru-apk` (~1.46 GB,
  all ABIs), `libglen-android-arm64` (~450 KB).
- Release signing is **debug-key** based unless `android/key.properties` exists.
- GitHub auth: `/data/data/com.termux/files/home/.config/verde/keys.env`.
- **heides** is available at `/tmp/opencode/grimtest/heides-aarch64-unknown-linux-gnu`
  (`scan`, `check`, `staged`, `mcp`). It is deterministic and local. **It has no Dart
  support**, so it scans glen and Python only — it cannot review the Flutter app. It did
  correctly flag 41 `unwrap` sites in glen, a class of bug that has already caused a real
  crash. Not currently wired into `opencode.jsonc`.

### Credentials — rotate all of these

Several secrets were pasted into chat during this work and are therefore in the
transcript: an early GitHub token, a Kaggle API key (legacy format), and a Kaggle
`KGAT_` token. Stored at `600` outside the repo and verified absent from git, but
exposure is exposure.

Kaggle now uses `~/.kaggle/access_token` containing the `KGAT_…` token, with
`KAGGLE_API_TOKEN` exported. The old `kaggle.json` username/key pair does not work —
`kernels list` returns "Authentication required" for it.

**Kaggle is probably not useful for glen.** There is no CUDA in glen, so a GPU notebook
runs the same CPU code. Kaggle is only relevant for choosing a *model*, and the
compute-bound finding makes the MoE direction unattractive anyway.
