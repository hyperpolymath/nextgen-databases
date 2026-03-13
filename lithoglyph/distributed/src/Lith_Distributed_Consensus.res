// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Distributed Consensus
 *
 * Raft-based consensus for distributed Lith clusters
 */

/** Log entry type */
type logEntryType =
  | Command(Js.Json.t)
  | Configuration(array<string>)
  | NoOp

/** Log entry */
type logEntry = {
  index: int,
  term: int,
  entryType: logEntryType,
  timestamp: float,
}

/** Raft state */
type raftState =
  | Follower
  | Candidate
  | Leader

/** Vote request */
type voteRequest = {
  term: int,
  candidateId: string,
  lastLogIndex: int,
  lastLogTerm: int,
}

/** Vote response */
type voteResponse = {
  term: int,
  voteGranted: bool,
}

/** Append entries request */
type appendEntriesRequest = {
  term: int,
  leaderId: string,
  prevLogIndex: int,
  prevLogTerm: int,
  entries: array<logEntry>,
  leaderCommit: int,
}

/** Append entries response */
type appendEntriesResponse = {
  term: int,
  success: bool,
  matchIndex: int,
}

/** Consensus node */
type consensusNode = {
  nodeId: string,
  mutable state: raftState,
  mutable currentTerm: int,
  mutable votedFor: option<string>,
  mutable log: array<logEntry>,
  mutable commitIndex: int,
  mutable lastApplied: int,
  // Leader state
  mutable nextIndex: Js.Dict.t<int>,
  mutable matchIndex: Js.Dict.t<int>,
  // Timing
  mutable lastHeartbeat: float,
  electionTimeout: float,
  heartbeatInterval: float,
}

/** Create consensus node */
let make = (
  ~nodeId: string,
  ~electionTimeout: float=5000.0,
  ~heartbeatInterval: float=1000.0,
): consensusNode => {
  {
    nodeId,
    state: Follower,
    currentTerm: 0,
    votedFor: None,
    log: [],
    commitIndex: 0,
    lastApplied: 0,
    nextIndex: Js.Dict.empty(),
    matchIndex: Js.Dict.empty(),
    lastHeartbeat: Js.Date.now(),
    electionTimeout,
    heartbeatInterval,
  }
}

/** Get last log index */
let getLastLogIndex = (node: consensusNode): int => {
  let len = Array.length(node.log)
  if len == 0 {
    0
  } else {
    switch node.log->Array.get(len - 1) {
    | Some(entry) => entry.index
    | None => 0
    }
  }
}

/** Get last log term */
let getLastLogTerm = (node: consensusNode): int => {
  let len = Array.length(node.log)
  if len == 0 {
    0
  } else {
    switch node.log->Array.get(len - 1) {
    | Some(entry) => entry.term
    | None => 0
    }
  }
}

/** Handle vote request */
let handleVoteRequest = (node: consensusNode, request: voteRequest): voteResponse => {
  // Update term if request has higher term
  if request.term > node.currentTerm {
    node.currentTerm = request.term
    node.state = Follower
    node.votedFor = None
  }

  // Check if we can grant vote
  let logOk =
    request.lastLogTerm > getLastLogTerm(node) ||
      (request.lastLogTerm == getLastLogTerm(node) && request.lastLogIndex >= getLastLogIndex(node))

  let canVote = switch node.votedFor {
  | None => true
  | Some(id) => id == request.candidateId
  }

  let voteGranted = request.term >= node.currentTerm && logOk && canVote

  if voteGranted {
    node.votedFor = Some(request.candidateId)
    node.lastHeartbeat = Js.Date.now()
  }

  {term: node.currentTerm, voteGranted}
}

/** Handle append entries */
let handleAppendEntries = (node: consensusNode, request: appendEntriesRequest): appendEntriesResponse => {
  // Update term if request has higher term
  if request.term > node.currentTerm {
    node.currentTerm = request.term
    node.state = Follower
    node.votedFor = None
  }

  // Reset heartbeat timer
  node.lastHeartbeat = Js.Date.now()

  // Reject if term is stale
  if request.term < node.currentTerm {
    {term: node.currentTerm, success: false, matchIndex: 0}
  } else {
    // Check log consistency
    let logConsistent = if request.prevLogIndex == 0 {
      true
    } else {
      switch node.log->Array.get(request.prevLogIndex - 1) {
      | Some(entry) => entry.term == request.prevLogTerm
      | None => false
      }
    }

    if !logConsistent {
      {term: node.currentTerm, success: false, matchIndex: 0}
    } else {
      // Append entries
      request.entries->Array.forEach(entry => {
        // Remove conflicting entries and append new ones
        node.log = node.log->Array.filter(e => e.index < entry.index)
        node.log->Array.push(entry)->ignore
      })

      // Update commit index
      if request.leaderCommit > node.commitIndex {
        let lastNewEntry = getLastLogIndex(node)
        node.commitIndex = min(request.leaderCommit, lastNewEntry)
      }

      {term: node.currentTerm, success: true, matchIndex: getLastLogIndex(node)}
    }
  }
}

/** Start election */
let startElection = (node: consensusNode): voteRequest => {
  node.currentTerm = node.currentTerm + 1
  node.state = Candidate
  node.votedFor = Some(node.nodeId)
  node.lastHeartbeat = Js.Date.now()

  {
    term: node.currentTerm,
    candidateId: node.nodeId,
    lastLogIndex: getLastLogIndex(node),
    lastLogTerm: getLastLogTerm(node),
  }
}

/** Become leader */
let becomeLeader = (node: consensusNode, peers: array<string>): unit => {
  node.state = Leader

  // Initialize next and match indices for all peers
  let lastIndex = getLastLogIndex(node) + 1
  peers->Array.forEach(peer => {
    Js.Dict.set(node.nextIndex, peer, lastIndex)
    Js.Dict.set(node.matchIndex, peer, 0)
  })
}

/** Append command to log (leader only) */
let appendCommand = (node: consensusNode, command: Js.Json.t): option<logEntry> => {
  if node.state != Leader {
    None
  } else {
    let entry = {
      index: getLastLogIndex(node) + 1,
      term: node.currentTerm,
      entryType: Command(command),
      timestamp: Js.Date.now(),
    }
    node.log->Array.push(entry)->ignore
    Some(entry)
  }
}

/** Check if election timeout elapsed */
let electionTimeoutElapsed = (node: consensusNode): bool => {
  Js.Date.now() -. node.lastHeartbeat > node.electionTimeout
}

/** Get state string */
let stateToString = (state: raftState): string => {
  switch state {
  | Follower => "follower"
  | Candidate => "candidate"
  | Leader => "leader"
  }
}
