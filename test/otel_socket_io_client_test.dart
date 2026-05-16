// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.
//
// We exercise the producer / consumer span machinery directly via
// `tracedSocketEmit` and `tracedSocketHandler` — that avoids needing
// a live Socket.IO server.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_socket_io_client/otel_socket_io_client.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;
  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrMap(Span span) => {
      for (final a in span.attributes.toList()) a.key: a.value,
    };

void main() {
  group('Socket.IO instrumentation', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'otel_socket_io_client-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('tracedSocketEmit creates a PRODUCER span with messaging attrs', () {
      var invoked = false;
      tracedSocketEmit<void>(
        event: 'chat:message',
        invoke: () => invoked = true,
      );
      expect(invoked, isTrue);
      expect(exporter.spans, hasLength(1));
      final span = exporter.spans.single;
      expect(span.name, 'chat:message publish');
      expect(span.kind, SpanKind.producer);
      final attrs = _attrMap(span);
      expect(attrs['messaging.system'], 'socket.io');
      expect(attrs['messaging.operation'], 'publish');
      expect(attrs['messaging.destination.name'], 'chat:message');
    });

    test('tracedSocketHandler creates a CONSUMER span on each call', () {
      var received = 0;
      final wrapped = tracedSocketHandler('chat:message', (data) {
        received++;
      });
      wrapped('payload-1');
      wrapped('payload-2');
      expect(received, 2);
      expect(exporter.spans, hasLength(2));
      for (final span in exporter.spans) {
        expect(span.kind, SpanKind.consumer);
        expect(span.name, 'chat:message receive');
      }
    });

    test('error in emit invoke records exception + sets error status', () {
      expect(
        () => tracedSocketEmit<void>(
          event: 'chat:message',
          invoke: () => throw StateError('boom'),
        ),
        throwsA(isA<StateError>()),
      );
      final span = exporter.spans.single;
      expect(span.status, SpanStatusCode.Error);
      expect(_attrMap(span)['error.type'], 'StateError');
    });

    test('error inside handler records exception + sets error status', () {
      final wrapped = tracedSocketHandler('chat:message', (data) {
        throw StateError('handler boom');
      });
      expect(() => wrapped('x'), throwsA(isA<StateError>()));
      final span = exporter.spans.single;
      expect(span.status, SpanStatusCode.Error);
      expect(_attrMap(span)['error.type'], 'StateError');
    });

    test('zone-scoped suppression skips both emit + handler spans', () {
      runWithoutSocketIoClientInstrumentation(() {
        tracedSocketEmit<void>(event: 'a', invoke: () {});
        tracedSocketHandler('b', (_) {})('payload');
      });
      expect(exporter.spans, isEmpty);
    });
  });
}
