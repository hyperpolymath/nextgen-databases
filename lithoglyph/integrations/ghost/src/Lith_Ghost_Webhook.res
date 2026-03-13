// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Ghost Webhook Handler
 *
 * HTTP handler for Ghost webhook events
 */

open Lith_Ghost_Types

/** Node.js fetch binding */
@val external fetch: (string, {..}) => promise<{..}> = "fetch"

/** Lith client */
type lithClient = {
  insert: (string, Js.Json.t) => promise<unit>,
  update: (string, Js.Json.t, string) => promise<unit>,
  delete: (string, string) => promise<unit>,
}

/** Create Lith client */
let makeClient = (config: integrationConfig): lithClient => {
  let headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
  }

  let headersWithAuth = switch config.apiKey {
  | Some(key) => {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-API-Key": key,
    }
  | None => headers
  }

  let request = async (method: string, path: string, body: option<Js.Json.t>): Js.Json.t => {
    let url = config.lithUrl ++ path
    let options = switch body {
    | Some(b) => {
        "method": method,
        "headers": headersWithAuth,
        "body": Js.Json.stringify(b),
      }
    | None => {
        "method": method,
        "headers": headersWithAuth,
      }
    }

    let response = await fetch(url, options)
    let json = await response["json"]()
    json
  }

  {
    insert: async (collection: string, document: Js.Json.t): unit => {
      let fdql = `INSERT INTO ${collection} ${Js.Json.stringify(document)}`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let _ = await request("POST", "/v1/query", Some(body))
      ()
    },

    update: async (collection: string, document: Js.Json.t, id: string): unit => {
      let setClause = Js.Json.stringify(document)
      let fdql = `UPDATE ${collection} SET ${setClause} WHERE id = "${id}"`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let _ = await request("POST", "/v1/query", Some(body))
      ()
    },

    delete: async (collection: string, id: string): unit => {
      let fdql = `DELETE FROM ${collection} WHERE id = "${id}"`
      let body = Js.Json.object_(Js.Dict.fromArray([("fdql", Js.Json.string(fdql))]))
      let _ = await request("POST", "/v1/query", Some(body))
      ()
    },
  }
}

/** Convert Ghost post to JSON */
let postToJson = (post: ghostPost): Js.Json.t => {
  let dict = Js.Dict.empty()
  Js.Dict.set(dict, "id", Js.Json.string(post.id))
  Js.Dict.set(dict, "uuid", Js.Json.string(post.uuid))
  Js.Dict.set(dict, "title", Js.Json.string(post.title))
  Js.Dict.set(dict, "slug", Js.Json.string(post.slug))
  Js.Dict.set(dict, "status", Js.Json.string(post.status))
  Js.Dict.set(dict, "visibility", Js.Json.string(post.visibility))
  Js.Dict.set(dict, "featured", Js.Json.boolean(post.featured))
  Js.Dict.set(dict, "createdAt", Js.Json.string(post.createdAt))
  Js.Dict.set(dict, "updatedAt", Js.Json.string(post.updatedAt))

  post.html->Option.forEach(v => Js.Dict.set(dict, "html", Js.Json.string(v)))
  post.plaintext->Option.forEach(v => Js.Dict.set(dict, "plaintext", Js.Json.string(v)))
  post.featureImage->Option.forEach(v => Js.Dict.set(dict, "featureImage", Js.Json.string(v)))
  post.publishedAt->Option.forEach(v => Js.Dict.set(dict, "publishedAt", Js.Json.string(v)))
  post.customExcerpt->Option.forEach(v => Js.Dict.set(dict, "customExcerpt", Js.Json.string(v)))

  Js.Json.object_(dict)
}

/** Convert Ghost page to JSON */
let pageToJson = (page: ghostPage): Js.Json.t => {
  let dict = Js.Dict.empty()
  Js.Dict.set(dict, "id", Js.Json.string(page.id))
  Js.Dict.set(dict, "uuid", Js.Json.string(page.uuid))
  Js.Dict.set(dict, "title", Js.Json.string(page.title))
  Js.Dict.set(dict, "slug", Js.Json.string(page.slug))
  Js.Dict.set(dict, "status", Js.Json.string(page.status))
  Js.Dict.set(dict, "createdAt", Js.Json.string(page.createdAt))
  Js.Dict.set(dict, "updatedAt", Js.Json.string(page.updatedAt))

  page.html->Option.forEach(v => Js.Dict.set(dict, "html", Js.Json.string(v)))
  page.publishedAt->Option.forEach(v => Js.Dict.set(dict, "publishedAt", Js.Json.string(v)))

  Js.Json.object_(dict)
}

/** Convert Ghost member to JSON */
let memberToJson = (member: ghostMember): Js.Json.t => {
  let dict = Js.Dict.empty()
  Js.Dict.set(dict, "id", Js.Json.string(member.id))
  Js.Dict.set(dict, "uuid", Js.Json.string(member.uuid))
  Js.Dict.set(dict, "email", Js.Json.string(member.email))
  Js.Dict.set(dict, "status", Js.Json.string(member.status))
  Js.Dict.set(dict, "createdAt", Js.Json.string(member.createdAt))
  Js.Dict.set(dict, "updatedAt", Js.Json.string(member.updatedAt))

  member.name->Option.forEach(v => Js.Dict.set(dict, "name", Js.Json.string(v)))

  Js.Json.object_(dict)
}

/** Handle webhook event */
let handleWebhook = async (
  config: integrationConfig,
  event: webhookEvent,
  payload: webhookPayload,
): result<unit, string> => {
  let client = makeClient(config)

  try {
    switch event {
    | PostPublished | PostUpdated =>
      if config.syncPosts {
        switch payload.post {
        | Some({current}) =>
          await client.update(config.postsCollection, postToJson(current), current.id)
        | None => ()
        }
      }

    | PostDeleted =>
      if config.syncPosts {
        switch payload.post {
        | Some({current}) =>
          await client.delete(config.postsCollection, current.id)
        | None => ()
        }
      }

    | PostScheduled =>
      if config.syncPosts {
        switch payload.post {
        | Some({current}) =>
          await client.insert(config.postsCollection, postToJson(current))
        | None => ()
        }
      }

    | PagePublished | PageUpdated =>
      if config.syncPages {
        switch payload.page {
        | Some({current}) =>
          await client.update(config.pagesCollection, pageToJson(current), current.id)
        | None => ()
        }
      }

    | PageDeleted =>
      if config.syncPages {
        switch payload.page {
        | Some({current}) =>
          await client.delete(config.pagesCollection, current.id)
        | None => ()
        }
      }

    | MemberCreated =>
      if config.syncMembers {
        switch payload.member {
        | Some({current}) =>
          await client.insert(config.membersCollection, memberToJson(current))
        | None => ()
        }
      }

    | MemberUpdated =>
      if config.syncMembers {
        switch payload.member {
        | Some({current}) =>
          await client.update(config.membersCollection, memberToJson(current), current.id)
        | None => ()
        }
      }

    | MemberDeleted =>
      if config.syncMembers {
        switch payload.member {
        | Some({current}) =>
          await client.delete(config.membersCollection, current.id)
        | None => ()
        }
      }
    }
    Ok()
  } catch {
  | Js.Exn.Error(e) =>
    let msg = Js.Exn.message(e)->Option.getOr("Unknown error")
    Error(`Webhook handler failed: ${msg}`)
  }
}
