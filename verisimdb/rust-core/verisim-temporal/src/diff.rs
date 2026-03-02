// SPDX-License-Identifier: PMPL-1.0-or-later
//! Diff functionality for comparing versions

use serde::{Deserialize, Serialize};
use std::fmt;

/// Represents a difference between two versions
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum Diff<T> {
    /// No changes between versions
    NoChange {
        value: T,
    },
    /// Value changed from old to new
    Changed {
        old: T,
        new: T,
    },
    /// Value was added (didn't exist before)
    Added {
        value: T,
    },
    /// Value was removed (existed before, doesn't now)
    Removed {
        value: T,
    },
}

impl<T> Diff<T> {
    /// Create a diff for no change
    pub fn no_change(value: T) -> Self {
        Diff::NoChange { value }
    }

    /// Create a diff for changed value
    pub fn changed(old: T, new: T) -> Self {
        Diff::Changed { old, new }
    }

    /// Create a diff for added value
    pub fn added(value: T) -> Self {
        Diff::Added { value }
    }

    /// Create a diff for removed value
    pub fn removed(value: T) -> Self {
        Diff::Removed { value }
    }

    /// Check if there's a change
    pub fn has_change(&self) -> bool {
        !matches!(self, Diff::NoChange { .. })
    }

    /// Get the new value if it exists
    pub fn new_value(&self) -> Option<&T> {
        match self {
            Diff::NoChange { value } => Some(value),
            Diff::Changed { new, .. } => Some(new),
            Diff::Added { value } => Some(value),
            Diff::Removed { .. } => None,
        }
    }

    /// Get the old value if it exists
    pub fn old_value(&self) -> Option<&T> {
        match self {
            Diff::NoChange { value } => Some(value),
            Diff::Changed { old, .. } => Some(old),
            Diff::Added { .. } => None,
            Diff::Removed { value } => Some(value),
        }
    }
}

impl<T: fmt::Display> fmt::Display for Diff<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Diff::NoChange { value } => write!(f, "= {}", value),
            Diff::Changed { old, new } => write!(f, "- {}\n+ {}", old, new),
            Diff::Added { value } => write!(f, "+ {}", value),
            Diff::Removed { value } => write!(f, "- {}", value),
        }
    }
}

/// Error type for diff comparison failures
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiffError {
    /// Both old and new values are absent — nothing to compare.
    IncomparableValues,
}

impl fmt::Display for DiffError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DiffError::IncomparableValues => write!(f, "Cannot compare two None values"),
        }
    }
}

impl std::error::Error for DiffError {}

/// Compare two optional values and produce a diff.
///
/// Returns `Err(DiffError::IncomparableValues)` when both values are `None`.
pub fn compare_values<T: Clone + PartialEq>(
    old: Option<&T>,
    new: Option<&T>,
) -> Result<Diff<T>, DiffError> {
    match (old, new) {
        (Some(old_val), Some(new_val)) => {
            if old_val == new_val {
                Ok(Diff::no_change(old_val.clone()))
            } else {
                Ok(Diff::changed(old_val.clone(), new_val.clone()))
            }
        }
        (Some(old_val), None) => Ok(Diff::removed(old_val.clone())),
        (None, Some(new_val)) => Ok(Diff::added(new_val.clone())),
        (None, None) => Err(DiffError::IncomparableValues),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_diff_no_change() {
        let diff = Diff::no_change("value");
        assert!(!diff.has_change());
        assert_eq!(diff.new_value(), Some(&"value"));
        assert_eq!(diff.old_value(), Some(&"value"));
    }

    #[test]
    fn test_diff_changed() {
        let diff = Diff::changed("old", "new");
        assert!(diff.has_change());
        assert_eq!(diff.new_value(), Some(&"new"));
        assert_eq!(diff.old_value(), Some(&"old"));
    }

    #[test]
    fn test_diff_added() {
        let diff: Diff<&str> = Diff::added("new");
        assert!(diff.has_change());
        assert_eq!(diff.new_value(), Some(&"new"));
        assert_eq!(diff.old_value(), None);
    }

    #[test]
    fn test_diff_removed() {
        let diff: Diff<&str> = Diff::removed("old");
        assert!(diff.has_change());
        assert_eq!(diff.new_value(), None);
        assert_eq!(diff.old_value(), Some(&"old"));
    }

    #[test]
    fn test_compare_values_same() {
        let old_val = "value".to_string();
        let new_val = "value".to_string();
        let diff = compare_values(Some(&old_val), Some(&new_val)).unwrap();
        assert!(!diff.has_change());
    }

    #[test]
    fn test_compare_values_changed() {
        let old_val = "old".to_string();
        let new_val = "new".to_string();
        let diff = compare_values(Some(&old_val), Some(&new_val)).unwrap();
        assert!(diff.has_change());
        assert_eq!(diff, Diff::Changed { old: "old".to_string(), new: "new".to_string() });
    }

    #[test]
    fn test_compare_values_added() {
        let new_val = "new".to_string();
        let diff = compare_values(None, Some(&new_val)).unwrap();
        assert_eq!(diff, Diff::Added { value: "new".to_string() });
    }

    #[test]
    fn test_compare_values_removed() {
        let old_val = "old".to_string();
        let diff = compare_values(Some(&old_val), None).unwrap();
        assert_eq!(diff, Diff::Removed { value: "old".to_string() });
    }

    #[test]
    fn test_compare_values_both_none() {
        let result = compare_values::<String>(None, None);
        assert_eq!(result, Err(DiffError::IncomparableValues));
    }
}
