// tools.rs : sampling (temp/top-k/top-p/repeat) + built-in tools (calc, date) for Glen.
use std::time::{SystemTime, UNIX_EPOCH};

pub struct Rng(pub u64);
impl Rng {
    pub fn new() -> Self {
        let t = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0x243f6a88);
        Rng(t | 1)
    }
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    pub fn next_f32(&mut self) -> f32 {
        ((self.next_u64() >> 11) as f64 / (1u64 << 53) as f64) as f32
    }
}

#[derive(Clone, Copy)]
pub struct Samp {
    pub temp: f32,
    pub top_k: usize,
    pub top_p: f32,
    pub repeat: f32,
}
impl Samp {
    pub fn from_env() -> Self {
        let f = |k: &str, d: f32| std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d);
        let u = |k: &str, d: usize| std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d);
        Samp { temp: f("Glen_TEMP", 0.0), top_k: u("Glen_TOP_K", 0), top_p: f("Glen_TOP_P", 1.0), repeat: f("Glen_REP", 1.0) }
    }
    pub fn desc(&self) -> String {
        format!("temp={} top_k={} top_p={} repeat={}", self.temp, self.top_k, self.top_p, self.repeat)
    }
}

/// A decoder that may not say anything.
///
/// A 0.5B model asked for structured output will happily open a brace and then
/// write prose. That is not a prompt problem, it is a vocabulary problem: the
/// tokens for "prose" are always available, so nothing pushes back. This masks
/// the logits down to the tokens that spell a required prefix, so the structure
/// is guaranteed rather than requested.
///
/// The mask is applied to the logits before sampling, which means it composes
/// with temperature, top-k and top-p rather than replacing them. Once the forced
/// text is spent the constraint ends and the model is free again, so this
/// constrains the opening of an answer and never the whole of it.
#[derive(Clone, Default)]
pub struct Constraint {
    /// The tokens that must come next, in order.
    forced: Vec<u32>,
    /// How many have already been emitted.
    taken: usize,
}

impl Constraint {
    /// Forces [ids] at the start of the next reply.
    pub fn forced(ids: Vec<u32>) -> Self {
        Constraint { forced: ids, taken: 0 }
    }

    /// True while tokens are still being forced.
    pub fn active(&self) -> bool {
        self.taken < self.forced.len()
    }

    /// The token that must come next, if any.
    pub fn next(&self) -> Option<u32> {
        self.forced.get(self.taken).copied()
    }

    /// Records that [id] was emitted.
    pub fn accept(&mut self, id: u32) {
        self.taken += 1;
        let _ = id;
    }

    /// Sets every logit except [keep] to negative infinity.
    ///
    /// A copy rather than a mutation of the caller's slice: the logits belong to
    /// the forward pass and are reused for the next token, so overwriting them
    /// would constrain every future step as well.
    pub fn mask(&self, logits: &[f32]) -> Option<Vec<f32>> {
        let keep = self.next()?;
        let mut out = vec![f32::NEG_INFINITY; logits.len()];
        let i = keep as usize;
        if i < out.len() {
            out[i] = logits[i];
        }
        Some(out)
    }
}

/// Sample next token id. temp<=0 → greedy argmax. hist = recent output ids (repeat penalty window).
pub fn sample(rng: &mut Rng, logits: &[f32], hist: &[u32], s: &Samp) -> u32 {
    let n = logits.len();
    let mut w: Vec<f32> = logits.to_vec();
    if s.repeat > 1.0 {
        let start = hist.len().saturating_sub(64);
        for &id in &hist[start..] {
            let i = id as usize;
            if i < n {
                if w[i] > 0.0 {
                    w[i] /= s.repeat;
                } else {
                    w[i] *= s.repeat;
                }
            }
        }
    }
    if s.temp <= 0.0 {
        let mut bi = 0usize;
        for i in 1..n {
            if w[i] > w[bi] {
                bi = i;
            }
        }
        return bi as u32;
    }
    for v in w.iter_mut() {
        *v /= s.temp;
    }
    if s.top_k > 0 && s.top_k < n {
        let mut idx: Vec<usize> = (0..n).collect();
        idx.sort_by(|&a, &b| w[b].partial_cmp(&w[a]).unwrap());
        let thr = w[idx[s.top_k]];
        for v in w.iter_mut() {
            if *v < thr {
                *v = f32::NEG_INFINITY;
            }
        }
    }
    let mx = w.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let mut probs: Vec<f32> = w.iter().map(|v| (*v - mx).exp()).collect();
    if s.top_p < 1.0 {
        let mut idx: Vec<usize> = (0..n).collect();
        idx.sort_by(|&a, &b| probs[b].partial_cmp(&probs[a]).unwrap());
        let total: f32 = probs.iter().sum();
        let mut cum = 0.0f32;
        let mut keep = 0usize;
        for &i in &idx {
            cum += probs[i] / total;
            keep += 1;
            if cum >= s.top_p {
                break;
            }
        }
        keep = keep.max(1);
        let mut allowed = vec![false; n];
        for &i in &idx[..keep] {
            allowed[i] = true;
        }
        for i in 0..n {
            if !allowed[i] {
                probs[i] = 0.0;
            }
        }
    }
    let sum: f32 = probs.iter().sum();
    if !(sum > 0.0) {
        return 0;
    }
    let mut r = rng.next_f32() * sum;
    for i in 0..n {
        r -= probs[i];
        if r <= 0.0 {
            return i as u32;
        }
    }
    (n - 1) as u32
}

pub const TOOLS_HINT: &str = "You have tools. To use one, emit exactly: <call>NAME ARGS</call> on its own. Tools: calc <arithmetic>, date, read <file path>, list <directory>, write <path> <text>, shell <command>, web <url>. Examples: <call>calc 37*41</call>, <call>read ~/tmp/note.txt</call>. After a tool result arrives, continue answering.";

pub fn extract_call(text: &str) -> Option<(String, String)> {
    let a = text.find("<call>")? + 6;
    let b = text[a..].find("</call>")? + a;
    let inner = text[a..b].trim();
    let mut sp = inner.splitn(2, char::is_whitespace);
    let name = sp.next()?.trim().to_string();
    let args = sp.next().unwrap_or("").trim().to_string();
    if name.is_empty() {
        return None;
    }
    Some((name, args))
}

pub fn builtin(name: &str, args: &str) -> String {
    match name {
        "calc" => match calc(args) {
            Ok(v) => {
                if v.fract() == 0.0 && v.abs() < 1e15 {
                    format!("{}", v as i64)
                } else {
                    format!("{}", v)
                }
            }
            Err(e) => format!("calc error: {}", e),
        },
        "date" => std::process::Command::new("date")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| match SystemTime::now().duration_since(UNIX_EPOCH) {
                Ok(d) => format!("epoch {}s", d.as_secs()),
                Err(_) => "unknown time".to_string(),
            }),
        "read" => {
            let p = args.split_whitespace().next().unwrap_or("");
            if p.is_empty() {
                return "read: missing path".to_string();
            }
            match std::fs::read(p) {
                Ok(b) => {
                    let n = b.len().min(6000);
                    format!("({} bytes)\n{}", b.len(), String::from_utf8_lossy(&b[..n]))
                }
                Err(e) => format!("read error: {}", e),
            }
        }
        "list" => {
            let p = if args.trim().is_empty() { "." } else { args.trim() };
            match std::fs::read_dir(p) {
                Ok(rd) => {
                    let mut v: Vec<String> = vec![];
                    for e in rd.flatten().take(60) {
                        v.push(e.file_name().to_string_lossy().into_owned());
                    }
                    if v.is_empty() {
                        "(empty)".to_string()
                    } else {
                        v.join("\n")
                    }
                }
                Err(e) => format!("list error: {}", e),
            }
        }
        "write" => {
            let mut sp = args.splitn(2, char::is_whitespace);
            let p = sp.next().unwrap_or("").trim();
            let t = sp.next().unwrap_or("");
            if p.is_empty() {
                return "write: missing path".to_string();
            }
            match std::fs::write(p, t) {
                Ok(()) => format!("wrote {} bytes to {}", t.len(), p),
                Err(e) => format!("write error: {}", e),
            }
        }
        "shell" => {
            if args.trim().is_empty() {
                return "shell: missing command".to_string();
            }
            match std::process::Command::new("timeout").arg("15").arg("sh").arg("-c").arg(args).output() {
                Ok(o) => {
                    let mut s = String::from_utf8_lossy(&o.stdout).into_owned();
                    if s.len() > 2000 {
                        s.truncate(2000);
                        s.push_str("\n[truncated]");
                    }
                    let e = String::from_utf8_lossy(&o.stderr);
                    if !e.trim().is_empty() {
                        s.push_str(&format!("\n[stderr] {}", e.trim()));
                    }
                    if s.trim().is_empty() {
                        format!("(exit {})", o.status.code().unwrap_or(-1))
                    } else {
                        s
                    }
                }
                Err(e) => format!("shell error: {}", e),
            }
        }
        "web" => {
            let u = args.split_whitespace().next().unwrap_or("");
            if u.is_empty() {
                return "web: missing url".to_string();
            }
            match std::process::Command::new("curl").arg("-sL").arg("--max-time").arg("15").arg(u).output() {
                Ok(o) => {
                    let mut s = String::from_utf8_lossy(&o.stdout).into_owned();
                    if s.len() > 2000 {
                        s.truncate(2000);
                        s.push_str("\n[truncated]");
                    }
                    if s.trim().is_empty() {
                        "web: empty response".to_string()
                    } else {
                        s
                    }
                }
                Err(e) => format!("web error: {}", e),
            }
        }
        _ => format!("unknown tool '{}'. Available: calc, date, read, list, write, shell, web", name),
    }
}

// Tiny arithmetic evaluator: + - * / % ^, parens, unary minus, decimals.
struct P {
    b: Vec<u8>,
    i: usize,
}
impl P {
    fn ws(&mut self) {
        while self.i < self.b.len() && self.b[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }
    fn expr(&mut self) -> Result<f64, String> {
        let mut v = self.term()?;
        loop {
            self.ws();
            if self.i >= self.b.len() {
                break;
            }
            let c = self.b[self.i] as char;
            if c == '+' || c == '-' {
                self.i += 1;
                let r = self.term()?;
                v = if c == '+' { v + r } else { v - r };
            } else {
                break;
            }
        }
        Ok(v)
    }
    fn term(&mut self) -> Result<f64, String> {
        let mut v = self.pow()?;
        loop {
            self.ws();
            if self.i >= self.b.len() {
                break;
            }
            let c = self.b[self.i] as char;
            if c == '*' || c == '/' || c == '%' {
                self.i += 1;
                let r = self.pow()?;
                v = if c == '*' {
                    v * r
                } else if c == '/' {
                    if r == 0.0 {
                        return Err("division by zero".into());
                    }
                    v / r
                } else {
                    v % r
                };
            } else {
                break;
            }
        }
        Ok(v)
    }
    fn pow(&mut self) -> Result<f64, String> {
        let mut v = self.unary()?;
        self.ws();
        if self.i < self.b.len() && self.b[self.i] as char == '^' {
            self.i += 1;
            let e = self.pow()?;
            v = v.powf(e);
        }
        Ok(v)
    }
    fn unary(&mut self) -> Result<f64, String> {
        self.ws();
        if self.i < self.b.len() && self.b[self.i] as char == '-' {
            self.i += 1;
            return Ok(-self.unary()?);
        }
        if self.i < self.b.len() && self.b[self.i] as char == '+' {
            self.i += 1;
            return self.unary();
        }
        self.atom()
    }
    fn atom(&mut self) -> Result<f64, String> {
        self.ws();
        if self.i < self.b.len() && self.b[self.i] as char == '(' {
            self.i += 1;
            let v = self.expr()?;
            self.ws();
            if self.i >= self.b.len() || self.b[self.i] as char != ')' {
                return Err("missing ')'".into());
            }
            self.i += 1;
            return Ok(v);
        }
        let s = self.i;
        while self.i < self.b.len() && (self.b[self.i].is_ascii_digit() || self.b[self.i] == b'.') {
            self.i += 1;
        }
        if s == self.i {
            return Err("expected number".into());
        }
        String::from_utf8_lossy(&self.b[s..self.i]).parse::<f64>().map_err(|_| "bad number".to_string())
    }
}

pub fn calc(s: &str) -> Result<f64, String> {
    let mut p = P { b: s.as_bytes().to_vec(), i: 0 };
    let v = p.expr()?;
    p.ws();
    if p.i != p.b.len() {
        return Err("trailing characters".into());
    }
    Ok(v)
}

// Tool calling is disabled in the app (Glen_TOOLS=0), but the extractor and the
// sampler are still reachable from the bench path, and the sampler decides every
// token. Both are pure enough to pin down.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_call() {
        let (name, args) = extract_call("sure <call>calc 2+2</call>").unwrap();
        assert_eq!(name, "calc");
        assert_eq!(args, "2+2");
    }

    #[test]
    fn handles_extra_text_around_the_call() {
        let (name, args) = extract_call("let me think. <call>calc 1+1</call> done").unwrap();
        assert_eq!(name, "calc");
        assert_eq!(args, "1+1");
    }

    #[test]
    fn a_call_with_no_arguments_is_still_a_call() {
        let (name, args) = extract_call("<call>date</call>").unwrap();
        assert_eq!(name, "date");
        assert_eq!(args, "");
    }

    #[test]
    fn text_without_a_call_is_not_one() {
        // The failure this guards is a model mentioning a tool in passing and the
        // app executing it.
        assert!(extract_call("I could call calc for that").is_none());
        assert!(extract_call("").is_none());
        assert!(extract_call("<call>").is_none());
        assert!(extract_call("</call>").is_none());
        assert!(extract_call("<call>   </call>").is_none(), "an empty name is not a tool");
    }

    #[test]
    fn greedy_sampling_picks_the_argmax() {
        let mut rng = Rng::new();
        let s = Samp { temp: 0.0, top_k: 0, top_p: 1.0, repeat: 1.0 };
        assert_eq!(sample(&mut rng, &[0.1, 0.9, 0.2], &[], &s), 1);
        assert_eq!(sample(&mut rng, &[5.0, 1.0, 2.0], &[], &s), 0);
    }

    #[test]
    fn greedy_sampling_never_runs_off_the_end() {
        // An all-equal or all-negative row has no obvious winner, and returning
        // an id outside the logits would index past the vocabulary.
        let mut rng = Rng::new();
        let s = Samp { temp: 0.0, top_k: 0, top_p: 1.0, repeat: 1.0 };
        for row in [&[0.0f32, 0.0][..], &[-1.0, -2.0][..], &[0.0][..]] {
            let id = sample(&mut rng, row, &[], &s);
            assert!(id < row.len() as u32, "sampled {} out of {} logits", id, row.len());
        }
    }
}
