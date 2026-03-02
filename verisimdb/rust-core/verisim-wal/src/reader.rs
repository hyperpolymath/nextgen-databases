// SPDX-License-Identifier: PMPL-1.0-or-later
//
// VeriSimDB Write-Ahead Log - Reader for crash recovery
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
//
// The `WalReader` reads WAL segment files and replays entries in sequence
// order. It verifies CRC32 checksums on each entry and gracefully handles
// corrupted or truncated entries (which are expected after a crash).

use std::fs;
use std::path::{Path, PathBuf};

use tracing::{debug, warn};

use crate::entry::{WalEntry, WalOperation, MAX_ENTRY_SIZE};
use crate::error::{WalError, WalResult};
use crate::segment::list_segments;

// ---------------------------------------------------------------------------
// WalReader
// ---------------------------------------------------------------------------

/// A reader that replays WAL entries from segment files on disk.
///
/// The reader scans all segment files in the WAL directory and presents
/// their entries as a sequential stream, ordered by sequence number.
pub struct WalReader {
    /// The WAL directory containing segment files.
    wal_dir: PathBuf,
}

impl WalReader {
    /// Open a WAL directory for reading.
    ///
    /// Does not read any data until `replay_from()` or
    /// `find_last_checkpoint()` is called.
    pub fn open(wal_dir: impl AsRef<Path>) -> WalResult<Self> {
        let wal_dir = wal_dir.as_ref().to_path_buf();
        if !wal_dir.is_dir() {
            return Err(WalError::DirectoryNotFound(
                wal_dir.display().to_string(),
            ));
        }
        Ok(Self { wal_dir })
    }

    /// Return an iterator that replays all WAL entries with sequence number
    /// >= `from_sequence`, across all segment files, in order.
    ///
    /// Corrupted entries are skipped with a warning log. Truncated entries
    /// at the end of a segment (indicating a crash during write) are silently
    /// ignored.
    pub fn replay_from(&self, from_sequence: u64) -> WalResult<WalEntryIterator> {
        let segments = list_segments(&self.wal_dir)?;

        // Collect all entries from relevant segments.
        let mut all_entries: Vec<WalEntry> = Vec::new();

        for segment in &segments {
            // Skip segments that are entirely before our starting point.
            // We cannot skip based on start_sequence alone because the last
            // entry in a segment may have a sequence >= from_sequence even
            // if the segment's start_sequence is less.
            let entries = read_segment_entries(&segment.path)?;
            for entry in entries {
                if entry.sequence >= from_sequence {
                    all_entries.push(entry);
                }
            }
        }

        // Sort by sequence number (segments should be in order, but be safe).
        all_entries.sort_by_key(|e| e.sequence);

        debug!(
            count = all_entries.len(),
            from_sequence,
            "Replaying WAL entries"
        );

        Ok(WalEntryIterator {
            entries: all_entries,
            position: 0,
        })
    }

    /// Replay all entries from the beginning of the WAL.
    pub fn replay_all(&self) -> WalResult<WalEntryIterator> {
        self.replay_from(0)
    }

    /// Find the sequence number of the last checkpoint entry in the WAL.
    ///
    /// Returns `None` if no checkpoint entries exist. This is used during
    /// recovery to determine the safe starting point for replay.
    pub fn find_last_checkpoint(&self) -> WalResult<Option<u64>> {
        let segments = list_segments(&self.wal_dir)?;
        let mut last_checkpoint: Option<u64> = None;

        // Scan segments in reverse order for efficiency (most likely to find
        // the last checkpoint in the latest segments).
        for segment in segments.iter().rev() {
            let entries = read_segment_entries(&segment.path)?;
            for entry in entries.iter().rev() {
                if entry.operation == WalOperation::Checkpoint {
                    match last_checkpoint {
                        Some(existing) if entry.sequence > existing => {
                            last_checkpoint = Some(entry.sequence);
                        }
                        None => {
                            last_checkpoint = Some(entry.sequence);
                        }
                        _ => {}
                    }
                    // Once we find a checkpoint in this segment, we can
                    // stop scanning earlier segments (they will have lower
                    // sequence numbers).
                    return Ok(last_checkpoint);
                }
            }
        }

        Ok(last_checkpoint)
    }

    /// Count the total number of valid entries across all segments.
    ///
    /// Useful for diagnostics and testing.
    pub fn entry_count(&self) -> WalResult<usize> {
        let segments = list_segments(&self.wal_dir)?;
        let mut count = 0;
        for segment in &segments {
            count += read_segment_entries(&segment.path)?.len();
        }
        Ok(count)
    }
}

// ---------------------------------------------------------------------------
// WalEntryIterator
// ---------------------------------------------------------------------------

/// An iterator over WAL entries, yielded in sequence order.
pub struct WalEntryIterator {
    /// Pre-loaded and sorted entries.
    entries: Vec<WalEntry>,
    /// Current position in the entries vector.
    position: usize,
}

impl Iterator for WalEntryIterator {
    type Item = WalEntry;

    fn next(&mut self) -> Option<Self::Item> {
        if self.position < self.entries.len() {
            let entry = self.entries[self.position].clone();
            self.position += 1;
            Some(entry)
        } else {
            None
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        let remaining = self.entries.len() - self.position;
        (remaining, Some(remaining))
    }
}

impl ExactSizeIterator for WalEntryIterator {}

// ---------------------------------------------------------------------------
// Segment reading helpers
// ---------------------------------------------------------------------------

/// Read all valid entries from a single segment file.
///
/// Corrupted entries (CRC mismatch) are logged and skipped. Truncated
/// entries at the end of the file are silently ignored (they indicate a
/// crash during write).
fn read_segment_entries(path: &Path) -> WalResult<Vec<WalEntry>> {
    let data = fs::read(path)?;
    let mut entries = Vec::new();
    let mut offset = 0usize;
    let segment_name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "<unknown>".to_string());

    while offset + 4 <= data.len() {
        // Read entry_length (u32 LE).
        let entry_length = u32::from_le_bytes(
            data[offset..offset + 4]
                .try_into()
                .map_err(|_| WalError::TruncatedEntry {
                    segment: segment_name.clone(),
                    offset: offset as u64,
                })?,
        );

        // Validate entry_length.
        if entry_length == 0 {
            // Zero-length entry is a padding sentinel; stop reading.
            break;
        }

        if entry_length > MAX_ENTRY_SIZE {
            warn!(
                offset,
                entry_length,
                segment = %segment_name,
                "Entry declares unreasonable length, stopping segment read"
            );
            break;
        }

        // Check if the full entry fits in the remaining data.
        let entry_end = offset + 4 + entry_length as usize;
        if entry_end > data.len() {
            // Truncated entry at end of segment (crash during write).
            debug!(
                offset,
                entry_length,
                available = data.len() - offset - 4,
                segment = %segment_name,
                "Truncated entry at end of segment (expected after crash)"
            );
            break;
        }

        // Try to deserialize the entry.
        let entry_data = &data[offset + 4..entry_end];
        match WalEntry::deserialize(entry_data, entry_length) {
            Ok(entry) => {
                entries.push(entry);
            }
            Err(WalError::CrcMismatch {
                sequence,
                expected,
                actual,
            }) => {
                warn!(
                    sequence,
                    expected = format!("{expected:#010x}"),
                    actual = format!("{actual:#010x}"),
                    offset,
                    segment = %segment_name,
                    "Skipping corrupted WAL entry (CRC mismatch)"
                );
                // Continue to next entry.
            }
            Err(other) => {
                warn!(
                    error = %other,
                    offset,
                    segment = %segment_name,
                    "Skipping unreadable WAL entry"
                );
            }
        }

        offset = entry_end;
    }

    Ok(entries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::{WalModality, WalOperation};
    use crate::writer::{SyncMode, WalWriter};
    use tempfile::TempDir;

    /// Helper: create a test WAL entry.
    fn test_entry(entity_id: &str, modality: WalModality) -> WalEntry {
        WalEntry {
            sequence: 0,
            timestamp: chrono::Utc::now(),
            operation: WalOperation::Insert,
            modality,
            entity_id: entity_id.to_string(),
            payload: serde_json::to_vec(&serde_json::json!({"test": true})).unwrap(),
        }
    }

    #[test]
    fn test_write_and_read_back() {
        let dir = TempDir::new().unwrap();

        // Write entries.
        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer
                .append(test_entry("entity-1", WalModality::Graph))
                .unwrap();
            writer
                .append(test_entry("entity-2", WalModality::Vector))
                .unwrap();
            writer
                .append(test_entry("entity-3", WalModality::Tensor))
                .unwrap();
        }

        // Read entries.
        let reader = WalReader::open(dir.path()).unwrap();
        let entries: Vec<WalEntry> = reader.replay_all().unwrap().collect();

        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0].sequence, 1);
        assert_eq!(entries[0].entity_id, "entity-1");
        assert_eq!(entries[0].modality, WalModality::Graph);
        assert_eq!(entries[1].sequence, 2);
        assert_eq!(entries[1].entity_id, "entity-2");
        assert_eq!(entries[2].sequence, 3);
        assert_eq!(entries[2].entity_id, "entity-3");
    }

    #[test]
    fn test_replay_from_sequence() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            for i in 0..10 {
                writer
                    .append(test_entry(&format!("e-{i}"), WalModality::Document))
                    .unwrap();
            }
        }

        let reader = WalReader::open(dir.path()).unwrap();

        // Replay from sequence 5 onward.
        let entries: Vec<WalEntry> = reader.replay_from(5).unwrap().collect();
        assert_eq!(entries.len(), 6); // sequences 5, 6, 7, 8, 9, 10
        assert_eq!(entries[0].sequence, 5);
        assert_eq!(entries[5].sequence, 10);
    }

    #[test]
    fn test_find_last_checkpoint() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer
                .append(test_entry("e-1", WalModality::Graph))
                .unwrap();
            writer
                .append(test_entry("e-2", WalModality::Vector))
                .unwrap();
            let cp1 = writer.checkpoint().unwrap();
            assert_eq!(cp1, 3);

            writer
                .append(test_entry("e-3", WalModality::Tensor))
                .unwrap();
            writer
                .append(test_entry("e-4", WalModality::Semantic))
                .unwrap();
            let cp2 = writer.checkpoint().unwrap();
            assert_eq!(cp2, 6);

            writer
                .append(test_entry("e-5", WalModality::Document))
                .unwrap();
        }

        let reader = WalReader::open(dir.path()).unwrap();
        let last_cp = reader.find_last_checkpoint().unwrap();
        assert_eq!(last_cp, Some(6));
    }

    #[test]
    fn test_no_checkpoint_returns_none() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer
                .append(test_entry("e-1", WalModality::Graph))
                .unwrap();
        }

        let reader = WalReader::open(dir.path()).unwrap();
        assert_eq!(reader.find_last_checkpoint().unwrap(), None);
    }

    #[test]
    fn test_empty_wal_produces_empty_iterator() {
        let dir = TempDir::new().unwrap();

        // Create the WAL directory with a writer (creates empty segment).
        {
            let _writer = WalWriter::open(dir.path(), SyncMode::Async).unwrap();
        }

        let reader = WalReader::open(dir.path()).unwrap();
        let entries: Vec<WalEntry> = reader.replay_all().unwrap().collect();
        assert!(entries.is_empty());
    }

    #[test]
    fn test_corrupted_entry_skipped() {
        let dir = TempDir::new().unwrap();

        // Write some entries.
        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer
                .append(test_entry("good-1", WalModality::Graph))
                .unwrap();
            writer
                .append(test_entry("will-corrupt", WalModality::Vector))
                .unwrap();
            writer
                .append(test_entry("good-3", WalModality::Tensor))
                .unwrap();
        }

        // Tamper with the second entry's CRC in the segment file.
        let segments = list_segments(dir.path()).unwrap();
        assert_eq!(segments.len(), 1);

        let mut data = fs::read(&segments[0].path).unwrap();

        // Find the second entry. The first entry starts at offset 0.
        // Read the first entry's length to find the second entry's offset.
        let first_len =
            u32::from_le_bytes(data[0..4].try_into().unwrap()) as usize;
        let second_entry_offset = 4 + first_len;

        // The CRC is at bytes [offset+4..offset+8] (after entry_length).
        let crc_offset = second_entry_offset + 4;
        data[crc_offset] ^= 0xFF; // Flip some bits in the CRC.

        fs::write(&segments[0].path, &data).unwrap();

        // Read back: should get entries 1 and 3, but skip 2.
        let reader = WalReader::open(dir.path()).unwrap();
        let entries: Vec<WalEntry> = reader.replay_all().unwrap().collect();

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].entity_id, "good-1");
        assert_eq!(entries[1].entity_id, "good-3");
    }

    #[test]
    fn test_multiple_modalities_in_same_wal() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            writer
                .append(test_entry("e-1", WalModality::Graph))
                .unwrap();
            writer
                .append(test_entry("e-2", WalModality::Vector))
                .unwrap();
            writer
                .append(test_entry("e-3", WalModality::Tensor))
                .unwrap();
            writer
                .append(test_entry("e-4", WalModality::Semantic))
                .unwrap();
            writer
                .append(test_entry("e-5", WalModality::Document))
                .unwrap();
            writer
                .append(test_entry("e-6", WalModality::Temporal))
                .unwrap();
        }

        let reader = WalReader::open(dir.path()).unwrap();
        let entries: Vec<WalEntry> = reader.replay_all().unwrap().collect();

        assert_eq!(entries.len(), 6);
        assert_eq!(entries[0].modality, WalModality::Graph);
        assert_eq!(entries[1].modality, WalModality::Vector);
        assert_eq!(entries[2].modality, WalModality::Tensor);
        assert_eq!(entries[3].modality, WalModality::Semantic);
        assert_eq!(entries[4].modality, WalModality::Document);
        assert_eq!(entries[5].modality, WalModality::Temporal);
    }

    #[test]
    fn test_checkpoint_and_replay_from_checkpoint() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();

            // Phase 1: some data + checkpoint.
            writer
                .append(test_entry("old-1", WalModality::Graph))
                .unwrap();
            writer
                .append(test_entry("old-2", WalModality::Vector))
                .unwrap();
            let cp = writer.checkpoint().unwrap();
            assert_eq!(cp, 3);

            // Phase 2: more data after checkpoint.
            writer
                .append(test_entry("new-1", WalModality::Tensor))
                .unwrap();
            writer
                .append(test_entry("new-2", WalModality::Semantic))
                .unwrap();
        }

        let reader = WalReader::open(dir.path()).unwrap();

        // Find the checkpoint.
        let cp_seq = reader.find_last_checkpoint().unwrap().unwrap();
        assert_eq!(cp_seq, 3);

        // Replay only from checkpoint onward.
        let entries: Vec<WalEntry> = reader.replay_from(cp_seq + 1).unwrap().collect();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].entity_id, "new-1");
        assert_eq!(entries[1].entity_id, "new-2");
    }

    #[test]
    fn test_entry_count() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            for _ in 0..7 {
                writer
                    .append(test_entry("e", WalModality::Graph))
                    .unwrap();
            }
        }

        let reader = WalReader::open(dir.path()).unwrap();
        assert_eq!(reader.entry_count().unwrap(), 7);
    }

    #[test]
    fn test_segment_rotation_read_across_segments() {
        let dir = TempDir::new().unwrap();

        // Write with tiny segments to force rotation.
        {
            let mut writer =
                WalWriter::open_with_max_size(dir.path(), SyncMode::Fsync, 100).unwrap();
            for i in 0..20 {
                writer
                    .append(test_entry(
                        &format!("entity-{i}"),
                        WalModality::Graph,
                    ))
                    .unwrap();
            }
        }

        // Verify multiple segments were created.
        let segments = list_segments(dir.path()).unwrap();
        assert!(segments.len() > 1);

        // Read all entries across segments.
        let reader = WalReader::open(dir.path()).unwrap();
        let entries: Vec<WalEntry> = reader.replay_all().unwrap().collect();
        assert_eq!(entries.len(), 20);

        // Verify sequence continuity.
        for (i, entry) in entries.iter().enumerate() {
            assert_eq!(entry.sequence, (i + 1) as u64);
            assert_eq!(entry.entity_id, format!("entity-{i}"));
        }
    }

    #[test]
    fn test_exact_size_iterator() {
        let dir = TempDir::new().unwrap();

        {
            let mut writer = WalWriter::open(dir.path(), SyncMode::Fsync).unwrap();
            for _ in 0..5 {
                writer
                    .append(test_entry("e", WalModality::Graph))
                    .unwrap();
            }
        }

        let reader = WalReader::open(dir.path()).unwrap();
        let iter = reader.replay_all().unwrap();
        assert_eq!(iter.len(), 5);
    }
}
