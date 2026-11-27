//! Tag values read out of a file name with a mask such as '%6 - %1 - %2' (port of
//! filenametags.pas). '\' in the mask also matches folder names: '%1\%3\%6 - %2' uses the last
//! two folders. %d skips a part. Matching tries shortest values first, except numeric fields
//! (track, disc, year, BPM), which take as many digits as they can.

use crate::model::TagField;
use crate::rename::{apply_case, extract_file_dir, extract_file_ext, extract_file_name, from16, lower16, utf16, CaseMode};
use crate::text::pascal_trim;
use std::collections::BTreeMap;

// from: TFileNameMatch
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct FileNameMatch {
    pub ok: bool,
    pub values: BTreeMap<TagField, String>,
    /// the fields the mask fills, in TTagField order
    pub used: Vec<TagField>,
}

#[derive(Debug, Clone, PartialEq)]
enum Token {
    /// lower case
    Literal(Vec<u16>),
    Field(TagField),
    Skip,
}

// from: Tokenize
fn tokenize(mask: &str) -> Vec<Token> {
    let u = utf16(&mask.replace('/', "\\"));
    let mut out = Vec::new();
    let mut lit: Vec<u16> = Vec::new();
    let flush = |lit: &mut Vec<u16>, out: &mut Vec<Token>| {
        if !lit.is_empty() {
            out.push(Token::Literal(lower16(lit)));
            lit.clear();
        }
    };
    let pct = b'%' as u16;
    let mut i = 0;
    while i < u.len() {
        if u[i] != pct || i == u.len() - 1 {
            lit.push(u[i]);
            i += 1;
            continue;
        }
        let two = from16(&lower16(&u[i + 1..(i + 3).min(u.len())]));
        let tok = match two.as_str() {
            "aa" => Some(Token::Field(TagField::AlbumArtist)),
            "cp" => Some(Token::Field(TagField::Composer)),
            "co" => Some(Token::Field(TagField::Conductor)),
            "lb" => Some(Token::Field(TagField::Publisher)),
            _ => None,
        };
        let tok = match tok {
            Some(t) => {
                i += 3;
                t
            }
            None => {
                let code = u[i + 1];
                i += 2;
                match char::from_u32(code as u32).unwrap_or('\0') {
                    '1' => Token::Field(TagField::Artist),
                    '2' => Token::Field(TagField::Title),
                    '3' => Token::Field(TagField::Album),
                    '4' => Token::Field(TagField::Year),
                    '5' => Token::Field(TagField::Genre),
                    '6' => Token::Field(TagField::Track),
                    '#' => Token::Field(TagField::Disc),
                    '9' => Token::Field(TagField::Comment),
                    'b' | 'B' => Token::Field(TagField::Bpm),
                    'd' | 'D' => Token::Skip,
                    _ => {
                        lit.push(pct); // unknown: literal
                        lit.push(code);
                        continue;
                    }
                }
            }
        };
        flush(&mut lit, &mut out);
        out.push(tok);
    }
    flush(&mut lit, &mut out);
    out
}

// from: MaskFields — which fields a mask fills (the preview's columns)
pub fn mask_fields(mask: &str) -> Vec<TagField> {
    let found: Vec<TagField> = tokenize(mask).into_iter().filter_map(|t| if let Token::Field(f) = t { Some(f) } else { None }).collect();
    TagField::ALL.into_iter().filter(|f| found.contains(f)).collect()
}

// from: IsNumericField
fn is_numeric(f: TagField) -> bool {
    matches!(f, TagField::Track | TagField::Disc | TagField::Year | TagField::Bpm)
}

// from: ValidNumeric
fn valid_numeric(v: &str, f: TagField) -> bool {
    !v.is_empty() && v.chars().all(|c| c.is_ascii_digit() || c == '/' || (f == TagField::Year && c == '-'))
}

fn trimmed16(v: &[u16]) -> String {
    pascal_trim(&from16(v)).to_string()
}

/// A value the token accepts (a field needs text, a numeric field digits).
fn accepts(t: &Token, v: &[u16]) -> bool {
    match t {
        Token::Skip => true,
        Token::Field(f) => {
            let s = trimmed16(v);
            !s.is_empty() && (!is_numeric(*f) || valid_numeric(&s, *f))
        }
        Token::Literal(_) => false,
    }
}

// from: MatchFrom — backtracking over the subject (and its lower-case copy for literals)
fn match_from(tokens: &[Token], ti: usize, subject: &[u16], lower: &[u16], si: usize, values: &mut [Vec<u16>]) -> bool {
    if ti == tokens.len() {
        return si == subject.len();
    }
    let t = &tokens[ti];
    if let Token::Literal(text) = t {
        let end = si + text.len();
        return end <= subject.len() && lower[si..end] == text[..] && match_from(tokens, ti + 1, subject, lower, end, values);
    }
    let max = subject.len() - si;
    if ti == tokens.len() - 1 {
        // the last token takes the rest
        let v = &subject[si..];
        if matches!(t, Token::Field(_)) && !accepts(t, v) {
            return false;
        }
        values[ti] = v.to_vec();
        return true;
    }
    // numeric fields are greedy, the others lazy (a skip may be empty)
    let lens: Vec<usize> = match t {
        Token::Field(f) if is_numeric(*f) => (0..=max).rev().collect(),
        Token::Skip => (0..=max).collect(),
        _ => (1..=max).collect(),
    };
    for len in lens {
        let v = &subject[si..si + len];
        if accepts(t, v) && match_from(tokens, ti + 1, subject, lower, si + len, values) {
            values[ti] = v.to_vec();
            return true;
        }
    }
    false
}

// from: MatchFileName (phone names come with phase 9)
pub fn match_file_name(mask: &str, path: &str, underscores_to_spaces: bool, case_mode: CaseMode) -> FileNameMatch {
    let mut r = FileNameMatch { values: TagField::ALL.iter().map(|&f| (f, String::new())).collect(), ..Default::default() };
    let tokens = tokenize(mask);
    if tokens.is_empty() {
        return r;
    }
    // the subject is as many trailing path parts as the mask has '\'-separated levels
    let bs = b'\\' as u16;
    let levels = 1 + tokens.iter().map(|t| if let Token::Literal(x) = t { x.iter().filter(|&&c| c == bs).count() } else { 0 }).sum::<usize>();
    let name = extract_file_name(path);
    let mut subject = utf16(&name[..name.len() - extract_file_ext(path).len()]);
    let mut dir = extract_file_dir(path);
    for _ in 2..=levels {
        let part = extract_file_name(&dir).to_string();
        if part.is_empty() {
            return r; // not enough folders
        }
        let mut s = utf16(&part);
        s.push(bs);
        s.extend(subject);
        subject = s;
        dir = extract_file_dir(&dir);
    }
    let mut values = vec![Vec::new(); tokens.len()];
    if !match_from(&tokens, 0, &subject, &lower16(&subject), 0, &mut values) {
        return r;
    }
    for (t, v) in tokens.iter().zip(&values) {
        if let Token::Field(f) = t {
            let mut s = from16(v);
            if underscores_to_spaces {
                s = s.replace('_', " ");
            }
            s = pascal_trim(&s.replace("  ", " ")).to_string();
            if !is_numeric(*f) {
                s = apply_case(&s, case_mode);
            }
            r.values.insert(*f, s);
            if !r.used.contains(f) {
                r.used.push(*f);
            }
        }
    }
    r.used.sort_by_key(|f| TagField::ALL.iter().position(|x| x == f));
    r.ok = !r.used.is_empty();
    r
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TagField as F;
    use crate::rename::CaseMode;

    // from: renametest.lpr TestMatch (the phone case comes with phase 9)
    #[test]
    fn matches_like_1_2() {
        let m = match_file_name("%6 - %1 - %2", "C:\\x\\01 - Kim Larsen - Om lidt bli'r her stille.mp3", false, CaseMode::None);
        assert!(m.ok);
        assert_eq!((m.values[&F::Track].as_str(), m.values[&F::Artist].as_str()), ("01", "Kim Larsen"));
        assert_eq!(m.values[&F::Title], "Om lidt bli'r her stille");

        let m = match_file_name("%1 - %2", "C:\\x\\A - B - C.flac", false, CaseMode::None);
        assert_eq!((m.values[&F::Artist].as_str(), m.values[&F::Title].as_str()), ("A", "B - C"));

        let m = match_file_name("%6%2", "C:\\x\\12Titel med tal 7.mp3", false, CaseMode::None);
        assert_eq!((m.values[&F::Track].as_str(), m.values[&F::Title].as_str()), ("12", "Titel med tal 7"));

        let m = match_file_name("%1\\%4 - %3\\%6. %2", "D:\\Musik\\Gasolin'\\1975 - Gas 5\\03. Kvinde_min.mp3", true, CaseMode::None);
        assert!(m.ok);
        assert_eq!((m.values[&F::Artist].as_str(), m.values[&F::Year].as_str()), ("Gasolin'", "1975"));
        assert_eq!((m.values[&F::Album].as_str(), m.values[&F::Title].as_str()), ("Gas 5", "Kvinde min"));

        let m = match_file_name("%d - %2", "C:\\x\\Noget - Titel.mp3", false, CaseMode::Title);
        assert_eq!(m.values[&F::Title], "Titel");
        assert!(!m.used.contains(&F::Artist));

        assert!(!match_file_name("%6 - %2", "C:\\x\\Ingen bindestreg.mp3", false, CaseMode::None).ok);
        assert!(!match_file_name("%6 - %2", "C:\\x\\AB - Titel.mp3", false, CaseMode::None).ok);

        let m = match_file_name("%1 - %2", "C:\\x\\ÆBLE - grød.mp3", false, CaseMode::Title);
        assert_eq!(m.values[&F::Artist], "Æble");
    }

    #[test]
    fn mask_fields_in_order() {
        assert_eq!(mask_fields("%6 - %aa - %2%d%x"), vec![F::Title, F::Track, F::AlbumArtist]);
    }
}
