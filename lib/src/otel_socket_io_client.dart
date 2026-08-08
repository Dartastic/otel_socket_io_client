// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'otel_socket_io_client_suppression.dart';

/// Local copy of `socket_io_common`'s `EventHandler` typedef. The
/// upstream type lives inside `socket_io_common/src/`, which would
/// trigger the `implementation_imports` lint to reference directly.
typedef EventHandler = dynamic Function(dynamic data);

const _tracerName = 'otel_socket_io_client';
const _messagingSystem = 'socket.io';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Typed attribute keys for Socket.IO instrumentation. The OTel
/// messaging semantic conventions define these names; we use a local
/// enum implementing [OTelSemantic] until the SDK adds them directly.
enum SocketIoSemantics implements OTelSemantic {
  /// `messaging.operation` — publish / receive / process.
  messagingOperation('messaging.operation'),

  /// `messaging.destination.name` — the Socket.IO event name.
  messagingDestinationName('messaging.destination.name'),

  /// `messaging.destination.namespace` — Socket.IO namespace (e.g.
  /// `/chat`), when known.
  messagingDestinationNamespace('messaging.destination.namespace');

  const SocketIoSemantics(this.key);

  @override
  final String key;

  @override
  String toString() => key;
}

Attributes _attrs({
  required String event,
  required String operation,
  String? namespace,
}) =>
    OTel.attributesFromMap(<String, Object>{
      Messaging.messagingSystem.key: _messagingSystem,
      SocketIoSemantics.messagingOperation.key: operation,
      SocketIoSemantics.messagingDestinationName.key: event,
      if (namespace != null)
        SocketIoSemantics.messagingDestinationNamespace.key: namespace,
    });

/// Emit a Socket.IO message inside a PRODUCER-kind span.
///
/// Span name follows the OTel messaging conventions: `<event> publish`.
/// The span is closed synchronously after [invoke] returns — Socket.IO
/// fire-and-forget emits don't acknowledge by default, so there's no
/// asynchronous "delivered" signal to wait for. (If you call
/// `emitWithAck(...)`, prefer wrapping that with [tracedSocketEmit] +
/// `operation: 'send'` and ending the span inside the ack callback.)
///
/// Exceptions thrown by [invoke] are recorded and rethrown.
T tracedSocketEmit<T>({
  required String event,
  required T Function() invoke,
  String? namespace,
  String operation = 'publish',
}) {
  if (socketIoClientInstrumentationSuppressed()) return invoke();
  final span = _tracer().startSpan(
    '$event $operation',
    kind: SpanKind.producer,
    attributes: _attrs(
      event: event,
      operation: operation,
      namespace: namespace,
    ),
  );
  try {
    return invoke();
  } catch (e, st) {
    span.addAttributes(
      OTel.attributes([
        OTel.attributeString(
          ErrorAttributes.errorType.key,
          e.runtimeType.toString(),
        ),
      ]),
    );
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Wrap a Socket.IO event [handler] so each invocation runs inside a
/// CONSUMER-kind span. Span name follows the OTel messaging
/// conventions: `<event> receive`.
EventHandler tracedSocketHandler(
  String event,
  EventHandler handler, {
  String? namespace,
}) {
  return (dynamic data) {
    if (socketIoClientInstrumentationSuppressed()) {
      return handler(data);
    }
    final span = _tracer().startSpan(
      '$event receive',
      kind: SpanKind.consumer,
      attributes: _attrs(
        event: event,
        operation: 'receive',
        namespace: namespace,
      ),
    );
    try {
      return handler(data);
    } catch (e, st) {
      span.addAttributes(
        OTel.attributes([
          OTel.attributeString(
            ErrorAttributes.errorType.key,
            e.runtimeType.toString(),
          ),
        ]),
      );
      span.recordException(e, stackTrace: st);
      span.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span.end();
    }
  };
}

/// Traced operations on [sio.Socket]. Use [emitTraced] and
/// [onTraced] in place of `emit` / `on` to get producer / consumer
/// spans automatically.
extension OTelSocket on sio.Socket {
  /// Emits [event] with [data] inside a PRODUCER span.
  void emitTraced(String event, [dynamic data]) {
    tracedSocketEmit<void>(
      event: event,
      invoke: () => emit(event, data),
    );
  }

  /// Binds [handler] to [event] as a CONSUMER-span-wrapped listener.
  /// Returns the unsubscribe function returned by [on].
  void Function() onTraced(String event, EventHandler handler) {
    return on(event, tracedSocketHandler(event, handler));
  }
}
