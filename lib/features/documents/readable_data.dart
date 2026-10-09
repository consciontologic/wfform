import 'dart:convert';
import 'document_format.dart';

/// Presentation budgets. Original text is always retained by the caller.
const maxReadableDataCharacters = 64000;
const maxDecodedDataSections = 12;
const _maxDepth = 32;

/// Detect only unambiguous structured data, never YAML-like ordinary prose.
String detectDataLanguage(String source) =>
    _jsonContainer(source) != null ? 'json' : 'text';

/// Adds whitespace only: number spelling, duplicate keys and string escapes
/// survive. YAML/source indentation and comments must not be reserialized.
String formatReadableSource(String source, String language) {
  language = language.trim().toLowerCase();
  if (source.length > maxReadableDataCharacters) return source;
  if (language == 'jsonl' || language == 'ndjson') {
    final lines = const LineSplitter().convert(source);
    if (lines.isEmpty || lines.any((line) => _jsonContainer(line) == null)) {
      return source;
    }
    final formatted = lines.map(_indentJson).join('\n\n');
    return formatted.length <= maxReadableDataCharacters ? formatted : source;
  }
  if (_jsonContainer(source) == null) return source;
  // A filename/fence with another known grammar always wins over detection.
  if (!{'json', 'text', '', 'markdown'}.contains(language)) return source;
  return _indentJson(source);
}

Object? _jsonContainer(String source) {
  if (source.length > maxReadableDataCharacters) return null;
  final text = source.trim();
  if (!text.startsWith('{') && !text.startsWith('[')) return null;
  var quoted = false, escaped = false, depth = 0;
  for (final unit in text.codeUnits) {
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        quoted = false;
      }
    } else if (unit == 34) {
      quoted = true;
    } else if (unit == 123 || unit == 91) {
      if (++depth > _maxDepth) return null;
    } else if (unit == 125 || unit == 93) {
      depth--;
    }
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String _indentJson(String source) {
  // Tokenize only after bounded validation; never rebuild through decoded nums.
  final tokens = RegExp(
    r'"(?:[^"\\]|\\.)*"|[^\s"{}\[\],:]+|[{}\[\],:]',
  ).allMatches(source).map((match) => match[0]!).toList(growable: false);
  final result = StringBuffer();
  var depth = 0;
  void newline() => result.write('\n${'  ' * depth}');
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    switch (token) {
      case '{' || '[':
        result.write(token);
        depth++;
        if (i + 1 < tokens.length && !{'}', ']'}.contains(tokens[i + 1])) {
          newline();
        }
      case '}' || ']':
        depth--;
        if (i > 0 && !{'{', '['}.contains(tokens[i - 1])) newline();
        result.write(token);
      case ',':
        result.write(',');
        newline();
      case ':':
        result.write(': ');
      default:
        result.write(token);
    }
    if (result.length > maxReadableDataCharacters) return source;
  }
  return result.toString();
}

class DecodedDataSection {
  const DecodedDataSection(this.path, this.source, this.language);
  final String path, source, language;
}

/// Additional views of JSON string values, never replacements for their types.
/// This reveals MCP text, stdout and code with actual newlines, while the raw
/// envelope remains available. Do not interpret decoded strings as Markdown/HTML.
List<DecodedDataSection> decodedDataSections(String source) {
  final root = _jsonContainer(source);
  if (root == null) return const [];
  final sections = <DecodedDataSection>[];
  var characters = 0, nodes = 0;
  void visit(
    Object? value,
    String path,
    int depth, [
    String? name,
    String? hint,
  ]) {
    if (++nodes > 4096 ||
        depth > _maxDepth ||
        sections.length >= maxDecodedDataSections) {
      return;
    }
    if (value is Map) {
      final filename = value['filename'] ?? value['path'] ?? value['name'];
      final explicitLanguage = value['language'];
      final language =
          explicitLanguage is String &&
              RegExp(r'^[A-Za-z0-9_+#-]{1,32}$').hasMatch(explicitLanguage)
          ? explicitLanguage.toLowerCase()
          : filename is String
          ? documentFormatFor(filename).language
          : null;
      for (final entry in value.entries) {
        final key = entry.key as String;
        final segment = RegExp(r'^[A-Za-z_]\w*$').hasMatch(key)
            ? '.$key'
            : '[${jsonEncode(key)}]';
        visit(
          entry.value,
          '$path$segment',
          depth + 1,
          key,
          {'code', 'script', 'source', 'text', 'content'}.contains(key)
              ? language
              : null,
        );
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        visit(value[i], '$path[$i]', depth + 1);
      }
    } else if (value is String && value.isNotEmpty) {
      final nested = _jsonContainer(value);
      if (nested == null &&
          !value.contains('\n') &&
          !value.contains('\r') &&
          !{'code', 'script', 'source'}.contains(name) &&
          hint == null) {
        return;
      }
      characters += value.length;
      if (characters > maxReadableDataCharacters) return;
      sections.add(
        DecodedDataSection(
          path,
          value,
          hint ?? (nested == null ? 'text' : 'json'),
        ),
      );
      if (nested != null) visit(nested, '$path (decoded)', depth + 1);
    }
  }

  visit(root, r'$', 0);
  return sections;
}
