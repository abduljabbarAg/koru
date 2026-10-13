//! PortLLM: a portable LLM engine that sizes itself to its device.
//!
//! The recommendation is what the engine serves; see the library crate for the
//! halves this file sits on top of.
//! which is why the recommendation is not a presentation detail.

// The engine itself lives in the library; this file is the command line.



















use portllm::device::{self, Accel};
use portllm::{fast, fit, gguf, kernel, model, moe, placement, registry, sampling, serve, stream, streaming, tokenizer, unpack, validate};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("recommend");

    let dev = device::probe();

    match cmd {
        "detect" => print_detect(&dev),

        "plan" => {
            print_detect(&dev);
            print_plan(&dev);
        }

        "serve" => {
            // Same shape as glen's --serve, because the app on the other end
            // already speaks to that and should not have to know which engine
            // it started.
            let path = args.get(1).cloned().unwrap_or_default();
            if path.is_empty() {
                eprintln!("usage: portllm serve <model.gguf> [port]");
                std::process::exit(2);
            }
            let port: u16 = args.get(2).and_then(|v| v.parse().ok()).unwrap_or(8080);
            let t0 = std::time::Instant::now();
            let engine = serve::Engine::load(std::path::Path::new(&path), 512)
                .unwrap_or_else(|e| {
                    eprintln!("portllm serve: {e}");
                    std::process::exit(1)
                });
            eprintln!("portllm model prepared in {:.2}s", t0.elapsed().as_secs_f64());
            if let Err(e) = serve::run(engine, port) {
                eprintln!("portllm serve: {e}");
                std::process::exit(1);
            }
        }

        "offsets" => {
            let path = args
                .get(1)
                .cloned()
                .unwrap_or_else(|| "/tmp/qwen05b-good.gguf".to_string());
            print_offsets(std::path::Path::new(&path));
        }

        "extract" => {
            // Dump the raw bytes of one tensor, for cross-checking a
            // dequantiser against a reference implementation.
            let path = args.get(1).cloned().unwrap_or_else(|| "/tmp/qwen05b-good.gguf".into());
            let want = args.get(2).cloned().unwrap_or_else(|| "blk.0.attn_q.weight".into());
            let nblk: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(4);
            let out = args.get(4).cloned().unwrap_or_else(|| "/tmp/blocks.bin".into());
            match gguf::read_header(std::path::Path::new(&path)) {
                Ok(h) => {
                    let mut data = Vec::new();
                    use std::io::Read;
                    if let Ok(mut f) = std::fs::File::open(&path) {
                        let _ = f.read_to_end(&mut data);
                    }
                    match h.tensors.iter().find(|t| t.name == want) {
                        Some(t) => {
                            // nblk = number of quantisation blocks to dump
                            let total = t.bytes().unwrap_or(0);
                            let nblocks = t.elements.div_ceil(
                                match t.ggml_type { 6 | 8 => 32, 12 | 14 => 256, 0 => 1, _ => 1 });
                            let per = total / nblocks.max(1);
                            let start = (h.data_offset + t.name_offset) as usize;
                            let n = (per * nblk as u64).min(total) as usize;
                            if start + n <= data.len() {
                                std::fs::write(&out, &data[start..start + n]).ok();
                                println!("wrote {n} bytes of {want} (block {per}B) to {out}");
                            } else {
                                println!("range out of bounds");
                            }
                        }
                        None => println!("{want} not found"),
                    }
                }
                Err(e) => println!("{e}"),
            }
        }

        "run" => {
            let path = args.get(1).cloned().unwrap_or_else(|| "/tmp/qwen05b-good.gguf".into());
            let prompt = args.get(2).cloned().unwrap_or_else(|| "Hello".into());
            let max_new: usize = args.get(3).and_then(|v| v.parse().ok()).unwrap_or(24);
            let temp: f32 = args.get(4).and_then(|v| v.parse().ok()).unwrap_or(0.0);
            let seed: u64 = args.get(5).and_then(|v| v.parse().ok()).unwrap_or(1);
            let repeat_penalty: f32 = args.get(6).and_then(|v| v.parse().ok()).unwrap_or(1.0);
            let stops: Vec<String> = args
                .iter()
                .skip(7)
                .take_while(|a| !a.starts_with("--"))
                .cloned()
                .collect();

            let Some(h) = gguf::read_header(std::path::Path::new(&path)).ok() else {
                println!("could not read {path}");
                return;
            };
            let tok = tokenizer::Tokenizer::from_header(&h).expect("tokenizer");
            let streaming = args.iter().any(|a| a == "--stream");
            let t0 = std::time::Instant::now();
            if streaming {
                return stream_generate(&path, &prompt, max_new, temp, seed, repeat_penalty, &stops);
            }
            let m = model::load(std::path::Path::new(&path)).expect("model");
            let blocks: Vec<_> = (0..m.n_layer)
                .filter_map(|i| m.block(i).map(|b| m.prepare(&b)))
                .collect();
            eprintln!("blocks prepared in {:?}", t0.elapsed());
            let output = m.as_i8(m.tensor("output.weight").expect("output weight"));
            let n_vocab = match h.get("tokenizer.ggml.tokens") {
                Some(gguf::Value::Array(a)) => a.len(),
                _ => 0,
            };
            let final_norm = m.as_f32(m.tensor("output_norm.weight").expect("output norm"));
            eprintln!("weights prepared in {:?}", t0.elapsed());
            let stopper = sampling::Stopper::from_texts(&tok, &stops);
            let out = m.generate(
                &blocks, &output, n_vocab, &final_norm, &tok, &prompt, max_new, temp, seed,
                repeat_penalty, &stopper,
                |_, _| {},
            ).expect("generate");
            let dt = t0.elapsed().as_secs_f32();
            println!();
            println!("{}", tok.decode(&out));
            eprintln!("[{} tokens in {:.1}s = {:.2} tok/s]", out.len(), dt, out.len() as f32 / dt.max(0.001));
        }

        "tok" => {
            let path = args.get(1).cloned().unwrap_or_else(|| "/tmp/qwen05b-good.gguf".into());
            let Some(h) = gguf::read_header(std::path::Path::new(&path)).ok() else { return };
            let t = tokenizer::Tokenizer::from_header(&h).expect("tok");
            for w in args.iter().skip(2) {
                let ids = t.encode(w);
                println!("{w:?} -> {ids:?} -> {:?}", t.decode(&ids));
                for id in &ids {
                    println!("    {id}: {:?}", t.token_text(*id));
                }
            }
        }

        "moe" => {
            let path = args.get(1).cloned().unwrap_or_default();
            match gguf::read_header(std::path::Path::new(&path)) {
                Ok(h) => {
                    for (k, v) in &h.metadata {
                        let d = match v {
                            gguf::Value::Array(a) => format!("array[{}]", a.len()),
                            gguf::Value::Str(x) => { if x.len() > 30 { format!("str({})", &x[..30]) } else { format!("str({x})") } }
                            o => format!("{o:?}"),
                        };
                        println!("{k} = {d}");
                    }
                    println!("--- tensors mentioning expert/router ---");
                    let mut n = 0;
                    for t in &h.tensors {
                        if t.name.contains("expert") || t.name.contains("ffn_gate_inp") || t.name.contains("router") {
                            if n < 14 { println!("  {}  elems={} type={}", t.name, t.elements, t.ggml_type); }
                            n += 1;
                        }
                    }
                    println!("  ... {} expert tensors total", n);
                    let mut l0 = 0;
                    for t in &h.tensors { if t.name.starts_with("blk.0.") { l0 += 1; } }
                    println!("blk.0 has {} tensors", l0);
                }
                Err(e) => println!("{e}"),
            }
        }

        "vocab" => {
            let path = args.get(1).cloned().unwrap_or_else(|| "/tmp/qwen05b-good.gguf".into());
            match gguf::read_header(std::path::Path::new(&path)) {
                Ok(h) => {
                    for (k, v) in &h.metadata {
                        let desc = match v {
                            gguf::Value::Array(a) => format!("array[{}]", a.len()),
                            gguf::Value::Str(s) => {
                                if s.len() > 40 { format!("str({})", &s[..40]) } else { format!("str({s})") }
                            }
                            other => format!("{other:?}"),
                        };
                        println!("{k} = {desc}");
                    }
                }
                Err(e) => println!("{e}"),
            }
        }

        "inspect" => {
            let path = args
                .get(1)
                .cloned()
                .unwrap_or_else(|| "/tmp/qwen05b.gguf".to_string());
            print_inspect(std::path::Path::new(&path));
        }

        "recommend" | "rec" => {
            print_detect(&dev);
            print_recommend(&dev);
            print_plan(&dev);
        }

        "help" | "--help" | "-h" => {
            eprintln!("portllm detect      what this device is");
            eprintln!("portllm recommend   what to run on it (default)");
            eprintln!("portllm inspect <f.gguf>  what a model file actually contains");
            eprintln!("portllm serve <model.gguf> [port]  OpenAI compatible server on loopback");
            eprintln!("portllm plan        where that model's bytes would live");
        }

        other => {
            eprintln!("unknown command: {other}");
            eprintln!("try: portllm detect | recommend | plan");
            std::process::exit(2);
        }
    }
}

/// Show where the chosen model's bytes would actually live.
///
/// This is the unified-memory idea made concrete: one pool, several tiers, and
/// a placement policy. The interesting column is the tier, because a region on
/// storage is a promise the device may not be able to keep.
fn print_plan(d: &device::Device) {
    let Some(m) = pick_model(d) else {
        return;
    };

    let regions = placement::regions_for(m, m.default_ctx);
    let plan = placement::Placement::plan(d, regions);

    println!();
    println!("memory plan for {} at {}k context", m.id, m.default_ctx / 1024);
    println!(
        "  {:<12} {:>9}  {:>4} reads/tok  {:>9}  {}",
        "region", "size", "", "est/token", "tier"
    );

    let speeds = placement::TierSpeeds::from_device(d);
    for r in &plan.regions {
        let ms = r.cost_per_token(&speeds) * 1000.0;
        println!(
            "  {:<12} {:>7} MB  {:>4}          {:>7.2}ms  {}",
            r.name,
            r.bytes / (1024 * 1024),
            r.reads_per_token,
            ms,
            r.tier.label()
        );
    }

    println!();
    println!(
        "  resident {:} MB of a {:} MB budget",
        plan.resident_bytes / (1024 * 1024),
        plan.budget_bytes / (1024 * 1024)
    );
    if plan.streamed_bytes > 0 {
        println!(
            "  streamed {:} MB from storage",
            plan.streamed_bytes / (1024 * 1024)
        );
    }
    println!("  estimated {:.1} ms per token", plan.est_ms_per_token(d));

    if speeds.gpu <= 0.0 {
        println!();
        println!("  No GPU tier appears above because this process cannot reach");
        println!("  one. That is a placement decision, not a formatting choice.");
    }
}

/// Where each tensor's data actually sits, and how far the last one reaches.
///
/// This exists because the integrity check reported a known-good HuggingFace
/// download as truncated, and the only way to find out why was to compare the
/// declared tensor extents against the real file.
fn print_offsets(path: &std::path::Path) {
    let h = match gguf::read_header(path) {
        Ok(h) => h,
        Err(e) => {
            println!("cannot read {}: {e}", path.display());
            std::process::exit(1);
        }
    };
    let mut max_end = 0u64;
    let mut sum = 0u64;
    let mut unknown = 0usize;
    let mut biggest: Vec<(u64, u32, u64, u64)> = Vec::new();

    for t in &h.tensors {
        let Some(bytes) = t.bytes() else {
            unknown += 1;
            continue;
        };
        let end = t.name_offset.saturating_add(bytes);
        if end > max_end {
            max_end = end;
        }
        sum += bytes;
        if bytes > 20_000_000 {
            biggest.push((t.name_offset, t.ggml_type, t.elements, bytes));
        }
    }

    let maxrel = h.tensors.iter().map(|t| t.name_offset).max().unwrap_or(0);
    println!("data starts at   {} (aligned)", h.data_offset);
    println!("max rel offset   {}", maxrel);
    println!("data_start+max   {}", h.data_offset + maxrel);
    println!("file size        {}", h.total_bytes);
    println!("file size        {}", h.total_bytes);
    println!("last tensor ends {}", h.data_offset + max_end);
    println!("sum of sizes     {}", sum);
    println!("unsized tensors  {}", unknown);
    biggest.sort_by(|a, b| b.3.cmp(&a.3));
    println!();
    println!("largest tensors:");
    for (off, ty, el, bytes) in biggest.iter().take(6) {
        println!(
            "  offset {off:>12}  type {ty:>3}  elems {el:>10}  bytes {bytes:>12}"
        );
    }
}

/// Read a real GGUF header and report what is actually in the file.
///
/// This is the honest counterpart to the registry. The registry holds
/// published numbers; this reads the bytes. Where they disagree, the bytes
/// win, and that is the whole reason the parser exists.
fn print_inspect(path: &std::path::Path) {
    let start = std::time::Instant::now();
    let h = match gguf::read_header(path) {
        Ok(h) => h,
        Err(e) => {
            println!("cannot read {}: {e}", path.display());
            std::process::exit(1);
        }
    };
    let elapsed = start.elapsed();

    println!("{}", path.display());
    println!("  file         {} MB", h.total_bytes / (1024 * 1024));
    println!("  gguf v{}      parsed in {} us", h.version, elapsed.as_micros());
    println!("  header       {} KB", h.data_offset / 1024);
    println!("  tensors      {}", h.tensor_count);
    println!("  metadata     {} keys", h.metadata_kv_count);

    let types: Vec<String> = h.types_used().iter().map(|t| gguf::type_name(*t)).collect();
    println!("  quant types  {}", types.join(", "));

    match h.tensor_bytes() {
        Some(b) => println!("  tensor data  {} MB", b / (1024 * 1024)),
        None => println!("  tensor data  unknown ({} tensors unsized)", h.unsized_tensors()),
    }

    if let Some(a) = h.get("general.architecture").and_then(|v| v.as_str()) {
        println!("  architecture {}", a);
    }
    if let Some(n) = h.get("general.name").and_then(|v| v.as_str()) {
        println!("  name         {}", n);
    }

    // The truncation check. Worth calling out explicitly because a short
    // download parses fine and only fails later, during inference.
    match h.integrity() {
        gguf::Integrity::Ok => println!("  integrity    ok"),
        gguf::Integrity::Truncated { short_by } => println!(
            "  integrity    TRUNCATED: header declares {} MB more than the file holds",
            short_by / (1024 * 1024)
        ),
        gguf::Integrity::Oversized { extra } => println!(
            "  integrity    OVERSIZED: {} MB of the file is not tensor data",
            extra / (1024 * 1024)
        ),
        gguf::Integrity::Unsized { count } => println!(
            "  integrity    UNKNOWN: {count} tensors use a quant type we cannot size"
        ),
    }
}

/// The best model this device can hold, which is what a plan is built for.
fn pick_model(d: &device::Device) -> Option<&'static registry::Model> {
    let fits = fit::recommend(d);
    let best = fits
        .iter()
        .find(|f| f.verdict != fit::Verdict::TooHeavy)?;

    registry::catalog().iter().find(|m| m.id == best.model_id)
}

fn print_detect(d: &device::Device) {
    println!("device");
    println!("  cores          {}", d.cores);
    if d.big_cores < d.cores {
        println!("  big cluster    {} of {}", d.big_cores, d.cores);
    }
    let mhz: Vec<String> = d
        .core_max_mhz
        .iter()
        .filter(|m| **m > 0)
        .map(|m| m.to_string())
        .collect();
    if !mhz.is_empty() {
        println!("  clocks         {} MHz", mhz.join(", "));
    }
    println!("  ram            {} MB total, {} MB available", d.ram_total_mb, d.ram_available_mb);
    if d.storage_read_mb_s > 0 {
        println!(
            "  storage        {} MB/s read, {} MB/s write (measured)",
            d.storage_read_mb_s, d.storage_write_mb_s
        );
    } else {
        println!("  storage        not measurable here");
    }
    println!("  accelerator    {} ({})", d.accel.label(), d.accel_detail);

    if d.accel == Accel::UnreachableGpu {
        println!();
        println!("  The GPU is present but this sandbox cannot open it, so every");
        println!("  number below assumes CPU. That is not pessimism, it is what");
        println!("  the process can actually do.");
    }
}

fn print_recommend(d: &device::Device) {
    let fits = fit::recommend(d);

    println!();
    println!("recommendations");
    println!(
        "  {:<24} {:>9}  {:>8}  {:>7}  {}",
        "model", "context", "peak", "est tok/s", "verdict"
    );

    for f in &fits {
        if f.verdict == fit::Verdict::TooHeavy {
            println!(
                "  {:<24} {:>9}  {:>8}  {:>7}  {}",
                f.model_id,
                "-",
                "-",
                "-",
                f.verdict.label()
            );
            continue;
        }
        println!(
            "  {:<24} {:>8}k  {:>7} MB  {:>7.1}  {}{}",
            f.model_id,
            f.ctx / 1024,
            f.peak_bytes / (1024 * 1024),
            f.est_tok_s,
            f.verdict.label(),
            if f.is_moe { "  (MoE)" } else { "" }
        );
    }

    let usable: Vec<_> = fits
        .iter()
        .filter(|f| f.verdict != fit::Verdict::TooHeavy)
        .collect();

    if let Some(best) = usable.first() {
        println!();
        println!("start with {}", best.model_id);
        if let Some(m) = crate::registry::catalog()
            .iter()
            .find(|m| m.id == best.model_id)
        {
            println!("  {}", m.note);
        }
    } else {
        println!();
        println!("nothing fits natively; only streaming is left, and it will crawl.");
        println!("free some RAM and rerun.");
    }

    println!();
    println!("  tok/s is estimated from measured memory bandwidth, not benchmarked.");
    println!("  peak includes the KV cache, which is why context dominates the number.");
}
/// Generation through the mapped, layer-at-a-time path.
///
/// Same arithmetic as the resident path; only the residency differs. This is
/// the path that lets a model larger than RAM run, and the point of it is that
/// peak memory is one layer rather than the whole file plus every decoded
/// layer.
#[allow(clippy::too_many_arguments)]
fn stream_generate(
    path: &str,
    prompt: &str,
    max_new: usize,
    temp: f32,
    seed: u64,
    repeat_penalty: f32,
    stops: &[String],
) {
    let t0 = std::time::Instant::now();
    let mut sm = match streaming::StreamingModel::open(std::path::Path::new(path), 2) {
        Ok(m) => m,
        Err(e) => {
            println!("{e}");
            return;
        }
    };
    eprintln!(
        "mapped in {:?}, resident budget {} MB",
        t0.elapsed(),
        sm.resident_budget() / (1024 * 1024)
    );

    let tok = match tokenizer::Tokenizer::from_header(sm.header()) {
        Ok(t) => t,
        Err(e) => {
            println!("{e}");
            return;
        }
    };
    let prompt_ids = tok.encode(prompt);
    if prompt_ids.is_empty() {
        println!("the prompt encoded to nothing");
        return;
    }

    // The geometry is copied out so the streaming model stays mutable: the
    // layer cache is what re-decoding a layer is meant to avoid, and holding
    // a borrow across it would defeat that.
    let meta = sm.meta.clone();
    let m = &meta;
    let output = sm.tensor_i8("output.weight").expect("output weight");
    let final_norm = sm.tensor_f32("output_norm.weight").expect("output norm");
    let vocab = m.vocab_len();

    let cap = prompt_ids.len() + max_new + 8;
    let mut cache = model::Cache::new(m.n_layer, m.n_kv_head, m.head_dim, cap);
    let mut trace = model::Trace::default();
    let mut scratch = model::Scratch::new(m.n_embd, m.n_head, m.n_kv_head, m.head_dim, m.n_ff);
    let mut logits = vec![0f32; vocab];
    let mut rng = sampling::Rng::new(seed);
    let embm = sm.tensor_f32("token_embd.weight").expect("embedding");
    let mut xs: Vec<f32> = Vec::with_capacity(m.n_embd);

    // Prefill.
    for (i, id) in prompt_ids.iter().enumerate() {
        let st = *id as usize * m.n_embd;
        xs.clear();
        xs.extend_from_slice(&embm[st..st + m.n_embd]);
        for bi in 0..m.n_layer {
            let blk = match sm.layer(bi) {
                Ok(b) => b,
                Err(e) => {
                    println!("{e}");
                    return;
                }
            };
            xs = m.block_forward_cached(blk, &xs, i, &mut trace, &mut scratch, &mut cache.layers[bi]);
        }
        cache.pos = i + 1;
    }

    // Decode.
    let stopper = sampling::Stopper::from_texts(&tok, stops);
    let t1 = std::time::Instant::now();
    let mut out = Vec::new();
    for _ in 0..max_new {
        m.logits_from(&xs, &final_norm, &output, &mut logits);
        if repeat_penalty != 1.0 {
            let mut hist: Vec<u32> = prompt_ids.clone();
            hist.extend_from_slice(&out);
            sampling::apply_repeat_penalty(&mut logits, &hist, repeat_penalty);
        }
        let next = sampling::sample(&logits, temp, &mut rng);
        if next as u32 == tok.eos {
            break;
        }
        let mut trial = out.clone();
        trial.push(next as u32);
        if let Some(n) = stopper.matches(&trial) {
            out.truncate(trial.len() - n);
            break;
        }
        out.push(next as u32);
        let st = next as usize * m.n_embd;
        xs.clear();
        xs.extend_from_slice(&embm[st..st + m.n_embd]);
        let pos = cache.pos;
        for bi in 0..m.n_layer {
            let blk = match sm.layer(bi) {
                Ok(b) => b,
                Err(e) => {
                    println!("{e}");
                    return;
                }
            };
            xs = m.block_forward_cached(blk, &xs, pos, &mut trace, &mut scratch, &mut cache.layers[bi]);
        }
        cache.pos = pos + 1;
    }

    let dt = t1.elapsed().as_secs_f32();
    println!();
    println!("{}", tok.decode(&out));
    eprintln!(
        "[{} tokens in {:.1}s = {:.2} tok/s]",
        out.len(),
        dt,
        out.len() as f32 / dt.max(0.001)
    );
}
