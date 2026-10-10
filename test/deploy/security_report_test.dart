import 'package:flutter_test/flutter_test.dart';
import '../../tool/security_report.dart';
import '../../tool/release_version.dart';
import '../../tool/release_notes.dart';

void main() {
  test('license lookup treats package root URI as a directory', () {
    final licenses = licenseInventory([
      {'name': 'http', 'version': '1.6.0'},
    ]);
    expect(licenses, hasLength(1));
    expect(licenses.single['licenseProvided'], isTrue);
    expect(licenses.single['licenseFiles'] as List, isNotEmpty);
  });
  test('release notes select only the exact semantic release section', () {
    const changelog =
        '# Changes\n\n## [Unreleased]\nFuture\n\n## [1.0.0] - date\n\n✨ Shipped\n\n## [0.3.0]\nOld\n';
    expect(
      releaseNotes(changelog, '1.0.0'),
      '## [1.0.0] - date\n\n✨ Shipped\n',
    );
    expect(() => releaseNotes(changelog, '2.0.0'), throwsStateError);
  });
  test('only deduplicated public hosted coordinates enter OSV and SBOM', () {
    final packages = hostedPackages([
      {
        'packages': [
          {'name': 'a', 'version': '1.2.3', 'source': 'hosted'},
          {'name': 'a', 'version': '1.2.3', 'source': 'hosted'},
          {'name': 'private', 'version': '1.0.0', 'source': 'git'},
          {'name': 'flutter', 'version': '0.0.0', 'source': 'sdk'},
        ],
      },
    ]);
    expect(packages, [
      {'name': 'a', 'version': '1.2.3'},
    ]);
    expect(osvQuery(packages), {
      'queries': [
        {
          'package': {'name': 'a', 'ecosystem': 'Pub'},
          'version': '1.2.3',
        },
      ],
    });
    expect(
      (dependencyBom(packages)['components'] as List).single['purl'],
      'pkg:pub/a@1.2.3',
    );
    expect(() => hostedPackages([{}]), throwsFormatException);
  });
  test('release tags and package versions use plain semantic versions', () {
    expect(readReleaseVersion(), '1.0.1');
    for (final value in ['v1.0.0', '1.0', '01.0.0', '1.0.0+10', '1.0.0-rc1']) {
      expect(semanticVersion.hasMatch(value), isFalse, reason: value);
    }
    expect(semanticVersion.hasMatch('10.20.30'), isTrue);
  });
}
