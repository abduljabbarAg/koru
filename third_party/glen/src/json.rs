// json.rs - tiny zero-dependency JSON parser and escaper for serve mode.
#[derive(Debug, Clone)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
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
}

pub fn parse(s: &str) -> Result<Json, String> {
    let b = s.as_bytes();
    let mut i = 0usize;
    let v = val(b, &mut i)?;
    skip_ws(b, &mut i);
    if i != b.len() {
        return Err(format!("trailing input at {}", i));
    }
    Ok(v)
}

fn skip_ws(b: &[u8], i: &mut usize) {
    while *i < b.len() && matches!(b[*i], b' ' | b'\t' | b'\n' | b'\r') {
        *i += 1;
    }
}

fn val(b: &[u8], i: &mut usize) -> Result<Json, String> {
    skip_ws(b, i);
    let c = *b.get(*i).ok_or("unexpected eof")?;
    match c {
        b'{' => obj(b, i),
        b'[' => arr(b, i),
        b'"' => Ok(Json::Str(string(b, i)?)),
        b't' => lit(b, i, "true", Json::Bool(true)),
        b'f' => lit(b, i, "false", Json::Bool(false)),
        b'n' => lit(b, i, "null", Json::Null),
        b'-' | b'0'..=b'9' => num(b, i),
        _ => Err(format!("unexpected byte {}", c)),
    }
}

fn lit(b: &[u8], i: &mut usize, s: &str, v: Json) -> Result<Json, String> {
    if b.len() >= *i + s.len() && &b[*i..*i + s.len()] == s.as_bytes() {
        *i += s.len();
        Ok(v)
    } else {
        Err("bad literal".to_string())
    }
}

fn obj(b: &[u8], i: &mut usize) -> Result<Json, String> {
    *i += 1;
    let mut out = Vec::new();
    skip_ws(b, i);
    if b.get(*i) == Some(&b'}') {
        *i += 1;
        return Ok(Json::Obj(out));
    }
    loop {
        skip_ws(b, i);
        let k = string(b, i)?;
        skip_ws(b, i);
        if b.get(*i) != Some(&b':') {
            return Err("expected :".to_string());
        }
        *i += 1;
        let v = val(b, i)?;
        out.push((k, v));
        skip_ws(b, i);
        match b.get(*i) {
            Some(&b',') => *i += 1,
            Some(&b'}') => {
                *i += 1;
                break;
            }
            _ => return Err("expected , or }".to_string()),
        }
    }
    Ok(Json::Obj(out))
}

fn arr(b: &[u8], i: &mut usize) -> Result<Json, String> {
    *i += 1;
    let mut out = Vec::new();
    skip_ws(b, i);
    if b.get(*i) == Some(&b']') {
        *i += 1;
        return Ok(Json::Arr(out));
    }
    loop {
        out.push(val(b, i)?);
        skip_ws(b, i);
        match b.get(*i) {
            Some(&b',') => *i += 1,
            Some(&b']') => {
                *i += 1;
                break;
            }
            _ => return Err("expected , or ]".to_string()),
        }
    }
    Ok(Json::Arr(out))
}

fn num(b: &[u8], i: &mut usize) -> Result<Json, String> {
    let start = *i;
    if b.get(*i) == Some(&b'-') {
        *i += 1;
    }
    while *i < b.len() && matches!(b[*i], b'0'..=b'9' | b'.' | b'e' | b'E' | b'+' | b'-') {
        *i += 1;
    }
    let s = std::str::from_utf8(&b[start..*i]).map_err(|_| "bad num".to_string())?;
    s.parse::<f64>().map(Json::Num).map_err(|_| format!("bad number {}", s))
}

fn hex4(b: &[u8], i: &mut usize) -> Result<u32, String> {
    if *i + 4 > b.len() {
        return Err("bad \\u".to_string());
    }
    let s = std::str::from_utf8(&b[*i..*i + 4]).map_err(|_| "bad \\u".to_string())?;
    *i += 4;
    u32::from_str_radix(s, 16).map_err(|_| "bad \\u".to_string())
}

fn string(b: &[u8], i: &mut usize) -> Result<String, String> {
    if b.get(*i) != Some(&b'"') {
        return Err("expected string".to_string());
    }
    *i += 1;
    let mut out = String::new();
    while *i < b.len() {
        let c = b[*i];
        *i += 1;
        match c {
            b'"' => return Ok(out),
            b'\\' => {
                let e = *b.get(*i).ok_or("eof escape")?;
                *i += 1;
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
                        let cp = hex4(b, i)?;
                        if (0xD800..0xDC00).contains(&cp) {
                            if b.get(*i) == Some(&b'\\') && b.get(*i + 1) == Some(&b'u') {
                                *i += 2;
                                let lo = hex4(b, i)?;
                                let c2 = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                out.push(char::from_u32(c2).unwrap_or('\u{fffd}'));
                            } else {
                                out.push('\u{fffd}');
                            }
                        } else {
                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                        }
                    }
                    other => return Err(format!("bad escape {}", other as char)),
                }
            }
            _ => {
                let start = *i - 1;
                let mut end = *i;
                while end < b.len() && b[end] != b'"' && b[end] != b'\\' {
                    end += 1;
                }
                out.push_str(std::str::from_utf8(&b[start..end]).map_err(|_| "bad utf8".to_string())?);
                *i = end;
            }
        }
    }
    Err("unterminated string".to_string())
}

pub fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o
}
