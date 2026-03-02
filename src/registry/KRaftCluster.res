// SPDX-License-Identifier: PMPL-1.0-or-later
// KRaft Cluster Manager
// Drives the Raft consensus lifecycle: elections, heartbeats, client requests,
// and applies committed commands to the Registry state machine.

// ============================================================================
// Cluster Configuration
// ============================================================================

type clusterConfig = {
  nodeId: MetadataLog.nodeId,
  peers: array<MetadataLog.nodeId>,
  electionTimeoutMinMs: int,
  electionTimeoutMaxMs: int,
  heartbeatIntervalMs: int,
  maxBatchSize: int,
}

let defaultConfig = (~nodeId: MetadataLog.nodeId): clusterConfig => {
  {
    nodeId: nodeId,
    peers: [],
    electionTimeoutMinMs: 150,
    electionTimeoutMaxMs: 300,
    heartbeatIntervalMs: 50,
    maxBatchSize: 100,
  }
}

// ============================================================================
// Cluster State
// ============================================================================

type electionTimer = {
  timeoutMs: int,
  elapsedMs: int,
}

type pendingRequest = {
  command: MetadataLog.command,
  index: MetadataLog.index,
  timestamp: float,
}

type clusterState = {
  config: clusterConfig,
  raft: MetadataLog.nodeState,
  registry: Registry.registryState,
  electionTimer: electionTimer,
  votesReceived: array<MetadataLog.nodeId>,
  pendingRequests: array<pendingRequest>,
  leaderId: option<MetadataLog.nodeId>,
  // Metrics
  totalCommitted: int,
  totalApplied: int,
  electionCount: int,
}

// ============================================================================
// Initialization
// ============================================================================

let createCluster = (~config: clusterConfig): clusterState => {
  let registryConfig = Registry.defaultConfig()

  {
    config: config,
    raft: MetadataLog.create(~nodeId=config.nodeId),
    registry: Registry.create(~config=registryConfig),
    electionTimer: {
      timeoutMs: config.electionTimeoutMinMs +
        mod(
          Belt.Int.fromFloat(Js.Date.now()),
          config.electionTimeoutMaxMs - config.electionTimeoutMinMs,
        ),
      elapsedMs: 0,
    },
    votesReceived: [],
    pendingRequests: [],
    leaderId: None,
    totalCommitted: 0,
    totalApplied: 0,
    electionCount: 0,
  }
}

// ============================================================================
// Election Management
// ============================================================================

/// Reset the election timer with a new random timeout.
let resetElectionTimer = (state: clusterState): clusterState => {
  let range = state.config.electionTimeoutMaxMs - state.config.electionTimeoutMinMs
  let jitter = mod(Belt.Int.fromFloat(Js.Date.now()), Js.Math.max_int(range, 1))
  let timeout = state.config.electionTimeoutMinMs + jitter

  {
    ...state,
    electionTimer: {timeoutMs: timeout, elapsedMs: 0},
  }
}

/// Advance the election timer by deltaMs. Returns true if timed out.
let tickElectionTimer = (state: clusterState, deltaMs: int): (clusterState, bool) => {
  let newElapsed = state.electionTimer.elapsedMs + deltaMs
  let timedOut = newElapsed >= state.electionTimer.timeoutMs

  let newState = {
    ...state,
    electionTimer: {...state.electionTimer, elapsedMs: newElapsed},
  }

  (newState, timedOut)
}

/// Start an election: become candidate, vote for self, prepare vote requests.
let startElection = (state: clusterState): (clusterState, array<(MetadataLog.nodeId, MetadataLog.voteRequest)>) => {
  let raft = MetadataLog.toCandidate(state.raft)

  // Vote for self
  let raft = {...raft, votedFor: Some(state.config.nodeId)}

  let voteRequest: MetadataLog.voteRequest = {
    term: raft.currentTerm,
    candidateId: state.config.nodeId,
    lastLogIndex: MetadataLog.getLastLogIndex(raft),
    lastLogTerm: MetadataLog.getLastLogTerm(raft),
  }

  // Prepare requests for all peers
  let requests = state.config.peers->Belt.Array.map(peer => (peer, voteRequest))

  let newState = resetElectionTimer({
    ...state,
    raft: raft,
    votesReceived: [state.config.nodeId], // Self-vote
    electionCount: state.electionCount + 1,
  })

  (newState, requests)
}

/// Handle a vote response from a peer.
let handleVoteResponse = (
  state: clusterState,
  fromPeer: MetadataLog.nodeId,
  response: MetadataLog.voteResponse,
): (clusterState, bool) => {
  // If response term is higher, step down
  if response.term > state.raft.currentTerm {
    let newState = {
      ...state,
      raft: MetadataLog.toFollower(state.raft, response.term),
      votesReceived: [],
      leaderId: None,
    }
    (resetElectionTimer(newState), false)
  } else if response.voteGranted && state.raft.role == Candidate {
    // Count vote
    let newVotes = Belt.Array.concat(state.votesReceived, [fromPeer])
    let totalNodes = Belt.Array.length(state.config.peers) + 1 // +1 for self
    let quorum = totalNodes / 2 + 1
    let wonElection = Belt.Array.length(newVotes) >= quorum

    let newState = if wonElection {
      // Become leader
      let raft = MetadataLog.toLeader(state.raft, state.config.peers)
      // Append NoOp to commit entries from previous terms
      let raft = MetadataLog.append(raft, MetadataLog.NoOp)

      {
        ...state,
        raft: raft,
        votesReceived: newVotes,
        leaderId: Some(state.config.nodeId),
      }
    } else {
      {
        ...state,
        votesReceived: newVotes,
      }
    }

    (newState, wonElection)
  } else {
    (state, false)
  }
}

/// Handle a vote request from a candidate.
let handleVoteRequest = (
  state: clusterState,
  request: MetadataLog.voteRequest,
): (clusterState, MetadataLog.voteResponse) => {
  let (newRaft, response) = MetadataLog.requestVote(state.raft, request)

  let newState = if response.voteGranted {
    resetElectionTimer({...state, raft: newRaft})
  } else {
    {...state, raft: newRaft}
  }

  (newState, response)
}

// ============================================================================
// Log Replication
// ============================================================================

/// Leader creates AppendEntries requests for all followers.
let createHeartbeats = (
  state: clusterState,
): array<(MetadataLog.nodeId, MetadataLog.appendEntriesRequest)> => {
  if state.raft.role != Leader {
    []
  } else {
    state.config.peers->Belt.Array.keepMap(peer => {
      switch MetadataLog.createAppendEntriesRequest(state.raft, peer) {
      | Some(request) => Some((peer, request))
      | None => None
      }
    })
  }
}

/// Handle AppendEntries from a leader.
let handleAppendEntries = (
  state: clusterState,
  request: MetadataLog.appendEntriesRequest,
): (clusterState, MetadataLog.appendEntriesResponse) => {
  let (newRaft, response) = MetadataLog.appendEntries(state.raft, request)

  let newState = if response.success {
    resetElectionTimer({
      ...state,
      raft: newRaft,
      leaderId: Some(request.leaderId),
    })
  } else if request.term >= state.raft.currentTerm {
    resetElectionTimer({
      ...state,
      raft: newRaft,
      leaderId: Some(request.leaderId),
    })
  } else {
    {...state, raft: newRaft}
  }

  (newState, response)
}

/// Leader handles AppendEntries response from a follower.
let handleAppendEntriesResponse = (
  state: clusterState,
  fromPeer: MetadataLog.nodeId,
  response: MetadataLog.appendEntriesResponse,
): clusterState => {
  if response.term > state.raft.currentTerm {
    // Step down
    resetElectionTimer({
      ...state,
      raft: MetadataLog.toFollower(state.raft, response.term),
      leaderId: None,
    })
  } else if state.raft.role == Leader {
    if response.success {
      // Update nextIndex and matchIndex for the follower
      let nextIndex = Js.Dict.fromArray(Js.Dict.entries(state.raft.nextIndex))
      let matchIndex = Js.Dict.fromArray(Js.Dict.entries(state.raft.matchIndex))

      Js.Dict.set(nextIndex, fromPeer, response.matchIndex + 1)
      Js.Dict.set(matchIndex, fromPeer, response.matchIndex)

      let raft = {...state.raft, nextIndex: nextIndex, matchIndex: matchIndex}
      // Try to advance commit index
      let raft = MetadataLog.updateCommit(raft, state.config.peers)

      {...state, raft: raft}
    } else {
      // Decrement nextIndex for the follower and retry
      let nextIndex = Js.Dict.fromArray(Js.Dict.entries(state.raft.nextIndex))
      let currentNext =
        Js.Dict.get(nextIndex, fromPeer)->Belt.Option.getWithDefault(1)
      Js.Dict.set(nextIndex, fromPeer, Js.Math.max_int(currentNext - 1, 1))

      {...state, raft: {...state.raft, nextIndex: nextIndex}}
    }
  } else {
    state
  }
}

// ============================================================================
// Client Request Handling
// ============================================================================

type clientResult =
  | Accepted({index: MetadataLog.index})
  | NotLeader({leaderId: option<MetadataLog.nodeId>})
  | Error({message: string})

/// Propose a command (only succeeds on the leader).
let propose = (state: clusterState, command: MetadataLog.command): (clusterState, clientResult) => {
  switch state.raft.role {
  | Leader => {
      let raft = MetadataLog.append(state.raft, command)
      let index = MetadataLog.getLastLogIndex(raft)

      let pending: pendingRequest = {
        command: command,
        index: index,
        timestamp: Js.Date.now(),
      }

      let newState = {
        ...state,
        raft: raft,
        pendingRequests: Belt.Array.concat(state.pendingRequests, [pending]),
      }

      (newState, Accepted({index: index}))
    }

  | _ => (state, NotLeader({leaderId: state.leaderId}))
  }
}

/// Convenience: propose a store registration.
let proposeRegisterStore = (
  state: clusterState,
  storeId: string,
  endpoint: string,
  modalities: array<string>,
): (clusterState, clientResult) => {
  propose(
    state,
    MetadataLog.RegisterStore({storeId, endpoint, modalities}),
  )
}

/// Convenience: propose updating a store's trust level.
let proposeUpdateTrust = (
  state: clusterState,
  storeId: string,
  newTrust: float,
): (clusterState, clientResult) => {
  propose(
    state,
    MetadataLog.UpdateTrust({storeId, newTrust}),
  )
}

/// Convenience: propose a hexad mapping.
let proposeMapHexad = (
  state: clusterState,
  hexadId: string,
  locations: Js.Dict.t<Js.Json.t>,
): (clusterState, clientResult) => {
  propose(
    state,
    MetadataLog.MapHexad({hexadId, locations}),
  )
}

// ============================================================================
// State Machine Application
// ============================================================================

/// Apply a single committed command to the Registry state machine.
let applyCommand = (registry: Registry.registryState, command: MetadataLog.command): Registry.registryState => {
  switch command {
  | RegisterStore({storeId, endpoint, modalities}) => {
      let modalityTypes =
        modalities->Belt.Array.keepMap(m => Registry.modalityFromString(m))
      Registry.register(registry, storeId, endpoint, modalityTypes)
    }

  | UnregisterStore({storeId}) => {
      // Remove store from registry
      let newStores = Js.Dict.fromArray(
        Js.Dict.entries(registry.stores)->Belt.Array.keep(((id, _)) => id != storeId),
      )
      {...registry, stores: newStores}
    }

  | MapHexad({hexadId, locations}) => {
      // Convert JSON locations to storeLocation dict
      // In production, would deserialize properly
      Registry.map(registry, hexadId, Js.Dict.empty())
    }

  | UnmapHexad({hexadId}) => {
      let newMappings = Js.Dict.fromArray(
        Js.Dict.entries(registry.mappings)->Belt.Array.keep(((id, _)) => id != hexadId),
      )
      {...registry, mappings: newMappings}
    }

  | UpdateTrust({storeId, newTrust: _}) => {
      // Trust updates go through health update mechanism
      // The newTrust is applied during health checks
      registry
    }

  | NoOp => registry
  }
}

/// Apply all committed but unapplied entries to the Registry.
let applyCommitted = (state: clusterState): clusterState => {
  let (newRaft, commands) = MetadataLog.applyCommitted(state.raft)

  let newRegistry = commands->Belt.Array.reduce(state.registry, (reg, cmd) => {
    applyCommand(reg, cmd)
  })

  // Remove fulfilled pending requests
  let newPending = state.pendingRequests->Belt.Array.keep(req => {
    req.index > newRaft.lastApplied
  })

  {
    ...state,
    raft: newRaft,
    registry: newRegistry,
    pendingRequests: newPending,
    totalApplied: state.totalApplied + Belt.Array.length(commands),
    totalCommitted: Js.Math.max_int(state.totalCommitted, newRaft.commitIndex),
  }
}

// ============================================================================
// Tick — Main Loop Driver
// ============================================================================

type tickAction =
  | SendVoteRequests(array<(MetadataLog.nodeId, MetadataLog.voteRequest)>)
  | SendAppendEntries(array<(MetadataLog.nodeId, MetadataLog.appendEntriesRequest)>)
  | BecameLeader
  | AppliedEntries({count: int})
  | NoAction

/// Advance the cluster by deltaMs. Returns the new state and any actions to perform.
let tick = (state: clusterState, deltaMs: int): (clusterState, array<tickAction>) => {
  let actions = []

  // 1. Advance election timer (followers and candidates only)
  let (state, actions) = switch state.raft.role {
  | Follower | Candidate => {
      let (state, timedOut) = tickElectionTimer(state, deltaMs)

      if timedOut {
        let (state, voteRequests) = startElection(state)
        (state, Belt.Array.concat(actions, [SendVoteRequests(voteRequests)]))
      } else {
        (state, actions)
      }
    }

  | Leader => {
      // Leaders don't use election timers; they send heartbeats
      let heartbeats = createHeartbeats(state)

      if Belt.Array.length(heartbeats) > 0 {
        (state, Belt.Array.concat(actions, [SendAppendEntries(heartbeats)]))
      } else {
        (state, actions)
      }
    }
  }

  // 2. Apply committed entries
  let prevApplied = state.raft.lastApplied
  let state = applyCommitted(state)
  let appliedCount = state.raft.lastApplied - prevApplied

  let actions = if appliedCount > 0 {
    Belt.Array.concat(actions, [AppliedEntries({count: appliedCount})])
  } else {
    actions
  }

  (state, actions)
}

// ============================================================================
// Cluster Diagnostics
// ============================================================================

type clusterDiagnostics = {
  nodeId: MetadataLog.nodeId,
  role: string,
  currentTerm: MetadataLog.term,
  commitIndex: MetadataLog.index,
  lastApplied: MetadataLog.index,
  logLength: int,
  peerCount: int,
  leaderId: option<MetadataLog.nodeId>,
  registeredStores: int,
  mappedHexads: int,
  totalCommitted: int,
  totalApplied: int,
  electionCount: int,
  pendingRequests: int,
}

let diagnostics = (state: clusterState): clusterDiagnostics => {
  let roleStr = switch state.raft.role {
  | Leader => "leader"
  | Follower => "follower"
  | Candidate => "candidate"
  }

  {
    nodeId: state.config.nodeId,
    role: roleStr,
    currentTerm: state.raft.currentTerm,
    commitIndex: state.raft.commitIndex,
    lastApplied: state.raft.lastApplied,
    logLength: Belt.Array.length(state.raft.log),
    peerCount: Belt.Array.length(state.config.peers),
    leaderId: state.leaderId,
    registeredStores: Belt.Array.length(Js.Dict.keys(state.registry.stores)),
    mappedHexads: Belt.Array.length(Js.Dict.keys(state.registry.mappings)),
    totalCommitted: state.totalCommitted,
    totalApplied: state.totalApplied,
    electionCount: state.electionCount,
    pendingRequests: Belt.Array.length(state.pendingRequests),
  }
}

// ============================================================================
// Public API
// ============================================================================

let create = createCluster
let election = startElection
let vote = handleVoteRequest
let voteResult = handleVoteResponse
let replicate = handleAppendEntries
let replicateResult = handleAppendEntriesResponse
let heartbeats = createHeartbeats
let submit = propose
let submitRegister = proposeRegisterStore
let submitTrust = proposeUpdateTrust
let submitMap = proposeMapHexad
let apply = applyCommitted
let advance = tick
let status = diagnostics
