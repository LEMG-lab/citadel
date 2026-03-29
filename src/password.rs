use crate::types::{CharsetFlags, VaultResult};
use rand::Rng;
use zeroize::Zeroizing;

const LOWER: &[u8] = b"abcdefghijklmnopqrstuvwxyz";
const UPPER: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS: &[u8] = b"0123456789";
const SYMBOLS: &[u8] = b"!@#$%^&*()-_=+[]{}<>?/|~`;:',.\"\\ ";

/// Build the character pool from charset bitmask flags.
fn build_charset(flags: u32) -> Vec<u8> {
    let mut charset = Vec::new();
    if flags & CharsetFlags::LOWERCASE != 0 {
        charset.extend_from_slice(LOWER);
    }
    if flags & CharsetFlags::UPPERCASE != 0 {
        charset.extend_from_slice(UPPER);
    }
    if flags & CharsetFlags::DIGITS != 0 {
        charset.extend_from_slice(DIGITS);
    }
    if flags & CharsetFlags::SYMBOLS != 0 {
        charset.extend_from_slice(SYMBOLS);
    }
    charset
}

/// Generate a random password of the given length using the specified charset flags.
///
/// At least one character from each requested character class is guaranteed to
/// appear in the result.  The length must be >= the number of requested classes.
/// Returns the password bytes (caller must zeroize when done).
pub fn generate(length: usize, charset_flags: u32) -> Result<Zeroizing<Vec<u8>>, VaultResult> {
    if length == 0 {
        return Err(VaultResult::InternalError);
    }

    // Collect the individual character classes that were requested.
    let mut classes: Vec<&[u8]> = Vec::new();
    if charset_flags & CharsetFlags::LOWERCASE != 0 {
        classes.push(LOWER);
    }
    if charset_flags & CharsetFlags::UPPERCASE != 0 {
        classes.push(UPPER);
    }
    if charset_flags & CharsetFlags::DIGITS != 0 {
        classes.push(DIGITS);
    }
    if charset_flags & CharsetFlags::SYMBOLS != 0 {
        classes.push(SYMBOLS);
    }
    if classes.is_empty() || length < classes.len() {
        return Err(VaultResult::InternalError);
    }

    let pool = build_charset(charset_flags);
    let mut rng = rand::rng();
    let mut buf = Zeroizing::new(Vec::with_capacity(length));

    // Reserve one position per requested class to guarantee inclusion.
    for class in &classes {
        let idx = rng.random_range(0..class.len());
        buf.push(class[idx]);
    }

    // Fill remaining positions from the combined pool.
    for _ in classes.len()..length {
        let idx = rng.random_range(0..pool.len());
        buf.push(pool[idx]);
    }

    // Fisher-Yates shuffle so the guaranteed chars aren't always at the front.
    for i in (1..buf.len()).rev() {
        let j = rng.random_range(0..=i);
        buf.swap(i, j);
    }

    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_correct_length() {
        let pw = generate(32, CharsetFlags::LOWERCASE | CharsetFlags::DIGITS).unwrap();
        assert_eq!(pw.len(), 32);
    }

    #[test]
    fn lowercase_only() {
        let pw = generate(100, CharsetFlags::LOWERCASE).unwrap();
        for &b in pw.iter() {
            assert!(b.is_ascii_lowercase(), "unexpected byte: {}", b);
        }
    }

    #[test]
    fn digits_only() {
        let pw = generate(100, CharsetFlags::DIGITS).unwrap();
        for &b in pw.iter() {
            assert!(b.is_ascii_digit(), "unexpected byte: {}", b);
        }
    }

    #[test]
    fn all_charsets_guaranteed() {
        let flags =
            CharsetFlags::LOWERCASE | CharsetFlags::UPPERCASE | CharsetFlags::DIGITS | CharsetFlags::SYMBOLS;
        // Even at minimum length (4 classes → 4 chars), every class must appear.
        for _ in 0..50 {
            let pw = generate(4, flags).unwrap();
            assert_eq!(pw.len(), 4);
            assert!(pw.iter().any(|b| b.is_ascii_lowercase()), "missing lowercase");
            assert!(pw.iter().any(|b| b.is_ascii_uppercase()), "missing uppercase");
            assert!(pw.iter().any(|b| b.is_ascii_digit()), "missing digit");
            let has_symbol = pw.iter().any(|b| !b.is_ascii_alphanumeric());
            assert!(has_symbol, "missing symbol");
        }
    }

    #[test]
    fn length_too_short_for_classes() {
        let flags =
            CharsetFlags::LOWERCASE | CharsetFlags::UPPERCASE | CharsetFlags::DIGITS | CharsetFlags::SYMBOLS;
        // 4 classes but only 3 chars — must fail
        assert_eq!(generate(3, flags).unwrap_err(), VaultResult::InternalError);
    }

    #[test]
    fn empty_charset_fails() {
        assert_eq!(generate(10, 0).unwrap_err(), VaultResult::InternalError);
    }

    #[test]
    fn zero_length_fails() {
        assert_eq!(
            generate(0, CharsetFlags::LOWERCASE).unwrap_err(),
            VaultResult::InternalError
        );
    }
}
