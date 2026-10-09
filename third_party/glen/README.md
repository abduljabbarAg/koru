# Glen

A mobile-first LLM inference engine in Rust. llama.cpp is desktop software
squeezed onto phones. Glen is designed for the phone from the first line.

![Qwen2.5](https://img.shields.io/badge/-Qwen2.5-FF6A00?style=for-the-badge)
![Llama](https://img.shields.io/badge/-Llama-0467DF?style=for-the-badge)
![Gemma](https://img.shields.io/badge/-Gemma-4285F4?style=for-the-badge)
![SmolLM](https://img.shields.io/badge/-SmolLM-FFD21E?style=for-the-badge&logoColor=black)
![TinyLlama](https://img.shields.io/badge/-TinyLlama-000000?style=for-the-badge)
![Phi](https://img.shields.io/badge/-Phi-00A4EF?style=for-the-badge)
![Mistral](https://img.shields.io/badge/-Mistral-FF7000?style=for-the-badge)
![Android](https://img.shields.io/badge/-Android-3DDC84?style=for-the-badge&logo=android&logoColor=black)
![Linux](https://img.shields.io/badge/-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Rust](https://img.shields.io/badge/-Rust-000000?style=for-the-badge&logo=rust&logoColor=white)

## What it is

- From-scratch transformer inference: GGUF parsing, quantized matmuls,
  BPE tokenizer, KV cache, batched prefill, sampling, all in one static
  binary near 1MB. One dependency (`memmap2`). No runtime.
- Phone-first engineering: mmap model loading, thread pool sharded for
  big.LITTLE, NEON dot-product paths, small Q4 models that fit in RAM.
- Chat REPL with tools the model can call: calc, date, read, list,
  write, shell, web. Plus perplexity, matmul and decode benchmarks
  built in, so every claim on this page is reproducible.
- Ternary weights: GGUF Q2_0 g128 (Prism Bonsai), so a 1.7B model runs
  from 442 MB. Qwen3 QK-norm and YaRN rope are handled, verified against
  llama.cpp output on Qwen3-0.6B.
- KV cache is int8 by default (32 value blocks with f32 scales), 3.4x
  smaller than f32: 132 MB instead of 470 MB at 2048 context for Bonsai
  1.7B. `Glen_CTX` sets the context size, `Glen_KVF32=1` restores f32.

## Benchmarks

Full writeup with reproduction commands: `docs/writeup.md`.
Release history: `CHANGELOG.md`.

Measured on Helio G99 (Android/Termux), Qwen2.5-0.5B-Instruct Q4_K_M,
model sha256 verified against Hugging Face:

| Engine | Prefill | Decode | Notes |
|---|---|---|---|
| Glen (current) | 29 to 31 tok/s | 6.39, 6.68, 6.89 tok/s | 3 consecutive runs, tools off |
| llama.cpp | 29.15 tok/s | 3.07 tok/s | llama-bench, 8 threads |

PPL on the same 1440 token file: Glen 21.95, llama.cpp 20.22. Glen scores
every token, llama.cpp scores two 512 token chunks, so the windows differ;
close agreement is the signal, not equality. Earlier optimization history
(1.34 to 3.37 tok/s builds) lives in git history. Raw commands and the
full table: `benchmarks/P0-baseline.md`. Single phone runs lie due to
thermals, every number above is a repeated run.

Ternary (Prism Bonsai 1.7B, Q2_0 g128, 442 MB): correct answers on
device, PPL 11.18 on the 181 token test prose. With the int8 activation
path and sdot kernels, decode is 1.7 to 3.4 tok/s and prefill 3.5 to
5.6 tok/s depending on device temperature. KV cache is int8: 132 MB at
2048 context, 264 MB at 4096. Further NEON weight expansion is the next
speed step.

## Supported models

Verified on device:

| Model | Quant | Status |
|---|---|---|
| Qwen2.5-0.5B-Instruct | Q4_K_M | Verified, daily driver |
| Qwen3-0.6B | Q8_0 | Verified, output matches llama.cpp |
| Ternary Bonsai 1.7B | Q2_0 g128 | Verified, correct answers, PPL 11.18 |

Expected compatible (same Qwen2/Llama tensor layout, same RoPE modes,
not yet measured — results welcome):

| Family | Examples |
|---|---|
| Qwen2 / Qwen2.5 | 0.5B, 1.5B, 3B, 7B |
| Llama 3 | 1B, 3B, 8B |
| Gemma 2 / Gemma 3 | 1B, 2B |
| SmolLM2 | 135M, 360M, 1.7B |
| TinyLlama | 1.1B |
| Phi 3 / 3.5 | mini |
| Mistral | 7B (needs a big phone) |

Set rope mode per family if output degrades (`neox` flag). File an
issue with the model link and the PPL output and it gets verified.

## Quickstart

Needs a Rust toolchain and one GGUF file. Point `Glen_MODEL` at it
or place it in `~/models/`. Models are never committed to this repo.

```sh
cargo build --release
cp target/release/Glen $PREFIX/bin/Glen

Glen --chat                    # interactive chat with tools
Glen "What is 2+2?" 12         # single prompt, 12 new tokens
Glen --bench                   # matmul plus decode benchmarks
Glen --ppl notes.txt           # perplexity over a text file
Glen --serve 8080              # OpenAI compatible server for agents
```

Serve mode keeps the KV cache across turns. A follow up request that
shares a prefix reuses the cached tokens instead of reprocessing the
whole prompt.

```sh
curl http://127.0.0.1:8080/v1/models
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hi in one word."}],"max_tokens":8}'
```

Chat commands: `/new` reset, `/quit` exit, `/temp X`, `/topk N`,
`/topp X`, `/rep X`, `/tools on|off`, `/samp` show, `/help` list.
Model tools: `<call>calc EXPR</call>`, `<call>date</call>`.

## How it works

- `gguf.rs`: zero-copy GGUF v3 reader over mmap. The model never
  fully sits in RAM.
- `quant.rs`: dequant plus GEMV/GEMM for Q4_K, Q6_K, Q5_0, Q8_0,
  F16/F32. Multithreaded pool, NEON int8 dot-product fast paths,
  optional one-time K-quant unpack cache.
- `tok.rs`: BPE with byte fallback, round-trip asserted on load.
- `main.rs`: RMSNorm, RoPE (both modes), GQA attention, SwiGLU MLP,
  prebuilt layer names, reused buffers, per-token rope table.
- `tools.rs`: sampling (temp, top-k, top-p, repeat penalty) plus
  the tool call protocol.
- `json.rs`: tiny JSON parser and escaper for serve mode, no deps.
- `serve.rs`: OpenAI compatible HTTP server, SSE streaming, and
  cross-turn KV reuse by longest common prefix.

## Roadmap

- Ternary speed: further NEON weight expansion (the 2-bit unpack is the
  bottleneck).
- KV: sliding window plus attention sinks for long chats.
- BitNet b1.58 2B measured on device.
- More quant types as measured models need them.
- Smaller default contexts for 2GB phones.

## License

MIT. See LICENSE file.
