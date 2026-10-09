# P0 baseline, 2026-09-23

Device: Helio G99 (Android/Termux), 8 cores, 5.6 GB RAM.
Model: Qwen2.5-0.5B-Instruct Q4_K_M, 491,400,032 bytes.
sha256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`,
matches the Hugging Face file exactly.
Commit under test: `e659d66` plus the serve changes in this commit.

## Speed

Glen, 3 consecutive runs, `Glen_TOOLS=0`, 16 new tokens:

| run | prefill 40 tok | decode |
|---|---|---|
| 1 | 1.35 s | 6.39 tok/s |
| 2 | 1.34 s | 6.68 tok/s |
| 3 | 1.29 s | 6.89 tok/s |

llama.cpp reference, same device and model, `llama-bench -p 32 -n 16 -t 8`:

| test | tok/s |
|---|---|
| pp32 | 29.15 +/- 3.71 |
| tg16 | 3.07 +/- 0.22 |

Glen binary size: 902,896 bytes.

## Correctness

Perplexity on this repo's README (1440 tokens):

| engine | PPL |
|---|---|
| Glen | 21.95 |
| llama.cpp | 20.22 |

Method note: Glen scores every token sequentially. llama.cpp evaluates
two chunks of 512 tokens with a 512 context, so the scored windows differ.
Close agreement is the signal, not equality.

## Serve mode

- `GET /v1/models`, `GET /health`, `POST /v1/chat/completions`
  with `stream: true` (SSE, OpenAI delta format, `[DONE]`) or plain JSON.
- Multi turn KV reuse verified: a follow up turn reused 30 cached tokens
  and prefilled only 18.
- Streaming verified end to end.

## Commands

```sh
cargo build --release
M=~/models/qwen2.5-0.5b-instruct-q4_k_m.gguf

Glen_MODEL=$M Glen_TOOLS=0 ./target/release/Glen "Explain gravity in one short sentence." 16
llama-bench -m $M -p 32 -n 16 -t 8
Glen_MODEL=$M ./target/release/Glen --ppl README.md
llama-perplexity -m $M -f README.md -c 512 -t 8
Glen_MODEL=$M ./target/release/Glen --serve 8080
```
