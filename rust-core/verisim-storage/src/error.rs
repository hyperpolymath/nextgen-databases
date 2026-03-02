// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Storage error types for VeriSimDB backend abstraction.
//
// Provides a unified error enum covering all failure modes that a storage
// backend may encounter: I/O errors, missing keys, serialization failures,
// data corruption, backend unavailability, and size limit violations.

use thiserror::Error;

/// Errors that can occur when interacting with a storage backend.
#[derive(Debug, Error)]
pub enum StorageError {
    /// An I/O error occurred in the underlying storage layer.
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// The requested key was not found.
    #[error("key not found: {0}")]
    NotFound(String),

    /// Failed to serialize or deserialize a value.
    #[error("serialization error: {0}")]
    SerializationError(String),

    /// The stored data is corrupted or in an unexpected format.
    #[error("corrupted data: {0}")]
    CorruptedData(String),

    /// The storage backend is not available (e.g., connection lost).
    #[error("backend unavailable: {0}")]
    BackendUnavailable(String),

    /// The key exceeds the maximum allowed size.
    #[error("key too large: {size} bytes (max: {max})")]
    KeyTooLarge {
        /// Actual key size in bytes.
        size: usize,
        /// Maximum allowed key size in bytes.
        max: usize,
    },

    /// The value exceeds the maximum allowed size.
    #[error("value too large: {size} bytes (max: {max})")]
    ValueTooLarge {
        /// Actual value size in bytes.
        size: usize,
        /// Maximum allowed value size in bytes.
        max: usize,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_io_error_display() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file gone");
        let err = StorageError::Io(io_err);
        assert!(err.to_string().contains("I/O error"));
    }

    #[test]
    fn test_not_found_display() {
        let err = StorageError::NotFound("my-key".to_string());
        assert_eq!(err.to_string(), "key not found: my-key");
    }

    #[test]
    fn test_serialization_error_display() {
        let err = StorageError::SerializationError("bad json".to_string());
        assert!(err.to_string().contains("serialization error"));
    }

    #[test]
    fn test_corrupted_data_display() {
        let err = StorageError::CorruptedData("checksum mismatch".to_string());
        assert!(err.to_string().contains("corrupted data"));
    }

    #[test]
    fn test_backend_unavailable_display() {
        let err = StorageError::BackendUnavailable("connection refused".to_string());
        assert!(err.to_string().contains("backend unavailable"));
    }

    #[test]
    fn test_key_too_large_display() {
        let err = StorageError::KeyTooLarge { size: 2048, max: 1024 };
        assert!(err.to_string().contains("key too large"));
        assert!(err.to_string().contains("2048"));
        assert!(err.to_string().contains("1024"));
    }

    #[test]
    fn test_value_too_large_display() {
        let err = StorageError::ValueTooLarge { size: 4096, max: 2048 };
        assert!(err.to_string().contains("value too large"));
        assert!(err.to_string().contains("4096"));
        assert!(err.to_string().contains("2048"));
    }
}
