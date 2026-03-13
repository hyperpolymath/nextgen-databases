// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Ghost Webhook Server
 *
 * Deno HTTP server for receiving Ghost webhooks
 */

open Lith_Ghost_Types
open Lith_Ghost_Webhook

/** Deno serve binding */
@val external serve: ({..} => promise<{..}>, {..}) => unit = "Deno.serve"

/** Create response */
let createResponse = (status: int, body: string): {..} => {
  %raw(`new Response(body, { status: status, headers: { "Content-Type": "application/json" } })`)
}

/** Parse request body */
let parseBody = async (request: {..}): option<Js.Json.t> => {
  try {
    let body = await request["json"]()
    Some(body)
  } catch {
  | _ => None
  }
}

/** Extract event from headers */
let getEventHeader = (request: {..}): option<string> => {
  let headers = request["headers"]
  let event: option<string> = headers["get"]("x-ghost-event")
  event
}

/** Verify webhook signature (simplified) */
let verifySignature = (_request: {..}, _secret: option<string>): bool => {
  // In production, verify HMAC-SHA256 signature
  // x-ghost-signature header contains: sha256=<signature>, t=<timestamp>
  true
}

/** Handle webhook request */
let handleRequest = async (config: integrationConfig, request: {..}): {..} => {
  let method: string = request["method"]
  let url: string = request["url"]

  // Health check endpoint
  if method === "GET" && String.includes(url, "/health") {
    return createResponse(200, `{"status":"ok","service":"lith-ghost"}`)
  }

  // Webhook endpoint
  if method === "POST" && String.includes(url, "/webhook") {
    // Verify signature
    if !verifySignature(request, config.webhookSecret) {
      return createResponse(401, `{"error":"Invalid signature"}`)
    }

    // Get event type
    let eventHeader = getEventHeader(request)
    let event = eventHeader->Option.flatMap(parseWebhookEvent)

    switch event {
    | None =>
      return createResponse(400, `{"error":"Missing or invalid event type"}`)
    | Some(webhookEvent) =>
      // Parse body
      let body = await parseBody(request)

      switch body {
      | None =>
        return createResponse(400, `{"error":"Invalid request body"}`)
      | Some(_json) =>
        // Convert JSON to payload (simplified)
        let payload: webhookPayload = {
          post: None,
          page: None,
          member: None,
        }

        let result = await handleWebhook(config, webhookEvent, payload)

        switch result {
        | Ok() =>
          return createResponse(200, `{"status":"ok","event":"${webhookEventToString(webhookEvent)}"}`)
        | Error(msg) =>
          return createResponse(500, `{"error":"${msg}"}`)
        }
      }
    }
  }

  createResponse(404, `{"error":"Not found"}`)
}

/** Start webhook server */
let startServer = (config: integrationConfig, port: int): unit => {
  let handler = async (request: {..}): {..} => {
    await handleRequest(config, request)
  }

  serve(handler, {"port": port})
  %raw(`console.log("Ghost webhook server running on port " + port)`)
}

/** Main entry point */
let main = (): unit => {
  // Read config from environment
  let config: integrationConfig = {
    lithUrl: %raw(`Deno.env.get("LITH_URL") || "http://localhost:8080"`),
    apiKey: %raw(`Deno.env.get("LITH_API_KEY") || undefined`),
    webhookSecret: %raw(`Deno.env.get("GHOST_WEBHOOK_SECRET") || undefined`),
    syncPosts: true,
    syncPages: true,
    syncMembers: false,
    postsCollection: "ghost_posts",
    pagesCollection: "ghost_pages",
    membersCollection: "ghost_members",
  }

  let port: int = %raw(`parseInt(Deno.env.get("PORT") || "3000", 10)`)
  startServer(config, port)
}

// Run if main module
let _ = main()
