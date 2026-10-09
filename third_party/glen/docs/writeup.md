# Ternary LLM inference on a budget Android phone

Engine, KV cache, and measured limits. Every number here was measured on
the device named below and is reproducible with the commands at the end.

## Hardware and models

- Device: Helio G99, 8 cores, 5.6 GB RAM, Android with Termux.
- Engine: Glen, a from-scratch Rust inference engine, 902,896 byte binary,
  one dependency (memmap2).
- Models: Qwen2.5-0.5B-Instruct Q4_K_M (491 MB, sha256 verified against
  Hugging Face), Ternary Bonsai 1.7B Q2_0 g128 (463 MB), Qwen3-0.6B Q8_0
  (639 MB) as a verification reference.

## Engine versus llama.cpp, same device and model

Qwen2.5-0.5B-Instruct Q4_K_M:

| Engine | Prefill | Decode |
| --- | ---: | ---: |
| Glen | 29 to 31 tok/s | 6.39, 6.68, 6.89 tok/s |
| llama.cpp, 8 threads | 29.15 tok/s | 3.07 tok/s |

Perplexity on the same 1440 token file: Glen 21.95, llama.cpp 20.22.
Glen scores every token sequentially, llama.cpp scores two 512 token
chunks, so the windows differ. Close agreement is the signal, not
equality.

## Ternary Bonsai 1.7B on the phone

| Metric | Value |
| --- | ---: |
| File size | 463 MB, 2.125 bits per weight |
| PPL, 181 token test prose | 11.18 |
| Decode | 1.7 to 3.4 tok/s, thermal dependent |
| Prefill | 3.5 to 5.6 tok/s |
| Resident at 2048 ctx, int8 KV | about 600 MB total |
| Answers | "What is 2+2" gives 4, capital of France gives Paris |

The model uses a Prism private Q2_0 layout: a group of 128 weights with
one f16 scale, 34 bytes per block. The installed llama.cpp build rejected
the file outright because the tensor type did not exist upstream yet.
Supporting it meant porting the group-128 codec, plus Qwen3 QK-norm and
YaRN rope, all verified against llama.cpp output on a model both engines
can load.

## KV cache

| Configuration | 2048 ctx | 4096 ctx |
| --- | ---: | ---: |
| f32 KV | 470 MB | 940 MB |
| int8 KV, 32 value blocks, f32 scales | 132 MB | 264 MB |

At 2048 context the int8 KV cache is 3.4x smaller with no measured
quality change in our tests. Serve mode also reuses the cache across
turns by longest common prefix: a follow up turn reused 30 cached tokens
and prefilled only 18.

## How correctness was established

1. Model file sha256 checked against the Hugging Face blob. Bit identical.
2. Plain perplexity, engine against engine, same file.
3. Output equality on Qwen3-0.6B: Glen generated exactly the same first
   16 tokens as llama.cpp for the same prompt, including the thinking
   block.
4. Ground truth vectors: for the small router model, torch logits from a
   Kaggle run are committed as test fixtures and the JavaScript runtime
   must match them within 0.1 with identical argmax.

Finding the two real bugs in that process (a missing position embedding
and missing layernorm weights in an export format) is exactly why the
ground truth fixture exists.

## Ecosystem use

Glen serves an OpenAI compatible endpoint with zero dependencies, so the
HEIDES-VOLT harness uses it as its offline brain. In that setup:

- A 2.17M parameter ternary router handles familiar intents in 296 ms
  with no brain call, verified by measurement.
- Brain turns on this phone take 15 to 30 seconds with a 1.7B ternary
  model. That is physics, not a bug. The fast path is the remedy.
- A second small model as a critic was measured and rejected: it added
  74 percent wall clock for zero correctness gain. Deterministic
  verification (rules, tests, exact checks) is the right judge on edge
  hardware. Details in the harness repo, notes/critic-ab.md.

## Reproduction

```sh
cargo build --release
M=~/models/qwen2.5-0.5b-instruct-q4_k_m.gguf

Glen_MODEL=$M Glen_TOOLS=0 ./target/release/Glen "Explain gravity in one short sentence." 16
llama-bench -m $M -p 32 -n 16 -t 8
Glen_MODEL=$M ./target/release/Glen --ppl README.md
llama-perplexity -m $M -f README.md -c 512 -t 8
Glen_MODEL=$M ./target/release/Glen --serve 8080
```

For Bonsai, point `Glen_MODEL` at the Q2_0 g128 file and use the same
commands. PPL will take minutes at 0.65 to 2 tok/s, which is the honest
cost of measuring on a phone.

## Limits and open items

- Single runs lie on a phone due to thermal throttling. Ranges above come
  from repeated, consecutive runs.
- The 2-bit unpack is the ternary speed bottleneck. Further NEON weight
  expansion is the next step, not done yet.
- Long context needs sliding window plus attention sinks, not done yet.
- Only the models in the supported table are verified. Everything else is
  expected compatible, not promised.
