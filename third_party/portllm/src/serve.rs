//! An OpenAI-compatible HTTP server.
//!
//! PortLLM generates text and had no way to hand it to anything. An application
//! on the same device still needs a socket to talk to, because the alternative
//! is linking an inference engine into the app's process and taking on its
//! memory and its threading as the app's problem.
//!
//! The surface is deliberately exactly what a chat client asks for and nothing
//! more:
//!
//! ```text
//! GET  /health                 readiness, answered before a model is loaded
//! GET  /v1/models              the loaded model
//! GET  /v1                    ditto, because clients probe several suffixes
//! POST /v1/chat/completions    stream=true or false
//! POST /chat/completions       ditto
//! ```
//!
//! Bound to loopback only. This is not a hardened network service and must not
//! become one: it holds a model in memory and will happily answer anyone who
//! can reach the port.

use crate::json::{self, Json};
use crate::model::{self, PreparedBlock};
use crate::sampling::{self, Stopper};
use crate::tokenizer::Tokenizer;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

/// Everything a request handler needs, loaded once.
pub struct Engine {
    pub model: model::Model,
    pub blocks: Vec<PreparedBlock>,
    pub output: (Vec<i8>, Vec<f32>),
    pub final_norm: Vec<f32>,
    pub tokenizer: Tokenizer,
    pub vocab: usize,
    pub max_new: usize,
    pub temperature: f32,
    pub seed: u64,
    pub repeat_penalty: f32,
    pub name: String,
}

impl Engine {
    /// Loads a model and prepares it for generation.
    ///
    /// Preparation is the slow part: blocks are unpacked and the output
    /// projection is quantised. Doing it here rather than per request is what
    /// makes the difference between a server that answers in a second and one
    /// that answers in a minute.
    pub fn load(path: &std::path::Path, max_new: usize) -> Result<Self, String> {
        let header = crate::gguf::read_header(path)
            .map_err(|e| format!("could not read {}: {e}", path.display()))?;
        let tokenizer = Tokenizer::from_header(&header)?;
        let m = model::load(path)?;
        let blocks: Vec<_> = (0..m.n_layer)
            .filter_map(|i| m.block(i).map(|b| m.prepare(&b)))
            .collect();
        if blocks.is_empty() {
            return Err("the model has no transformer blocks".into());
        }
        let output = m.as_i8(m.tensor("output.weight").ok_or("no output.weight")?);
        let final_norm = m.as_f32(m.tensor("output_norm.weight").ok_or("no output_norm.weight")?);
        let vocab = m.vocab_len();
        Ok(Engine {
            name: path
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "portllm".into()),
            model: m,
            blocks,
            output,
            final_norm,
            tokenizer,
            vocab,
            max_new,
            temperature: 0.7,
            seed: 1,
            repeat_penalty: 1.05,
        })
    }
}

/// Serves until the process is killed. One model, one request at a time.
///
/// Single-threaded on purpose. The engine owns a large scratch buffer and a KV
/// cache sized for one conversation; two concurrent conversations would mean two
/// of both, and on the phones this is built for that is the difference between
/// running and being killed.
pub fn run(engine: Engine, port: u16) -> std::io::Result<()> {
    // Shared rather than moved into the generating thread. Generation happens on
    // its own thread so a slow socket cannot stall it, and the engine is far
    // too large to clone; an Arc clone is a pointer copy.
    let engine = Arc::new(engine);
    let listener = TcpListener::bind(("127.0.0.1", port))?;
    println!("portllm serve ready on http://127.0.0.1:{port}");
    println!("  GET  /health");
    println!("  GET  /v1/models");
    println!("  POST /v1/chat/completions");
    for conn in listener.incoming() {
        match conn {
            Ok(sock) => {
                if let Err(e) = handle(&engine, sock) {
                    eprintln!("portllm serve: {e}");
                }
            }
            Err(e) => eprintln!("portllm serve: accept failed: {e}"),
        }
    }
    Ok(())
}

fn handle(engine: &Arc<Engine>, mut sock: TcpStream) -> std::io::Result<()> {
    let mut reader = BufReader::new(sock.try_clone()?);

    let mut request_line = String::new();
    if reader.read_line(&mut request_line)? == 0 {
        return Ok(());
    }
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let path = parts.next().unwrap_or("/").to_string();

    let mut content_length = 0usize;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            break;
        }
        if let Some(v) = trimmed.strip_prefix("Content-Length:") {
            content_length = v.trim().parse().unwrap_or(0);
        }
        // Connection: close is answered with the same, which keeps curl, the
        // Dart client and a browser all on the simple one-request-per-socket
        // path instead of each of them needing a persistent connection.
        if trimmed.eq_ignore_ascii_case("connection: keep-alive") {
            // honoured below by echoing close anyway
        }
    }

    let mut body = vec![0u8; content_length];
    if content_length > 0 {
        reader.read_exact(&mut body)?;
    }
    let body = String::from_utf8_lossy(&body).to_string();

    let path = path.split('?').next().unwrap_or("/");

    match (&method[..], path) {
        ("GET", "/health") => respond(&mut sock, 200, "text/plain", b"ok"),
        ("GET", "/v1") | ("GET", "/v1/") => {
            let body = models_json(engine);
            respond(&mut sock, 200, "application/json", body.as_bytes())
        }
        ("GET", "/v1/models") => {
            let body = models_json(engine);
            respond(&mut sock, 200, "application/json", body.as_bytes())
        }
        ("POST", "/v1/chat/completions") | ("POST", "/chat/completions") => {
            chat(engine, &mut sock, &body)
        }
        _ => respond(&mut sock, 404, "text/plain", b"not found"),
    }
}

fn models_json(engine: &Engine) -> String {
    format!(
        "{{\"object\":\"list\",\"data\":[{{\"id\":{},\"object\":\"model\"}}]}}",
        json::escape(&engine.name)
    )
}

fn chat(engine: &Arc<Engine>, sock: &mut TcpStream, body: &str) -> std::io::Result<()> {
    let request = match json::parse(body) {
        Ok(v) => v,
        Err(e) => {
            return respond(
                sock,
                400,
                "application/json",
                format!("{{\"error\":{}}}", json::escape(&e)).as_bytes(),
            )
        }
    };

    let prompt = match build_prompt(&request) {
        Ok(p) => p,
        Err(e) => {
            return respond(
                sock,
                400,
                "application/json",
                format!("{{\"error\":{}}}", json::escape(&e)).as_bytes(),
            )
        }
    };

    // Encoding proves the prompt is real text to this tokenizer rather than
    // something it will silently collapse to nothing. Checked here rather than
    // inside build_prompt so the layout stays a pure function of the request.
    if engine.tokenizer.encode(&prompt).is_empty() {
        return respond(
            sock,
            400,
            "application/json",
            b"{\"error\":\"the prompt encoded to nothing\"}",
        );
    }

    let max_new = request
        .get("max_tokens")
        .and_then(Json::as_f64)
        .map(|n| n.max(1.0) as usize)
        .unwrap_or(engine.max_new)
        .min(engine.max_new);
    let temperature = request
        .get("temperature")
        .and_then(Json::as_f64)
        .map(|t| t as f32)
        .unwrap_or(engine.temperature);
    let stream = request.get("stream").and_then(Json::as_bool).unwrap_or(false);

    if stream {
        stream_completion(engine, sock, &prompt, max_new, temperature)
    } else {
        whole_completion(engine, sock, &prompt, max_new, temperature)
    }
}

/// Lays a chat request out as a prompt.
///
/// ChatML, because that is the template the Qwen-family models in the registry
/// were trained against. A mismatch here is not a formatting bug, it is the
/// model answering a prompt it has never seen, which looks like the model being
/// stupid rather than the server being wrong.
fn build_prompt(request: &Json) -> Result<String, String> {
    let messages = request
        .get("messages")
        .and_then(Json::as_arr)
        .ok_or("no messages")?;
    if messages.is_empty() {
        return Err("no messages".into());
    }
    let mut out = String::new();
    for m in messages {
        let role = m.get("role").and_then(Json::as_str).unwrap_or("user");
        let content = m.get("content").and_then(Json::as_str).unwrap_or("");
        // The model emits the closing tag itself when it stops, so an assistant
        // turn is written without one. Adding it would teach the model to stop
        // mid sentence on its own reply and then ramble on as a new turn.
        if role == "assistant" {
            out.push_str("<|im_start|>assistant\n");
            out.push_str(content);
        } else {
            out.push_str("<|im_start|>");
            out.push_str(role);
            out.push_str("\n");
            out.push_str(content);
            out.push_str("<|im_end|>\n");
        }
    }
    out.push_str("<|im_start|>assistant\n");
    Ok(out)
}

fn stream_completion(
    engine: &Arc<Engine>,
    sock: &mut TcpStream,
    prompt: &str,
    max_new: usize,
    temperature: f32,
) -> std::io::Result<()> {
    let head = "HTTP/1.1 200 OK\r\n\
                Content-Type: text/event-stream\r\n\
                Cache-Control: no-cache\r\n\
                Connection: close\r\n\r\n";
    sock.write_all(head.as_bytes())?;
    sock.flush()?;

    let created = unix_now();
    let id = json::escape(&engine.name);

    // Tokens are written on the generating thread and flushed from this one, so
    // a slow socket cannot stall generation and a slow generation cannot fill a
    // channel. The channel is bounded so a client that stops reading applies
    // backpressure instead of growing the heap without limit.
    let (tx, rx) = mpsc::sync_channel::<String>(64);
    let worker = Arc::clone(engine);
    let prompt = prompt.to_string();
    let handle = std::thread::spawn(move || {
        let engine = worker;
        let prompt = prompt.as_str();
        let stopper = Stopper::from_texts(&engine.tokenizer, &["<|im_end|>".to_string()]);
        let mut first: Option<String> = None;
        let result = engine.model.generate(
            &engine.blocks,
            &engine.output,
            engine.vocab,
            &engine.final_norm,
            &engine.tokenizer,
            prompt,
            max_new,
            temperature,
            engine.seed,
            engine.repeat_penalty,
            &stopper,
            |_, piece| {
                if piece.is_empty() {
                    return;
                }
                if first.is_none() {
                    first = Some(piece.to_string());
                }
                let _ = tx.send(piece.to_string());
            },
        );
        (result, first)
    });

    let mut wrote_role = false;
    for piece in rx {
        if !wrote_role {
            wrote_role = true;
            let role = format!(
                "data: {{\"id\":{id},\"object\":\"chat.completion.chunk\",\"created\":{created},\
                 \"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\"}}}}]}}\n\n"
            );
            sock.write_all(role.as_bytes())?;
        }
        let frame = format!(
            "data: {{\"id\":{id},\"object\":\"chat.completion.chunk\",\"created\":{created},\
             \"choices\":[{{\"index\":0,\"delta\":{{\"content\":{}}},\"finish_reason\":null}}]}}\n\n",
            json::escape(&piece)
        );
        sock.write_all(frame.as_bytes())?;
        sock.flush()?;
    }

    let (result, _first) = match handle.join() {
        Ok(v) => v,
        Err(_) => {
            let _ = sock.write_all(b"data: {\"error\":\"the engine panicked\"}\n\ndata: [DONE]\n\n");
            let _ = sock.flush();
            return Ok(());
        }
    };

    // A generation that failed after the headers are already out cannot change
    // its status code. Saying so in the stream is the only honest channel left,
    // and a client that reads [DONE] without an error will show the part that
    // did arrive rather than an empty bubble.
    if let Err(e) = result {
        let err = format!("data: {{\"error\":{}}}\n\n", json::escape(&e));
        let _ = sock.write_all(err.as_bytes());
    }
    sock.write_all(b"data: [DONE]\n\n")?;
    sock.flush()?;
    Ok(())
}

fn whole_completion(
    engine: &Engine,
    sock: &mut TcpStream,
    prompt: &str,
    max_new: usize,
    temperature: f32,
) -> std::io::Result<()> {
    let stopper = Stopper::from_texts(&engine.tokenizer, &["<|im_end|>".to_string()]);
    let mut text = String::new();
    let result = engine.model.generate(
        &engine.blocks,
        &engine.output,
        engine.vocab,
        &engine.final_norm,
        &engine.tokenizer,
        prompt,
        max_new,
        temperature,
        engine.seed,
        engine.repeat_penalty,
        &stopper,
        |_, piece| text.push_str(piece),
    );

    let body = match result {
        Ok(ids) => format!(
            "{{\"id\":{},\"object\":\"chat.completion\",\"created\":{},\
             \"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":{}}},\
             \"finish_reason\":\"stop\"}}],\"usage\":{{\"completion_tokens\":{}}}}}",
            json::escape(&engine.name),
            unix_now(),
            json::escape(&text),
            ids.len()
        ),
        Err(e) => format!("{{\"error\":{}}}", json::escape(&e)),
    };
    respond(sock, 200, "application/json", body.as_bytes())
}

fn respond(sock: &mut TcpStream, status: u16, content_type: &str, body: &[u8]) -> std::io::Result<()> {
    let reason = match status {
        200 => "OK",
        400 => "Bad Request",
        404 => "Not Found",
        _ => "Error",
    };
    let head = format!(
        "HTTP/1.1 {status} {reason}\r\n\
         Content-Type: {content_type}\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\r\n",
        body.len()
    );
    sock.write_all(head.as_bytes())?;
    sock.write_all(body)?;
    sock.flush()?;
    let _ = sock.shutdown(std::net::Shutdown::Both);
    Ok(())
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_chat_request_becomes_a_prompt_that_ends_asking_for_a_reply() {
        let v = json::parse(
            r#"{"messages":[{"role":"system","content":"be brief"},
                            {"role":"user","content":"who owes me"}]}"#,
        )
        .unwrap();
        let prompt = build_prompt(&v).unwrap();
        assert_eq!(
            prompt,
            "<|im_start|>system\nbe brief<|im_end|>\n\
             <|im_start|>user\nwho owes me<|im_end|>\n\
             <|im_start|>assistant\n"
        );
    }

    #[test]
    fn an_assistant_turn_is_left_open_so_the_model_can_continue_it() {
        let v = json::parse(
            r#"{"messages":[{"role":"user","content":"hi"},
                            {"role":"assistant","content":"hello"},
                            {"role":"user","content":"and you?"}]}"#,
        )
        .unwrap();
        let prompt = build_prompt(&v).unwrap();
        // If the assistant turn were closed, the model would learn to stop
        // halfway through its own reply and then continue as a fresh turn.
        assert!(prompt.contains("<|im_start|>assistant\nhello<|im_start|>user"));
        assert!(!prompt.contains("hello<|im_end|>"));
    }

    #[test]
    fn a_request_with_no_messages_is_refused_rather_than_answered() {
        let v = json::parse(r#"{"model":"m"}"#).unwrap();
        assert!(build_prompt(&v).is_err());
    }

}
