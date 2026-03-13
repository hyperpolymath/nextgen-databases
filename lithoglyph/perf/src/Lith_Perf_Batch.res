// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Batch Operations
 *
 * Batch processing for improved throughput
 */

/** Batch operation */
type batchOp =
  | Insert({collection: string, document: Js.Json.t})
  | Update({collection: string, document: Js.Json.t, id: string})
  | Delete({collection: string, id: string})

/** Batch result */
type batchResult = {
  successful: int,
  failed: int,
  errors: array<{index: int, error: string}>,
}

/** Batch configuration */
type batchConfig = {
  maxBatchSize: int,
  flushIntervalMs: float,
  retryOnFailure: bool,
  maxRetries: int,
}

/** Default batch config */
let defaultConfig: batchConfig = {
  maxBatchSize: 100,
  flushIntervalMs: 100.0,
  retryOnFailure: true,
  maxRetries: 3,
}

/** Batch processor */
type batchProcessor = {
  config: batchConfig,
  mutable queue: array<batchOp>,
  mutable processing: bool,
}

/** Create batch processor */
let make = (~config: batchConfig=defaultConfig): batchProcessor => {
  {
    config,
    queue: [],
    processing: false,
  }
}

/** Add operation to batch */
let add = (processor: batchProcessor, op: batchOp): unit => {
  processor.queue->Array.push(op)->ignore

  // Auto-flush if at max size
  if Array.length(processor.queue) >= processor.config.maxBatchSize {
    // Would trigger flush
    ()
  }
}

/** Process batch */
let flush = async (processor: batchProcessor): batchResult => {
  if processor.processing || Array.length(processor.queue) == 0 {
    {successful: 0, failed: 0, errors: []}
  } else {
    processor.processing = true
    let batch = processor.queue
    processor.queue = []

    let successful = ref(0)
    let failed = ref(0)
    let errors: array<{index: int, error: string}> = []

    // Process each operation
    batch->Array.forEachWithIndex((op, index) => {
      try {
        // In production, would execute against storage
        switch op {
        | Insert(_) | Update(_) | Delete(_) => {
            successful := successful.contents + 1
          }
        }
      } catch {
      | Js.Exn.Error(e) => {
          failed := failed.contents + 1
          errors->Array.push({
            index,
            error: Js.Exn.message(e)->Option.getOr("Unknown error"),
          })->ignore
        }
      | _ => {
          failed := failed.contents + 1
          errors->Array.push({index, error: "Unknown error"})->ignore
        }
      }
    })

    processor.processing = false

    {
      successful: successful.contents,
      failed: failed.contents,
      errors,
    }
  }
}

/** Get queue size */
let queueSize = (processor: batchProcessor): int => {
  Array.length(processor.queue)
}

/** Clear queue */
let clear = (processor: batchProcessor): unit => {
  processor.queue = []
}

/** Global batch processor */
let globalProcessor: batchProcessor = make()

/** Batch insert */
let batchInsert = (collection: string, documents: array<Js.Json.t>): unit => {
  documents->Array.forEach(doc => {
    add(globalProcessor, Insert({collection, document: doc}))
  })
}

/** Batch update */
let batchUpdate = (collection: string, updates: array<{id: string, document: Js.Json.t}>): unit => {
  updates->Array.forEach(({id, document}) => {
    add(globalProcessor, Update({collection, document, id}))
  })
}

/** Batch delete */
let batchDelete = (collection: string, ids: array<string>): unit => {
  ids->Array.forEach(id => {
    add(globalProcessor, Delete({collection, id}))
  })
}
