# otel_socket_io_client

OpenTelemetry instrumentation for
[`package:socket_io_client`](https://pub.dev/packages/socket_io_client).

Wraps Socket.IO `emit` calls in `PRODUCER`-kind spans and `on(...)`
handlers in `CONSUMER`-kind spans following the OTel messaging
semantic conventions (`messaging.system=socket.io`,
`messaging.operation`, `messaging.destination.name=<event>`).

## Install

```yaml
dependencies:
  socket_io_client: ^3.0.0
  otel_socket_io_client: ^0.1.0
```

## Use

```dart
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_socket_io_client/otel_socket_io_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

Future<void> main() async {
  await OTel.initialize(
    serviceName: 'my-app',
  );

  final socket = sio.io('http://localhost:3000');
  socket.connect();

  // Outgoing — PRODUCER span around each emit.
  socket.emitTraced('chat:message', {'text': 'hello'});

  // Incoming — handler runs inside a CONSUMER span.
  socket.onTraced('chat:message', (data) {
    print('got $data');
  });
}
```

For more control, call the helpers directly:

```dart
tracedSocketEmit<void>(
  event: 'chat:message',
  namespace: '/chat',
  invoke: () => socket.emit('chat:message', payload),
);

final wrapped = tracedSocketHandler('chat:message', myHandler);
socket.on('chat:message', wrapped);
```

## Span shape

| OTel attribute                       | Source                          |
|--------------------------------------|---------------------------------|
| `messaging.system`                   | hardcoded `socket.io`           |
| `messaging.operation`                | `publish` (emit) / `receive` (on) |
| `messaging.destination.name`         | the event name                  |
| `messaging.destination.namespace`    | optional `namespace:` argument  |
| `error.type`                         | exception class (on throw)      |

## Suppression

```dart
runWithoutSocketIoClientInstrumentation(() {
  socket.emit('hot-loop-event', payload);  // not spanned
});
```

## License

Apache 2.0 — copyright Mindful Software LLC.
