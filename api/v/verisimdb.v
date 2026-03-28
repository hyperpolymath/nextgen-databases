// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V-lang API — Cross-modal entity consistency engine client.
module verisimdb

pub enum OctadField {
	name
	description
	provenance
	temporal
	spatial
	relational
	categorical
	metric
}

pub struct Octad {
pub:
	id          string
	fields      map[string]string
	version     int
	created_at  i64
	modified_at i64
}

pub struct DriftReport {
pub:
	entity_id   string
	field       OctadField
	old_value   string
	new_value   string
	drift_score f64 // 0.0 = identical, 1.0 = completely changed
}

fn C.verisimdb_store_octad(id_ptr &u8, data_ptr &u8, data_len int) int
fn C.verisimdb_get_octad(id_ptr &u8, out_ptr &&u8, out_len &int) int
fn C.verisimdb_detect_drift(id_ptr &u8) int
fn C.verisimdb_clamp_drift_score(score f64) f64

// store saves an octad to VeriSimDB.
pub fn store(id string, data []u8) !int {
	result := C.verisimdb_store_octad(id.str, data.data, data.len)
	if result != 0 {
		return error('store failed: ${result}')
	}
	return result
}

// detect_drift checks for entity drift on a given ID.
pub fn detect_drift(id string) bool {
	return C.verisimdb_detect_drift(id.str) == 1
}

// clamp_drift_score ensures drift is within [0.0, 1.0].
pub fn clamp_drift_score(score f64) f64 {
	return C.verisimdb_clamp_drift_score(score)
}
