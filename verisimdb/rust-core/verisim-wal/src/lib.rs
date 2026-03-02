// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log (WAL) crate
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Provides crash recovery for VeriSimDB by recording all mutations to an
// append-only log before they are applied to the modality stores. On crash,
// the WAL is replayed from the last checkpoint to bring the database back
// to a consistent state.
//
// # Architecture
//
// The WAL is organized as a sequence of **segment files** in a dedicated
// directory. Each segment is an append-only binary file containing
// length-prefixed, CRC32-protected entries. Segments are rotated when they
// exceed a configurable maximum size (default 64 MiB).
//
// ## On-disk entry format (all integers little-endian)
//
// ```text
// [4 bytes: entry_length (u32)]   -- length of everything after this field
// [4 bytes: crc32 checksum]       -- CRC32 of all bytes after this field
// [8 bytes: sequence (u64)]
// [8 bytes: timestamp (i64)]      -- Unix milliseconds UTC
// [1 byte:  operation]            -- 0=Insert, 1=Update, 2=Delete, 3=Checkpoint
// [1 byte:  modality]             -- 0-7 for modalities (octad), 255=All
// [4 bytes: entity_id_len (u32)]  -- length of entity_id UTF-8 bytes
// [N bytes: entity_id]
// [4 bytes: payload_len (u32)]    -- length of payload bytes
// [M bytes: payload]
// ```
//
// ## Usage
//
// ```no_run
// use verisim_wal::{WalWriter, WalReader, WalEntry, WalOperation, WalModality, SyncMode};
// use chrono::Utc;
//
// // Open a WAL for writing.
// let mut writer = WalWriter::open("/tmp/verisim-wal", SyncMode::Fsync).unwrap();
//
// // Append an entry.
// let entry = WalEntry {
//     sequence: 0, // assigned by the writer
//     timestamp: Utc::now(),
//     operation: WalOperation::Insert,
//     modality: WalModality::Graph,
//     entity_id: "entity-123".to_string(),
//     payload: b"{}".to_vec(),
// };
// let seq = writer.append(entry).unwrap();
//
// // Write a checkpoint.
// writer.checkpoint().unwrap();
//
// // Read back.
// let reader = WalReader::open("/tmp/verisim-wal").unwrap();
// for entry in reader.replay_all().unwrap() {
//     println!("seq={} op={:?} entity={}", entry.sequence, entry.operation, entry.entity_id);
// }
// ```

pub mod entry;
pub mod error;
pub mod reader;
pub mod segment;
pub mod writer;

// Re-export the primary public API for ergonomic imports.
pub use entry::{WalEntry, WalModality, WalOperation};
pub use error::{WalError, WalResult};
pub use reader::{WalEntryIterator, WalReader};
pub use segment::{SegmentInfo, DEFAULT_MAX_SEGMENT_SIZE};
pub use writer::{SyncMode, WalWriter};
