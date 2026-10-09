import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/pwa_cache_identity.dart';

void main() {
  test('only exact generated build queries are safe cache identities', () {
    final id = 'a' * 64;
    expect(
      pwaCacheBuild(Uri.parse('https://example.test/main.dart.js?build=$id')),
      id,
    );
    for (final query in [
      'token=$id',
      'build=secret',
      'build=$id&token=secret',
      'build=$id&build=$id',
    ]) {
      expect(
        pwaCacheBuild(Uri.parse('https://example.test/main.dart.js?$query')),
        isNull,
      );
    }
    expect(
      pwaCompletionBuild(
        Uri.parse('https://example.test/release.json?build=$id'),
      ),
      id,
    );
    expect(
      pwaCompletionBuild(
        Uri.parse('https://example.test/__releases/$id/release.json'),
      ),
      id,
    );
    expect(
      pwaCompletionBuild(
        Uri.parse('https://example.test/main.dart.js?build=$id'),
      ),
      isNull,
    );
  });
}
