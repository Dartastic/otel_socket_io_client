// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_socket_io_client/otel_socket_io_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

/// Connects to a Socket.IO server and shows the traced emit / handler
/// surface: `emitTraced` wraps `emit` in a PRODUCER span named
/// `<event> publish`, and `onTraced` wraps each handler invocation in
/// a CONSUMER span named `<event> receive`, both carrying the OTel
/// messaging attributes (`messaging.system=socket.io`,
/// `messaging.destination.name=<event>`).
Future<void> main() async {
  // 1. Bring up OTel first so spans have somewhere to go. With no
  //    arguments beyond serviceName, the SDK exports OTLP to the
  //    default local collector endpoint.
  await OTel.initialize(serviceName: 'socket-io-example');

  // 2. Build the socket exactly as you would without instrumentation.
  final socket = sio.io(
    'http://localhost:3000',
    sio.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build(),
  );

  // 3. `onTraced` in place of `on`: every delivery of `chat:message`
  //    runs inside a CONSUMER span (`chat:message receive`).
  socket.onTraced('chat:message', (data) {
    // Handle the payload; exceptions thrown here are recorded on the
    // span with error.type + ERROR status, then rethrown.
    return null;
  });

  socket.connect();

  // 4. `emitTraced` in place of `emit`: the send runs inside a
  //    PRODUCER span (`chat:message publish`).
  socket.emitTraced('chat:message', {'text': 'hello from OTel'});

  // Lower-level: wrap any callable yourself, e.g. an emitWithAck where
  // you want the span to cover the acknowledgement round-trip.
  tracedSocketEmit<void>(
    event: 'chat:typing',
    operation: 'send',
    invoke: () => socket.emit('chat:typing', {'user': 'demo'}),
  );

  // Zone-scoped suppression: nothing inside the callback produces
  // spans (useful for high-frequency heartbeats).
  runWithoutSocketIoClientInstrumentation(() {
    socket.emitTraced('heartbeat', {'at': DateTime.now().toIso8601String()});
  });

  await Future<void>.delayed(const Duration(seconds: 1));
  socket.dispose();
  await OTel.shutdown();
}
