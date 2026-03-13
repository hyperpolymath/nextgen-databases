// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Graceful Shutdown
 *
 * Coordinated shutdown with connection draining and cleanup
 */

/** Shutdown phase */
type shutdownPhase =
  | Running
  | DrainConnections
  | FlushBuffers
  | CloseResources
  | Terminated

/** Shutdown handler */
type shutdownHandler = {
  name: string,
  priority: int,
  handler: unit => promise<unit>,
}

/** Shutdown coordinator */
type shutdownCoordinator = {
  mutable phase: shutdownPhase,
  mutable handlers: array<shutdownHandler>,
  mutable isShuttingDown: bool,
  timeoutMs: float,
}

/** Create shutdown coordinator */
let make = (~timeoutMs: float=30000.0): shutdownCoordinator => {
  {
    phase: Running,
    handlers: [],
    isShuttingDown: false,
    timeoutMs,
  }
}

/** Register shutdown handler */
let register = (
  coordinator: shutdownCoordinator,
  name: string,
  ~priority: int=50,
  handler: unit => promise<unit>,
): unit => {
  coordinator.handlers->Array.push({name, priority, handler})->ignore
  // Sort by priority (lower runs first)
  coordinator.handlers->Array.sort((a, b) => a.priority - b.priority)
}

/** Get current phase */
let getPhase = (coordinator: shutdownCoordinator): shutdownPhase => {
  coordinator.phase
}

/** Check if shutting down */
let isShuttingDown = (coordinator: shutdownCoordinator): bool => {
  coordinator.isShuttingDown
}

/** Execute shutdown sequence */
let shutdown = async (coordinator: shutdownCoordinator): unit => {
  if coordinator.isShuttingDown {
    // Already shutting down
    ()
  } else {
    coordinator.isShuttingDown = true

    // Phase 1: Drain connections
    coordinator.phase = DrainConnections
    // Would stop accepting new connections here

    // Phase 2: Flush buffers
    coordinator.phase = FlushBuffers
    // Would flush any pending writes

    // Phase 3: Close resources
    coordinator.phase = CloseResources

    // Run all handlers in priority order
    for i in 0 to Array.length(coordinator.handlers) - 1 {
      switch coordinator.handlers->Array.get(i) {
      | Some({handler, _}) => {
          try {
            await handler()
          } catch {
          | _ => () // Log but continue
          }
        }
      | None => ()
      }
    }

    // Phase 4: Terminated
    coordinator.phase = Terminated
  }
}

/** Phase to string */
let phaseToString = (phase: shutdownPhase): string => {
  switch phase {
  | Running => "running"
  | DrainConnections => "drain_connections"
  | FlushBuffers => "flush_buffers"
  | CloseResources => "close_resources"
  | Terminated => "terminated"
  }
}

/** Get status */
let getStatus = (coordinator: shutdownCoordinator): Js.Dict.t<Js.Json.t> => {
  let obj = Js.Dict.empty()
  Js.Dict.set(obj, "phase", Js.Json.string(phaseToString(coordinator.phase)))
  Js.Dict.set(obj, "isShuttingDown", Js.Json.boolean(coordinator.isShuttingDown))
  Js.Dict.set(obj, "handlerCount", Js.Json.number(Int.toFloat(Array.length(coordinator.handlers))))
  Js.Dict.set(obj, "timeoutMs", Js.Json.number(coordinator.timeoutMs))
  obj
}

/** Global coordinator */
let globalCoordinator: shutdownCoordinator = make()

/** Register global handler */
let onShutdown = (name: string, ~priority: int=50, handler: unit => promise<unit>): unit => {
  register(globalCoordinator, name, ~priority, handler)
}

/** Initiate global shutdown */
let initiateShutdown = async (): unit => {
  await shutdown(globalCoordinator)
}
