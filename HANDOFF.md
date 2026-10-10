# Koru — engineering handoff

Read this before touching anything. Most of what is here is **not** derivable from
the code, and it is the expensive part to rediscover.

Last verified: CI green, analyze clean, 319 tests, both jobs passing.

---

## What this is

A local-first business buddy for freelancers. Clients, what is owed, what is
due, money received. It was a general life companion with fitness and learning
tracks; those were cut in 0.4.0 because breadth had produced shallow features
with zero writers and a mascot that talked about body measurements instead of
invoices. **The product is the loop, not the assistant.**

---

## The device, and why it dictates everything

The phone has **~1.6 GB available RAM** (5.6 GB total, ~4 GB in use) and 28 GB
storage. The bundled model is **491 MB**.

That single fact explains the most-reported symptom: **loading the bundled model
takes up to ~30 minutes.** It is memory starvation and cold storage I/O, not slow
code. Freeing RAM and storage on the device is the first thing to try.

**Build in GitHub Actions only.** Never build or test locally. Flutter is not
installed here and the environment cannot run it.

### The failure that looked like streaming

"Tokens arrive all at once" is **not** a streaming bug. glen ran the entire
prefill loop *before* writing the SSE headers, so during the longest silent
stretch the client had received no bytes and `send()` had not returned. Prefill
carries the caller's records and takes seconds; decode then runs at ~4 tok/s, so
every token landed a quarter-second apart. Long blank, then a drip.

Fixed by moving the headers ahead of prefill and reporting progress as SSE
comments (`serve.rs`). The Dart side reads them in
`LocalModelClient.parseProgress`. **This has never been watched on a real
device** — if it still hangs, that is where to look.

---

## glen: what is measured, and what is not

Vendored at `third_party/glen`, pinned in `third_party/GLEN_COMMIT`. Pure Rust,
one dependency (`memmap2`), no llama.cpp, no CUDA.

### Established by measurement

| fact | evidence |
|---|---|
| **glen is compute-bound, not bandwidth-bound** | Qwen3-0.6B is 19% *smaller* on disk (397 MB vs 491 MB) and **2.4x slower**. More layers plus per-head `qk_norm` outweigh the smaller file. |
| **Qwen2.5-0.5B-Instruct-Q4_K_M stays bundled** | Qwen3-0.6B is smarter but far too slow to be the default. |
| **4 threads beats 8** | 1 thread 412 ms/token, 2: 397 ms, **4: 255–259 ms**, 8: anywhere 213–511 ms. 8 is glen's default and was the cause of the erratic behaviour. |
| **Current baseline: 4.03–4.08 tok/s** | Stable within 1%. This is the number to beat. |
| **The KU cache is a large win** | `Glen_NOKU=1` drops to 3.07 then 1.33 tok/s. The pre-unpacked Q4_K path is on by default and must stay on. |
| **Prefill is I/O-bound cold, compute-bound warm** | Cold 44-token prefill took 5.30 s. Different problem from decode. Do not conflate them. |

### Measured on the device, v0.5.0, 2026-11-10

Run directly in Termux against the model extracted from the APK. These are not
estimates, and they are the most expensive thing in this file to rediscover.

| what | time |
|---|---|
| Model load + `warm()`, page cache already warm | **0.6 s** |
| Model load + `warm()`, first load | 2.9 s |
| Decode | **4.13 tok/s**, matching the documented baseline |
| **First question, 160-token prompt, cold KV** | **15.8 s** |
| The same question again, KV warm | **1.2 s** |
| 754-token prompt, cold KV | **106 s** |
| 754-token prompt, KV warm | 1.2 s |

**KV prefix reuse is the single biggest factor in perceived speed.** The same
754-token prompt took 106 s cold and 1.2 s warm, an 88x difference. Only the
*first* question after the engine starts pays full prefill; every later question
reuses the cached prefix and prefills only its own tail.

That is the whole of "2 tok/s first, then 4 tok/s". It is not the model warming
up and not the phone getting faster.

**`warm()` prefills the single token "warm" and discards the caches**, so it pays
the storage cost of pulling the model into page cache (0.6 s versus minutes when
cold) but contributes nothing to the first question. Making it prefill the real
system-prompt prefix into the *live* cache is the highest value optimisation
available, and it needs the app and the engine to agree on that prefix. **Try
that before any NEON work.**

### The streaming fix, verified against the running server

- First byte **immediately**, before prefill finishes.
- `: prefill 256/754` comments during prefill, read by
  `LocalModelClient.parseProgress`.
- Then tokens ~300 ms apart, each flushed individually.

Before the fix the client received nothing until prefill ended: a silent 15 s
blank for a realistic first question, and a silent 106 s blank for a large one.
The latency did not change. It is now visible.

### The next optimisation, and where NOT to put it

**NEON/SIMD is unfinished.** The trap: `gemv_range` dispatches to NEON only for
dtype 6 (Q5_0) and 8 (Q8_0). It is tempting to add Q4_K (dtype 12) there, but
that path is **rarely reached**, because Q4_K goes through the pre-unpacked
`gemv_ku_mt` / `gemm_ku_batch_mt` kernels instead.

**The correct target is `gemv_ku_mt` / `gemm_ku_batch_mt`.**

### A failure worth remembering

Lowering the `rows < 256` threading gate in `Pool::run` to let the 128-row K/V
projections use all threads **made things worse**: 3.90 → 2.99 tok/s. Sync
overhead exceeded the parallelism gained. Reverted (`f27a63e`). The reasoning
sounded right and was wrong.

### How to measure

Do not benchmark through CI; it is a ~30 minute loop. Instead:

1. The glen artifact is only ~450 KB. Release assets are the dependable route:
   `https://github.com/AbduljabbarBXR/koru/releases/download/<tag>/libglen.so`
2. The model can be extracted from the APK already on device rather than
   re-downloaded: `assets/flutter_assets/assets/models/qwen2.5-0.5b-instruct-q4_k_m.gguf`
3. `Glen_MODEL=/tmp/gbz/model.gguf Glen_THREADS=4 ./libglen.so "prompt" 60`
4. Three runs each, old binary vs new, same prompt. One run tells you nothing.

**Env vars are case-sensitive and the prefix is `Glen_`, not `GLEN_`.**
`Glen_MODEL`, `Glen_THREADS`, `Glen_CTX`, `Glen_TOOLS`, `Glen_NOKU`, `Glen_VERBOSE`.

### glen now has tests

`cargo test` runs in CI (`tool/` has none). The JSON escaper builds every SSE
chunk and the sampler picks every token; a mistake in either shows up as a stream
a client silently stops reading, not as a crash. Run them before changing
`json.rs`, `tools.rs` or `tok.rs`.

---

## The build, and the three ways it will waste an afternoon

`.github/workflows/apk.yml`. Flutter 3.24.0, JDK 17, NDK 27.0.12077973.
Artifacts: `koru-apk-arm64` (~464 MB, the one to install), `libglen-android-arm64`
(~450 KB). `koru-apk` (all ABIs, 1.39 GB) is **not** published any more.

1. **The Actions storage quota is 0.5 GB per month and caches count against it.**
   `cache: true` on the Flutter action caches the SDK, which is **763 MB**. The
   workflow now sets `cache: false` + `pub-cache: true`, which keeps only the
   22 MB pub cache. If artifacts start failing with "quota has been hit", check
   `actions/caches` before anything else.
2. **The repository is private, so an unauthenticated release download returns
   404, not 401.** That reads exactly like the asset not being there yet. Always
   send `Authorization: Bearer $GH_TOKEN`.
3. **The release asset CDN 404s for a few seconds after an upload** even though
   the API already lists the asset. `curl --retry` does not retry a 404. The APK
   job fetches `libglen.so` **by asset id through the API** for this reason.

Also: `flutter analyze` on this Flutter version **fails on infos**, not just
errors. One `prefer_const_constructors` will red the build.

`git push` hangs on this device after succeeding. Check `git ls-remote origin
HEAD` rather than re-pushing.

---

## Android specifics that were expensive to learn

- **Native libs are not extracted by default.** Since Android 6 the default maps
  `jniLibs` straight out of the APK, so `File(nativeLibraryDir, "libglen.so")`
  does not exist. Fixed with `useLegacyPackaging = true` in
  `android/app/build.gradle.kts`. Symptom: "no bundled model".
- **Flutter assets are under `assets/flutter_assets/`.** A model at
  `assets/flutter_assets/assets/models/x.gguf` is opened as
  `flutter_assets/assets/models/x.gguf`. Getting this wrong returns null silently.
- **Every launch failure must write its reason.** A bare `false` from
  `startEngine` made four distinct failures indistinguishable.
- The engine is launched from `nativeLibraryDir` because Android 10+ blocks exec
  from the app's writable data directory.
- **Release signing is still the debug key** unless `android/key.properties`
  exists. Every update therefore needs an uninstall first. This is the one
  production blocker that is not a bug.

---

## Product decisions that are not up for relitigating

**Koru is a tool for freelancers.** The loop is: clients → work done and
pending → money received → balance → deadlines, with AI on top.

- **Money is a ledger, not a status.** "Paid 500 of 2000 today" is the normal
  case and one amount plus a settled flag cannot say it. `Client.balanceWith` is
  the only place the arithmetic is written; the store and the screen both go
  through it so they cannot disagree.
- **A retainer is deliberately not in the balance.** It has no invoice to be
  behind on, so a balance would invent money owed that nobody billed. It reports
  last paid and next due instead.
- **Capacity warns in one direction only.** Below capacity is an opportunity;
  at capacity is a warning. Nagging someone for having too few clients punishes
  the person doing fine. Only work under way counts: a lead is a hope, a settled
  client is history.
- **Removed: fitness, learning, drafts.** All three existed with zero writers.
  The tables survive for older installs and are still cleared by `wipe`, because
  dropping one needs a migration that destroys what was logged there.

### The write path, and why it is not tool calling

`Glen_TOOLS=0` stays off. Creating an entry in the app is a *local* write, so
privacy was never the objection — **reliability** is. A 0.5B model at 4 tok/s
emits malformed JSON and picks wrong arguments often enough to corrupt a ledger.

So `lib/local/write_intent.dart` is a plain Dart parser and the model keeps the
talking. It refuses anything phrased as a question, guesses no client from free
text, and executes nothing — the caller shows a card. A wrong read is an edit
rather than a corrupted record. It is tested adversarially: every case is a
sentence that could plausibly write the wrong thing.

---

## Data model

`schemaVersion = 4`. All migrations are additive, so existing installs migrate
without data loss.

- `payments(client_id, amount, date, note)` — the ledger.
- `deadlines(client_id?, title, due, done)` — own table so they sort by urgency
  across all clients.
- `business.monthly` (v4) — a retainer, nullable.
- `fitness`, `knowledge`, `drafts` — **tables only.** The features are gone.
  Nothing reads or writes them.

**Migrations run once per user, on their phone, with their data.** Every other
test builds a fresh database, so nothing else covers them. `test/migration_test.dart`
builds a database that really is on the old schema and opens it the way the app
does. **Extend it when you bump `schemaVersion`.**

`balanceFor` is floored at zero. Documented before it was implemented, and a test
caught the gap: overpaying returned −500, which reads as money owed to the
freelancer.

---

## Testing

`flutter analyze` (infos are fatal) then `flutter test`, both in CI only.

| file | what it covers |
|---|---|
| `flow_test.dart` | End to end: a sentence in the chat, the card, the row in SQLite. Refusals, discard, fallbacks. |
| `ui_test.dart` | Business and the client screen, driven the way a person drives them. |
| `migration_test.dart` | Old schema to new. Extend this when the version moves. |
| `backup_test.dart` | Export and restore, including what restore refuses. |
| `write_intent_test.dart` | The parser, adversarially. |

**A ListView only builds what is near the viewport**, so a section further down is
not in the tree and a finder reports nothing, which is indistinguishable from the
section not existing. `ui_test.dart` has a `reveal` helper for this. And
`ensureVisible` cannot help a widget that has not been built yet.

### Checks that exist because CI is a 5 minute round trip

Run these before pushing. They do not replace a compiler; they move the obvious
failures off the loop.

- brace balance per file
- every `Consumer*` class has a `build` signature matching its base class
  (an edit once silently dropped `WidgetRef ref`)
- no local function referenced before it is declared
- import blocks sorted

---

## Known gaps

- **The streaming fix has never been watched on a real device.** Verified by
  reading the SSE ordering and by unit tests on the parser.
- **The whole app is unverified on the phone.** 319 green tests say the logic is
  right and nothing about a 486 MB APK installing on a device with 1.6 GB of RAM.
- **Release signing is the debug key**, so updates need an uninstall.
- The on-device model is exercised by a fake client in `flow_test.dart`. Nothing
  runs a real HTTP server emitting SSE.

---

## Credentials — rotate all of these

Several secrets were pasted into chat and are in the transcript. Stored at `600`
outside the repo, but exposure is exposure. **The GitHub token is embedded in
plaintext in the git remote URL** and so in `.git/config`.

Kaggle now uses `~/.kaggle/access_token`. **Kaggle is probably not useful for
glen**: there is no CUDA in glen, so a GPU notebook runs the same CPU code.
