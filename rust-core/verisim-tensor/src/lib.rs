// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Tensor Modality
//!
//! Multi-dimensional array operations via ndarray and Burn.
//! Implements Marr's Computational Level: "What transformations apply?"

use async_trait::async_trait;
use ndarray::{Array, ArrayD, IxDyn};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;

/// Tensor modality errors
#[derive(Error, Debug)]
pub enum TensorError {
    #[error("Shape mismatch: expected {expected:?}, got {actual:?}")]
    ShapeMismatch { expected: Vec<usize>, actual: Vec<usize> },

    #[error("Tensor not found: {0}")]
    NotFound(String),

    #[error("Invalid operation: {0}")]
    InvalidOperation(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Lock poisoned: internal concurrency error")]
    LockPoisoned,
}

/// Data type for tensor elements
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum DType {
    Float32,
    Float64,
    Int32,
    Int64,
    Bool,
}

/// A named tensor with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tensor {
    /// Unique identifier (matches Hexad entity ID)
    pub id: String,
    /// Shape of the tensor
    pub shape: Vec<usize>,
    /// Data type
    pub dtype: DType,
    /// Flattened data (row-major order)
    pub data: Vec<f64>,
    /// Optional metadata
    pub metadata: HashMap<String, String>,
}

impl Tensor {
    /// Create a new tensor from shape and data
    pub fn new(id: impl Into<String>, shape: Vec<usize>, data: Vec<f64>) -> Result<Self, TensorError> {
        let expected_len: usize = shape.iter().product();
        if data.len() != expected_len {
            return Err(TensorError::InvalidOperation(format!(
                "Data length {} doesn't match shape {:?} (expected {})",
                data.len(),
                shape,
                expected_len
            )));
        }
        Ok(Self {
            id: id.into(),
            shape,
            dtype: DType::Float64,
            data,
            metadata: HashMap::new(),
        })
    }

    /// Create a zeros tensor
    pub fn zeros(id: impl Into<String>, shape: Vec<usize>) -> Self {
        let len: usize = shape.iter().product();
        Self {
            id: id.into(),
            shape,
            dtype: DType::Float64,
            data: vec![0.0; len],
            metadata: HashMap::new(),
        }
    }

    /// Create a ones tensor
    pub fn ones(id: impl Into<String>, shape: Vec<usize>) -> Self {
        let len: usize = shape.iter().product();
        Self {
            id: id.into(),
            shape,
            dtype: DType::Float64,
            data: vec![1.0; len],
            metadata: HashMap::new(),
        }
    }

    /// Convert to ndarray
    pub fn to_ndarray(&self) -> ArrayD<f64> {
        let shape = IxDyn(&self.shape);
        // Use C order (row-major) to match data layout documented on line 49
        Array::from_shape_vec(shape, self.data.clone())
            .expect("Shape should match data length")
    }

    /// Create from ndarray
    pub fn from_ndarray(id: impl Into<String>, arr: &ArrayD<f64>) -> Self {
        Self {
            id: id.into(),
            shape: arr.shape().to_vec(),
            dtype: DType::Float64,
            data: arr.iter().copied().collect(),
            metadata: HashMap::new(),
        }
    }

    /// Get number of dimensions
    pub fn ndim(&self) -> usize {
        self.shape.len()
    }

    /// Get total number of elements
    pub fn numel(&self) -> usize {
        self.shape.iter().product()
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.metadata.insert(key.into(), value.into());
        self
    }
}

/// Tensor store trait for cross-modal consistency
#[async_trait]
pub trait TensorStore: Send + Sync {
    /// Store a tensor
    async fn put(&self, tensor: &Tensor) -> Result<(), TensorError>;

    /// Retrieve a tensor by ID
    async fn get(&self, id: &str) -> Result<Option<Tensor>, TensorError>;

    /// Delete a tensor
    async fn delete(&self, id: &str) -> Result<(), TensorError>;

    /// List all tensor IDs
    async fn list(&self) -> Result<Vec<String>, TensorError>;

    /// Apply element-wise operation
    async fn map(&self, id: &str, op: fn(f64) -> f64) -> Result<Tensor, TensorError>;

    /// Reduce along an axis
    async fn reduce(&self, id: &str, axis: usize, op: ReduceOp) -> Result<Tensor, TensorError>;
}

/// Reduction operations
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ReduceOp {
    Sum,
    Mean,
    Max,
    Min,
    Prod,
}

/// In-memory tensor store
pub struct InMemoryTensorStore {
    tensors: Arc<RwLock<HashMap<String, Tensor>>>,
}

impl InMemoryTensorStore {
    pub fn new() -> Self {
        Self {
            tensors: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl Default for InMemoryTensorStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl TensorStore for InMemoryTensorStore {
    async fn put(&self, tensor: &Tensor) -> Result<(), TensorError> {
        self.tensors.write().map_err(|_| TensorError::LockPoisoned)?.insert(tensor.id.clone(), tensor.clone());
        Ok(())
    }

    async fn get(&self, id: &str) -> Result<Option<Tensor>, TensorError> {
        Ok(self.tensors.read().map_err(|_| TensorError::LockPoisoned)?.get(id).cloned())
    }

    async fn delete(&self, id: &str) -> Result<(), TensorError> {
        self.tensors.write().map_err(|_| TensorError::LockPoisoned)?.remove(id);
        Ok(())
    }

    async fn list(&self) -> Result<Vec<String>, TensorError> {
        Ok(self.tensors.read().map_err(|_| TensorError::LockPoisoned)?.keys().cloned().collect())
    }

    async fn map(&self, id: &str, op: fn(f64) -> f64) -> Result<Tensor, TensorError> {
        let tensor = self.tensors.read().map_err(|_| TensorError::LockPoisoned)?
            .get(id)
            .cloned()
            .ok_or_else(|| TensorError::NotFound(id.to_string()))?;

        let new_data: Vec<f64> = tensor.data.iter().map(|&x| op(x)).collect();
        Ok(Tensor {
            id: format!("{}_mapped", tensor.id),
            shape: tensor.shape,
            dtype: tensor.dtype,
            data: new_data,
            metadata: tensor.metadata,
        })
    }

    async fn reduce(&self, id: &str, axis: usize, op: ReduceOp) -> Result<Tensor, TensorError> {
        let tensor = self.tensors.read().map_err(|_| TensorError::LockPoisoned)?
            .get(id)
            .cloned()
            .ok_or_else(|| TensorError::NotFound(id.to_string()))?;

        if axis >= tensor.shape.len() {
            return Err(TensorError::InvalidOperation(format!(
                "Axis {} out of bounds for tensor with {} dimensions",
                axis,
                tensor.shape.len()
            )));
        }

        let arr = tensor.to_ndarray();
        let reduced = match op {
            ReduceOp::Sum => arr.sum_axis(ndarray::Axis(axis)),
            ReduceOp::Mean => arr.mean_axis(ndarray::Axis(axis)).expect("non-empty axis"),
            ReduceOp::Max => {
                arr.map_axis(ndarray::Axis(axis), |lane| {
                    lane.iter().copied().fold(f64::NEG_INFINITY, f64::max)
                })
            }
            ReduceOp::Min => {
                arr.map_axis(ndarray::Axis(axis), |lane| {
                    lane.iter().copied().fold(f64::INFINITY, f64::min)
                })
            }
            ReduceOp::Prod => {
                arr.map_axis(ndarray::Axis(axis), |lane| {
                    lane.iter().copied().product()
                })
            }
        };

        Ok(Tensor::from_ndarray(format!("{}_reduced", tensor.id), &reduced))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_tensor_store() {
        let store = InMemoryTensorStore::new();

        let tensor = Tensor::new("t1", vec![2, 3], vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
        store.put(&tensor).await.unwrap();

        let retrieved = store.get("t1").await.unwrap().unwrap();
        assert_eq!(retrieved.shape, vec![2, 3]);
        assert_eq!(retrieved.data, vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
    }

    #[test]
    fn test_tensor_to_ndarray() {
        let tensor = Tensor::new("t", vec![2, 2], vec![1.0, 2.0, 3.0, 4.0]).unwrap();
        let arr = tensor.to_ndarray();
        assert_eq!(arr.shape(), &[2, 2]);
    }

    #[tokio::test]
    async fn test_reduce_max() {
        let store = InMemoryTensorStore::new();
        // 2x3 tensor: [[1, 5, 3], [4, 2, 6]]
        let tensor = Tensor::new("t_max", vec![2, 3], vec![1.0, 5.0, 3.0, 4.0, 2.0, 6.0]).unwrap();
        store.put(&tensor).await.unwrap();

        // Max along axis 0 → [4, 5, 6]
        let result = store.reduce("t_max", 0, ReduceOp::Max).await.unwrap();
        assert_eq!(result.data, vec![4.0, 5.0, 6.0]);

        // Max along axis 1 → [5, 6]
        let result = store.reduce("t_max", 1, ReduceOp::Max).await.unwrap();
        assert_eq!(result.data, vec![5.0, 6.0]);
    }

    #[tokio::test]
    async fn test_reduce_min() {
        let store = InMemoryTensorStore::new();
        let tensor = Tensor::new("t_min", vec![2, 3], vec![1.0, 5.0, 3.0, 4.0, 2.0, 6.0]).unwrap();
        store.put(&tensor).await.unwrap();

        // Min along axis 0 → [1, 2, 3]
        let result = store.reduce("t_min", 0, ReduceOp::Min).await.unwrap();
        assert_eq!(result.data, vec![1.0, 2.0, 3.0]);
    }

    #[tokio::test]
    async fn test_reduce_prod() {
        let store = InMemoryTensorStore::new();
        let tensor = Tensor::new("t_prod", vec![2, 3], vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).unwrap();
        store.put(&tensor).await.unwrap();

        // Prod along axis 0 → [1*4, 2*5, 3*6] = [4, 10, 18]
        let result = store.reduce("t_prod", 0, ReduceOp::Prod).await.unwrap();
        assert_eq!(result.data, vec![4.0, 10.0, 18.0]);
    }
}
