import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/transport.dart';

void main() {
  test(
    'transport never follows redirects or forwards connection credentials',
    () async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var forwarded = 0;
      target.listen((request) async {
        forwarded++;
        request.response.write('unexpected');
        await request.response.close();
      });
      source.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 307;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${target.port}/leak',
        );
        await request.response.close();
      });
      try {
        final response = await HttpApiTransport().send(
          'GET',
          Uri.parse('http://127.0.0.1:${source.port}/mcp'),
          headers: {'Authorization': 'Bearer private-connection-token'},
          timeout: const Duration(seconds: 5),
        );
        await response.readText();
        expect(response.status, 307);
        expect(forwarded, 0);
      } finally {
        await source.close(force: true);
        await target.close(force: true);
      }
    },
  );
}
