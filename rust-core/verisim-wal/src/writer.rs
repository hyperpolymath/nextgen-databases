// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log - Append-only writer
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// The `WalWriter` is responsible for appending entries to the current WAL
// segment file, managing segment rotation, and controlling fsync behavior
// according to the configured `SyncMode`.

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use chrono::Utc;
use tracing::{debug, info};

use crate::entry::{WalEntry, WalModality, WalOperation};
use crate::error::{WalError, WalResult};
use crate::segment::{
    list_segments, segment_path, DEFAULT_MAX_SEGMENT_SIZE, SegmentInfo,
};

// ---------------------------------------------------------------------------
// SyncMode
// ---------------------------------------------------------------------------

/// Controls how aggressively the WAL writer calls `fsync` to flush data to
/// stable storage.
#[derive(Debug, Clone)]
pub enum SyncMode {
    /// Call `fsync` after every single `append()`. This is the safest mode
    /// and guarantees that acknowledged writes survive a crash, but it is
    /// also the slowest.
    Fsync,

    /// Call `fsync` at most once per the specified duration. Writes between
    /// syncs may be lost on crash. This is a good balance between safety
    /// and throughput.
    Periodic(Duration),

    /// Never explicitly call `fsync`; rely on the OS page cache to flush
    /// data to disk eventually. This is the fastest mode but data loss is
    /// possible on crash.
    Async,
}

// ---------------------------------------------------------------------------
// WalWriter
// ---------------------------------------------------------------------------

/// An append-only writer for WAL segment files.
///
/// The writer maintains a monotonically increasing sequence counter and
/// automatically rotates to a new segment file when the current one exceeds
/// `max_segment_size`.
pub struct WalWriter {
    /// The directory containing all WAL segment files.
    wal_dir: PathBuf,

    /// The currently open segment file handle.
    current_file: File,

    /// Metadata about the current segment.
    current_segment: SegmentInfo,

    /// Monotonically increasing sequence number counter.
    next_sequence: u64,

    /// Maximum size (in bytes) of a single segment before rotation.
    max_segment_size: u64,

    /// How fsync is managed.
    sync_mode: SyncMode,

    /// Timestamp of the last fsync call (for `SyncMode::Periodic`).
    last_sync: Instant,
}

impl WalWriter {
    /// Open an existing WAL directory or initialize a new one.
    ///
    /// If the directory already contains segment files, the writer resumes
    /// from the end of the last segment (highest sequence number). If the
    /// directory is empty or does not exist, a fresh segment is created
    /// starting at sequence 1.
    ///
    /// # Arguments
    ///
    /// * `wal_dir` - Path to the WAL directory. Created if it does not exist.
    /// * `sync_mode` - Controls fsync behavior.
    pub fn open(wal_dir: impl AsRef<Path>, sync_mode: SyncMode) -> WalResult<Self> {
        Self::open_with_max_size(wal_dir, sync_mode, DEFAULT_MAX_SEGMENT_SIZE)
    }

    /// Open the WAL directory with a custom maximum segment size.
    ///
    /// This is primarily useful for testing with small segment sizes.
    pub fn open_with_max_size(
        wal_dir: impl AsRef<Path>,
        sync_mode: SyncMode,
        max_segment_size: u64,
    ) -> WalResult<Self> {
        let wal_dir = wal_dir.as_ref().to_path_buf();

        // Ensure the WAL directory exists.
        if !wal_dir.exists() {
            fs::create_dir_all(&wal_dir)?;
            info!(dir = %wal_dir.display(), "Created WAL directory");
        }

        // Discover existing segments.
        let segments = list_segments(&wal_dir)?;

        let (current_segment, current_file, next_sequence) = if segments.is_empty() {
            // Fresh WAL: create the first segment.
            let start_seq = 0;
            let path = segment_path(&wal_dir, start_seq);
            let file = File::create(&path)?;
            let segment = SegmentInfo {
                path,
                start_sequence: start_seq,
                file_size: 0,
            };
            info!("Initialized fresh WAL at sequence 0");
            (segment, file, 1u64)
        } else {
            // Resume from the last segment (safe: is_empty() checked above).
            let last = segments.last().expect("segments is non-empty").clone();
            let next_seq = Self::scan_last_sequence(&last)?;
            let file = OpenOptions::new().append(true).open(&last.path)?;
            info!(
                segment = %last.path.display(),
                next_sequence = next_seq,
                "Resuming WAL"
            );
            (last, file, next_seq)
        };

        Ok(Self {
            wal_dir,
            current_file,
            current_segment,
            next_sequence,
            max_segment_size,
            sync_mode,
            last_sync: Instant::now(),
        })
    }

    /// Append a new entry to the WAL.
    ///
    /// The entry's `sequence` field is overwritten with the next sequence
    /// number assigned by the writer. Returns the assigned sequence number.
    pub fn append(&mut self, mut entry: WalEntry) -> WalResult<u64> {
        // Assign the next sequence number.
        let sequence = self.next_sequence;
        entry.sequence = sequence;
        self.next_sequence += 1;

        let bytes = entry.serialize();

        // Check if we need to rotate before writing.
        if self.current_segment.file_size + bytes.len() as u64 > self.max_segment_size {
            self.rotate()?;
        }

        self.current_file.write_all(&bytes)?;
        self.current_segment.file_size += bytes.len() as u64;

        // Handle sync according to the configured mode.
        self.maybe_sync()?;

        debug!(sequence, entity_id = %entry.entity_id, "Appended WAL entry");

        Ok(sequence)
    }

    /// Force an immediate `fsync` of the current segment file, regardless
    /// of the configured `SyncMode`.
    pub fn sync(&mut self) -> WalResult<()> {
        self.current_file.sync_all()?;
        self.last_sync = Instant::now();
        Ok(())
    }

    /// Write a checkpoint entry to the WAL.
    ///
    /// A checkpoint marks a point in the log where all preceding entries
    /// have been durably applied to the modality stores. During recovery,
    /// replay can start from the last checkpoint instead of the beginning.
    ///
    /// Returns the sequence number of the checkpoint entry.
    pub fn checkpoint(&mut self) -> WalResult<u64> {
        let entry = WalEntry {
            sequence: 0, // Will be overwritten by append().
            timestamp: Utc::now(),
            operation: WalOperation::Checkpoint,
            modality: WalModality::All,
            entity_id: String::new(),
            payload: Vec::new(),
        };

        let sequence = self.append(entry)?;

        // Always fsync after a checkpoint for crash safety.
        self.sync()?;

        info!(sequence, "WAL checkpoint written");

        Ok(sequence)
    }

    /// Rotate to a new segment file.
    ///
    /// The current segment is fsynced and closed, and a new segment file is
    /// created starting at the current `next_sequence` value.
    pub fn rotate(&mut self) -> WalResult<()> {
        // Sync the current segment before closing.
        self.sync()?;

        let new_start = self.next_sequence;
        let new_path = segment_path(&self.wal_dir, new_start);
        let new_file = File::create(&new_path)?;

        info!(
            old_segment = %self.current_segment.path.display(),
            new_segment = %new_path.display(),
            start_sequence = new_start,
            "Rotated WAL segment"
        );

        self.current_file = new_file;
        self.current_segment = SegmentInfo {
            path: new_path,
            start_sequence: new_start,
            file_size: 0,
        };

        Ok(())
    }

    /// Returns the sequence number that will be assigned to the next entry.
    pub fn next_sequence(&self) -> u64 {
        self.next_sequence
    }

    /// Returns the path to the WAL directory.
    pub fn wal_dir(&self) -> &Path {
        &self.wal_dir
    }

    /// Returns a reference to the current segment's metadata.
    pub fn current_segment(&self) -> &SegmentInfo {
        &self.current_segment
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    /// Conditionally call fsync based on the configured sync mode.
    fn maybe_sync(&mut self) -> WalResult<()> {
        match &self.sync_mode {
            SyncMode::Fsync => {
                self.current_file.sync_all()?;
                self.last_sync = Instant::now();
            }
            SyncMode::Periodic(interval) => {
                if self.last_sync.elapsed() >= *interval {
                    self.current_file.sync_all()?;
                    self.last_sync = Instant::now();
                }
            }
            SyncMode::Async => {
                // No-op: rely on OS page cache.
            }
        }
        Ok(())
    }

    /// Scan the last segment file to determine the next sequence number.
    ///
    /// Reads through all valid entries in the segment and returns the
    /// sequence number one past the last valid entry. If the segment is
    /// empty, returns `start_sequence + 1`.
    fn scan_last_sequence(segment: &SegmentInfo) -> WalResult<u64> {
        if segment.file_size == 0 {
            return Ok(segment.start_sequence + 1);
        }

        let data = fs::read(&segment.path)?;
        let mut offset = 0usize;
        let mut last_sequence = segment.start_sequence;

        let segment_name = segment
            .path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "<unknown>".to_string());

        while offset + 4 <= data.len() {
            let entry_length = u32::from_le_bytes(
                data[offset..offset + 4]
                    .try_into()
                    .map_err(|_| WalError::TruncatedEntry {
                        segment: segment_name.clone(),
                        offset: offset as u64,
                    })?,
            );

            // Sanity check: the entry must fit within the remaining data.
            if offset + 4 + entry_length as usize > data.len() {
                // Truncated entry at end of file (crash during write).
                break;
            }

            // Try to read just the sequence number from the inner content.
            // Layout: [4 bytes crc][8 bytes sequence][...]
            let inner_start = offset + 4 + 4; // skip entry_length + crc
            if inner_start + 8 <= data.len() {
                let seq = u64::from_le_bytes(
                    data[inner_start..inner_start + 8]
                        .try_into()
                        .map_err(|_| WalError::TruncatedEntry {
                            segment: segment_name.clone(),
                            offset: inner_start as u64,
                        })?,
                );
                if seq >= last_sequence {
                    last_sequence = seq;
                }
            }

            offset += 4 + entry_length as usize;
        }

        Ok(last_sequence + 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::{WalModality, WalOperation};
    use tempfile::TempDir;

    /// Helper: create a test WAL entry.
    fn test_entry(modality: WalModality) -> WalEntry {
        WalEntry {
            sequence: 0,
            timestamp: Utc::now(),
            operation: WalOperation::Insert,
            modality,
            entity_id: "test-entity".to_string(),
            payload: b"{}".to_vec(),
        }
    }

    #[test]
    fn test_open_fresh_directory() {
        let dir = TempDir::new().unwrap();
        let writer = WalWriter::open(dir.path(), SyncMode::Async).unwrap();
        assert_eq!(writer.next_sequence(), 1);
    }

    #[test]
    fn test_append_increments_sequence() {
        let dir = TempDir::new().unwrap();
        let mut writer = WalWriter::open(dir.path(), SyncMode::Async).unwrap();

        let seq1 = writer.append(test_entry(WalModality::Graph)).unwrap();
        let seq2 = writer.append(test_entry(WalModality::Vector)).unwrap();
        let seq3 = writer.append(test_entry(WalModality::Tensor)).unwrap();

        assert_eq!(seq1, 1);
        assert_eq!(seq2, 2);
        assert_eq!(seq3, 3);
        assert_eq!(writer.next_sequence(), 4);
    }

    #[test]
    fn test_checkpoint_writes_entry() {
        let dir = TempDir::new().unwrap();
        let mut writer = WalWriter::open(dir.path(), SyncMode::Async).unwrap();

        writer.append(test_entry(WalModality::Graph)).unwrap();
        writer.append(test_entry(WalModality::Vector)).unwrap();
        let cp_seq = writer.checkpoint().unwrap();

        assert_eq!(cp_seq, 3);
        assert_eq!(writer.next_sequence(), 4);
    }

    #[test]
    fn test_segment_rotation() {
        let dir = TempDir::new().unwrap();
        // Use a tiny max segment size to force rotation.
        let mut writer =
            WalWriter::open_with_max_size(dir.path(), SyncMode::Async, 100).unwrap();

        // Write entries until rotation occurs.
        for _ in 0..10 {
            writer.append(test_entry(WalModality::Document)).unwrap();
        }

        let segments = list_segments(dir.path()).unwrap();
        assert!(
            segments.len() > 1,
            "Expected multiple segments after rotation, got {}",
            segments.len()
        );
    }

    #[test]
    fn test_resume_after_close() {
        let dir = TempDir::new().unwrap();

        // Write some entries.
        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer.append(test_entry(WalModality::Graph)).unwrap();
            writer.append(test_entry(WalModality::Vector)).unwrap();
            writer.append(test_entry(WalModality::Tensor)).unwrap();
        }

        // Re-open and verify sequence continues.
        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            let seq = writer.append(test_entry(WalModality::Semantic)).unwrap();
            assert_eq!(seq, 4, "Expected sequence 4 after resuming, got {seq}");
        }
    }

    #[test]
    fn test_open_creates_directory() {
        let dir = TempDir::new().unwrap();
        let wal_path = dir.path().join("subdir").join("wal");
        assert!(!wal_path.exists());

        let _writer = WalWriter::open(&wal_path, SyncMode::Async).unwrap();
        assert!(wal_path.exists());
    }

    #[test]
    fn test_fsync_mode() {
        let dir = TempDir::new().unwrap();
        let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();

        // Should not panic or error even with fsync on every write.
        for _ in 0..5 {
            writer.append(test_entry(WalModality::Temporal)).unwrap();
        }
    }

    #[test]
    fn test_periodic_sync_mode() {
        let dir = TempDir::new().unwrap();
        let mut writer = WalWriter::open(
            dir.path(),
            SyncMode::Periodic(Duration::from_millis(10)),
        )
        .unwrap();

        for _ in 0..5 {
            writer.append(test_entry(WalModality::Temporal)).unwrap();
        }

        // Explicit sync should always work.
        writer.sync().unwrap();
    }
}
