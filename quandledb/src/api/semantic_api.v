// SPDX-License-Identifier: PMPL-1.0-or-later

module api

import json
import net.http

pub struct SemanticEntry {
pub:
	knot_name               string
	descriptor_version      string
	descriptor_hash         string
	quandle_key             string
	diagram_format          string
	canonical_representation string
	component_count         int
	crossing_number         int
	writhe                  int
	genus                   ?int
	determinant             ?int
	signature               ?int
	alexander_polynomial    ?string
	jones_polynomial        ?string
	quandle_generator_count ?int
	quandle_relation_count  ?int
	quandle_degree_partition ?string
	colouring_count_3       ?int
	colouring_count_5       ?int
	indexed_at              string
}

pub struct SemanticSummary {
pub:
	descriptor_hash         string
	quandle_key             string
	quandle_generator_count ?int
	quandle_relation_count  ?int
	colouring_count_3       ?int
	colouring_count_5       ?int
}

pub struct SemanticIndexResponse {
pub:
	semantic_index []SemanticEntry
	count          int
	limit          int
	offset         int
}

pub struct SemanticEquivalenceResponse {
pub:
	name                string
	descriptor_hash     string
	quandle_key         string
	strong_candidates   []string
	weak_candidates     []string
	combined_candidates []string
	count               int
}

fn normalize_base_url(base_url string) string {
	if base_url.len > 0 && base_url.ends_with('/') {
		return base_url[..base_url.len - 1]
	}
	return base_url
}

fn get_json[T](url string) !T {
	resp := http.get(url)!
	if resp.status_code != 200 {
		return error('HTTP ${resp.status_code} for ${url}')
	}
	return json.decode(T, resp.body)!
}

fn build_query(params map[string]string) string {
	if params.len == 0 {
		return ''
	}
	mut keys := params.keys()
	keys.sort()
	mut pairs := []string{}
	for key in keys {
		pairs << '${key}=${params[key]}'
	}
	return '?' + pairs.join('&')
}

// fetch_semantic_entry returns the semantic descriptor payload for a knot name.
pub fn fetch_semantic_entry(base_url string, name string) !SemanticEntry {
	base := normalize_base_url(base_url)
	return get_json[SemanticEntry]('${base}/api/semantic/${name}')
}

// fetch_semantic_equivalents returns strong/weak equivalence candidate buckets.
pub fn fetch_semantic_equivalents(base_url string, name string) !SemanticEquivalenceResponse {
	base := normalize_base_url(base_url)
	return get_json[SemanticEquivalenceResponse]('${base}/api/semantic-equivalents/${name}')
}

// fetch_semantic_index lists semantic index rows with optional filter params.
pub fn fetch_semantic_index(base_url string, params map[string]string) !SemanticIndexResponse {
	base := normalize_base_url(base_url)
	query := build_query(params)
	return get_json[SemanticIndexResponse]('${base}/api/semantic${query}')
}
