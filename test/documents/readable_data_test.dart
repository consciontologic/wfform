import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/documents/readable_data.dart';

void main() {
  test('JSON formatting preserves numeric tokens, key order and duplicates', () {
    const source =
        '{"id":9007199254740993,"value":1e+99,"value":-0,"items":[1,2]}';
    expect(
      formatReadableSource(source, 'json'),
      '{\n  "id": 9007199254740993,\n  "value": 1e+99,\n  "value": -0,\n  "items": [\n    1,\n    2\n  ]\n}',
    );
    expect(detectDataLanguage(source), 'json');
  });

  test(
    'JSONL formats each record while malformed and unknown content survives',
    () {
      expect(
        formatReadableSource('{"one":1}\n{"two":2}', 'jsonl'),
        '{\n  "one": 1\n}\n\n{\n  "two": 2\n}',
      );
      for (final source in [
        '{unfinished',
        'hello: world',
        '<script>alert(1)</script>',
      ]) {
        expect(formatReadableSource(source, 'text'), source);
        expect(detectDataLanguage(source), 'text');
      }
    },
  );

  test('YAML block scalars, comments, anchors and tags remain verbatim', () {
    const source =
        '# config\ndefault: &d yes\nscript: |\n  print("hi")\ncopy: *d\nvalue: !custom 12\n';
    expect(formatReadableSource(source, 'yaml'), source);
  });

  test(
    'decoded previews expose exact code and nested MCP JSON without rewriting source',
    () {
      const source =
          r'{"code":"import csv\nprint(\"hi\")\n","content":[{"type":"text","text":"{\"stdout\":\"done\\n\",\"exitCode\":0}"}]}';
      final sections = decodedDataSections(source);
      expect(sections.first.path, r'$.code');
      expect(sections.first.source, 'import csv\nprint("hi")\n');
      expect(sections.first.language, 'text');
      expect(sections[1].path, r'$.content[0].text');
      expect(sections[1].language, 'json');
      expect(sections[2].source, 'done\n');
    },
  );

  test('untrusted previews have size, depth and count bounds', () {
    final huge = '{"data":"${'x' * (maxReadableDataCharacters + 1)}"}';
    expect(formatReadableSource(huge, 'json'), huge);
    expect(decodedDataSections(huge), isEmpty);
    final deep = '${'[' * 80}0${']' * 80}';
    expect(formatReadableSource(deep, 'json'), deep);
    expect(decodedDataSections(deep), isEmpty);
    expect(
      decodedDataSections(
        '{${List.generate(80, (i) => '"$i":"line\\n"').join(',')}}',
      ).length,
      lessThanOrEqualTo(maxDecodedDataSections),
    );
  });

  test(
    'nested filename and language hints select safe named source grammars',
    () {
      expect(
        decodedDataSections(
          r'{"filename":"demo.py","text":"print(2)"}',
        ).single.language,
        'python',
      );
      expect(
        decodedDataSections(
          r'{"language":"yaml","code":"message: hi"}',
        ).single.language,
        'yaml',
      );
      expect(formatReadableSource('{"ok":true}', 'JSON'), '{\n  "ok": true\n}');
    },
  );
}
