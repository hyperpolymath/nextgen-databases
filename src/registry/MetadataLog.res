// SPDX-License-Identifier: PMPL-1.0-or-later
// KRaft-Inspired Metadata Log
// Replicated state machine with Raft consensus

// ============================================================================
// Types
// ============================================================================

type term = int
type index = int
type nodeId = string

type logEntry = {
  term: term,
  index: index,
  command: command,
  timestamp: float,
}

and command =
  | RegisterStore({storeId: string, endpoint: string, modalities: array<string>})
  | UnregisterStore({storeId: string})
  | MapHexad({hexadId: string, locations: Js.Dict.t<Js.Json.t>})
  | UnmapHexad({hexadId: string})
  | UpdateTrust({storeId: string, newTrust: float})
  | NoOp

type nodeRole =
  | Leader
  | Follower
  | Candidate

type nodeState = {
  role: nodeRole,
  currentTerm: term,
  votedFor: option<nodeId>,
  log: array<logEntry>,
  commitIndex: index,
  lastApplied: index,
  // Leader state
  nextIndex: Js.Dict.t<index>,
  matchIndex: Js.Dict.t<index>,
}

type voteRequest = {
  term: term,
  candidateId: nodeId,
  lastLogIndex: index,
  lastLogTerm: term,
}

type voteResponse = {
  term: term,
  voteGranted: bool,
}

type appendEntriesRequest = {
  term: term,
  leaderId: nodeId,
  prevLogIndex: index,
  prevLogTerm: term,
  entries: array<logEntry>,
  leaderCommit: index,
}

type appendEntriesResponse = {
  term: term,
  success: bool,
  matchIndex: index,
}

// ============================================================================
// Node Operations
// ============================================================================

let createNode = (~nodeId: nodeId): nodeState => {
  {
    role: Follower,
    currentTerm: 0,
    votedFor: None,
    log: [],
    commitIndex: 0,
    lastApplied: 0,
    nextIndex: Js.Dict.empty(),
    matchIndex: Js.Dict.empty(),
  }
}

// Append entry to log
let appendEntry = (state: nodeState, command: command): nodeState => {
  let newIndex = Belt.Array.length(state.log) + 1
  let entry: logEntry = {
    term: state.currentTerm,
    index: newIndex,
    command: command,
    timestamp: Js.Date.now(),
  }

  {...state, log: Belt.Array.concat(state.log, [entry])}
}

// Get last log entry
let getLastLogEntry = (state: nodeState): option<logEntry> => {
  Belt.Array.get(state.log, Belt.Array.length(state.log) - 1)
}

// Get last log term
let getLastLogTerm = (state: nodeState): term => {
  switch getLastLogEntry(state) {
  | None => 0
  | Some(entry) => entry.term
  }
}

// Get last log index
let getLastLogIndex = (state: nodeState): index => {
  Belt.Array.length(state.log)
}

// ============================================================================
// Leader Election
// ============================================================================

let becomeCandidate = (state: nodeState): nodeState => {
  {
    ...state,
    role: Candidate,
    currentTerm: state.currentTerm + 1,
    votedFor: None, // Will vote for self
  }
}

let becomeLeader = (state: nodeState, peers: array<nodeId>): nodeState => {
  // Initialize nextIndex and matchIndex for all peers
  let nextIndex = Js.Dict.empty()
  let matchIndex = Js.Dict.empty()

  peers->Belt.Array.forEach(peer => {
    Js.Dict.set(nextIndex, peer, getLastLogIndex(state) + 1)
    Js.Dict.set(matchIndex, peer, 0)
  })

  {
    ...state,
    role: Leader,
    nextIndex: nextIndex,
    matchIndex: matchIndex,
  }
}

let becomeFollower = (state: nodeState, newTerm: term): nodeState => {
  {
    ...state,
    role: Follower,
    currentTerm: newTerm,
    votedFor: None,
  }
}

// Request vote from a follower
let handleVoteRequest = (
  state: nodeState,
  request: voteRequest,
): (nodeState, voteResponse) => {
  let grantVote = if request.term < state.currentTerm {
    false
  } else if request.term > state.currentTerm {
    // Higher term, become follower and grant vote
    true
  } else {
    // Same term
    switch state.votedFor {
    | Some(_) => false // Already voted
    | None => {
        // Check if candidate's log is at least as up-to-date
        let lastLogTerm = getLastLogTerm(state)
        let lastLogIndex = getLastLogIndex(state)

        if request.lastLogTerm > lastLogTerm {
          true
        } else if request.lastLogTerm == lastLogTerm && request.lastLogIndex >= lastLogIndex {
          true
        } else {
          false
        }
      }
    }
  }

  let newState = if grantVote && request.term >= state.currentTerm {
    {...state, currentTerm: request.term, votedFor: Some(request.candidateId)}
  } else if request.term > state.currentTerm {
    becomeFollower(state, request.term)
  } else {
    state
  }

  let response: voteResponse = {
    term: newState.currentTerm,
    voteGranted: grantVote,
  }

  (newState, response)
}

// ============================================================================
// Log Replication
// ============================================================================

let handleAppendEntries = (
  state: nodeState,
  request: appendEntriesRequest,
): (nodeState, appendEntriesResponse) => {
  // Check term
  if request.term < state.currentTerm {
    let response: appendEntriesResponse = {
      term: state.currentTerm,
      success: false,
      matchIndex: 0,
    }
    (state, response)
  } else {
    // Become follower if we were candidate
    let newState = if request.term > state.currentTerm {
      becomeFollower(state, request.term)
    } else {
      state
    }

    // Check if log contains entry at prevLogIndex with prevLogTerm
    let prevEntry = if request.prevLogIndex == 0 {
      Some({term: 0, index: 0, command: NoOp, timestamp: 0.0})
    } else {
      Belt.Array.get(newState.log, request.prevLogIndex - 1)
    }

    switch prevEntry {
    | None => {
        // Log doesn't have entry at prevLogIndex
        let response: appendEntriesResponse = {
          term: newState.currentTerm,
          success: false,
          matchIndex: 0,
        }
        (newState, response)
      }
    | Some(entry) =>
      if entry.term != request.prevLogTerm {
        // Log entry doesn't match
        let response: appendEntriesResponse = {
          term: newState.currentTerm,
          success: false,
          matchIndex: entry.index,
        }
        (newState, response)
      } else {
        // Append new entries
        let logBeforePrev = Belt.Array.slice(newState.log, ~offset=0, ~len=request.prevLogIndex)
        let newLog = Belt.Array.concat(logBeforePrev, request.entries)

        let finalState = {
          ...newState,
          log: newLog,
          commitIndex: Js.Math.min_int(request.leaderCommit, getLastLogIndex({...newState, log: newLog})),
        }

        let response: appendEntriesResponse = {
          term: finalState.currentTerm,
          success: true,
          matchIndex: getLastLogIndex(finalState),
        }

        (finalState, response)
      }
    }
  }
}

// Leader sends AppendEntries to follower
let createAppendEntriesRequest = (
  state: nodeState,
  followerId: nodeId,
): option<appendEntriesRequest> => {
  switch state.role {
  | Leader => {
      let nextIdx = Js.Dict.get(state.nextIndex, followerId)->Belt.Option.getWithDefault(1)

      let prevLogIndex = nextIdx - 1
      let prevLogTerm = if prevLogIndex == 0 {
        0
      } else {
        Belt.Array.get(state.log, prevLogIndex - 1)
        ->Belt.Option.map(e => e.term)
        ->Belt.Option.getWithDefault(0)
      }

      let entries = Belt.Array.sliceToEnd(state.log, nextIdx - 1)

      Some({
        term: state.currentTerm,
        leaderId: "self", // Would be actual node ID
        prevLogIndex: prevLogIndex,
        prevLogTerm: prevLogTerm,
        entries: entries,
        leaderCommit: state.commitIndex,
      })
    }
  | _ => None
  }
}

// ============================================================================
// Commit & Apply
// ============================================================================

let updateCommitIndex = (state: nodeState, peers: array<nodeId>): nodeState => {
  switch state.role {
  | Leader => {
      // Find highest N where majority of matchIndex[i] >= N
      let matchIndices = peers
        ->Belt.Array.map(peer => {
          Js.Dict.get(state.matchIndex, peer)->Belt.Option.getWithDefault(0)
        })
        ->Belt.Array.concat([getLastLogIndex(state)])
        ->Belt.SortArray.stableSortBy((a, b) => b - a)

      let quorumIndex = (Belt.Array.length(peers) + 1) / 2
      let newCommitIndex = Belt.Array.get(matchIndices, quorumIndex)->Belt.Option.getWithDefault(state.commitIndex)

      // Only commit entries from current term
      let canCommit = switch Belt.Array.get(state.log, newCommitIndex - 1) {
      | None => false
      | Some(entry) => entry.term == state.currentTerm
      }

      if canCommit && newCommitIndex > state.commitIndex {
        {...state, commitIndex: newCommitIndex}
      } else {
        state
      }
    }
  | _ => state
  }
}

// Apply committed entries to state machine
let applyCommittedEntries = (state: nodeState): (nodeState, array<command>) => {
  if state.lastApplied >= state.commitIndex {
    (state, [])
  } else {
    let toApply = Belt.Array.slice(
      state.log,
      ~offset=state.lastApplied,
      ~len=state.commitIndex - state.lastApplied,
    )

    let commands = toApply->Belt.Array.map(entry => entry.command)

    ({...state, lastApplied: state.commitIndex}, commands)
  }
}

// ============================================================================
// Public API
// ============================================================================

let create = createNode
let append = appendEntry
let requestVote = handleVoteRequest
let appendEntries = handleAppendEntries
let toCandidate = becomeCandidate
let toLeader = becomeLeader
let toFollower = becomeFollower
let updateCommit = updateCommitIndex
let applyCommitted = applyCommittedEntries
