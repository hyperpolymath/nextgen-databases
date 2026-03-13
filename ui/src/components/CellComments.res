// SPDX-License-Identifier: PMPL-1.0-or-later
// Cell comments component with @mention support

type comment = {
  id: string,
  author: string,
  authorId: string,
  content: string,
  mentions: array<string>,
  createdAt: Date.t,
  updatedAt: Date.t,
}

@react.component
let make = (
  ~rowId: string,
  ~fieldId: string,
  ~comments: array<comment>,
  ~onAddComment: string => unit,
  ~onClose: unit => unit,
) => {
  let (newComment, setNewComment) = React.useState(() => "")
  let (showMentionMenu, setShowMentionMenu) = React.useState(() => false)
  let (mentionQuery, setMentionQuery) = React.useState(() => "")

  // Parse @mentions from comment text
  let parseMentions = (text: string): array<string> => {
    let mentionRegex = /@(\w+)/g
    // Extract all @mentions from text
    [] // Placeholder - would need proper regex matching
  }

  let handleSubmitComment = () => {
    if newComment->String.trim != "" {
      onAddComment(newComment)
      setNewComment(_ => "")
    }
  }

  let handleInputChange = (value: string) => {
    setNewComment(_ => value)

    // Detect @mention trigger
    let lastAtIndex = value->String.lastIndexOf("@")
    if lastAtIndex >= 0 {
      let afterAt = value->String.slice(~start=lastAtIndex + 1)
      if afterAt->String.includes(" ") {
        setShowMentionMenu(_ => false)
      } else {
        setShowMentionMenu(_ => true)
        setMentionQuery(_ => afterAt)
      }
    } else {
      setShowMentionMenu(_ => false)
    }
  }

  <div className="cell-comments-panel">
    <div className="comments-header">
      <h3> {React.string("Comments")} </h3>
      <button className="close-button" onClick={_ => onClose()}> {React.string("×")} </button>
    </div>
    <div className="comments-list">
      {if Array.length(comments) == 0 {
        <div className="comments-empty">
          {React.string("No comments yet. Be the first to comment!")}
        </div>
      } else {
        comments
        ->Array.map(comment => {
          <div key={comment.id} className="comment-item">
            <div className="comment-header">
              <span className="comment-author"> {React.string(comment.author)} </span>
              <span className="comment-time">
                {React.string(Date.toISOString(comment.createdAt)->String.slice(~start=0, ~end=16))}
              </span>
            </div>
            <div className="comment-content"> {React.string(comment.content)} </div>
            {if Array.length(comment.mentions) > 0 {
              <div className="comment-mentions">
                {comment.mentions
                ->Array.map(mention => {
                  <span key={mention} className="mention-tag"> {React.string(`@${mention}`)} </span>
                })
                ->React.array}
              </div>
            } else {
              React.null
            }}
          </div>
        })
        ->React.array
      }}
    </div>
    <div className="comments-input-container">
      <textarea
        className="comments-input"
        placeholder="Add a comment... (use @ to mention someone)"
        value={newComment}
        onChange={evt => {
          let value = %raw(`evt.target.value`)
          handleInputChange(value)
        }}
        onKeyDown={evt => {
          if evt->ReactEvent.Keyboard.key == "Enter" && evt->ReactEvent.Keyboard.ctrlKey {
            evt->ReactEvent.Keyboard.preventDefault
            handleSubmitComment()
          }
        }}
      />
      {if showMentionMenu {
        <div className="mention-menu">
          <div className="mention-query"> {React.string(`Searching for: ${mentionQuery}`)} </div>
        </div>
      } else {
        React.null
      }}
      <div className="comments-actions">
        <span className="comment-hint"> {React.string("Ctrl+Enter to submit")} </span>
        <button className="comment-submit-button" onClick={_ => handleSubmitComment()}>
          {React.string("Comment")}
        </button>
      </div>
    </div>
  </div>
}
