// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Connection Pool
 *
 * Connection pooling for database backends
 */

/** Connection state */
type connectionState =
  | Idle
  | InUse
  | Closed

/** Connection */
type connection = {
  id: string,
  mutable state: connectionState,
  createdAt: float,
  mutable lastUsedAt: float,
}

/** Pool configuration */
type poolConfig = {
  minConnections: int,
  maxConnections: int,
  idleTimeoutMs: float,
  acquireTimeoutMs: float,
}

/** Default pool config */
let defaultConfig: poolConfig = {
  minConnections: 2,
  maxConnections: 10,
  idleTimeoutMs: 30000.0,
  acquireTimeoutMs: 5000.0,
}

/** Connection pool */
type pool = {
  config: poolConfig,
  mutable connections: array<connection>,
  mutable waitQueue: array<unit => unit>,
  mutable nextId: int,
}

/** Create connection pool */
let make = (~config: poolConfig=defaultConfig): pool => {
  let pool = {
    config,
    connections: [],
    waitQueue: [],
    nextId: 1,
  }

  // Create minimum connections
  for _ in 1 to config.minConnections {
    let conn = {
      id: `conn-${Int.toString(pool.nextId)}`,
      state: Idle,
      createdAt: Js.Date.now(),
      lastUsedAt: Js.Date.now(),
    }
    pool.nextId = pool.nextId + 1
    pool.connections->Array.push(conn)->ignore
  }

  pool
}

/** Get pool stats */
let stats = (pool: pool): {total: int, idle: int, inUse: int, waiting: int} => {
  let idle = ref(0)
  let inUse = ref(0)

  pool.connections->Array.forEach(conn => {
    switch conn.state {
    | Idle => idle := idle.contents + 1
    | InUse => inUse := inUse.contents + 1
    | Closed => ()
    }
  })

  {
    total: Array.length(pool.connections),
    idle: idle.contents,
    inUse: inUse.contents,
    waiting: Array.length(pool.waitQueue),
  }
}

/** Acquire connection */
let acquire = async (pool: pool): option<connection> => {
  // Find idle connection
  let idleConn = pool.connections->Array.find(c => c.state == Idle)

  switch idleConn {
  | Some(conn) => {
      conn.state = InUse
      conn.lastUsedAt = Js.Date.now()
      Some(conn)
    }
  | None => {
      // Create new if under max
      if Array.length(pool.connections) < pool.config.maxConnections {
        let conn = {
          id: `conn-${Int.toString(pool.nextId)}`,
          state: InUse,
          createdAt: Js.Date.now(),
          lastUsedAt: Js.Date.now(),
        }
        pool.nextId = pool.nextId + 1
        pool.connections->Array.push(conn)->ignore
        Some(conn)
      } else {
        // Wait for available connection (simplified)
        None
      }
    }
  }
}

/** Release connection */
let release = (pool: pool, conn: connection): unit => {
  conn.state = Idle
  conn.lastUsedAt = Js.Date.now()

  // Check if anyone is waiting
  switch pool.waitQueue[0] {
  | Some(callback) => {
      pool.waitQueue = pool.waitQueue->Array.sliceToEnd(~start=1)
      callback()
    }
  | None => ()
  }
}

/** Close connection */
let close = (_pool: pool, conn: connection): unit => {
  conn.state = Closed
}

/** Cleanup idle connections */
let cleanup = (pool: pool): int => {
  let now = Js.Date.now()
  let closed = ref(0)

  pool.connections = pool.connections->Array.filter(conn => {
    if conn.state == Idle && now -. conn.lastUsedAt > pool.config.idleTimeoutMs {
      // Keep minimum connections
      if Array.length(pool.connections) - closed.contents > pool.config.minConnections {
        conn.state = Closed
        closed := closed.contents + 1
        false
      } else {
        true
      }
    } else {
      conn.state != Closed
    }
  })

  closed.contents
}

/** Global connection pool */
let globalPool: pool = make()
