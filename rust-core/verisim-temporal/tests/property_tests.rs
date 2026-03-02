// SPDX-License-Identifier: PMPL-1.0-or-later
//! Property-based tests for temporal modality

use chrono::{Duration, Utc};
use proptest::prelude::*;
use verisim_temporal::{diff, InMemoryTimeSeriesStore, InMemoryVersionStore, TemporalStore, TimePoint, TimeRange, TimeSeriesStore};

/// Generate arbitrary entity IDs
fn arb_entity_id() -> impl Strategy<Value = String> {
    "[a-z]{3,8}-[0-9]{1,4}"
}

/// Generate arbitrary data
fn arb_data() -> impl Strategy<Value = String> {
    "[A-Za-z0-9 ]{10,50}"
}

/// Generate arbitrary author names
fn arb_author() -> impl Strategy<Value = String> {
    "[a-z]{4,10}"
}

proptest! {
    #[test]
    fn test_version_append_increases_version_number(
        entity_id in arb_entity_id(),
        data1 in arb_data(),
        data2 in arb_data(),
        author in arb_author()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

            let v1 = store.append(&entity_id, data1, &author, None).await.unwrap();
            let v2 = store.append(&entity_id, data2, &author, None).await.unwrap();

            prop_assert_eq!(v1, 1);
            prop_assert_eq!(v2, 2);

            Ok(())
        })?;
    }

    #[test]
    fn test_latest_returns_most_recent_version(
        entity_id in arb_entity_id(),
        versions in prop::collection::vec(arb_data(), 1..10),
        author in arb_author()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

            // Append all versions
            for data in &versions {
                store.append(&entity_id, data.clone(), &author, None).await.unwrap();
            }

            // Latest should be the last one
            let latest = store.latest(&entity_id).await.unwrap();
            prop_assert!(latest.is_some());

            let latest = latest.unwrap();
            prop_assert_eq!(latest.version, versions.len() as u64);
            prop_assert_eq!(&latest.data, versions.last().unwrap());

            Ok(())
        })?;
    }

    #[test]
    fn test_at_version_retrieves_specific_version(
        entity_id in arb_entity_id(),
        data1 in arb_data(),
        data2 in arb_data(),
        data3 in arb_data(),
        author in arb_author()
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

            store.append(&entity_id, data1.clone(), &author, None).await.unwrap();
            store.append(&entity_id, data2.clone(), &author, None).await.unwrap();
            store.append(&entity_id, data3.clone(), &author, None).await.unwrap();

            // Check each version
            let v1 = store.at_version(&entity_id, 1).await.unwrap().unwrap();
            let v2 = store.at_version(&entity_id, 2).await.unwrap().unwrap();
            let v3 = store.at_version(&entity_id, 3).await.unwrap().unwrap();

            prop_assert_eq!(v1.data, data1);
            prop_assert_eq!(v2.data, data2);
            prop_assert_eq!(v3.data, data3);

            Ok(())
        })?;
    }

    #[test]
    fn test_history_returns_limited_versions(
        entity_id in arb_entity_id(),
        versions in prop::collection::vec(arb_data(), 5..15),
        author in arb_author(),
        limit in 1usize..10
    ) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

            // Append all versions
            for data in &versions {
                store.append(&entity_id, data.clone(), &author, None).await.unwrap();
            }

            // Get history with limit
            let history = store.history(&entity_id, limit).await.unwrap();

            let expected_count = std::cmp::min(limit, versions.len());
            prop_assert_eq!(history.len(), expected_count);

            // History should be in reverse order (newest first)
            if !history.is_empty() {
                prop_assert_eq!(history[0].version, versions.len() as u64);
            }

            Ok(())
        })?;
    }
}

/// Integration test: time-travel queries
#[tokio::test]
async fn test_time_travel_query() {
    let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();

    let now = Utc::now();
    let entity_id = "doc-123";

    // Create version 1
    tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    let v1_time = Utc::now();
    store.append(entity_id, "version 1".to_string(), "alice", Some("initial")).await.unwrap();

    // Create version 2
    tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    let v2_time = Utc::now();
    store.append(entity_id, "version 2".to_string(), "bob", Some("update")).await.unwrap();

    // Create version 3
    tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    let v3_time = Utc::now();
    store.append(entity_id, "version 3".to_string(), "charlie", Some("final")).await.unwrap();

    // Query before any versions
    let before = store.at_time(entity_id, now).await.unwrap();
    assert!(before.is_none(), "Should have no version before creation");

    // Query at v1 time
    let at_v1 = store.at_time(entity_id, v1_time + Duration::milliseconds(1)).await.unwrap();
    assert_eq!(at_v1.unwrap().data, "version 1");

    // Query at v2 time
    let at_v2 = store.at_time(entity_id, v2_time + Duration::milliseconds(1)).await.unwrap();
    assert_eq!(at_v2.unwrap().data, "version 2");

    // Query at v3 time
    let at_v3 = store.at_time(entity_id, v3_time + Duration::milliseconds(1)).await.unwrap();
    assert_eq!(at_v3.unwrap().data, "version 3");

    // Query after all versions
    let after = store.at_time(entity_id, Utc::now()).await.unwrap();
    assert_eq!(after.unwrap().data, "version 3");
}

/// Integration test: time range queries
#[tokio::test]
async fn test_time_range_query() {
    let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();
    let entity_id = "doc-456";

    let start_time = Utc::now();

    // Create 5 versions with small delays
    for i in 1..=5 {
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        store.append(
            entity_id,
            format!("version {}", i),
            "author",
            Some(&format!("v{}", i))
        ).await.unwrap();
    }

    let end_time = Utc::now();

    // Query all versions in range
    let range = TimeRange::new(start_time, end_time).unwrap();
    let versions = store.in_range(entity_id, &range).await.unwrap();

    assert_eq!(versions.len(), 5, "Should find all 5 versions");

    // Verify they're in order
    for (i, version) in versions.iter().enumerate() {
        assert_eq!(version.version, (i + 1) as u64);
        assert_eq!(version.data, format!("version {}", i + 1));
    }
}

/// Integration test: diff between versions
#[tokio::test]
async fn test_diff_versions() {
    let store: InMemoryVersionStore<String> = InMemoryVersionStore::new();
    let entity_id = "doc-789";

    // Create versions
    store.append(entity_id, "first".to_string(), "alice", None).await.unwrap();
    store.append(entity_id, "second".to_string(), "bob", None).await.unwrap();
    store.append(entity_id, "third".to_string(), "charlie", None).await.unwrap();

    // Diff v1 and v2
    let diff_1_2 = store.diff(entity_id, 1, 2).await.unwrap();
    assert!(diff_1_2.has_change());
    assert_eq!(diff_1_2.old_value(), Some(&"first".to_string()));
    assert_eq!(diff_1_2.new_value(), Some(&"second".to_string()));

    // Diff v1 and v1 (same version)
    let diff_same = store.diff(entity_id, 1, 1).await.unwrap();
    assert!(!diff_same.has_change());

    // Diff v2 and v3
    let diff_2_3 = store.diff(entity_id, 2, 3).await.unwrap();
    assert!(diff_2_3.has_change());
    assert_eq!(diff_2_3.old_value(), Some(&"second".to_string()));
    assert_eq!(diff_2_3.new_value(), Some(&"third".to_string()));
}

/// Integration test: time series
#[tokio::test]
async fn test_time_series_store() {
    let store: InMemoryTimeSeriesStore<f64> = InMemoryTimeSeriesStore::new();
    let series_id = "cpu_usage";

    let start = Utc::now();

    // Append data points
    for i in 0..10 {
        let value = 0.1 * i as f64;
        let point = TimePoint::now(value);
        store.append(series_id, point).await.unwrap();
        tokio::time::sleep(tokio::time::Duration::from_millis(5)).await;
    }

    let end = Utc::now();

    // Query all points
    let range = TimeRange::new(start, end).unwrap();
    let points = store.query(series_id, &range).await.unwrap();

    assert_eq!(points.len(), 10);

    // Verify values
    for (i, point) in points.iter().enumerate() {
        assert!((point.value - 0.1 * i as f64).abs() < f64::EPSILON);
    }

    // Latest should be 0.9
    let latest = store.latest(series_id).await.unwrap().unwrap();
    assert!((latest.value - 0.9).abs() < f64::EPSILON);
}

/// Integration test: time series with labels
#[tokio::test]
async fn test_time_series_with_labels() {
    let store: InMemoryTimeSeriesStore<String> = InMemoryTimeSeriesStore::new();

    let point1 = TimePoint::now("event_1".to_string())
        .with_label("severity", "high")
        .with_label("source", "server-1");

    let point2 = TimePoint::now("event_2".to_string())
        .with_label("severity", "low")
        .with_label("source", "server-2");

    store.append("events", point1).await.unwrap();
    store.append("events", point2).await.unwrap();

    let latest = store.latest("events").await.unwrap().unwrap();
    assert_eq!(latest.value, "event_2");
    assert_eq!(latest.labels.get("severity"), Some(&"low".to_string()));
    assert_eq!(latest.labels.get("source"), Some(&"server-2".to_string()));
}

/// Test diff operations
#[test]
fn test_diff_operations() {
    // No change
    let diff = diff::Diff::no_change("value");
    assert!(!diff.has_change());

    // Changed
    let diff = diff::Diff::changed("old", "new");
    assert!(diff.has_change());
    assert_eq!(diff.old_value(), Some(&"old"));
    assert_eq!(diff.new_value(), Some(&"new"));

    // Added
    let diff: diff::Diff<&str> = diff::Diff::added("new");
    assert!(diff.has_change());
    assert_eq!(diff.old_value(), None);
    assert_eq!(diff.new_value(), Some(&"new"));

    // Removed
    let diff: diff::Diff<&str> = diff::Diff::removed("old");
    assert!(diff.has_change());
    assert_eq!(diff.old_value(), Some(&"old"));
    assert_eq!(diff.new_value(), None);
}
