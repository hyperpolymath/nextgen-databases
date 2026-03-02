// SPDX-License-Identifier: PMPL-1.0-or-later
// VeriSimDB V API Gateway
//
// Unified REST + GraphQL gateway proxying to the Rust core (data operations)
// and Elixir orchestration layer (telemetry, status). Built using the
// v-ecosystem v-api-interfaces patterns.
//
// Architecture:
//   Client → V Gateway (port 9090) → Rust core (port 8080)
//                                   → Elixir orch (port 4080)

module main

import json
import net.http
import os
import time

// --- Configuration ---

struct Config {
	gateway_port int    = 9090
	rust_url     string = 'http://localhost:8080/api/v1'
	orch_url     string = 'http://localhost:4080'
}

fn load_config() Config {
	port_str := os.getenv_opt('VERISIM_GATEWAY_PORT') or { '9090' }
	return Config{
		gateway_port: port_str.int()
		rust_url:     os.getenv_opt('VERISIM_RUST_URL') or { 'http://localhost:8080/api/v1' }
		orch_url:     os.getenv_opt('VERISIM_ORCH_URL') or { 'http://localhost:4080' }
	}
}

// --- Proxy Layer ---
// Forwards requests to the appropriate backend (Rust core or Elixir orchestration).

fn proxy_get(url string) !string {
	resp := http.get(url)!
	if resp.status_code >= 400 {
		return error('backend returned ${resp.status_code}: ${resp.body}')
	}
	return resp.body
}

fn proxy_post_json(url string, payload string) !string {
	mut config := http.FetchConfig{
		url:    url
		method: .post
		data:   payload
	}
	config.header.add(.content_type, 'application/json')
	resp := http.fetch(config)!
	if resp.status_code >= 400 {
		return error('backend returned ${resp.status_code}: ${resp.body}')
	}
	return resp.body
}

// --- GraphQL request parsing ---

struct GraphqlRequest {
	query     string            @[json: 'query']
	variables map[string]string @[json: 'variables']
}

// --- Gateway Handler ---
// Implements the net.http.Handler interface for the V HTTP server.

struct Gateway {
	config Config
}

fn (mut g Gateway) handle(req http.Request) http.Response {
	// CORS headers on all responses
	mut headers := http.new_header(
		key:   .content_type
		value: 'application/json'
	)
	headers.add_custom('Access-Control-Allow-Origin', '*') or {}
	headers.add_custom('Access-Control-Allow-Methods', 'GET, POST, OPTIONS') or {}
	headers.add_custom('Access-Control-Allow-Headers', 'Content-Type') or {}

	// OPTIONS preflight
	if req.method == .options {
		return http.Response{
			status_code: 204
			header:      headers
		}
	}

	url := req.url

	// --- REST endpoints ---

	// Combined health: gateway + rust + elixir
	if url == '/api/v1/health' && req.method == .get {
		return g.handle_health(headers)
	}

	// Hexad CRUD — proxy to Rust core
	if url.starts_with('/api/v1/hexads') && req.method == .get {
		return g.proxy_to_rust(url.replace('/api/v1', ''), headers)
	}
	if url == '/api/v1/hexads' && req.method == .post {
		return g.proxy_post_to_rust('/hexads', req.data, headers)
	}

	// VQL execution — proxy to Rust core
	if url == '/api/v1/vql/execute' && req.method == .post {
		return g.proxy_post_to_rust('/vql/execute', req.data, headers)
	}

	// Drift — proxy to Rust core
	if url.starts_with('/api/v1/drift/') && req.method == .get {
		return g.proxy_to_rust(url.replace('/api/v1', ''), headers)
	}

	// Search — proxy to Rust core
	if url.starts_with('/api/v1/search/') {
		if req.method == .get {
			return g.proxy_to_rust(url.replace('/api/v1', ''), headers)
		}
		if req.method == .post {
			return g.proxy_post_to_rust(url.replace('/api/v1', ''), req.data, headers)
		}
	}

	// Provenance — proxy to Rust core
	if url.starts_with('/api/v1/provenance/') && req.method == .get {
		return g.proxy_to_rust(url.replace('/api/v1', ''), headers)
	}

	// Spatial — proxy to Rust core
	if url.starts_with('/api/v1/spatial/') && req.method == .post {
		return g.proxy_post_to_rust(url.replace('/api/v1', ''), req.data, headers)
	}

	// Telemetry — proxy to Elixir orchestration
	if url.starts_with('/api/v1/telemetry') && req.method == .get {
		path := url.replace('/api/v1/telemetry', '/telemetry')
		effective_path := if path == '' { '/telemetry' } else { path }
		return g.proxy_to_orch(effective_path, headers)
	}

	// Status — proxy to Elixir orchestration
	if url == '/api/v1/status' && req.method == .get {
		return g.proxy_to_orch('/status', headers)
	}

	// --- GraphQL endpoint ---

	if url == '/graphql' && req.method == .post {
		return g.do_handle_graphql(req.data, headers)
	}

	// --- 404 ---
	return http.Response{
		status_code: 404
		body:        '{"error":"not_found","message":"Unknown endpoint: ${url}"}'
		header:      headers
	}
}

// --- Health (combined) ---

fn (g Gateway) handle_health(headers http.Header) http.Response {
	mut rust_status := 'unreachable'
	mut orch_status := 'unreachable'

	// Check Rust core
	rust_body := proxy_get('${g.config.rust_url}/health') or { '' }
	if rust_body.len > 0 {
		rust_status = 'ok'
	}

	// Check Elixir orchestration
	orch_body := proxy_get('${g.config.orch_url}/health') or { '' }
	if orch_body.len > 0 {
		orch_status = 'ok'
	}

	overall := if rust_status == 'ok' && orch_status == 'ok' {
		'healthy'
	} else if rust_status == 'ok' || orch_status == 'ok' {
		'degraded'
	} else {
		'unhealthy'
	}

	body := '{"status":"${overall}","gateway":"ok","rust_core":"${rust_status}","orchestration":"${orch_status}","timestamp":"${time.now().format_rfc3339()}"}'

	return http.Response{
		status_code: 200
		body:        body
		header:      headers
	}
}

// --- Proxy helpers ---

fn (g Gateway) proxy_to_rust(path string, headers http.Header) http.Response {
	body := proxy_get('${g.config.rust_url}${path}') or {
		return http.Response{
			status_code: 502
			body:        '{"error":"backend_unavailable","message":"Rust core unreachable: ${err.msg()}"}'
			header:      headers
		}
	}
	return http.Response{
		status_code: 200
		body:        body
		header:      headers
	}
}

fn (g Gateway) proxy_post_to_rust(path string, payload string, headers http.Header) http.Response {
	body := proxy_post_json('${g.config.rust_url}${path}', payload) or {
		return http.Response{
			status_code: 502
			body:        '{"error":"backend_unavailable","message":"Rust core unreachable: ${err.msg()}"}'
			header:      headers
		}
	}
	return http.Response{
		status_code: 200
		body:        body
		header:      headers
	}
}

fn (g Gateway) proxy_to_orch(path string, headers http.Header) http.Response {
	body := proxy_get('${g.config.orch_url}${path}') or {
		return http.Response{
			status_code: 502
			body:        '{"error":"backend_unavailable","message":"Orchestration layer unreachable: ${err.msg()}"}'
			header:      headers
		}
	}
	return http.Response{
		status_code: 200
		body:        body
		header:      headers
	}
}

// --- GraphQL Handler ---
// Minimal GraphQL implementation: parses the query field and routes to
// appropriate backend operations. Supports queries and mutations.

fn (g Gateway) do_handle_graphql(data string, headers http.Header) http.Response {
	// Parse the GraphQL request body: { "query": "...", "variables": {} }
	gql_req := json.decode(GraphqlRequest, data) or {
		return http.Response{
			status_code: 400
			body:        '{"errors":[{"message":"Invalid JSON body"}]}'
			header:      headers
		}
	}

	query := gql_req.query

	if query.len == 0 {
		return http.Response{
			status_code: 400
			body:        '{"errors":[{"message":"Missing or empty query field"}]}'
			header:      headers
		}
	}

	// Route based on query content (simplified field routing)
	if query.contains('health') {
		health_resp := g.handle_health(headers)
		return http.Response{
			status_code: 200
			body:        '{"data":{"health":${health_resp.body}}}'
			header:      headers
		}
	}

	if query.contains('telemetry') {
		tel_body := proxy_get('${g.config.orch_url}/telemetry') or {
			return http.Response{
				status_code: 200
				body:        '{"data":{"telemetry":null},"errors":[{"message":"Telemetry unavailable: ${err.msg()}"}]}'
				header:      headers
			}
		}
		return http.Response{
			status_code: 200
			body:        '{"data":{"telemetry":${tel_body}}}'
			header:      headers
		}
	}

	if query.contains('hexads') || query.contains('hexad') {
		hexads_body := proxy_get('${g.config.rust_url}/hexads?limit=20&offset=0') or {
			return http.Response{
				status_code: 200
				body:        '{"data":{"hexads":null},"errors":[{"message":"Hexads unavailable: ${err.msg()}"}]}'
				header:      headers
			}
		}
		return http.Response{
			status_code: 200
			body:        '{"data":{"hexads":${hexads_body}}}'
			header:      headers
		}
	}

	if query.contains('executeVql') || query.contains('mutation') {
		// Extract VQL query from variables
		vql_query := gql_req.variables['query'] or {
			return http.Response{
				status_code: 200
				body:        '{"errors":[{"message":"VQL mutation requires variables.query"}]}'
				header:      headers
			}
		}
		payload := '{"query":"${vql_query}"}'
		result := proxy_post_json('${g.config.rust_url}/vql/execute', payload) or {
			return http.Response{
				status_code: 200
				body:        '{"data":{"executeVql":null},"errors":[{"message":"VQL execution failed: ${err.msg()}"}]}'
				header:      headers
			}
		}
		return http.Response{
			status_code: 200
			body:        '{"data":{"executeVql":${result}}}'
			header:      headers
		}
	}

	if query.contains('driftScore') {
		entity_id := gql_req.variables['entityId'] or {
			return http.Response{
				status_code: 200
				body:        '{"errors":[{"message":"driftScore requires variables.entityId"}]}'
				header:      headers
			}
		}
		drift_body := proxy_get('${g.config.rust_url}/drift/entity/${entity_id}') or {
			return http.Response{
				status_code: 200
				body:        '{"data":{"driftScore":null},"errors":[{"message":"Drift unavailable: ${err.msg()}"}]}'
				header:      headers
			}
		}
		return http.Response{
			status_code: 200
			body:        '{"data":{"driftScore":${drift_body}}}'
			header:      headers
		}
	}

	// Unsupported query
	return http.Response{
		status_code: 200
		body:        '{"errors":[{"message":"Unrecognised query. Supported: health, telemetry, hexads, driftScore, executeVql"}]}'
		header:      headers
	}
}

// --- Main ---

fn main() {
	config := load_config()

	println('VeriSimDB V API Gateway')
	println('  REST + GraphQL on port ${config.gateway_port}')
	println('  Rust core backend:     ${config.rust_url}')
	println('  Elixir orchestration:  ${config.orch_url}')
	println('')
	println('Endpoints:')
	println('  REST:    http://localhost:${config.gateway_port}/api/v1/')
	println('  GraphQL: http://localhost:${config.gateway_port}/graphql')
	println('')

	mut server := http.Server{
		addr:    ':${config.gateway_port}'
		handler: &Gateway{
			config: config
		}
	}

	server.listen_and_serve()
}
