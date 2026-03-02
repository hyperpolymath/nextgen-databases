// SPDX-License-Identifier: PMPL-1.0-or-later
//! Circuit Registry for VeriSimDB ZKP Custom Circuits
//!
//! In-memory registry mapping circuit names to compiled verification functions.
//! Custom circuits allow VQL queries to include `PROOF CUSTOM "circuit-name"
//! WITH (param=value, ...)` clauses that verify application-specific properties.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::RwLock;
use thiserror::Error;

use super::SemanticError;

/// Errors specific to circuit operations
#[derive(Error, Debug)]
pub enum CircuitError {
    #[error("Circuit not found: {0}")]
    NotFound(String),

    #[error("Circuit already registered: {0}")]
    AlreadyExists(String),

    #[error("Compilation failed: {0}")]
    CompilationFailed(String),

    #[error("Verification failed: {0}")]
    VerificationFailed(String),

    #[error("Invalid witness: {0}")]
    InvalidWitness(String),

    #[error("Lock poisoned")]
    LockPoisoned,
}

impl From<CircuitError> for SemanticError {
    fn from(e: CircuitError) -> Self {
        SemanticError::InvalidProof(e.to_string())
    }
}

/// A gate type in the circuit
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum GateType {
    And,
    Or,
    Xor,
    Not,
    /// Linear combination: output = sum(coeff_i * input_i)
    LinearCombination,
}

/// A single constraint in an R1CS system: A * B = C
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct R1CSConstraint {
    /// Left input coefficients (wire_index -> coefficient)
    pub a: HashMap<usize, f64>,
    /// Right input coefficients
    pub b: HashMap<usize, f64>,
    /// Output coefficients
    pub c: HashMap<usize, f64>,
}

/// Intermediate representation for a compiled circuit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitIR {
    /// Circuit name
    pub name: String,
    /// Number of public input wires
    pub num_public_inputs: usize,
    /// Number of private witness wires
    pub num_witness_wires: usize,
    /// Total number of wires (public + witness + internal)
    pub num_wires: usize,
    /// R1CS constraint system
    pub constraints: Vec<R1CSConstraint>,
    /// Parameter names → wire index mapping
    pub parameter_map: HashMap<String, usize>,
}

/// A compiled circuit ready for verification
#[derive(Debug, Clone)]
pub struct CompiledCircuit {
    /// The circuit's intermediate representation
    pub ir: CircuitIR,
    /// SHA-256 hash of the circuit definition (for integrity)
    pub circuit_hash: String,
    /// Verification key (serialized)
    pub verification_key: Vec<u8>,
}

impl CompiledCircuit {
    /// Verify a witness against this circuit's constraints
    pub fn verify(
        &self,
        witness: &[f64],
        public_inputs: &[f64],
    ) -> Result<bool, CircuitError> {
        if public_inputs.len() != self.ir.num_public_inputs {
            return Err(CircuitError::InvalidWitness(format!(
                "Expected {} public inputs, got {}",
                self.ir.num_public_inputs,
                public_inputs.len()
            )));
        }

        let expected_witness_len = self.ir.num_wires - self.ir.num_public_inputs;
        if witness.len() != expected_witness_len {
            return Err(CircuitError::InvalidWitness(format!(
                "Expected {} witness values, got {}",
                expected_witness_len,
                witness.len()
            )));
        }

        // Build the full assignment: [public_inputs | witness]
        let mut assignment: Vec<f64> = Vec::with_capacity(self.ir.num_wires);
        assignment.extend_from_slice(public_inputs);
        assignment.extend_from_slice(witness);

        // Verify each R1CS constraint: A * B = C
        for constraint in &self.ir.constraints {
            let a_val = eval_linear(&constraint.a, &assignment);
            let b_val = eval_linear(&constraint.b, &assignment);
            let c_val = eval_linear(&constraint.c, &assignment);

            let product = a_val * b_val;
            if (product - c_val).abs() > 1e-10 {
                return Ok(false);
            }
        }

        Ok(true)
    }
}

/// Evaluate a linear combination: sum(coeff * assignment[wire])
fn eval_linear(terms: &HashMap<usize, f64>, assignment: &[f64]) -> f64 {
    terms
        .iter()
        .map(|(&wire, &coeff)| coeff * assignment.get(wire).copied().unwrap_or(0.0))
        .sum()
}

/// The circuit registry — manages named circuits
pub struct CircuitRegistry {
    circuits: RwLock<HashMap<String, CompiledCircuit>>,
}

impl CircuitRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self {
            circuits: RwLock::new(HashMap::new()),
        }
    }

    /// Register a compiled circuit
    pub fn register_circuit(
        &self,
        name: &str,
        circuit: CompiledCircuit,
    ) -> Result<(), CircuitError> {
        let mut circuits = self.circuits.write().map_err(|_| CircuitError::LockPoisoned)?;

        if circuits.contains_key(name) {
            return Err(CircuitError::AlreadyExists(name.to_string()));
        }

        circuits.insert(name.to_string(), circuit);
        Ok(())
    }

    /// Get a circuit by name
    pub fn get_circuit(&self, name: &str) -> Result<Option<CompiledCircuit>, CircuitError> {
        let circuits = self.circuits.read().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(circuits.get(name).cloned())
    }

    /// Verify with a named circuit
    pub fn verify_with_circuit(
        &self,
        name: &str,
        witness: &[f64],
        public_inputs: &[f64],
    ) -> Result<bool, CircuitError> {
        let circuits = self.circuits.read().map_err(|_| CircuitError::LockPoisoned)?;

        let circuit = circuits
            .get(name)
            .ok_or_else(|| CircuitError::NotFound(name.to_string()))?;

        circuit.verify(witness, public_inputs)
    }

    /// List all registered circuit names
    pub fn list_circuits(&self) -> Result<Vec<String>, CircuitError> {
        let circuits = self.circuits.read().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(circuits.keys().cloned().collect())
    }

    /// Remove a circuit
    pub fn unregister_circuit(&self, name: &str) -> Result<bool, CircuitError> {
        let mut circuits = self.circuits.write().map_err(|_| CircuitError::LockPoisoned)?;
        Ok(circuits.remove(name).is_some())
    }
}

impl Default for CircuitRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Compute SHA-256 hash of arbitrary bytes, return hex string
pub fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    result.iter().map(|b| format!("{:02x}", b)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_circuit() -> CompiledCircuit {
        // Simple circuit: x * y = z (3 wires, 1 constraint)
        // Layout: [public_inputs..., witness...]
        // Wire 0: x (public input)
        // Wire 1: z (public output)
        // Wire 2: y (witness)
        // Constraint: wire0 * wire2 = wire1 (x * y = z)
        let constraint = R1CSConstraint {
            a: HashMap::from([(0, 1.0)]),  // A = x
            b: HashMap::from([(2, 1.0)]),  // B = y (witness)
            c: HashMap::from([(1, 1.0)]),  // C = z
        };

        let ir = CircuitIR {
            name: "multiply".to_string(),
            num_public_inputs: 2,  // x and z
            num_witness_wires: 1,  // y
            num_wires: 3,
            constraints: vec![constraint],
            parameter_map: HashMap::from([
                ("x".to_string(), 0),
                ("z".to_string(), 1),
            ]),
        };

        let circuit_bytes = serde_json::to_vec(&ir).unwrap();
        let hash = sha256_hex(&circuit_bytes);

        CompiledCircuit {
            ir,
            circuit_hash: hash,
            verification_key: vec![0u8; 32], // Placeholder key
        }
    }

    #[test]
    fn test_register_and_verify() {
        let registry = CircuitRegistry::new();
        let circuit = make_test_circuit();

        registry.register_circuit("multiply", circuit).unwrap();

        // x=3, z=12 → y must be 4 (3 * 4 = 12)
        // Assignment: [x=3, z=12, y=4] → 3 * 4 = 12 ✓
        let public_inputs = &[3.0, 12.0]; // x, z
        let witness = &[4.0];              // y

        let valid = registry.verify_with_circuit("multiply", witness, public_inputs).unwrap();
        assert!(valid);

        // Wrong witness: 3 * 5 = 15 ≠ 12
        let invalid = registry.verify_with_circuit("multiply", &[5.0], public_inputs).unwrap();
        assert!(!invalid);
    }

    #[test]
    fn test_circuit_not_found() {
        let registry = CircuitRegistry::new();
        let result = registry.verify_with_circuit("nonexistent", &[], &[]);
        assert!(matches!(result, Err(CircuitError::NotFound(_))));
    }

    #[test]
    fn test_duplicate_registration() {
        let registry = CircuitRegistry::new();
        let circuit = make_test_circuit();

        registry.register_circuit("multiply", circuit.clone()).unwrap();
        let result = registry.register_circuit("multiply", circuit);
        assert!(matches!(result, Err(CircuitError::AlreadyExists(_))));
    }

    #[test]
    fn test_list_and_unregister() {
        let registry = CircuitRegistry::new();
        let circuit = make_test_circuit();

        registry.register_circuit("mul", circuit).unwrap();
        let list = registry.list_circuits().unwrap();
        assert_eq!(list, vec!["mul"]);

        assert!(registry.unregister_circuit("mul").unwrap());
        assert!(registry.list_circuits().unwrap().is_empty());
    }
}
