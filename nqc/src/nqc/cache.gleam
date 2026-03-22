// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam/Hex ecosystem)
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// cache.gleam — In-memory query result cache for NQC.
//
// Caches query results by (database_id, query_text) key. Limited to a fixed
// number of entries (LRU eviction by insertion order). Cache is session-scoped
// — cleared on exit. Mutations (INSERT/DELETE/CREATE) bypass the cache.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/string

/// Maximum number of cached results.
const max_cache_entries = 64

/// A cache entry — the result and the insertion order (for LRU).
pub type CacheEntry {
  CacheEntry(result: Dynamic, order: Int)
}

/// Cache key — database ID + query text.
pub type CacheKey {
  CacheKey(db_id: String, query: String)
}

/// The query result cache.
pub type Cache {
  Cache(entries: Dict(String, CacheEntry), next_order: Int)
}

/// Create an empty cache.
pub fn empty() -> Cache {
  Cache(entries: dict.new(), next_order: 0)
}

/// Build a string key from database ID and query text.
fn make_key(db_id: String, query: String) -> String {
  db_id <> ":" <> query
}

/// Look up a cached result. Returns the result if found.
pub fn get(cache: Cache, db_id: String, query: String) -> Result(Dynamic, Nil) {
  let key = make_key(db_id, query)
  case dict.get(cache.entries, key) {
    Ok(entry) -> Ok(entry.result)
    Error(_) -> Error(Nil)
  }
}

/// Store a result in the cache. Evicts the oldest entry if full.
/// Skips caching for mutation queries (INSERT, DELETE, CREATE, UPDATE, DROP).
pub fn put(
  cache: Cache,
  db_id: String,
  query: String,
  result: Dynamic,
) -> Cache {
  case is_mutation(query) {
    True -> cache
    False -> {
      let key = make_key(db_id, query)
      let entry = CacheEntry(result: result, order: cache.next_order)
      let new_entries = dict.insert(cache.entries, key, entry)
      let evicted = evict_if_full(new_entries)
      Cache(entries: evicted, next_order: cache.next_order + 1)
    }
  }
}

/// Invalidate all cached results for a specific database.
pub fn invalidate_db(cache: Cache, db_id: String) -> Cache {
  let prefix = db_id <> ":"
  let filtered =
    dict.to_list(cache.entries)
    |> list.filter(fn(pair) { !string.starts_with(pair.0, prefix) })
    |> dict.from_list
  Cache(..cache, entries: filtered)
}

/// Clear the entire cache.
pub fn clear(cache: Cache) -> Cache {
  Cache(entries: dict.new(), next_order: cache.next_order)
}

/// Get the number of cached entries.
pub fn size(cache: Cache) -> Int {
  dict.size(cache.entries)
}

/// Check if a query is a mutation (should not be cached).
fn is_mutation(query: String) -> Bool {
  let upper = string.uppercase(string.trim(query))
  let mutation_prefixes = [
    "INSERT", "DELETE", "CREATE", "UPDATE", "DROP", "ALTER",
    "DEFORM", "TRANSFORM", "SET",
  ]
  list.any(mutation_prefixes, fn(prefix) {
    string.starts_with(upper, prefix)
  })
}

/// Evict the oldest entry if the cache exceeds max size.
fn evict_if_full(entries: Dict(String, CacheEntry)) -> Dict(String, CacheEntry) {
  case dict.size(entries) > max_cache_entries {
    False -> entries
    True -> {
      // Find the entry with the lowest order (oldest).
      let pairs = dict.to_list(entries)
      case find_oldest(pairs) {
        Ok(oldest_key) -> dict.delete(entries, oldest_key)
        Error(_) -> entries
      }
    }
  }
}

/// Find the key of the oldest entry (lowest order value).
fn find_oldest(
  pairs: List(#(String, CacheEntry)),
) -> Result(String, Nil) {
  case pairs {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(find_oldest_loop(rest, first.0, first.1.order))
  }
}

/// Recursive helper — find the key with the minimum order.
fn find_oldest_loop(
  pairs: List(#(String, CacheEntry)),
  best_key: String,
  best_order: Int,
) -> String {
  case pairs {
    [] -> best_key
    [pair, ..rest] -> {
      case pair.1.order < best_order {
        True -> find_oldest_loop(rest, pair.0, pair.1.order)
        False -> find_oldest_loop(rest, best_key, best_order)
      }
    }
  }
}
