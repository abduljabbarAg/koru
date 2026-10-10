// serve.rs - OpenAI compatible HTTP server with KV reuse across turns. Zero deps.
use crate::json::{self, Json};
use crate::{cache_new, forward, forward_batch, tok, tools, Cache, Model, Tmp, TmpB};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

struct State {
    pos: usize,
    prev: Vec<u32>,
    tpb: TmpB,
}

/// Pulls the checkpoint into the page cache before anyone can send a request.
///
/// The first forward pass streams the whole model off storage. Measured on the
/// target phone that dominated: a 44 token prefill took 5.30s cold against a
/// decode rate of 1.59 tok/s, which is prefill running far slower than it
/// should. It is I/O, not arithmetic, and it is charged to whichever unlucky
/// question arrives first. Paying it here moves the wait to start-up, where it
/// is expected and can show progress, instead of onto the user's first question.
fn warm(m: &Model, bpe: &tok::Bpe, tpb: &mut TmpB) {
    let t0 = Instant::now();
    let ids = tok::encode(bpe, "warm");
    if ids.is_empty() {
        return;
    }
    let kv_dim = m.n_kv * m.head_dim;
    // Scratch caches, so the live KV state a conversation is building up is
    // never written to by a throwaway pass.
    let mut scratch: Vec<Cache> = (0..m.n_layer)
        .map(|_| cache_new(ids.len(), kv_dim, false))
        .collect();
    let _ = forward_batch(m, &ids, 0, &mut scratch, tpb, m.n_layer);
    println!("Glen warm complete in {:.2}s", t0.elapsed().as_secs_f64());
}

pub fn run(m: &Model, bpe: &tok::Bpe, caches: &mut [Cache], tmp: &mut Tmp, max_pos: usize, port: u16) {
    let mut st = State {
        pos: 0,
        prev: Vec::new(),
        tpb: TmpB::new(256, m.hidden, m.n_head * m.head_dim, m.n_kv * m.head_dim, m.ff, max_pos),
    };
    warm(m, bpe, &mut st.tpb);

    let listener = TcpListener::bind(("127.0.0.1", port))
        .unwrap_or_else(|e| panic!("bind 127.0.0.1:{} failed: {}", port, e));
    println!("Glen serve ready on http://127.0.0.1:{}", port);
    println!("  GET  /v1/models");
    println!("  GET  /health");
    println!("  POST /v1/chat/completions  (stream true or false)");
    for conn in listener.incoming() {
        match conn {
            Ok(s) => {
                if let Err(e) = handle(s, m, bpe, caches, tmp, &mut st) {
                    eprintln!("[serve] {}", e);
                }
            }
            Err(e) => eprintln!("[serve] accept: {}", e),
        }
    }
}

fn model_id(m: &Model) -> String {
    match m.g.kv.get("general.name") {
        Some(crate::gguf::Kv::Str(n)) => n.clone(),
        _ => m.g.arch.clone(),
    }
}

fn now_ms() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0)
}

fn find_sub(h: &[u8], n: &[u8]) -> Option<usize> {
    if n.is_empty() || h.len() < n.len() {
        return None;
    }
    (0..=h.len() - n.len()).find(|&i| &h[i..i + n.len()] == n)
}

fn read_request(s: &mut TcpStream) -> std::io::Result<(String, String, Vec<u8>)> {
    let mut buf: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 4096];
    let mut header_end = None;
    while buf.len() < 65536 {
        let n = s.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(p) = find_sub(&buf, b"\r\n\r\n") {
            header_end = Some(p);
            break;
        }
    }
    let he = header_end.unwrap_or(0);
    let head = String::from_utf8_lossy(&buf[..he]).to_string();
    let mut lines = head.lines();
    let first = lines.next().unwrap_or("");
    let mut parts = first.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("/").to_string();
    let mut clen = 0usize;
    for l in lines {
        if let Some(v) = l.to_ascii_lowercase().strip_prefix("content-length:") {
            clen = v.trim().parse().unwrap_or(0);
        }
    }
    let mut body: Vec<u8> = if buf.len() > he + 4 { buf[he + 4..].to_vec() } else { Vec::new() };
    while body.len() < clen {
        let n = s.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&chunk[..n]);
    }
    if body.len() > clen {
        body.truncate(clen);
    }
    Ok((method, path, body))
}

fn respond_json(s: &mut TcpStream, status: u16, body: &str) -> std::io::Result<()> {
    let head = format!(
        "HTTP/1.1 {} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        status,
        body.len()
    );
    s.write_all(head.as_bytes())?;
    s.write_all(body.as_bytes())?;
    s.flush()
}

fn handle(
    mut s: TcpStream,
    m: &Model,
    bpe: &tok::Bpe,
    caches: &mut [Cache],
    tmp: &mut Tmp,
    st: &mut State,
) -> std::io::Result<()> {
    s.set_nodelay(true).ok();
    let (method, path, body) = read_request(&mut s)?;
    if method == "GET" && path.starts_with("/v1/models") {
        let id = model_id(m);
        let js = format!(
            "{{\"object\":\"list\",\"data\":[{{\"id\":\"{}\",\"object\":\"model\",\"owned_by\":\"glen\"}}]}}",
            json::esc(&id)
        );
        return respond_json(&mut s, 200, &js);
    }
    if method == "GET" {
        return respond_json(&mut s, 200, "{\"ok\":true,\"engine\":\"glen\"}");
    }
    if method == "POST" && path.starts_with("/v1/chat/completions") {
        return chat(s, m, bpe, caches, tmp, st, &body);
    }
    respond_json(&mut s, 404, "{\"error\":{\"message\":\"not found\"}}")
}

fn build_prompt(m: &Model, bpe: &tok::Bpe, msgs: &[Json]) -> Vec<u32> {
    let llama = m.g.arch == "llama";
    let mut s = String::new();
    if llama {
        s.push_str("<|begin_of_text|>");
    }
    for msg in msgs {
        let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("user");
        let content = match msg.get("content") {
            Some(Json::Str(t)) => t.clone(),
            Some(Json::Arr(parts)) => parts
                .iter()
                .filter_map(|p| p.get("text").and_then(|v| v.as_str()))
                .collect::<Vec<_>>()
                .join(" "),
            _ => String::new(),
        };
        if llama {
            s.push_str(&format!(
                "<|start_header_id|>{}<|end_header_id|>\n\n{}<|eot_id|>",
                role, content
            ));
        } else {
            s.push_str(&format!("<|im_start|>{}\n{}<|im_end|>\n", role, content));
        }
    }
    if llama {
        s.push_str("<|start_header_id|>assistant<|end_header_id|>\n\n");
    } else {
        s.push_str("<|im_start|>assistant\n");
    }
    let mut ids = tok::encode(bpe, &s);
    if llama {
        ids.insert(0, bpe.bos);
    }
    ids
}

fn chat(
    mut s: TcpStream,
    m: &Model,
    bpe: &tok::Bpe,
    caches: &mut [Cache],
    tmp: &mut Tmp,
    st: &mut State,
    body: &[u8],
) -> std::io::Result<()> {
    let req = match json::parse(&String::from_utf8_lossy(body)) {
        Ok(v) => v,
        Err(e) => {
            return respond_json(
                &mut s,
                400,
                &format!("{{\"error\":{{\"message\":\"bad json: {}\"}}}}", json::esc(&e)),
            )
        }
    };
    let msgs: Vec<Json> = req
        .get("messages")
        .and_then(|v| v.as_arr())
        .map(|a| a.to_vec())
        .unwrap_or_default();
    if msgs.is_empty() {
        return respond_json(&mut s, 400, "{\"error\":{\"message\":\"messages required\"}}");
    }
    let stream = req.get("stream").and_then(|v| v.as_bool()).unwrap_or(false);
    let max_tokens = req
        .get("max_tokens")
        .and_then(|v| v.as_f64())
        .or_else(|| req.get("max_completion_tokens").and_then(|v| v.as_f64()))
        .unwrap_or(256.0)
        .max(1.0)
        .min(2048.0) as usize;
    let mut samp = tools::Samp::from_env();
    if let Some(t) = req.get("temperature").and_then(|v| v.as_f64()) {
        samp.temp = t as f32;
    }
    if let Some(p) = req.get("top_p").and_then(|v| v.as_f64()) {
        samp.top_p = p as f32;
    }
    let ids = build_prompt(m, bpe, &msgs);
    if ids.is_empty() {
        return respond_json(&mut s, 400, "{\"error\":{\"message\":\"empty prompt\"}}");
    }

    // KV reuse: longest common prefix with the cached transcript.
    let n = ids.len().min(st.prev.len());
    let mut common = 0usize;
    while common < n && ids[common] == st.prev[common] {
        common += 1;
    }
    let reuse = if common >= 4 { common } else { 0 };
    let mut start = reuse;
    if start >= ids.len() {
        start = ids.len() - 1;
    }
    if reuse == 0 {
        st.pos = 0;
    }
    let t0 = Instant::now();
    let mut logits: Vec<f32> = Vec::new();
    let mut done = start;
    while done < ids.len() {
        let end = (done + st.tpb.ncap).min(ids.len());
        logits = forward_batch(m, &ids[done..end], done, caches, &mut st.tpb, m.n_layer);
        done = end;
    }
    let reused_tok = reuse;
    let prefill_new = ids.len() - start;
    st.pos = ids.len();

    let id = format!("glen-{}", now_ms());
    let model = model_id(m);
    if stream {
        s.write_all(
            b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
        )?;
        s.flush().ok();
    }
    let mut rng = tools::Rng::new();
    let mut gen_ids: Vec<u32> = Vec::new();
    let mut out = String::new();
    let mut cur: &[f32] = &logits;
    let mut finish = "length";
    for step in 0..max_tokens {
        let nx = tools::sample(&mut rng, cur, &ids, &samp);
        if nx == bpe.eos {
            finish = "stop";
            break;
        }
        gen_ids.push(nx);
        let piece = tok::decode(bpe, &[nx]);
        out.push_str(&piece);
        if stream {
            let payload = format!(
                "{{\"id\":\"{}\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{\"content\":\"{}\"}},\"finish_reason\":null}}]}}",
                id,
                now_ms() / 1000,
                json::esc(&model),
                json::esc(&piece)
            );
            if write!(s, "data: {}\n\n", payload).is_err() {
                break;
            }
            s.flush().ok();
        }
        cur = forward(m, nx, ids.len() + step, caches, tmp, m.n_layer, false);
    }
    st.pos = ids.len() + gen_ids.len();
    st.prev = ids.clone();
    st.prev.extend_from_slice(&gen_ids);
    let dt = t0.elapsed().as_secs_f64();
    println!(
        "[serve] prompt {} tok (reused {}, prefill {}), gen {} tok in {:.2}s = {:.2} tok/s",
        ids.len(),
        reused_tok,
        prefill_new,
        gen_ids.len(),
        dt,
        gen_ids.len() as f64 / dt.max(1e-9)
    );
    if stream {
        let fin = format!(
            "{{\"id\":\"{}\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"{}\"}}]}}",
            id,
            now_ms() / 1000,
            json::esc(&model),
            finish
        );
        let _ = write!(s, "data: {}\n\n", fin);
        let _ = write!(s, "data: [DONE]\n\n");
        let _ = s.flush();
        return Ok(());
    }
    let resp = format!(
        "{{\"id\":\"{}\",\"object\":\"chat.completion\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":\"{}\"}},\"finish_reason\":\"{}\"}}],\"usage\":{{\"prompt_tokens\":{},\"completion_tokens\":{},\"total_tokens\":{}}}}}",
        id,
        now_ms() / 1000,
        json::esc(&model),
        json::esc(&out),
        finish,
        ids.len(),
        gen_ids.len(),
        ids.len() + gen_ids.len()
    );
    respond_json(&mut s, 200, &resp)
}
