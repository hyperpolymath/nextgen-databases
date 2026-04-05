// SPDX-License-Identifier: PMPL-1.0-or-later

module api

import json

fn test_build_query_is_stable() {
	params := {
		'quandle_key': '2:2:3,3:9:9'
		'limit':       '25'
		'offset':      '0'
	}
	query := build_query(params)
	assert query == '?limit=25&offset=0&quandle_key=2:2:3,3:9:9'
}

fn test_semantic_equivalence_response_decode() {
	payload := '{"name":"3_1","descriptor_hash":"abc","quandle_key":"3:3:2,2,2:9:9","strong_candidates":["3_1"],"weak_candidates":["3_1","6_1"],"combined_candidates":["3_1","6_1"],"count":2}'
	decoded := json.decode(SemanticEquivalenceResponse, payload) or {
		panic(err)
	}
	assert decoded.name == '3_1'
	assert decoded.strong_candidates.len == 1
	assert decoded.combined_candidates.len == 2
}
