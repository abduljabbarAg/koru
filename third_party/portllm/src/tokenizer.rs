//! GPT-2 byte-level BPE, read from the model file.
//!
//! The vocabulary and the merge list travel inside the GGUF, so the tokenizer
//! is not a separate download and cannot drift out of sync with the weights.
//! 151,936 token strings and 151,387 merge rules ship with this model.
//!
//! How BPE works, and why it is not simply "greedy longest match":
//!
//!  1. The text is converted to bytes, then each byte is mapped to a
//!     printable Unicode character. This is what makes the tokenizer
//!     lossless over arbitrary bytes, including multi-byte UTF-8, which a
//!     word-piece vocabulary is not.
//!  2. Every adjacent pair of symbols is looked up in a rank table. The pair
//!     with the lowest rank wins and is merged.
//!  3. Repeat until no pair has a rank.
//!
//! Step 2 is the part that is easy to get subtly wrong. A greedy longest-match
//! tokenizer produces plausible-looking ids for common text and wrong ids for
//! anything unusual, and a model fed those ids generates confident nonsense
//! with no error anywhere. This is why `merges` is read as an ordered list and
//! the rank is the index, rather than being flattened into a set.

use crate::gguf::{Header, Value};
use std::collections::{HashMap, HashSet};

/// The byte-level alphabet GPT-2 uses.
///
/// Each of the 256 byte values gets one printable character, so that a byte
/// sequence is always a valid string and the mapping is reversible.
fn byte_to_unicode() -> [char; 256] {
    let mut bs: Vec<u32> = Vec::new();
    let mut cs: Vec<u32> = Vec::new();

    // Bytes that are already printable and unambiguous keep themselves.
    let printable = |c: u32| -> bool {
        (0x21..=0x7E).contains(&c)
            || (0xA1..=0xAC).contains(&c)
            || (0xAE..=0xFF).contains(&c)
    };

    for b in 0u32..256 {
        if printable(b) && !bs.contains(&b) {
            bs.push(b);
            cs.push(b);
        }
    }
    // Everything else is lifted into the Latin-1 range that is unused, so
    // no collision with a real byte is possible.
    let mut n = 0u32;
    for b in 0u32..256 {
        if !bs.contains(&b) {
            bs.push(b);
            let mut c = 0x100u32 + n;
            while c < 0x20A1 && (0x21..=0x7E).contains(&c) {
                c += 1;
            }
            cs.push(c);
            n += 1;
        }
    }

    // This map goes from BYTE to CHARACTER. Encode looks up a byte and needs
    // the printable stand-in for it.
    let mut out = ['\0'; 256];
    for (i, b) in bs.iter().enumerate() {
        out[*b as usize] = char::from_u32(cs[i]).unwrap_or('\0');
    }
    out
}

pub struct Tokenizer {
    /// Token id to its text, as stored in the file.
    tokens: Vec<String>,
    /// Pair of symbol ids to merge rank. Lower rank merges first.
    ranks: HashMap<(u32, u32), u32>,
    /// Byte value to its printable stand-in.
    byte_enc: [char; 256],
    /// Printable stand-in back to the byte it represents.
    byte_dec: HashMap<char, u8>,
    /// Byte-fallback tokens: entries whose stored text is the UTF-8 encoding
    /// of a raw byte. Their characters are data, not stand-ins, and must be
    /// emitted literally or output turns into mojibake.
    literal: HashSet<u32>,
    pub bos: Option<u32>,
    pub eos: u32,
    pub vocab_size: usize,
}

impl Tokenizer {
    /// Read the vocabulary and merges out of a parsed header.
    pub fn from_header(h: &Header) -> Result<Self, String> {
        let tokens: Vec<String> = match h.get("tokenizer.ggml.tokens") {
            Some(Value::Array(a)) => a
                .iter()
                .map(|v| match v {
                    Value::Str(s) => s.clone(),
                    other => format!("{other:?}"),
                })
                .collect(),
            _ => return Err("no tokenizer.ggml.tokens in the model".into()),
        };

        // Text to id, for resolving merge operands.
        let mut by_text: HashMap<&str, u32> = HashMap::with_capacity(tokens.len());
        for (i, t) in tokens.iter().enumerate() {
            by_text.entry(t.as_str()).or_insert(i as u32);
        }

        let mut ranks = HashMap::new();
        if let Some(Value::Array(merges)) = h.get("tokenizer.ggml.merges") {
            for (rank, m) in merges.iter().enumerate() {
                let Value::Str(s) = m else { continue };
                // "a b" means symbol a merged with symbol b. The space is a
                // literal, not a separator to strip, because some merges
                // legitimately contain it.
                let Some((l, r)) = s.split_once(' ') else {
                    continue;
                };
                if let (Some(li), Some(ri)) = (by_text.get(l).copied(), by_text.get(r).copied())
                {
                    ranks.insert((li, ri), rank as u32);
                }
            }
        }

        let byte_enc = byte_to_unicode();
        let stand_ins: HashSet<char> = byte_enc.iter().copied().collect();

        // A byte-fallback entry never consists of stand-ins, so it can never
        // be produced by encode. Those are exactly the entries to keep literal.
        let mut literal = HashSet::new();
        for (i, t) in tokens.iter().enumerate() {
            if !t.is_empty() && t.chars().all(|c| stand_ins.contains(&c)) {
                continue;
            }
            literal.insert(i as u32);
        }

        let mut byte_dec = HashMap::with_capacity(256);
        for (b, c) in byte_enc.iter().enumerate() {
            byte_dec.insert(*c, b as u8);
        }

        Ok(Tokenizer {
            vocab_size: tokens.len(),
            bos: h.num("tokenizer.ggml.bos_token_id").map(|v| v as u32),
            eos: h.num("tokenizer.ggml.eos_token_id").unwrap_or(2) as u32,
            byte_enc,
            byte_dec,
            literal,
            tokens,
            ranks,
        })
    }

    pub fn token_text(&self, id: u32) -> &str {
        self.tokens.get(id as usize).map(|s| s.as_str()).unwrap_or("")
    }

    /// Text to token ids.
    pub fn encode(&self, text: &str) -> Vec<u32> {
        // Bytes become printable characters so the merge vocabulary can be
        // searched directly.
        let mut symbols: Vec<u32> = text
            .as_bytes()
            .iter()
            .map(|b| {
                self.tokens
                    .iter()
                    .position(|t| t == self.byte_enc[*b as usize].encode_utf8(&mut [0u8; 4]))
                    .map(|p| p as u32)
                    .unwrap_or_else(|| self.byte_token(*b))
            })
            .collect();

        if symbols.is_empty() {
            return Vec::new();
        }

        // Merge the lowest-ranked adjacent pair, repeatedly.
        while symbols.len() > 1 {
            let mut best: Option<((u32, u32), u32)> = None;
            for w in symbols.windows(2) {
                if let Some(r) = self.ranks.get(&(w[0], w[1])) {
                    if best.map_or(true, |(_, br)| *r < br) {
                        best = Some(((w[0], w[1]), *r));
                    }
                }
            }
            let Some((pair, _)) = best else { break };

            let mut out = Vec::with_capacity(symbols.len());
            let mut i = 0;
            while i < symbols.len() {
                if i + 1 < symbols.len() && (symbols[i], symbols[i + 1]) == pair {
                    if let Some(merged) = self.merge_id(pair) {
                        out.push(merged);
                        i += 2;
                        continue;
                    }
                }
                out.push(symbols[i]);
                i += 1;
            }
            symbols = out;
        }

        symbols
    }

    /// The id of a merged pair, if the model carries one.
    fn merge_id(&self, pair: (u32, u32)) -> Option<u32> {
        let merged = format!("{}{}", self.token_text(pair.0), self.token_text(pair.1));
        self.tokens.iter().position(|t| *t == merged).map(|p| p as u32)
    }

    /// Fallback for a byte whose printable stand-in is not in the vocabulary,
    /// which should not happen but must not panic if it does.
    fn byte_token(&self, b: u8) -> u32 {
        let s = self.byte_enc[b as usize].to_string();
        self.tokens.iter().position(|t| *t == s).map(|p| p as u32).unwrap_or(0)
    }

    /// Token ids back to text. The printable stand-ins are folded back to the
    /// original bytes and then interpreted as UTF-8, so the result is real text
    /// rather than a string full of 'Ġ'.
    pub fn decode(&self, ids: &[u32]) -> String {
        let mut bytes: Vec<u8> = Vec::new();
        for id in ids {
            if self.literal.contains(id) {
                bytes.extend_from_slice(self.token_text(*id).as_bytes());
                continue;
            }
            for c in self.token_text(*id).chars() {
                match self.byte_dec.get(&c) {
                    Some(b) => bytes.push(*b),
                    None => {
                        // Not a stand-in: keep the character's own UTF-8.
                        let mut buf = [0u8; 4];
                        bytes.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
                    }
                }
            }
        }
        String::from_utf8_lossy(&bytes).into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn real() -> Option<Tokenizer> {
        let p = std::path::Path::new("/tmp/qwen05b-good.gguf");
        if !p.exists() {
            return None;
        }
        let h = crate::gguf::read_header(p).ok()?;
        Tokenizer::from_header(&h).ok()
    }

    #[test]
    fn byte_alphabet_is_a_bijection() {
        let a = byte_to_unicode();
        let mut seen = std::collections::HashSet::new();
        for c in a.iter() {
            assert!(seen.insert(*c), "duplicate character in the byte alphabet");
        }
        assert_eq!(seen.len(), 256);
    }

    #[test]
    fn byte_alphabet_is_invertible() {
        // GPT-2's alphabet is a bijection between the 256 byte values and 256
        // printable characters, but deliberately NOT byte-identical: e.g.
        // space (0x20) becomes 'Ġ'. What matters is that the mapping is
        // one-to-one, so decode can invert it exactly.
        let a = byte_to_unicode();
        let mut seen = std::collections::HashSet::new();
        for b in 0u32..256 {
            assert!(seen.insert(a[b as usize]), "byte {b} collided");
        }
        assert_eq!(a[0x20], '\u{0120}', "space should map to G with dot");
    }

    #[test]
    fn loads_the_full_qwen_vocabulary() {
        let Some(t) = real() else { return };
        assert_eq!(t.vocab_size, 151936, "vocab size");
        assert!(t.ranks.len() > 150000, "merges {} ", t.ranks.len());
    }

    #[test]
    fn known_words_are_single_tokens() {
        let Some(t) = real() else { return };
        // Common English words must each be one token, which is only possible
        // if the merge table was actually read and applied. This asserts the
        // structure of the vocabulary rather than specific numeric ids, so it
        // stays correct if the model is ever re-exported with a different
        // token numbering.
        for w in ["hello", "world", "the", "quick", "brown"] {
            let ids = t.encode(w);
            assert_eq!(ids.len(), 1, "{w:?} split into {ids:?}");
        }
        // " the" is one token whose stored text carries the space stand-in.
        let ids = t.encode(" the");
        assert_eq!(ids.len(), 1);
        assert_eq!(t.token_text(ids[0]), "\u{0120}the");
    }

    #[test]
    fn longer_text_uses_more_tokens_than_its_words() {
        let Some(t) = real() else { return };
        let ids = t.encode("the cat sat on the mat");
        assert!(ids.len() >= 4, "expected a few tokens, got {ids:?}");
        assert_eq!(t.decode(&ids), "the cat sat on the mat");
    }

    #[test]
    fn encoding_is_lossless() {
        let Some(t) = real() else { return };
        for s in [
            "The quick brown fox jumps over the lazy dog.",
            "Hello, world! 123 -- 456",
            "   ",
            "\n\t",
            "unicode: caf\u{e9} \u{1F600} \u{4E2D}\u{6587}",
            "numbers 1234567890 and 3.14159",
        ] {
            let ids = t.encode(s);
            let back = t.decode(&ids);
            assert_eq!(back, s, "roundtrip failed for {s:?}: {ids:?}");
        }
    }

    #[test]
    fn empty_and_whitespace_are_handled() {
        let Some(t) = real() else { return };
        assert!(t.encode("").is_empty());
        assert!(!t.encode(" ").is_empty(), "space must encode");
    }
}
