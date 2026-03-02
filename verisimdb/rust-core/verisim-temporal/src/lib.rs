// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Temporal Modality
//!
//! Time-series and versioning for audit-grade history.
//! Implements Marr's Computational Level: "What happened when?"

pub mod diff;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, RwLock};
use thiserror::Error;

/// Temporal modality errors
#[derive(Error, Debug)]
pub enum TemporalError {
    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Version not found: {entity_id} @ {version}")]
    VersionNotFound { entity_id: String, version: u64 },

    #[error("Invalid time range: {0}")]
    InvalidTimeRange(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Lock poisoned: internal concurrency error")]
    LockPoisoned,
}

/// A timestamped version of an entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Version<T> {
    /// Version number (monotonically increasing)
    pub version: u64,
    /// When this version was created
    pub timestamp: DateTime<Utc>,
    /// The data at this version
    pub data: T,
    /// Who/what created this version
    pub author: String,
    /// Optional commit message
    pub message: Option<String>,
}

impl<T> Version<T> {
    /// Create a new version
    pub fn new(version: u64, data: T, author: impl Into<String>) -> Self {
        Self {
            version,
            timestamp: Utc::now(),
            data,
            author: author.into(),
            message: None,
        }
    }

    /// Add a message
    pub fn with_message(mut self, message: impl Into<String>) -> Self {
        self.message = Some(message.into());
        self
    }
}

/// A time-series data point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimePoint<T> {
    /// Timestamp
    pub time: DateTime<Utc>,
    /// Value at this time
    pub value: T,
    /// Optional labels/tags
    pub labels: HashMap<String, String>,
}

impl<T> TimePoint<T> {
    /// Create a new time point
    pub fn new(time: DateTime<Utc>, value: T) -> Self {
        Self {
            time,
            value,
            labels: HashMap::new(),
        }
    }

    /// Create with current time
    pub fn now(value: T) -> Self {
        Self::new(Utc::now(), value)
    }

    /// Add a label
    pub fn with_label(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.labels.insert(key.into(), value.into());
        self
    }
}

/// Time range for queries
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeRange {
    /// Start time (inclusive)
    pub start: DateTime<Utc>,
    /// End time (exclusive)
    pub end: DateTime<Utc>,
}

impl TimeRange {
    /// Create a time range
    pub fn new(start: DateTime<Utc>, end: DateTime<Utc>) -> Result<Self, TemporalError> {
        if start >= end {
            return Err(TemporalError::InvalidTimeRange(
                "start must be before end".to_string(),
            ));
        }
        Ok(Self { start, end })
    }

    /// Last N duration from now
    pub fn last(duration: chrono::Duration) -> Self {
        let now = Utc::now();
        Self {
            start: now - duration,
            end: now,
        }
    }

    /// Check if a timestamp is within the range
    pub fn contains(&self, time: &DateTime<Utc>) -> bool {
        *time >= self.start && *time < self.end
    }
}

/// Temporal store trait for cross-modal consistency
#[async_trait]
pub trait TemporalStore: Send + Sync {
    /// Type of data being versioned
    type Data: Clone + Send + Sync;

    /// Append a new version
    async fn append(&self, entity_id: &str, data: Self::Data, author: &str, message: Option<&str>) -> Result<u64, TemporalError>;

    /// Get the latest version
    async fn latest(&self, entity_id: &str) -> Result<Option<Version<Self::Data>>, TemporalError>;

    /// Get a specific version
    async fn at_version(&self, entity_id: &str, version: u64) -> Result<Option<Version<Self::Data>>, TemporalError>;

    /// Get version at a specific time
    async fn at_time(&self, entity_id: &str, time: DateTime<Utc>) -> Result<Option<Version<Self::Data>>, TemporalError>;

    /// Get all versions in a time range
    async fn in_range(&self, entity_id: &str, range: &TimeRange) -> Result<Vec<Version<Self::Data>>, TemporalError>;

    /// Get version history
    async fn history(&self, entity_id: &str, limit: usize) -> Result<Vec<Version<Self::Data>>, TemporalError>;

    /// Diff two versions
    async fn diff(&self, entity_id: &str, v1: u64, v2: u64) -> Result<diff::Diff<Self::Data>, TemporalError>
    where
        Self::Data: PartialEq,
    {
        let version1 = self.at_version(entity_id, v1).await?;
        let version2 = self.at_version(entity_id, v2).await?;

        diff::compare_values(
            version1.as_ref().map(|v| &v.data),
            version2.as_ref().map(|v| &v.data),
        )
        .map_err(|_| TemporalError::NotFound(format!("No versions to compare for entity {}", entity_id)))
    }

    /// Diff two timestamps
    async fn diff_time(&self, entity_id: &str, t1: DateTime<Utc>, t2: DateTime<Utc>) -> Result<diff::Diff<Self::Data>, TemporalError>
    where
        Self::Data: PartialEq,
    {
        let version1 = self.at_time(entity_id, t1).await?;
        let version2 = self.at_time(entity_id, t2).await?;

        diff::compare_values(
            version1.as_ref().map(|v| &v.data),
            version2.as_ref().map(|v| &v.data),
        )
        .map_err(|_| TemporalError::NotFound(format!("No versions to compare for entity {}", entity_id)))
    }
}

/// Type alias for version history map
type VersionHistory<T> = HashMap<String, BTreeMap<u64, Version<T>>>;

/// In-memory versioned store
pub struct InMemoryVersionStore<T> {
    /// Map of entity_id -> (version -> Version<T>)
    versions: Arc<RwLock<VersionHistory<T>>>,
}

impl<T: Clone + Send + Sync + 'static> InMemoryVersionStore<T> {
    pub fn new() -> Self {
        Self {
            versions: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl<T: Clone + Send + Sync + 'static> Default for InMemoryVersionStore<T> {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl<T: Clone + Send + Sync + 'static> TemporalStore for InMemoryVersionStore<T> {
    type Data = T;

    async fn append(&self, entity_id: &str, data: Self::Data, author: &str, message: Option<&str>) -> Result<u64, TemporalError> {
        let mut store = self.versions.write().map_err(|_| TemporalError::LockPoisoned)?;
        let versions = store.entry(entity_id.to_string()).or_default();

        let next_version = versions.keys().last().map(|v| v + 1).unwrap_or(1);
        let mut version = Version::new(next_version, data, author);
        if let Some(msg) = message {
            version = version.with_message(msg);
        }

        versions.insert(next_version, version);
        Ok(next_version)
    }

    async fn latest(&self, entity_id: &str) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self.versions.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .and_then(|versions| versions.values().last().cloned()))
    }

    async fn at_version(&self, entity_id: &str, version: u64) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self.versions.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .and_then(|versions| versions.get(&version).cloned()))
    }

    async fn at_time(&self, entity_id: &str, time: DateTime<Utc>) -> Result<Option<Version<Self::Data>>, TemporalError> {
        let store = self.versions.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store.get(entity_id).and_then(|versions| {
            versions
                .values()
                .filter(|v| v.timestamp <= time)
                .last()
                .cloned()
        }))
    }

    async fn in_range(&self, entity_id: &str, range: &TimeRange) -> Result<Vec<Version<Self::Data>>, TemporalError> {
        let store = self.versions.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .map(|versions| {
                versions
                    .values()
                    .filter(|v| range.contains(&v.timestamp))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default())
    }

    async fn history(&self, entity_id: &str, limit: usize) -> Result<Vec<Version<Self::Data>>, TemporalError> {
        let store = self.versions.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(entity_id)
            .map(|versions| {
                versions
                    .values()
                    .rev()
                    .take(limit)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default())
    }
}

/// Time-series store for metrics
#[async_trait]
pub trait TimeSeriesStore: Send + Sync {
    type Value: Clone + Send + Sync;

    /// Append a time point
    async fn append(&self, series_id: &str, point: TimePoint<Self::Value>) -> Result<(), TemporalError>;

    /// Query points in a time range
    async fn query(&self, series_id: &str, range: &TimeRange) -> Result<Vec<TimePoint<Self::Value>>, TemporalError>;

    /// Get the latest point
    async fn latest(&self, series_id: &str) -> Result<Option<TimePoint<Self::Value>>, TemporalError>;
}

/// In-memory time series store
pub struct InMemoryTimeSeriesStore<T> {
    series: Arc<RwLock<HashMap<String, Vec<TimePoint<T>>>>>,
}

impl<T: Clone + Send + Sync + 'static> InMemoryTimeSeriesStore<T> {
    pub fn new() -> Self {
        Self {
            series: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl<T: Clone + Send + Sync + 'static> Default for InMemoryTimeSeriesStore<T> {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl<T: Clone + Send + Sync + 'static> TimeSeriesStore for InMemoryTimeSeriesStore<T> {
    type Value = T;

    async fn append(&self, series_id: &str, point: TimePoint<Self::Value>) -> Result<(), TemporalError> {
        let mut store = self.series.write().map_err(|_| TemporalError::LockPoisoned)?;
        store.entry(series_id.to_string()).or_default().push(point);
        Ok(())
    }

    async fn query(&self, series_id: &str, range: &TimeRange) -> Result<Vec<TimePoint<Self::Value>>, TemporalError> {
        let store = self.series.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store
            .get(series_id)
            .map(|points| {
                points
                    .iter()
                    .filter(|p| range.contains(&p.time))
                    .cloned()
                    .collect()
            })
            .unwrap_or_default())
    }

    async fn latest(&self, series_id: &str) -> Result<Option<TimePoint<Self::Value>>, TemporalError> {
        let store = self.series.read().map_err(|_| TemporalError::LockPoisoned)?;
        Ok(store.get(series_id).and_then(|points| points.last().cloned()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_version_store() {
        let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

        let v1 = store.append("entity1", "data v1".to_string(), "alice", Some("initial")).await.unwrap();
        let v2 = store.append("entity1", "data v2".to_string(), "bob", Some("update")).await.unwrap();

        assert_eq!(v1, 1);
        assert_eq!(v2, 2);

        let latest = store.latest("entity1").await.unwrap().unwrap();
        assert_eq!(latest.version, 2);
        assert_eq!(latest.data, "data v2");

        let v1_data = store.at_version("entity1", 1).await.unwrap().unwrap();
        assert_eq!(v1_data.data, "data v1");
    }

    #[tokio::test]
    async fn test_time_series() {
        let store: InMemoryTimeSeriesStore<f64> = InMemoryTimeSeriesStore::new();

        store.append("cpu", TimePoint::now(0.5)).await.unwrap();
        store.append("cpu", TimePoint::now(0.7)).await.unwrap();
        store.append("cpu", TimePoint::now(0.6)).await.unwrap();

        let latest = store.latest("cpu").await.unwrap().unwrap();
        assert!((latest.value - 0.6).abs() < f64::EPSILON);
    }
}
