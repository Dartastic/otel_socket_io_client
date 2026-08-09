# Changelog

## [0.2.0-wip]

## [0.1.0] - 2026-08-10

### Added

- `tracedSocketEmit<T>(...)` — runs an emit-style invocation inside
  a PRODUCER-kind span with OTel messaging conventions
  (`messaging.system=socket.io`, `messaging.operation=publish`,
  `messaging.destination.name=<event>`).
- `tracedSocketHandler(event, handler)` — wraps a Socket.IO event
  handler so each invocation runs inside a CONSUMER-kind span.
- `Socket.emitTraced(...)` / `Socket.onTraced(...)` extension methods
  as drop-in replacements for `emit` / `on`.
- Local `SocketIoSemantics` enum (implements `OTelSemantic`) for the
  `messaging.operation` / `messaging.destination.name` /
  `messaging.destination.namespace` keys.
- Error path records `error.type`, calls `recordException`, sets the
  span status to `Error` before rethrowing.
- Zone-scoped suppression via
  `runWithoutSocketIoClientInstrumentation()`.
