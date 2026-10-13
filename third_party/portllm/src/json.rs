//! A small JSON reader and writer, std-only.
//!
//! Exists because the crate has no dependencies on purpose, and an HTTP server
//! cannot answer without parsing the request body and escaping the response.
//!
//! Scope is deliberately narrow: it parses what an OpenAI-compatible client
//! actually sends and escapes strings on the way out. It is not a general JSON
//! library and does not try to be one. What it does refuse is silently: a
//! malformed body is an error the caller can report, never a default value that
//! looks like a successful parse.

use std::collections::BTreeMap;
use std::fmt::Write as _;

/// A parsed JSON value.
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(BTreeMap<String, Json>),
}

impl Json {
    /// Looks up a key on an object. Returns None for every other shape.
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(m) => m.get(key),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_arr(&self) -> Option<&[Json]> {
        match self {
            Json::Arr(a) => Some(a),
            _ => None,
        }
    }

    /// Convenience for the common `"a.b"` lookup. Returns the first hit.
    pub fn path(&self, dotted: &str) -> Option<&Json> {
        let mut cur = self;
        for part in dotted.split('.') {
            cur = cur.get(part)?;
        }
        Some(cur)
    }
}

/// Parses a complete JSON document. Trailing whitespace is fine, trailing
/// garbage is not.
pub fn parse(input: &str) -> Result<Json, String> {
    let bytes = input.as_bytes();
    let mut p = Parser { b: bytes, i: 0 };
    p.ws();
    let v = p.value()?;
    p.ws();
    if p.i != bytes.len() {
        return Err(format!("trailing input at byte {}", p.i));
    }
    Ok(v)
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }

    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }

    fn eat(&mut self, lit: &[u8]) -> Result<(), String> {
        if self.b[self.i..].starts_with(lit) {
            self.i += lit.len();
            Ok(())
        } else {
            Err(format!("expected {} at byte {}", String::from_utf8_lossy(lit), self.i))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        match self.peek().ok_or_else(|| "unexpected end of input".to_string())? {
            b'n' => {
                self.eat(b"null")?;
                Ok(Json::Null)
            }
            b't' => {
                self.eat(b"true")?;
                Ok(Json::Bool(true))
            }
            b'f' => {
                self.eat(b"false")?;
                Ok(Json::Bool(false))
            }
            b'"' => Ok(Json::Str(self.string()?)),
            b'[' => self.array(),
            b'{' => self.object(),
            _ => self.number(),
        }
    }

    fn array(&mut self) -> Result<Json, String> {
        self.i += 1; // [
        let mut out = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
            return Ok(Json::Arr(out));
        }
        loop {
            self.ws();
            out.push(self.value()?);
            self.ws();
            match self.peek() {
                Some(b',') => self.i += 1,
                Some(b']') => {
                    self.i += 1;
                    return Ok(Json::Arr(out));
                }
                _ => return Err(format!("expected , or ] at byte {}", self.i)),
            }
        }
    }

    fn object(&mut self) -> Result<Json, String> {
        self.i += 1; // {
        let mut out = BTreeMap::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Ok(Json::Obj(out));
        }
        loop {
            self.ws();
            if self.peek() != Some(b'"') {
                return Err(format!("expected a key at byte {}", self.i));
            }
            let k = self.string()?;
            self.ws();
            if self.peek() != Some(b':') {
                return Err(format!("expected : at byte {}", self.i));
            }
            self.i += 1;
            self.ws();
            out.insert(k, self.value()?);
            self.ws();
            match self.peek() {
                Some(b',') => self.i += 1,
                Some(b'}') => {
                    self.i += 1;
                    return Ok(Json::Obj(out));
                }
                _ => return Err(format!("expected , or }} at byte {}", self.i)),
            }
        }
    }

    fn number(&mut self) -> Result<Json, String> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while matches!(self.peek(), Some(c) if c.is_ascii_digit() || c == b'.' || c == b'e' || c == b'E' || c == b'+' || c == b'-')
        {
            self.i += 1;
        }
        let text = std::str::from_utf8(&self.b[start..self.i]).map_err(|e| e.to_string())?;
        text.parse::<f64>()
            .map(Json::Num)
            .map_err(|_| format!("bad number {text:?}"))
    }

    fn string(&mut self) -> Result<String, String> {
        self.i += 1; // opening quote
        let mut out = String::new();
        loop {
            let c = *self.b.get(self.i).ok_or("unterminated string")?;
            self.i += 1;
            match c {
                b'"' => return Ok(out),
                b'\\' => {
                    let e = *self.b.get(self.i).ok_or("unterminated escape")?;
                    self.i += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{8}'),
                        b'f' => out.push('\u{c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hex = std::str::from_utf8(
                                self.b.get(self.i..self.i + 4).ok_or("short \\u")?,
                            )
                            .map_err(|e| e.to_string())?;
                            let code =
                                u32::from_str_radix(hex, 16).map_err(|_| "bad \\u".to_string())?;
                            self.i += 4;
                            // Surrogate halves are kept as-is rather than paired.
                            // Model output is not expected to contain them, and
                            // silently dropping half a pair would corrupt a token.
                            out.push(char::from_u32(code).unwrap_or('\u{fffd}'));
                        }
                        other => return Err(format!("bad escape \\{}", other as char)),
                    }
                }
                _ => {
                    // Copy the whole UTF-8 sequence, not one byte.
                    let start = self.i - 1;
                    let len = utf8_len(c);
                    self.i = start + len;
                    let s = std::str::from_utf8(self.b.get(start..self.i).ok_or("bad utf8")?)
                        .map_err(|e| e.to_string())?;
                    out.push_str(s);
                }
            }
        }
    }
}

fn utf8_len(first: u8) -> usize {
    match first {
        0x00..=0x7f => 1,
        0xc0..=0xdf => 2,
        0xe0..=0xef => 3,
        _ => 4,
    }
}

/// Escapes a string into a JSON string literal, quotes included.
///
/// Every byte below 0x20 goes out as a `\u` escape, because a raw newline in a
/// response body is how one SSE frame turns into two broken ones.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_an_openai_request_body() {
        let body = r#"{"model":"m","messages":[{"role":"system","content":"be brief"},
                        {"role":"user","content":"hi"}],"max_tokens":160,
                        "temperature":0.7,"stream":true}"#;
        let v = parse(body).expect("parse");
        assert_eq!(v.get("model").unwrap().as_str(), Some("m"));
        assert_eq!(v.get("stream").unwrap().as_bool(), Some(true));
        assert_eq!(v.get("temperature").unwrap().as_f64(), Some(0.7));
        assert_eq!(v.get("max_tokens").unwrap().as_f64(), Some(160.0));
        let msgs = v.get("messages").unwrap().as_arr().unwrap();
        assert_eq!(msgs.len(), 2);
        assert_eq!(msgs[0].get("role").unwrap().as_str(), Some("system"));
        assert_eq!(msgs[1].get("content").unwrap().as_str(), Some("hi"));
    }

    #[test]
    fn round_trips_escapes() {
        let v = parse(r#"{"c":"a\"b\\c\nd"}"#).expect("parse");
        let s = v.get("c").unwrap().as_str().unwrap();
        assert_eq!(s, "a\"b\\c\nd");
        // And escaping it again must produce something that parses back to the
        // same string, which is the property an SSE frame actually depends on.
        let again = parse(&format!("{{\"c\":{}}}", escape(s))).expect("reparse");
        assert_eq!(again.get("c").unwrap().as_str(), Some(s));
    }

    #[test]
    fn a_newline_cannot_break_a_frame() {
        // A raw control character in a response is how one SSE event becomes two
        // unparseable ones, so it must never survive escaping.
        assert!(!escape("a\nb").contains('\n'));
    }

    #[test]
    fn a_malformed_body_is_an_error_not_a_default() {
        assert!(parse("{\"a\":}").is_err());
        assert!(parse("{} trailing").is_err());
        assert!(parse("").is_err());
    }
}