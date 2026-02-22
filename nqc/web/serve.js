// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)

/**
 * NQC Web UI — Deno static file server for development.
 *
 * Serves the web UI files on localhost:8000.
 * Implements SPA fallback: any path that doesn't match a file
 * returns index.html (so cadre-router handles client-side routing).
 *
 * Usage:
 *   deno run --allow-net --allow-read serve.js
 *   # or via task:
 *   deno task dev
 */

const DEV_PORT = 8000;

// MIME types for common web assets
const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

/**
 * Determine MIME type from file extension.
 */
function getMimeType(path) {
  const ext = path.substring(path.lastIndexOf("."));
  return MIME_TYPES[ext] || "application/octet-stream";
}

/**
 * Try to read a file relative to the script directory.
 * Returns null if the file doesn't exist.
 */
async function tryReadFile(filePath) {
  try {
    const data = await Deno.readFile(filePath);
    return data;
  } catch {
    return null;
  }
}

/**
 * Handle incoming HTTP requests.
 * Serves static files from the web/ directory.
 * Falls back to index.html for SPA routing.
 */
async function handler(request) {
  const url = new URL(request.url);
  let pathname = url.pathname;

  // Resolve the script's directory (where this file lives)
  const baseDir = new URL(".", import.meta.url).pathname;

  // Try to serve the exact file path
  if (pathname !== "/") {
    const filePath = baseDir + pathname.slice(1); // Remove leading /
    const data = await tryReadFile(filePath);
    if (data) {
      return new Response(data, {
        headers: { "Content-Type": getMimeType(pathname) },
      });
    }
  }

  // SPA fallback — serve index.html for any unmatched path
  // This enables cadre-router client-side routing to work with
  // direct URL navigation (e.g. typing /query/vql in the address bar)
  const indexPath = baseDir + "index.html";
  const indexData = await tryReadFile(indexPath);
  if (indexData) {
    return new Response(indexData, {
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }

  return new Response("Not Found", { status: 404 });
}

console.log(`NQC Web UI dev server on http://localhost:${DEV_PORT}`);
Deno.serve({ port: DEV_PORT }, handler);
