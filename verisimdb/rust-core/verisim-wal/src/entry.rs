// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log - Entry types
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Defines the WAL entry struct and its constituent enums (operation type,
// modality). Provides binary serialization/deserialization for the on-disk
// format with CRC32 integrity checking.
//
// On-disk binary format (all integers little-endian):
//   [4 bytes: entry_length (u32)]   -- length of everything after this field
//   [4 bytes: crc32 checksum]       -- CRC32 of all bytes after this field
//   [8 bytes: sequence (u64)]
//   [8 bytes: timestamp (i64)]      -- Unix milliseconds UTC
//   [1 byte:  operation]            -- 0=Insert, 1=Update, 2=Delete, 3=Checkpoint
//   [1 byte:  modality]             -- 0-7 for modalities (octad), 255=All
//   [4 bytes: entity_id_len (u32)]  -- length of entity_id UTF-8 bytes
//   [N bytes: entity_id]
//   [4 bytes: payload_len (u32)]    -- length of payload bytes
//   [M bytes: payload]

use chrono::{DateTime, TimeZone, Utc};
use crc32fast::Hasher as Crc32Hasher;
use serde::{Deserialize, Serialize};

use crate::error::{WalError, WalResult};

/// Maximum allowed entry size: 64 MiB. Any entry declaring a larger size
/// is treated as corrupted.
pub const MAX_ENTRY_SIZE: u32 = 64 * 1024 * 1024;

/// Size of the fixed-length entry header prefix (entry_length + crc32).
pub const HEADER_PREFIX_SIZE: usize = 4 + 4;

/// Size of the fixed fields after the header prefix (sequence + timestamp +
/// operation + modality).
pub const FIXED_FIELDS_SIZE: usize = 8 + 8 + 1 + 1;

// ---------------------------------------------------------------------------
// WalOperation
// ---------------------------------------------------------------------------

/// The type of mutation recorded by this WAL entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WalOperation {
    /// A new entity was inserted.
    Insert = 0,
    /// An existing entity was updated.
    Update = 1,
    /// An entity was deleted.
    Delete = 2,
    /// A checkpoint marker (used for recovery truncation points).
    Checkpoint = 3,
}

impl WalOperation {
    /// Decode a single byte into a `WalOperation`.
    pub fn from_byte(byte: u8) -> WalResult<Self> {
        match byte {
            0 => Ok(Self::Insert),
            1 => Ok(Self::Update),
            2 => Ok(Self::Delete),
            3 => Ok(Self::Checkpoint),
            other => Err(WalError::InvalidOperation(other)),
        }
    }

    /// Encode this operation as a single byte.
    pub fn to_byte(self) -> u8 {
        self as u8
    }
}

// ---------------------------------------------------------------------------
// WalModality
// ---------------------------------------------------------------------------

/// Which VeriSimDB modality this entry targets (octad: 8 modalities).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WalModality {
    /// RDF / property graph store.
    Graph = 0,
    /// HNSW vector similarity store.
    Vector = 1,
    /// Tensor (ndarray/Burn) store.
    Tensor = 2,
    /// Semantic proof-blob store.
    Semantic = 3,
    /// Tantivy full-text document store.
    Document = 4,
    /// Temporal versioning / time-series store.
    Temporal = 5,
    /// Origin/lineage tracking store.
    Provenance = 6,
    /// Geospatial/R-tree indexing store.
    Spatial = 7,
    /// Applies to all modalities (used in checkpoints).
    All = 255,
}

impl WalModality {
    /// Decode a single byte into a `WalModality`.
    pub fn from_byte(byte: u8) -> WalResult<Self> {
        match byte {
            0 => Ok(Self::Graph),
            1 => Ok(Self::Vector),
            2 => Ok(Self::Tensor),
            3 => Ok(Self::Semantic),
            4 => Ok(Self::Document),
            5 => Ok(Self::Temporal),
            6 => Ok(Self::Provenance),
            7 => Ok(Self::Spatial),
            255 => Ok(Self::All),
            other => Err(WalError::InvalidModality(other)),
        }
    }

    /// Encode this modality as a single byte.
    pub fn to_byte(self) -> u8 {
        self as u8
    }
}

// ---------------------------------------------------------------------------
// WalEntry
// ---------------------------------------------------------------------------

/// A single entry in the write-ahead log.
///
/// Each entry records one mutation operation against one entity in one
/// modality. Checkpoint entries use `WalModality::All` and an empty payload
/// to mark a recovery point.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WalEntry {
    /// Monotonically increasing sequence number assigned by the WAL writer.
    pub sequence: u64,

    /// UTC timestamp of when the entry was created.
    pub timestamp: DateTime<Utc>,

    /// The mutation operation type.
    pub operation: WalOperation,

    /// The target modality for this mutation.
    pub modality: WalModality,

    /// The entity identifier this mutation applies to.
    pub entity_id: String,

    /// Opaque payload bytes (typically JSON-encoded modality data).
    pub payload: Vec<u8>,
}

impl WalEntry {
    /// Serialize this entry to the on-disk binary format.
    ///
    /// Returns the complete byte buffer including the length prefix and CRC.
    pub fn serialize(&self) -> Vec<u8> {
        // Build the inner content (everything after entry_length and crc32).
        let entity_id_bytes = self.entity_id.as_bytes();
        let inner_size = FIXED_FIELDS_SIZE
            + 4
            + entity_id_bytes.len()
            + 4
            + self.payload.len();

        let mut inner = Vec::with_capacity(inner_size);

        // Sequence number (u64 LE).
        inner.extend_from_slice(&self.sequence.to_le_bytes());

        // Timestamp as Unix milliseconds (i64 LE).
        let timestamp_millis = self.timestamp.timestamp_millis();
        inner.extend_from_slice(&timestamp_millis.to_le_bytes());

        // Operation (1 byte).
        inner.push(self.operation.to_byte());

        // Modality (1 byte).
        inner.push(self.modality.to_byte());

        // Entity ID (length-prefixed).
        inner.extend_from_slice(&(entity_id_bytes.len() as u32).to_le_bytes());
        inner.extend_from_slice(entity_id_bytes);

        // Payload (length-prefixed).
        inner.extend_from_slice(&(self.payload.len() as u32).to_le_bytes());
        inner.extend_from_slice(&self.payload);

        // Compute CRC32 over the inner content.
        let crc = compute_crc32(&inner);

        // Build the final buffer: [entry_length][crc32][inner...].
        let entry_length = (4 + inner.len()) as u32; // crc32 field + inner content
        let mut buffer = Vec::with_capacity(4 + entry_length as usize);
        buffer.extend_from_slice(&entry_length.to_le_bytes());
        buffer.extend_from_slice(&crc.to_le_bytes());
        buffer.extend_from_slice(&inner);

        buffer
    }

    /// Deserialize a WAL entry from a byte slice that starts immediately
    /// after the entry_length field (i.e., begins with the CRC32 bytes).
    ///
    /// The `entry_length` is provided separately so the caller can validate
    /// size bounds before allocating.
    pub fn deserialize(data: &[u8], entry_length: u32) -> WalResult<Self> {
        if (data.len() as u32) < entry_length {
            return Err(WalError::UnexpectedEof(data.len() as u64));
        }

        let data = &data[..entry_length as usize];

        // First 4 bytes: stored CRC32.
        if data.len() < 4 {
            return Err(WalError::UnexpectedEof(0));
        }
        let stored_crc = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        let inner = &data[4..];

        // Verify CRC32 over the inner content.
        let computed_crc = compute_crc32(inner);
        if stored_crc != computed_crc {
            // Try to extract sequence for a better error message.
            let sequence = if inner.len() >= 8 {
                u64::from_le_bytes(inner[0..8].try_into().unwrap())
            } else {
                0
            };
            return Err(WalError::CrcMismatch {
                sequence,
                expected: stored_crc,
                actual: computed_crc,
            });
        }

        // Parse the inner content.
        Self::parse_inner(inner)
    }

    /// Parse the inner content bytes (after CRC verification).
    fn parse_inner(inner: &[u8]) -> WalResult<Self> {
        let mut offset = 0;

        // Sequence (u64 LE).
        if inner.len() < offset + 8 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let sequence = u64::from_le_bytes(inner[offset..offset + 8].try_into().unwrap());
        offset += 8;

        // Timestamp (i64 LE, Unix millis).
        if inner.len() < offset + 8 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let timestamp_millis = i64::from_le_bytes(inner[offset..offset + 8].try_into().unwrap());
        offset += 8;

        let timestamp = Utc
            .timestamp_millis_opt(timestamp_millis)
            .single()
            .unwrap_or_else(Utc::now);

        // Operation (1 byte).
        if inner.len() < offset + 1 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let operation = WalOperation::from_byte(inner[offset])?;
        offset += 1;

        // Modality (1 byte).
        if inner.len() < offset + 1 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let modality = WalModality::from_byte(inner[offset])?;
        offset += 1;

        // Entity ID (length-prefixed u32 LE + UTF-8 bytes).
        if inner.len() < offset + 4 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let entity_id_len =
            u32::from_le_bytes(inner[offset..offset + 4].try_into().unwrap()) as usize;
        offset += 4;

        if inner.len() < offset + entity_id_len {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let entity_id = String::from_utf8(inner[offset..offset + entity_id_len].to_vec())?;
        offset += entity_id_len;

        // Payload (length-prefixed u32 LE + bytes).
        if inner.len() < offset + 4 {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let payload_len =
            u32::from_le_bytes(inner[offset..offset + 4].try_into().unwrap()) as usize;
        offset += 4;

        if inner.len() < offset + payload_len {
            return Err(WalError::UnexpectedEof(offset as u64));
        }
        let payload = inner[offset..offset + payload_len].to_vec();

        Ok(Self {
            sequence,
            timestamp,
            operation,
            modality,
            entity_id,
            payload,
        })
    }
}

/// Compute a CRC32 checksum over the given byte slice using the IEEE
/// polynomial (same as zlib/gzip).
pub fn compute_crc32(data: &[u8]) -> u32 {
    let mut hasher = Crc32Hasher::new();
    hasher.update(data);
    hasher.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: create a sample entry for testing.
    fn sample_entry(seq: u64) -> WalEntry {
        WalEntry {
            sequence: seq,
            timestamp: Utc::now(),
            operation: WalOperation::Insert,
            modality: WalModality::Graph,
            entity_id: format!("entity-{seq}"),
            payload: serde_json::to_vec(&serde_json::json!({
                "type": "test",
                "value": seq
            }))
            .unwrap(),
        }
    }

    #[test]
    fn test_roundtrip_serialize_deserialize() {
        let entry = sample_entry(1);
        let bytes = entry.serialize();

        // Read entry_length from the first 4 bytes.
        let entry_length = u32::from_le_bytes(bytes[0..4].try_into().unwrap());

        // Deserialize from the bytes after the length prefix.
        let recovered = WalEntry::deserialize(&bytes[4..], entry_length).unwrap();

        assert_eq!(entry.sequence, recovered.sequence);
        assert_eq!(entry.operation, recovered.operation);
        assert_eq!(entry.modality, recovered.modality);
        assert_eq!(entry.entity_id, recovered.entity_id);
        assert_eq!(entry.payload, recovered.payload);
        // Timestamps may lose sub-millisecond precision; compare millis.
        assert_eq!(
            entry.timestamp.timestamp_millis(),
            recovered.timestamp.timestamp_millis()
        );
    }

    #[test]
    fn test_crc_mismatch_detection() {
        let entry = sample_entry(42);
        let mut bytes = entry.serialize();

        // Tamper with one byte in the payload area (after the 8-byte header prefix).
        let tamper_offset = bytes.len() - 1;
        bytes[tamper_offset] ^= 0xFF;

        let entry_length = u32::from_le_bytes(bytes[0..4].try_into().unwrap());
        let result = WalEntry::deserialize(&bytes[4..], entry_length);

        assert!(result.is_err());
        match result.unwrap_err() {
            WalError::CrcMismatch {
                sequence,
                expected,
                actual,
            } => {
                assert_eq!(sequence, 42);
                assert_ne!(expected, actual);
            }
            other => panic!("Expected CrcMismatch, got: {other:?}"),
        }
    }

    #[test]
    fn test_all_operations_roundtrip() {
        for op in [
            WalOperation::Insert,
            WalOperation::Update,
            WalOperation::Delete,
            WalOperation::Checkpoint,
        ] {
            assert_eq!(WalOperation::from_byte(op.to_byte()).unwrap(), op);
        }
    }

    #[test]
    fn test_all_modalities_roundtrip() {
        for modality in [
            WalModality::Graph,
            WalModality::Vector,
            WalModality::Tensor,
            WalModality::Semantic,
            WalModality::Document,
            WalModality::Temporal,
            WalModality::Provenance,
            WalModality::Spatial,
            WalModality::All,
        ] {
            assert_eq!(WalModality::from_byte(modality.to_byte()).unwrap(), modality);
        }
    }

    #[test]
    fn test_invalid_operation_byte() {
        assert!(WalOperation::from_byte(99).is_err());
    }

    #[test]
    fn test_invalid_modality_byte() {
        assert!(WalModality::from_byte(128).is_err());
    }

    #[test]
    fn test_empty_payload_and_entity_id() {
        let entry = WalEntry {
            sequence: 0,
            timestamp: Utc::now(),
            operation: WalOperation::Checkpoint,
            modality: WalModality::All,
            entity_id: String::new(),
            payload: Vec::new(),
        };
        let bytes = entry.serialize();
        let entry_length = u32::from_le_bytes(bytes[0..4].try_into().unwrap());
        let recovered = WalEntry::deserialize(&bytes[4..], entry_length).unwrap();
        assert_eq!(recovered.entity_id, "");
        assert!(recovered.payload.is_empty());
    }

    #[test]
    fn test_large_entity_id() {
        let long_id = "x".repeat(10_000);
        let entry = WalEntry {
            sequence: 99,
            timestamp: Utc::now(),
            operation: WalOperation::Insert,
            modality: WalModality::Document,
            entity_id: long_id.clone(),
            payload: vec![1, 2, 3],
        };
        let bytes = entry.serialize();
        let entry_length = u32::from_le_bytes(bytes[0..4].try_into().unwrap());
        let recovered = WalEntry::deserialize(&bytes[4..], entry_length).unwrap();
        assert_eq!(recovered.entity_id, long_id);
    }
}
