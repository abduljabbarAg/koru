# Changelog

## 0.2.0

- Ternary: GGUF Q2_0 g128 support (the Prism private group-128 layout that
  mainline llama.cpp builds could not load), dequant plus int8 activation
  kernels with NEON sdot, batch prefill path, int8 embeddings.
- Qwen3: per-head QK-norm, head_dim read from attention.key_length, YaRN
  rope scaling in both the single token and batch paths.
- Verified against llama.cpp: Qwen3-0.6B Q8_0 output matches exactly;
  Qwen2.5-0.5B Q4_K_M PPL 21.95 vs 20.22 on the same file; Bonsai 1.7B
  Q2_0 answers correctly with PPL 11.18 on the test prose.
- KV cache is int8 by default, 32 value blocks with f32 scales, 3.4x
  smaller than f32. `Glen_CTX` sets context, `Glen_KVF32=1` restores f32.
- Serve mode: OpenAI compatible HTTP with SSE streaming, zero new
  dependencies, cross-turn KV reuse by longest common prefix.
- All layers run by default. The old hardcoded 24 layer default silently
  truncated every 28 layer model.
- PPL output no longer prints a hardcoded reference constant.

## 0.1.0

- First cut: GGUF v3 reader over mmap, Q4_K, Q5_0, Q6_K, Q8_0 kernels,
  BPE tokenizer, GQA attention, SwiGLU MLP, chat REPL with tools, matmul
  and perplexity commands, single 1 MB static binary, one dependency.
