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
#![cfg(not(feature = "full_file_database"))]
use crate::state::store::*;
use crate::util::crypto::{get_new_salt, get_password_hash, is_hashed_password};
use log::info;

/// Merge collections from one store to another.
/// This is done only once, so no need to optimize too much.
///
/// Special handling for the `user` collection: any `password` field that is
/// not already a PHC-format argon2 hash (i.e. plain-text from seed data) is
/// hashed with argon2id before being written to the target store.
pub async fn merge_database(st1: &mut dyn Store, st2: &mut dyn Store) {
    let collections = st1.get_collections().await;
    for collection in &collections {
        info!("Merge collection: {}", &collection);
        let items = st1.get_all_items(collection, "id", "").await;
        for item in &items.map {
            info!("Setting {} item {}", &collection, &item.0);
            let mut itm = item.1.clone();
						// TODO: Outfactor into a utility function?
            if collection == "user" {
                let pw = itm.safe_str("password", "");
                if !pw.is_empty() && !is_hashed_password(&pw) {
                    info!("Hashing plain-text password for user id {}", itm.id);
                    let salt = get_new_salt();
                    let hash = get_password_hash(&pw, &salt);
                    itm.set_str("password", &hash);
                }
            }
            st2.set_item(&collection, &itm, false).await;
        }
    }
}
