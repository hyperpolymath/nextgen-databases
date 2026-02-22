// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

/**
 * NQC CORS Proxy — Deno HTTP server
 *
 * Listens on localhost:4000 and forwards requests to the appropriate
 * NextGen database engine based on the URL path.
 *
 * Routing:
 *   /api/{dbId}/*  →  localhost:{port}/*
 *
 * Port mapping (mirrors Database.res builtins):
 *   vql  → 8080  (VeriSimDB)
 *   gql  → 8081  (Lithoglyph)
 *   kql  → 8082  (QuandleDB)
 *
 * The proxy adds CORS headers to every response so the browser
 * can communicate with database engines running on different ports.
 *
 * Usage:
 *   deno run --allow-net proxy/server.js
 *   # or via task:
 *   deno task proxy
 */

// Database ID → port mapping.
// Keep in sync with Database.res builtins.
const PORT_MAP = {
  vql: 8080,
  gql: 8081,
  kql: 8082,
};

// CORS headers added to every proxied response
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

/**
 * Handle a single incoming request.
 *
 * 1. If it's an OPTIONS preflight, respond immediately with CORS headers.
 * 2. Parse the URL to extract the database ID from /api/{dbId}/...
 * 3. Look up the target port from PORT_MAP.
 * 4. Forward the request to localhost:{port}/{remainder}.
 * 5. Return the response with added CORS headers.
 */
async function handler(request) {
  const url = new URL(request.url);

  // Handle CORS preflight
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // Parse route: /api/{dbId}/{...rest}
  const match = url.pathname.match(/^\/api\/([a-z]+)(\/.*)?$/);
  if (!match) {
    return new Response(
      JSON.stringify({ error: "Invalid path. Expected /api/{dbId}/..." }),
      {
        status: 400,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      },
    );
  }

  const dbId = match[1];
  const rest = match[2] || "/";

  // Look up port
  const port = PORT_MAP[dbId];
  if (!port) {
    return new Response(
      JSON.stringify({
        error: `Unknown database: ${dbId}. Known: ${Object.keys(PORT_MAP).join(", ")}`,
      }),
      {
        status: 404,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      },
    );
  }

  // Build target URL
  const targetUrl = `http://localhost:${port}${rest}${url.search}`;

  try {
    // Forward the request — preserve method, headers, and body
    const forwardHeaders = new Headers(request.headers);
    // Remove host header to avoid confusing the backend
    forwardHeaders.delete("host");

    const response = await fetch(targetUrl, {
      method: request.method,
      headers: forwardHeaders,
      body: request.body,
    });

    // Clone response and add CORS headers
    const responseHeaders = new Headers(response.headers);
    for (const [key, value] of Object.entries(CORS_HEADERS)) {
      responseHeaders.set(key, value);
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders,
    });
  } catch (err) {
    // Database engine is unreachable
    return new Response(
      JSON.stringify({
        error: `Failed to reach ${dbId} at localhost:${port}: ${err.message}`,
      }),
      {
        status: 502,
        headers: { "Content-Type": "application/json", ...CORS_HEADERS },
      },
    );
  }
}

// Start the proxy server
const PROXY_PORT = 4000;
console.log(`NQC CORS Proxy listening on http://localhost:${PROXY_PORT}`);
console.log(`Forwarding: ${Object.entries(PORT_MAP).map(([id, port]) => `${id} → :${port}`).join(", ")}`);

Deno.serve({ port: PROXY_PORT }, handler);
