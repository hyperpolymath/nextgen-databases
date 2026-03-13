// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Query Plan Cache
 *
 * LRU cache for compiled query plans
 */

/** Cache entry */
type cacheEntry<'a> = {
  value: 'a,
  timestamp: float,
  hits: int,
}

/** LRU cache */
type lruCache<'a> = {
  mutable entries: Js.Dict.t<cacheEntry<'a>>,
  mutable order: array<string>,
  maxSize: int,
  ttlMs: float,
}

/** Create LRU cache */
let make = (~maxSize: int=1000, ~ttlMs: float=300000.0): lruCache<'a> => {
  entries: Js.Dict.empty(),
  order: [],
  maxSize,
  ttlMs,
}

/** Get cache entry */
let get = (cache: lruCache<'a>, key: string): option<'a> => {
  switch Js.Dict.get(cache.entries, key) {
  | Some(entry) => {
      let now = Js.Date.now()
      if now -. entry.timestamp > cache.ttlMs {
        // Expired
        Js.Dict.set(cache.entries, key, {...entry, hits: entry.hits})
        None
      } else {
        // Update hits and move to front
        Js.Dict.set(cache.entries, key, {...entry, hits: entry.hits + 1})
        cache.order = cache.order->Array.filter(k => k != key)
        cache.order->Array.push(key)->ignore
        Some(entry.value)
      }
    }
  | None => None
  }
}

/** Set cache entry */
let set = (cache: lruCache<'a>, key: string, value: 'a): unit => {
  // Evict if at capacity
  if Array.length(cache.order) >= cache.maxSize {
    switch cache.order[0] {
    | Some(oldest) => {
        cache.order = cache.order->Array.sliceToEnd(~start=1)
        %raw(`delete cache.entries[oldest]`)
      }
    | None => ()
    }
  }

  let entry = {
    value,
    timestamp: Js.Date.now(),
    hits: 0,
  }
  Js.Dict.set(cache.entries, key, entry)
  cache.order->Array.push(key)->ignore
}

/** Clear cache */
let clear = (cache: lruCache<'a>): unit => {
  cache.entries = Js.Dict.empty()
  cache.order = []
}

/** Get cache stats */
let stats = (cache: lruCache<'a>): {size: int, maxSize: int, hitRate: float} => {
  let totalHits = ref(0)
  let totalEntries = ref(0)

  Js.Dict.keys(cache.entries)->Array.forEach(key => {
    switch Js.Dict.get(cache.entries, key) {
    | Some(entry) => {
        totalHits := totalHits.contents + entry.hits
        totalEntries := totalEntries.contents + 1
      }
    | None => ()
    }
  })

  {
    size: totalEntries.contents,
    maxSize: cache.maxSize,
    hitRate: if totalEntries.contents > 0 {
      Float.fromInt(totalHits.contents) /. Float.fromInt(totalEntries.contents)
    } else {
      0.0
    },
  }
}

/** Global query plan cache */
let queryPlanCache: lruCache<string> = make(~maxSize=1000, ~ttlMs=300000.0)

/** Cache a query plan */
let cachePlan = (gql: string, plan: string): unit => {
  let key = gql // In production, would hash this
  set(queryPlanCache, key, plan)
}

/** Get cached plan */
let getCachedPlan = (gql: string): option<string> => {
  get(queryPlanCache, gql)
}
