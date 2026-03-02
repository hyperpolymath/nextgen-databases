// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log - Error types
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Defines all error conditions that can arise during WAL operations including
// I/O failures, data corruption, and invalid state transitions.

use thiserror::Error;

/// Errors that can occur during WAL operations.
#[derive(Debug, Error)]
pub enum WalError {
    /// An I/O error occurred while reading or writing a WAL segment file.
    #[error("WAL I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// CRC32 checksum mismatch detected during entry validation.
    /// This indicates data corruption, either from disk failure or
    /// an incomplete write (crash mid-flush).
    #[error("CRC mismatch at sequence {sequence}: expected {expected:#010x}, got {actual:#010x}")]
    CrcMismatch {
        /// The sequence number of the corrupted entry.
        sequence: u64,
        /// The CRC32 value stored in the entry header.
        expected: u32,
        /// The CRC32 value computed from the entry payload.
        actual: u32,
    },

    /// The entry header declares a length that exceeds the maximum allowed
    /// entry size, indicating corruption or a malformed write.
    #[error("Entry at sequence {sequence} declares length {length} bytes, exceeding maximum {max_length}")]
    EntryTooLarge {
        /// The sequence number (if recoverable from the header).
        sequence: u64,
        /// The declared length in the entry header.
        length: u32,
        /// The maximum allowed entry length.
        max_length: u32,
    },

    /// An invalid operation byte was encountered while deserializing an entry.
    #[error("Invalid operation byte: {0}")]
    InvalidOperation(u8),

    /// An invalid modality byte was encountered while deserializing an entry.
    #[error("Invalid modality byte: {0}")]
    InvalidModality(u8),

    /// The WAL segment file is truncated or contains an incomplete entry.
    /// This typically happens when a crash occurs mid-write.
    #[error("Truncated entry at offset {offset} in segment {segment}")]
    TruncatedEntry {
        /// The byte offset where the truncation was detected.
        offset: u64,
        /// The segment file path or identifier.
        segment: String,
    },

    /// JSON serialization or deserialization failed for an entry payload.
    #[error("JSON error in WAL payload: {0}")]
    Json(#[from] serde_json::Error),

    /// UTF-8 decoding failed for the entity ID string.
    #[error("Invalid UTF-8 in entity ID: {0}")]
    InvalidEntityId(#[from] std::string::FromUtf8Error),

    /// The WAL directory does not exist or is not accessible.
    #[error("WAL directory not found or inaccessible: {0}")]
    DirectoryNotFound(String),

    /// Attempted to read past the end of a segment file.
    #[error("Unexpected end of segment at offset {0}")]
    UnexpectedEof(u64),
}

/// Convenience type alias for WAL results.
pub type WalResult<T> = Result<T, WalError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display_crc_mismatch() {
        let error = WalError::CrcMismatch {
            sequence: 42,
            expected: 0xDEADBEEF,
            actual: 0xCAFEBABE,
        };
        let message = format!("{error}");
        assert!(message.contains("42"));
        assert!(message.contains("0xdeadbeef"));
        assert!(message.contains("0xcafebabe"));
    }

    #[test]
    fn test_error_display_io() {
        let io_error = std::io::Error::new(std::io::ErrorKind::NotFound, "file gone");
        let error = WalError::Io(io_error);
        let message = format!("{error}");
        assert!(message.contains("file gone"));
    }

    #[test]
    fn test_error_display_entry_too_large() {
        let error = WalError::EntryTooLarge {
            sequence: 7,
            length: 999_999_999,
            max_length: 67_108_864,
        };
        let message = format!("{error}");
        assert!(message.contains("999999999"));
    }
}
