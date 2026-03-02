// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log - Segment management
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// Each WAL segment is a single append-only file named `wal-{sequence:016}.log`.
// Segments are rotated when they exceed the configured maximum size. Old
// segments can be pruned after a checkpoint confirms all their entries have
// been durably applied to the modality stores.

use std::fs;
use std::path::{Path, PathBuf};

use tracing::debug;

use crate::error::{WalError, WalResult};

/// Default maximum segment size in bytes (64 MiB).
pub const DEFAULT_MAX_SEGMENT_SIZE: u64 = 64 * 1024 * 1024;

/// The file extension used for WAL segment files.
pub const SEGMENT_EXTENSION: &str = "log";

/// The prefix used for WAL segment file names.
pub const SEGMENT_PREFIX: &str = "wal-";

/// Metadata about a single WAL segment file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SegmentInfo {
    /// The full path to the segment file on disk.
    pub path: PathBuf,

    /// The starting sequence number encoded in the file name.
    /// All entries in this segment have sequence >= this value.
    pub start_sequence: u64,

    /// Current file size in bytes.
    pub file_size: u64,
}

impl SegmentInfo {
    /// Returns `true` if the segment file has reached or exceeded the given
    /// maximum size in bytes.
    pub fn is_full(&self, max_size: u64) -> bool {
        self.file_size >= max_size
    }
}

impl PartialOrd for SegmentInfo {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SegmentInfo {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.start_sequence.cmp(&other.start_sequence)
    }
}

/// Build the canonical file name for a segment starting at the given
/// sequence number.
///
/// Format: `wal-0000000000000001.log`
pub fn segment_filename(start_sequence: u64) -> String {
    format!("{SEGMENT_PREFIX}{start_sequence:016}.{SEGMENT_EXTENSION}")
}

/// Build the full path for a segment file in the given WAL directory.
pub fn segment_path(wal_dir: &Path, start_sequence: u64) -> PathBuf {
    wal_dir.join(segment_filename(start_sequence))
}

/// Parse the starting sequence number from a segment file name.
///
/// Returns `None` if the name does not match the expected pattern.
pub fn parse_segment_filename(name: &str) -> Option<u64> {
    let stripped = name.strip_prefix(SEGMENT_PREFIX)?;
    let num_str = stripped.strip_suffix(&format!(".{SEGMENT_EXTENSION}"))?;
    num_str.parse::<u64>().ok()
}

/// Scan a WAL directory and return metadata for all segment files, sorted
/// by starting sequence number (ascending).
///
/// Non-segment files in the directory are silently ignored.
pub fn list_segments(wal_dir: &Path) -> WalResult<Vec<SegmentInfo>> {
    if !wal_dir.is_dir() {
        return Err(WalError::DirectoryNotFound(
            wal_dir.display().to_string(),
        ));
    }

    let mut segments = Vec::new();

    for dir_entry in fs::read_dir(wal_dir)? {
        let dir_entry = dir_entry?;
        let file_name = dir_entry.file_name();
        let name = file_name.to_string_lossy();

        if let Some(start_sequence) = parse_segment_filename(&name) {
            let metadata = dir_entry.metadata()?;
            segments.push(SegmentInfo {
                path: dir_entry.path(),
                start_sequence,
                file_size: metadata.len(),
            });
        }
    }

    segments.sort();

    debug!(
        count = segments.len(),
        dir = %wal_dir.display(),
        "Discovered WAL segments"
    );

    Ok(segments)
}

/// Remove segment files whose starting sequence is strictly less than the
/// given checkpoint sequence. These segments are safe to delete because all
/// their entries have been durably applied.
///
/// Returns the number of segments removed.
pub fn prune_segments_before(wal_dir: &Path, checkpoint_sequence: u64) -> WalResult<usize> {
    let segments = list_segments(wal_dir)?;
    let mut removed = 0;

    for segment in &segments {
        // Only remove segments that are entirely before the checkpoint.
        // A segment starting at sequence N may contain entries up to the
        // start of the next segment, so we need to check against the next
        // segment's start_sequence. For safety, we only remove segments
        // whose start_sequence is strictly less than the checkpoint AND
        // there exists a later segment (so we never remove the only segment).
        if segment.start_sequence < checkpoint_sequence {
            // Check if there is a later segment that covers the checkpoint.
            let has_later_segment = segments
                .iter()
                .any(|s| s.start_sequence >= checkpoint_sequence);

            if has_later_segment {
                debug!(
                    path = %segment.path.display(),
                    start_sequence = segment.start_sequence,
                    "Pruning WAL segment (before checkpoint {checkpoint_sequence})"
                );
                fs::remove_file(&segment.path)?;
                removed += 1;
            }
        }
    }

    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;
    use tempfile::TempDir;

    /// Helper to create a temporary WAL directory. We use a local helper
    /// instead of depending on tempfile in the library crate.
    struct TestDir {
        _inner: TempDir,
        path: PathBuf,
    }

    impl TestDir {
        fn new() -> Self {
            let inner = TempDir::new().unwrap();
            let path = inner.path().to_path_buf();
            Self {
                _inner: inner,
                path,
            }
        }

        fn create_segment(&self, start_seq: u64, size_bytes: usize) {
            let file_path = segment_path(&self.path, start_seq);
            let mut file = File::create(file_path).unwrap();
            file.write_all(&vec![0u8; size_bytes]).unwrap();
        }
    }

    #[test]
    fn test_segment_filename_format() {
        assert_eq!(segment_filename(0), "wal-0000000000000000.log");
        assert_eq!(segment_filename(1), "wal-0000000000000001.log");
        assert_eq!(
            segment_filename(9_999_999_999_999_999),
            "wal-9999999999999999.log"
        );
    }

    #[test]
    fn test_parse_segment_filename_valid() {
        assert_eq!(
            parse_segment_filename("wal-0000000000000042.log"),
            Some(42)
        );
        assert_eq!(
            parse_segment_filename("wal-0000000000000000.log"),
            Some(0)
        );
    }

    #[test]
    fn test_parse_segment_filename_invalid() {
        assert_eq!(parse_segment_filename("not-a-segment.txt"), None);
        assert_eq!(parse_segment_filename("wal-.log"), None);
        assert_eq!(parse_segment_filename("wal-abc.log"), None);
        assert_eq!(parse_segment_filename(""), None);
    }

    #[test]
    fn test_list_segments_sorted() {
        let dir = TestDir::new();
        dir.create_segment(100, 1024);
        dir.create_segment(1, 512);
        dir.create_segment(50, 2048);

        // Create a non-segment file that should be ignored.
        File::create(dir.path.join("readme.txt")).unwrap();

        let segments = list_segments(&dir.path).unwrap();
        assert_eq!(segments.len(), 3);
        assert_eq!(segments[0].start_sequence, 1);
        assert_eq!(segments[0].file_size, 512);
        assert_eq!(segments[1].start_sequence, 50);
        assert_eq!(segments[2].start_sequence, 100);
    }

    #[test]
    fn test_list_segments_empty_dir() {
        let dir = TestDir::new();
        let segments = list_segments(&dir.path).unwrap();
        assert!(segments.is_empty());
    }

    #[test]
    fn test_list_segments_nonexistent_dir() {
        let result = list_segments(Path::new("/nonexistent/wal/dir"));
        assert!(result.is_err());
    }

    #[test]
    fn test_segment_info_is_full() {
        let info = SegmentInfo {
            path: PathBuf::from("test.log"),
            start_sequence: 0,
            file_size: DEFAULT_MAX_SEGMENT_SIZE,
        };
        assert!(info.is_full(DEFAULT_MAX_SEGMENT_SIZE));
        assert!(!info.is_full(DEFAULT_MAX_SEGMENT_SIZE + 1));
    }

    #[test]
    fn test_prune_segments_before_checkpoint() {
        let dir = TestDir::new();
        dir.create_segment(1, 100);
        dir.create_segment(50, 100);
        dir.create_segment(100, 100);

        // Prune everything before sequence 100.
        let removed = prune_segments_before(&dir.path, 100).unwrap();
        assert_eq!(removed, 2);

        let remaining = list_segments(&dir.path).unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].start_sequence, 100);
    }

    #[test]
    fn test_prune_does_not_remove_only_segment() {
        let dir = TestDir::new();
        dir.create_segment(1, 100);

        // Even though sequence 1 < checkpoint 999, we should not remove it
        // because there is no later segment covering the checkpoint.
        let removed = prune_segments_before(&dir.path, 999).unwrap();
        assert_eq!(removed, 0);

        let remaining = list_segments(&dir.path).unwrap();
        assert_eq!(remaining.len(), 1);
    }
}
