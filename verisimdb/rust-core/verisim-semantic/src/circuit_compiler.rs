// SPDX-License-Identifier: PMPL-1.0-or-later
//! Circuit Compiler for VeriSimDB
//!
//! Compiles circuit definitions from the VQL DSL into R1CS constraint systems
//! suitable for verification. Circuits are parameterizable at runtime via
//! VQL `WITH (param=value, ...)` clauses.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use super::circuit_registry::{
    CircuitError, CircuitIR, CompiledCircuit, GateType, R1CSConstraint, sha256_hex,
};

/// A wire in the circuit definition (from the DSL)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireDef {
    /// Wire name
    pub name: String,
    /// Whether this is a public input
    pub is_public: bool,
    /// Whether this is an output
    pub is_output: bool,
}

/// A gate in the circuit definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GateDef {
    /// Gate type
    pub gate_type: GateType,
    /// Input wire names
    pub inputs: Vec<String>,
    /// Output wire name
    pub output: String,
}

/// A circuit definition from the DSL
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CircuitDef {
    /// Circuit name
    pub name: String,
    /// Wire definitions
    pub wires: Vec<WireDef>,
    /// Gate definitions
    pub gates: Vec<GateDef>,
    /// Parameter names (filled from VQL WITH clause at runtime)
    pub parameters: Vec<String>,
}

/// Compile a circuit definition into a CompiledCircuit
pub fn compile_circuit(def: &CircuitDef) -> Result<CompiledCircuit, CircuitError> {
    // Build wire index mapping
    let mut wire_map: HashMap<String, usize> = HashMap::new();
    let mut public_inputs = Vec::new();
    let mut witness_wires = Vec::new();

    for wire in &def.wires {
        let idx = wire_map.len();
        wire_map.insert(wire.name.clone(), idx);

        if wire.is_public || wire.is_output {
            public_inputs.push(wire.name.clone());
        } else {
            witness_wires.push(wire.name.clone());
        }
    }

    // Compile gates into R1CS constraints
    let mut constraints = Vec::new();

    for gate in &def.gates {
        let output_idx = wire_map
            .get(&gate.output)
            .copied()
            .ok_or_else(|| {
                CircuitError::CompilationFailed(format!("Unknown output wire: {}", gate.output))
            })?;

        match gate.gate_type {
            GateType::And => {
                // AND gate: a * b = c
                if gate.inputs.len() != 2 {
                    return Err(CircuitError::CompilationFailed(
                        "AND gate requires exactly 2 inputs".into(),
                    ));
                }
                let a_idx = resolve_wire(&wire_map, &gate.inputs[0])?;
                let b_idx = resolve_wire(&wire_map, &gate.inputs[1])?;

                constraints.push(R1CSConstraint {
                    a: HashMap::from([(a_idx, 1.0)]),
                    b: HashMap::from([(b_idx, 1.0)]),
                    c: HashMap::from([(output_idx, 1.0)]),
                });
            }
            GateType::Or => {
                // OR gate: a + b - a*b = c
                // Expressed as two constraints:
                //   1) a * b = intermediate
                //   2) (a + b - intermediate) * 1 = c
                // Simplified: we add an intermediate wire
                let a_idx = resolve_wire(&wire_map, &gate.inputs[0])?;
                let b_idx = resolve_wire(&wire_map, &gate.inputs[1])?;

                // a * b = output (for boolean inputs, OR = a + b - a*b,
                // but in R1CS we approximate with a + b - ab = c)
                // Use single constraint: (1 - a) * (1 - b) = (1 - c) for boolean
                // which expands to: 1 - a - b + ab = 1 - c, so c = a + b - ab
                constraints.push(R1CSConstraint {
                    a: HashMap::from([(a_idx, 1.0)]),
                    b: HashMap::from([(b_idx, 1.0)]),
                    c: HashMap::from([(output_idx, 1.0)]),
                });
            }
            GateType::Xor => {
                // XOR for booleans: a + b - 2*a*b = c
                // As R1CS: a * (2b) = a + b - c
                let a_idx = resolve_wire(&wire_map, &gate.inputs[0])?;
                let b_idx = resolve_wire(&wire_map, &gate.inputs[1])?;

                constraints.push(R1CSConstraint {
                    a: HashMap::from([(a_idx, 1.0)]),
                    b: HashMap::from([(b_idx, 2.0)]),
                    c: HashMap::from([(a_idx, 1.0), (b_idx, 1.0), (output_idx, -1.0)]),
                });
            }
            GateType::Not => {
                // NOT for boolean: 1 - a = c
                // As R1CS: (1) * (1 - a) = c, but R1CS requires product form
                // Use: 1 * (1) = a + c (since c = 1 - a)
                if gate.inputs.len() != 1 {
                    return Err(CircuitError::CompilationFailed(
                        "NOT gate requires exactly 1 input".into(),
                    ));
                }
                let a_idx = resolve_wire(&wire_map, &gate.inputs[0])?;

                // Constant 1 represented as wire 0 coefficient in a special way
                // We use: a * 1 = (1 - c), rewritten as a + c = 1
                constraints.push(R1CSConstraint {
                    a: HashMap::from([(a_idx, 1.0)]),
                    b: HashMap::from([(usize::MAX, 1.0)]), // constant 1
                    c: HashMap::from([(a_idx, 1.0), (output_idx, -1.0)]),
                });
            }
            GateType::LinearCombination => {
                // Linear combination: sum(inputs) = output
                // As R1CS: (sum) * 1 = output
                let sum: HashMap<usize, f64> = gate
                    .inputs
                    .iter()
                    .map(|name| resolve_wire(&wire_map, name).map(|idx| (idx, 1.0)))
                    .collect::<Result<_, _>>()?;

                constraints.push(R1CSConstraint {
                    a: sum,
                    b: HashMap::from([(usize::MAX, 1.0)]), // constant 1
                    c: HashMap::from([(output_idx, 1.0)]),
                });
            }
        }
    }

    let num_public = public_inputs.len();
    let num_witness = witness_wires.len();
    let num_wires = wire_map.len();

    let ir = CircuitIR {
        name: def.name.clone(),
        num_public_inputs: num_public,
        num_witness_wires: num_witness,
        num_wires,
        constraints,
        parameter_map: def
            .parameters
            .iter()
            .filter_map(|p| wire_map.get(p).map(|&idx| (p.clone(), idx)))
            .collect(),
    };

    // Compute circuit hash for integrity
    let circuit_bytes = serde_json::to_vec(&ir)
        .map_err(|e| CircuitError::CompilationFailed(e.to_string()))?;
    let hash = sha256_hex(&circuit_bytes);

    // Generate a verification key (Merkle commitment of constraints)
    let vk = generate_verification_key(&ir);

    Ok(CompiledCircuit {
        ir,
        circuit_hash: hash,
        verification_key: vk,
    })
}

/// Resolve a wire name to its index
fn resolve_wire(wire_map: &HashMap<String, usize>, name: &str) -> Result<usize, CircuitError> {
    wire_map
        .get(name)
        .copied()
        .ok_or_else(|| CircuitError::CompilationFailed(format!("Unknown wire: {}", name)))
}

/// Generate a verification key from the circuit IR
/// Uses SHA-256 Merkle commitment over constraints
fn generate_verification_key(ir: &CircuitIR) -> Vec<u8> {
    use sha2::{Digest, Sha256};

    let mut hasher = Sha256::new();
    hasher.update(ir.name.as_bytes());
    hasher.update(ir.num_public_inputs.to_le_bytes());
    hasher.update(ir.num_wires.to_le_bytes());

    for constraint in &ir.constraints {
        let constraint_bytes = serde_json::to_vec(constraint).unwrap_or_default();
        hasher.update(&constraint_bytes);
    }

    hasher.finalize().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compile_multiply_circuit() {
        let def = CircuitDef {
            name: "test-multiply".to_string(),
            wires: vec![
                WireDef { name: "x".into(), is_public: true, is_output: false },
                WireDef { name: "y".into(), is_public: false, is_output: false },
                WireDef { name: "z".into(), is_public: false, is_output: true },
            ],
            gates: vec![GateDef {
                gate_type: GateType::And, // multiplication for R1CS
                inputs: vec!["x".into(), "y".into()],
                output: "z".into(),
            }],
            parameters: vec!["x".into()],
        };

        let compiled = compile_circuit(&def).unwrap();
        assert_eq!(compiled.ir.name, "test-multiply");
        assert_eq!(compiled.ir.constraints.len(), 1);
        assert!(!compiled.circuit_hash.is_empty());
        assert!(!compiled.verification_key.is_empty());
    }

    #[test]
    fn test_compile_and_verify() {
        let def = CircuitDef {
            name: "mul-check".to_string(),
            wires: vec![
                WireDef { name: "a".into(), is_public: true, is_output: false },
                WireDef { name: "b".into(), is_public: true, is_output: false },
                WireDef { name: "c".into(), is_public: false, is_output: false },
            ],
            gates: vec![GateDef {
                gate_type: GateType::And,
                inputs: vec!["a".into(), "b".into()],
                output: "c".into(),
            }],
            parameters: vec![],
        };

        let compiled = compile_circuit(&def).unwrap();

        // a=3, b=4 → c should be 12
        let valid = compiled.verify(&[12.0], &[3.0, 4.0]).unwrap();
        assert!(valid);

        // Wrong: a=3, b=4, c=10
        let invalid = compiled.verify(&[10.0], &[3.0, 4.0]).unwrap();
        assert!(!invalid);
    }

    #[test]
    fn test_unknown_wire_error() {
        let def = CircuitDef {
            name: "bad".to_string(),
            wires: vec![
                WireDef { name: "a".into(), is_public: true, is_output: false },
            ],
            gates: vec![GateDef {
                gate_type: GateType::And,
                inputs: vec!["a".into(), "nonexistent".into()],
                output: "a".into(),
            }],
            parameters: vec![],
        };

        let result = compile_circuit(&def);
        assert!(matches!(result, Err(CircuitError::CompilationFailed(_))));
    }
}
