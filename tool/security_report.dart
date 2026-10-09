import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Public package coordinates only leave the machine; no source or credentials.
List<Map<String, dynamic>> hostedPackages(List<Object?> inventories) {
  final packages = <String, Map<String, dynamic>>{};
  for (final inventory in inventories) {
    if (inventory is! Map || inventory['packages'] is! List) {
      throw const FormatException('Expected pub deps --json inventory.');
    }
    for (final value in inventory['packages'] as List) {
      if (value is! Map || value['source'] != 'hosted') continue;
      final name = value['name'], version = value['version'];
      if (name is! String ||
          !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name) ||
          version is! String ||
          version.isEmpty) {
        throw const FormatException('Invalid package coordinate.');
      }
      packages['$name@$version'] = {'name': name, 'version': version};
    }
  }
  return packages.values.toList()..sort(
    (a, b) => '${a['name']}@${a['version']}'.compareTo(
      '${b['name']}@${b['version']}',
    ),
  );
}

Map<String, Object> osvQuery(List<Map<String, dynamic>> packages) => {
  'queries': [
    for (final package in packages)
      {
        'package': {'name': package['name'], 'ecosystem': 'Pub'},
        'version': package['version'],
      },
  ],
};

Map<String, Object> dependencyBom(List<Map<String, dynamic>> packages) => {
  'bomFormat': 'CycloneDX',
  'specVersion': '1.6',
  'version': 1,
  'components': [
    for (final package in packages)
      {
        'type': 'library',
        'name': package['name'],
        'version': package['version'],
        'purl': 'pkg:pub/${package['name']}@${package['version']}',
      },
  ],
};

/// Preserve license texts as package evidence; do not guess SPDX classifications.
List<Map<String, Object?>> licenseInventory(
  List<Map<String, dynamic>> packages,
) {
  final result = <Map<String, Object?>>[];
  final names = {for (final package in packages) package['name'] as String};
  final seen = <String>{};
  for (final path in [
    '.dart_tool/package_config.json',
    'companion/.dart_tool/package_config.json',
  ]) {
    final config = File(path);
    final data = jsonDecode(config.readAsStringSync()) as Map;
    for (final entry in data['packages'] as List) {
      if (!names.contains(entry['name'])) continue;
      final root = config.absolute.uri.resolve(entry['rootUri'] as String);
      if (root.scheme != 'file' || !seen.add(root.toString())) continue;
      final files = <Map<String, String>>[];
      for (final name in [
        'LICENSE',
        'LICENSE.md',
        'LICENSE.txt',
        'COPYING',
        'NOTICE',
      ]) {
        final file = File.fromUri(Directory.fromUri(root).uri.resolve(name));
        if (file.existsSync() && file.lengthSync() <= 128 * 1024) {
          files.add({'file': name, 'text': file.readAsStringSync()});
        }
      }
      result.add({
        'name': entry['name'],
        'licenseFiles': files,
        'licenseProvided': files.isNotEmpty,
      });
    }
  }
  return result;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError('Pass pub deps --json inventory files.');
  }
  final packages = hostedPackages([
    for (final path in args) jsonDecode(File(path).readAsStringSync()),
  ]);
  final output = Directory('build/reports')..createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  File(
    '${output.path}/dependencies.cdx.json',
  ).writeAsStringSync('${encoder.convert(dependencyBom(packages))}\n');
  File(
    '${output.path}/licenses.json',
  ).writeAsStringSync('${encoder.convert(licenseInventory(packages))}\n');
  final response = await http
      .post(
        Uri.parse('https://api.osv.dev/v1/querybatch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(osvQuery(packages)),
      )
      .timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    throw StateError(
      'OSV unavailable (${response.statusCode}); security check is incomplete.',
    );
  }
  final data = jsonDecode(response.body);
  if (data is! Map ||
      data['results'] is! List ||
      (data['results'] as List).length != packages.length) {
    throw const FormatException('OSV returned incomplete results.');
  }
  final findings = <Map<String, dynamic>>[];
  for (var index = 0; index < packages.length; index++) {
    final result = data['results'][index];
    if (result is! Map || result.containsKey('next_page_token')) {
      throw const FormatException(
        'OSV result was malformed or paginated; scan incomplete.',
      );
    }
    for (final vulnerability in (result['vulns'] as List? ?? [])) {
      findings.add({...packages[index], 'vulnerability': vulnerability});
    }
  }
  File('${output.path}/osv.json').writeAsStringSync(
    '${encoder.convert({'packages': packages.length, 'findings': findings})}\n',
  );
  final summary =
      '🛡️ OSV checked ${packages.length} locked public packages: ${findings.length} known vulnerabilities.\n';
  File('${output.path}/security-summary.md').writeAsStringSync(summary);
  stdout.write(summary);
  if (findings.isNotEmpty) exitCode = 1;
}
