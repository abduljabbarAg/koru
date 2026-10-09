// tok.rs - GPT2-style byte-level BPE from GGUF tokenizer arrays.
use crate::gguf::{Gguf, Kv};
use std::collections::HashMap;

pub struct Bpe {
    tok_bytes: Vec<Vec<u8>>, // id -> raw bytes
    str_to_id: HashMap<String, u32>,
    rank: HashMap<(u32, u32), u32>,
    piece: HashMap<Vec<u8>, u32>, // raw bytes -> id (all tokens)
    pub bos: u32,
    pub eos: u32,
    specials: Vec<(String, u32)>,
}

fn byte_encoder() -> Vec<u8> {
    // byte -> mapped char (as UTF-8 bytes). GPT2 mapping.
    let mut bs: Vec<u8> = (33u8..=126).chain(161u8..=172).chain(174u8..=255).collect();
    let mut cs: Vec<u32> = bs.iter().map(|&b| b as u32).collect();
    let mut n = 0u32;
    for b in 0..256u16 {
        if !bs.contains(&(b as u8)) {
            bs.push(b as u8);
            cs.push(256 + n);
            n += 1;
        }
    }
    // return table enc[byte] = char's UTF-8 bytes
    let mut table: Vec<Vec<u8>> = vec![vec![]; 256];
    for (b, c) in bs.iter().zip(cs.iter()) {
        let ch = char::from_u32(*c).unwrap();
        let mut buf = [0u8; 4];
        let s = ch.encode_utf8(&mut buf);
        table[*b as usize] = s.as_bytes().to_vec();
    }
    table.into_iter().flatten().collect::<Vec<u8>>() // placeholder, replaced below
}

pub fn build(g: &Gguf) -> Bpe {
    let toks = match g.kv.get("tokenizer.ggml.tokens") {
        Some(Kv::ArrStr(v)) => v.clone(),
        _ => panic!("no tokens"),
    };
    let merges = match g.kv.get("tokenizer.ggml.merges") {
        Some(Kv::ArrStr(v)) => v.clone(),
        _ => vec![],
    };
    // byte decoder: char -> byte
    let mut b2u_bs: Vec<u8> = (33u8..=126).chain(161u8..=172).chain(174u8..=255).collect();
    let mut b2u_cs: Vec<u32> = b2u_bs.iter().map(|&b| b as u32).collect();
    let mut n = 0u32;
    for b in 0..256u16 {
        if !b2u_bs.contains(&(b as u8)) {
            b2u_bs.push(b as u8);
            b2u_cs.push(256 + n);
            n += 1;
        }
    }
    let mut decode_map: HashMap<char, u8> = HashMap::new();
    let mut encode_map: Vec<Vec<u8>> = vec![vec![]; 256];
    for (b, c) in b2u_bs.iter().zip(b2u_cs.iter()) {
        let ch = char::from_u32(*c).unwrap();
        decode_map.insert(ch, *b);
        let mut buf = [0u8; 4];
        encode_map[*b as usize] = ch.encode_utf8(&mut buf).as_bytes().to_vec();
    }
    // token string -> bytes
    let mut tok_bytes: Vec<Vec<u8>> = Vec::with_capacity(toks.len());
    for s in toks.iter() {
        let mut v = vec![];
        for ch in s.chars() {
            if let Some(b) = decode_map.get(&ch) {
                v.push(*b);
            } else {
                let mut buf = [0u8; 4];
                v.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            }
        }
        tok_bytes.push(v);
    }
    let mut str_to_id = HashMap::new();
    for (i, s) in toks.iter().enumerate() {
        str_to_id.insert(s.clone(), i as u32);
    }
    // merges "a b" -> rank; map pieces to ids via str_to_id on the UNICODE strings
    let mut rank = HashMap::new();
    for (i, m) in merges.iter().enumerate() {
        if let Some(sp) = m.find(' ') {
            let a = &m[..sp];
            let b = &m[sp + 1..];
            if let (Some(&ia), Some(&ib)) = (str_to_id.get(a), str_to_id.get(b)) {
                rank.insert((ia, ib), i as u32);
            }
        }
    }
    let bos = g.u32("tokenizer.ggml.bos_token_id", 151643);
    let eos = g.u32("tokenizer.ggml.eos_token_id", 151645);
    let mut specials = vec![];
    for s in ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "<|begin_of_text|>", "<|start_header_id|>", "<|end_header_id|>", "<|eot_id|>"] {
        if let Some(&id) = str_to_id.get(s) {
            specials.push((s.to_string(), id));
        }
    }
    let _ = byte_encoder;
    let _ = encode_map;
    let mut piece = HashMap::new();
    for (id, tb) in tok_bytes.iter().enumerate() {
        piece.insert(tb.clone(), id as u32);
    }
    Bpe { tok_bytes, str_to_id, rank, piece, bos, eos, specials }
}

fn bpe_word(mut ids: Vec<u32>, rank: &HashMap<(u32, u32), u32>, str_to_id: &HashMap<String, u32>, tok_bytes: &[Vec<u8>]) -> Vec<u32> {
    // byte ids -> merge loop. ids here are byte-level token ids (single bytes must exist in vocab).
    // GPT2 quirk: single bytes may not all be tokens; fall back: keep bytes, map at end via byte-pair pieces.
    // Simpler robust path: work with Vec<Vec<u8>> pieces.
    let _ = (str_to_id, tok_bytes);
    loop {
        if ids.len() < 2 {
            break;
        }
        let mut best: Option<(usize, u32)> = None;
        for i in 0..ids.len() - 1 {
            if let Some(r) = rank.get(&(ids[i], ids[i + 1])) {
                if best.map_or(true, |(_, br)| *r < br) {
                    best = Some((i, *r));
                }
            }
        }
        let (bi, _) = match best {
            Some(v) => v,
            None => break,
        };
        // merged id: must be a vocab token whose bytes == concat. Find via piece concat is expensive;
        // instead track pieces alongside. (Handled by caller using pieces version below.)
        let _ = bi;
        break; // placeholder - real loop is in encode() with pieces
    }
    ids
}

pub fn encode(bpe: &Bpe, text: &str) -> Vec<u32> {
    // split specials first
    let mut out = vec![];
    let mut rest = text;
    loop {
        // find earliest special
        let mut hit: Option<(usize, usize, u32)> = None; // (pos, len, id)
        for (s, id) in bpe.specials.iter() {
            if let Some(p) = rest.find(s) {
                if hit.map_or(true, |(hp, _, _)| p < hp) {
                    hit = Some((p, s.len(), *id));
                }
            }
        }
        match hit {
            Some((p, l, id)) => {
                out.extend(encode_chunk(bpe, &rest[..p]));
                out.push(id);
                rest = &rest[p + l..];
            }
            None => {
                out.extend(encode_chunk(bpe, rest));
                break;
            }
        }
    }
    out
}

fn encode_chunk(bpe: &Bpe, s: &str) -> Vec<u32> {
    if s.is_empty() {
        return vec![];
    }
    let bytes = s.as_bytes();
    let mut pieces: Vec<Vec<u8>> = bytes.iter().map(|&b| vec![b]).collect();
    // every single byte must be a vocab token for BPE to start; GPT2 vocabs include all 256
    // (as mapped chars); if one is missing, fall back to byte 0 mapping error
    loop {
        if pieces.len() < 2 {
            break;
        }
        let mut best: Option<(usize, u32)> = None;
        for i in 0..pieces.len() - 1 {
            let a = match bpe.piece.get(&pieces[i]) {
                Some(&v) => v,
                None => continue,
            };
            let b = match bpe.piece.get(&pieces[i + 1]) {
                Some(&v) => v,
                None => continue,
            };
            let mut cat = pieces[i].clone();
            cat.extend_from_slice(&pieces[i + 1]);
            if !bpe.piece.contains_key(&cat) {
                continue;
            }
            if let Some(r) = bpe.rank.get(&(a, b)) {
                if best.map_or(true, |(_, br)| *r < br) {
                    best = Some((i, *r));
                }
            }
        }
        match best {
            Some((bi, _)) => {
                let nxt = pieces.remove(bi + 1);
                let mut cat = pieces[bi].clone();
                cat.extend_from_slice(&nxt);
                pieces[bi] = cat;
            }
            None => break,
        }
    }
    pieces.iter().map(|p| *bpe.piece.get(p).expect("bpe piece missing from vocab")).collect()
}

pub fn decode(bpe: &Bpe, ids: &[u32]) -> String {
    let mut bytes = vec![];
    for &id in ids {
        if let Some(tb) = bpe.tok_bytes.get(id as usize) {
            bytes.extend_from_slice(tb);
        }
    }
    String::from_utf8_lossy(&bytes).to_string()
}

#[allow(dead_code)]
pub fn unused_bpe_word_hook() {
    let _ = bpe_word;
}
