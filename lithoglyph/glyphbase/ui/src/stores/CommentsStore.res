// SPDX-License-Identifier: PMPL-1.0-or-later
// Comments store for managing cell comments and mentions

type comment = {
  id: string,
  rowId: string,
  fieldId: string,
  author: string,
  authorId: string,
  content: string,
  mentions: array<string>,
  createdAt: Date.t,
  updatedAt: Date.t,
}

// In-memory store for comments (would be persisted to database)
let commentsMap: ref<dict<array<comment>>> = ref(Dict.make())

// Extract @mentions from comment text
let extractMentions = (text: string): array<string> => {
  // Simple mention extraction (would use proper regex in production)
  let words = text->String.split(" ")
  words
  ->Array.filter(word => word->String.startsWith("@"))
  ->Array.map(word => word->String.slice(~start=1))
}

// Get comments for a specific cell
let getCellComments = (rowId: string, fieldId: string): array<comment> => {
  let key = `${rowId}:${fieldId}`
  commentsMap.contents->Dict.get(key)->Option.getOr([])
}

// Add a comment to a cell
let addComment = (
  rowId: string,
  fieldId: string,
  content: string,
  authorId: string,
  authorName: string,
): comment => {
  let key = `${rowId}:${fieldId}`

  // Extract @mentions from content
  let mentions = extractMentions(content)

  let newComment: comment = {
    id: "comment_" ++ Float.toString(Date.now()),
    rowId,
    fieldId,
    author: authorName,
    authorId,
    content,
    mentions,
    createdAt: Date.make(),
    updatedAt: Date.make(),
  }

  // Add to comments map
  let existingComments = getCellComments(rowId, fieldId)
  let updatedComments = Array.concat(existingComments, [newComment])
  commentsMap.contents->Dict.set(key, updatedComments)

  newComment
}

// Get all mentions for a user across all comments
let getUserMentions = (userId: string): array<comment> => {
  commentsMap.contents
  ->Dict.valuesToArray
  ->Array.flatMap(comments => comments)
  ->Array.filter(comment => comment.mentions->Array.includes(userId))
}

// Get comment count for a cell
let getCellCommentCount = (rowId: string, fieldId: string): int => {
  Array.length(getCellComments(rowId, fieldId))
}

// Delete a comment
let deleteComment = (commentId: string): unit => {
  commentsMap.contents
  ->Dict.toArray
  ->Array.forEach(((key, comments)) => {
    let filtered = comments->Array.filter(c => c.id != commentId)
    commentsMap.contents->Dict.set(key, filtered)
  })
}

// Update a comment
let updateComment = (commentId: string, newContent: string): option<comment> => {
  let found = ref(None)

  commentsMap.contents
  ->Dict.toArray
  ->Array.forEach(((key, comments)) => {
    let updated = comments->Array.map(comment => {
      if comment.id == commentId {
        let updatedComment = {
          ...comment,
          content: newContent,
          mentions: extractMentions(newContent),
          updatedAt: Date.make(),
        }
        found := Some(updatedComment)
        updatedComment
      } else {
        comment
      }
    })
    commentsMap.contents->Dict.set(key, updated)
  })

  found.contents
}

// Get all comments for a row (all cells)
let getRowComments = (rowId: string): array<comment> => {
  commentsMap.contents
  ->Dict.valuesToArray
  ->Array.flatMap(comments => comments)
  ->Array.filter(comment => comment.rowId == rowId)
}
