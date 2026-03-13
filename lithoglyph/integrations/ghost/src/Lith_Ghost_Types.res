// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Ghost Integration Types
 *
 * Type definitions for Ghost webhook integration
 */

/** Ghost webhook event types */
type webhookEvent =
  | PostPublished
  | PostUpdated
  | PostDeleted
  | PostScheduled
  | PagePublished
  | PageUpdated
  | PageDeleted
  | MemberCreated
  | MemberUpdated
  | MemberDeleted

/** Ghost post */
type ghostPost = {
  id: string,
  uuid: string,
  title: string,
  slug: string,
  html: option<string>,
  plaintext: option<string>,
  featureImage: option<string>,
  featured: bool,
  status: string,
  visibility: string,
  createdAt: string,
  updatedAt: string,
  publishedAt: option<string>,
  customExcerpt: option<string>,
  authors: array<ghostAuthor>,
  tags: array<ghostTag>,
  primaryAuthor: option<ghostAuthor>,
  primaryTag: option<ghostTag>,
}
and ghostAuthor = {
  id: string,
  name: string,
  slug: string,
  email: option<string>,
  profileImage: option<string>,
}
and ghostTag = {
  id: string,
  name: string,
  slug: string,
  description: option<string>,
}

/** Ghost page */
type ghostPage = {
  id: string,
  uuid: string,
  title: string,
  slug: string,
  html: option<string>,
  status: string,
  createdAt: string,
  updatedAt: string,
  publishedAt: option<string>,
}

/** Ghost member */
type ghostMember = {
  id: string,
  uuid: string,
  email: string,
  name: option<string>,
  status: string,
  createdAt: string,
  updatedAt: string,
}

/** Webhook payload */
type webhookPayload = {
  post: option<webhookPostPayload>,
  page: option<webhookPagePayload>,
  member: option<webhookMemberPayload>,
}
and webhookPostPayload = {
  current: ghostPost,
  previous: option<ghostPost>,
}
and webhookPagePayload = {
  current: ghostPage,
  previous: option<ghostPage>,
}
and webhookMemberPayload = {
  current: ghostMember,
  previous: option<ghostMember>,
}

/** Integration configuration */
type integrationConfig = {
  lithUrl: string,
  apiKey: option<string>,
  webhookSecret: option<string>,
  syncPosts: bool,
  syncPages: bool,
  syncMembers: bool,
  postsCollection: string,
  pagesCollection: string,
  membersCollection: string,
}

/** Default configuration */
let defaultConfig: integrationConfig = {
  lithUrl: "http://localhost:8080",
  apiKey: None,
  webhookSecret: None,
  syncPosts: true,
  syncPages: true,
  syncMembers: false,
  postsCollection: "ghost_posts",
  pagesCollection: "ghost_pages",
  membersCollection: "ghost_members",
}

/** Parse webhook event from string */
let parseWebhookEvent = (event: string): option<webhookEvent> =>
  switch event {
  | "post.published" => Some(PostPublished)
  | "post.updated" => Some(PostUpdated)
  | "post.deleted" => Some(PostDeleted)
  | "post.scheduled" => Some(PostScheduled)
  | "page.published" => Some(PagePublished)
  | "page.updated" => Some(PageUpdated)
  | "page.deleted" => Some(PageDeleted)
  | "member.created" => Some(MemberCreated)
  | "member.updated" => Some(MemberUpdated)
  | "member.deleted" => Some(MemberDeleted)
  | _ => None
  }

/** Webhook event to string */
let webhookEventToString = (event: webhookEvent): string =>
  switch event {
  | PostPublished => "post.published"
  | PostUpdated => "post.updated"
  | PostDeleted => "post.deleted"
  | PostScheduled => "post.scheduled"
  | PagePublished => "page.published"
  | PageUpdated => "page.updated"
  | PageDeleted => "page.deleted"
  | MemberCreated => "member.created"
  | MemberUpdated => "member.updated"
  | MemberDeleted => "member.deleted"
  }
