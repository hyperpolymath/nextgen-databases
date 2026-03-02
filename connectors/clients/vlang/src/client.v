// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// VeriSimDB V Client — Connection configuration, authentication, and HTTP transport.
//
// This module provides the core Client struct used by all other SDK modules to
// communicate with a VeriSimDB server instance. It supports multiple authentication
// methods (API key, Basic, Bearer token, or none) and manages base URL routing,
// request timeouts, and standard HTTP verb helpers (GET, POST, PUT, DELETE).
//
// Usage:
//   import verisimdb_client
//   client := verisimdb_client.new_client('http://localhost:8080')
//   healthy := client.health()!

module verisimdb_client

import net.http
import json
import time

// Auth represents the authentication method for connecting to VeriSimDB.
// VeriSimDB supports API key, HTTP Basic, Bearer token, or unauthenticated access.
pub type Auth = ApiKey | Basic | Bearer | NoAuth

// ApiKey authenticates via an X-API-Key header.
pub struct ApiKey {
pub:
	key string
}

// Basic authenticates via HTTP Basic Authentication (username:password).
pub struct Basic {
pub:
	username string
	password string
}

// Bearer authenticates via an Authorization: Bearer <token> header.
pub struct Bearer {
pub:
	token string
}

// NoAuth indicates no authentication is required.
pub struct NoAuth {}

// Client holds connection configuration for a VeriSimDB server.
//
// Fields:
//   base_url — The root URL of the VeriSimDB API (e.g. "http://localhost:8080/api/v1").
//   timeout  — Request timeout in milliseconds. Defaults to 30000 (30 seconds).
//   auth     — The authentication method to use. Defaults to NoAuth.
pub struct Client {
pub:
	base_url string
	timeout  int  = 30000
	auth     Auth = NoAuth{}
}

// new_client creates a Client with the given base URL and no authentication.
//
// Parameters:
//   base_url — The root API URL of the VeriSimDB instance.
//
// Returns:
//   A configured Client ready for unauthenticated requests.
pub fn new_client(base_url string) Client {
	return Client{
		base_url: base_url.trim_right('/')
		auth: NoAuth{}
	}
}

// new_client_with_auth creates a Client with the given base URL and authentication method.
//
// Parameters:
//   base_url — The root API URL of the VeriSimDB instance.
//   auth     — The Auth variant to use for all requests.
//
// Returns:
//   A configured Client with the specified authentication.
pub fn new_client_with_auth(base_url string, auth Auth) Client {
	return Client{
		base_url: base_url.trim_right('/')
		auth: auth
	}
}

// new_client_with_api_key creates a Client authenticated with an API key.
//
// Parameters:
//   base_url — The root API URL of the VeriSimDB instance.
//   key      — The API key string.
//
// Returns:
//   A configured Client using API key authentication.
pub fn new_client_with_api_key(base_url string, key string) Client {
	return Client{
		base_url: base_url.trim_right('/')
		auth: ApiKey{
			key: key
		}
	}
}

// health checks whether the VeriSimDB server is reachable and healthy.
//
// Sends a GET request to /health and expects a 200 OK response.
//
// Returns:
//   true if the server reports healthy status, or an error on failure.
pub fn (c Client) health() !bool {
	resp := c.do_get('/health')!
	return resp.status_code == 200
}

// do_get sends an authenticated GET request to the given path.
//
// Parameters:
//   path — The API path (appended to base_url), e.g. "/hexads".
//
// Returns:
//   The HTTP response, or an error if the request fails.
fn (c Client) do_get(path string) !http.Response {
	mut config := http.FetchConfig{
		url: c.base_url + path
		method: .get
		header: c.auth_header()
	}
	return http.fetch(config)
}

// do_post sends an authenticated POST request with a JSON body.
//
// Parameters:
//   path — The API path.
//   body — The JSON-encoded request body.
//
// Returns:
//   The HTTP response, or an error if the request fails.
fn (c Client) do_post(path string, body string) !http.Response {
	mut h := c.auth_header()
	h.add(.content_type, 'application/json')
	mut config := http.FetchConfig{
		url: c.base_url + path
		method: .post
		header: h
		data: body
	}
	return http.fetch(config)
}

// do_put sends an authenticated PUT request with a JSON body.
//
// Parameters:
//   path — The API path.
//   body — The JSON-encoded request body.
//
// Returns:
//   The HTTP response, or an error if the request fails.
fn (c Client) do_put(path string, body string) !http.Response {
	mut h := c.auth_header()
	h.add(.content_type, 'application/json')
	mut config := http.FetchConfig{
		url: c.base_url + path
		method: .put
		header: h
		data: body
	}
	return http.fetch(config)
}

// do_delete sends an authenticated DELETE request to the given path.
//
// Parameters:
//   path — The API path.
//
// Returns:
//   The HTTP response, or an error if the request fails.
fn (c Client) do_delete(path string) !http.Response {
	mut config := http.FetchConfig{
		url: c.base_url + path
		method: .delete
		header: c.auth_header()
	}
	return http.fetch(config)
}

// auth_header builds an HTTP header with the appropriate authentication credentials.
//
// Returns:
//   An http.Header populated with auth fields, or an empty header for NoAuth.
fn (c Client) auth_header() http.Header {
	mut h := http.Header{}
	match c.auth {
		ApiKey {
			h.add_custom('X-API-Key', c.auth.key) or {}
		}
		Basic {
			encoded := '${c.auth.username}:${c.auth.password}'.bytes().encode_base64()
			h.add(.authorization, 'Basic ${encoded}')
		}
		Bearer {
			h.add(.authorization, 'Bearer ${c.auth.token}')
		}
		NoAuth {}
	}
	return h
}
