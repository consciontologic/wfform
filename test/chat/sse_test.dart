import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/sse.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

void main() {
  test(
    'every UTF8 byte boundary, BOM, CRLF, comments and multiline data',
    () async {
      final input = utf8.encode(
        '\uFEFF: keepalive\r\nid: 1\r\nevent: message\r\ndata: {"answer":\r\ndata: "çilek 🍓"}\r\n\r\ndata: [DONE]\r\n\r\n',
      );
      for (var size = 1; size < 16; size++) {
        final chunks = <List<int>>[];
        for (var i = 0; i < input.length; i += size) {
          chunks.add(
            input.sublist(i, i + size > input.length ? input.length : i + size),
          );
        }
        expect(await decodeSse(Stream.fromIterable(chunks)).toList(), [
          '{"answer":\n"çilek 🍓"}',
          '[DONE]',
        ]);
      }
    },
  );

  test('rejects torn event instead of presenting it as complete', () async {
    final parsed = decodeSse(Stream.value(utf8.encode('data: incomplete')));
    await expectLater(
      parsed,
      emitsError(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.stream),
      ),
    );
  });

  test('caps individual SSE events', () async {
    await expectLater(
      decodeSse(
        Stream.value(utf8.encode('data: 0123456789\n\n')),
        maxEventChars: 5,
      ),
      emitsError(isA<AppFailure>().having((e) => e.field, 'field', 'SSE.data')),
    );
  });

  test(
    'cancels while awaiting more bytes and cancels upstream subscription',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final token = CancelToken();
      final expectation = expectLater(
        decodeSse(source.stream, cancel: token),
        emitsError(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectation;
      expect(cancelled, isTrue);
      await source.close();
    },
  );

  test('does not start an already cancelled stream', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      decodeSse(Stream.value([65]), cancel: token),
      emitsError(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      ),
    );
  });
}
