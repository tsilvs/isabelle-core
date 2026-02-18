/*
 * Isabelle project
 *
 * Copyright 2023-2024 Maxim Menshikov
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the “Software”),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use rand::Rng;

/// Returns true when `pw_hash` is a well-formed PHC string (i.e. already
/// hashed). Used by the database merger to detect plain-text seed passwords.
pub fn is_hashed_password(pw_hash: &str) -> bool {
    PasswordHash::new(pw_hash).is_ok()
}

/// Verify password: the real password, the hash.
/// Returns false (never panics) when the stored hash is not a valid PHC
/// string — e.g. a plain-text or differently-encoded password imported
/// from seed data.
pub fn verify_password(pw: &str, pw_hash: &str) -> bool {
	//TODO: Critical security function, requires review and audit
    let parsed_hash = match PasswordHash::new(pw_hash) {
        Ok(h) => h,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(pw.as_bytes(), &parsed_hash)
        .is_ok()
}

/// Get new salt
pub fn get_new_salt() -> String {
    let salt = SaltString::generate(&mut OsRng);
    return salt.to_string();
}

/// Derive hash from given password and salt
pub fn get_password_hash(pw: &str, salt: &str) -> String {
    let argon2 = Argon2::default();

    let saltstr = match SaltString::from_b64(salt) {
        Ok(s) => s,
        Err(_) => return String::new(),
    };
    match argon2.hash_password(pw.as_bytes(), saltstr.as_salt()) {
        Ok(hash) => hash.serialize().as_str().to_string(),
        Err(_) => String::new(),
    }
}

/// Generate new OTP code
pub fn get_otp_code() -> String {
    let num = rand::thread_rng().gen_range(100000000..999999999);
    num.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn print_admin_hash() {
        let salt = get_new_salt();
        let hash = get_password_hash("admin", &salt);
        println!("\nadmin argon2id hash: {}", hash);
        assert!(!hash.is_empty());
        // Verify the round-trip works
        assert!(verify_password("admin", &hash));
    }
}
