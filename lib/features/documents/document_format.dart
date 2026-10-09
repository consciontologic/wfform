import 'dart:convert';

import '../../shared/diagnostics.dart';

const maxTextDocumentBytes = 256 * 1024;

/// Formats describe presentation only. Content is never executed or evaluated.
class DocumentFormat {
  const DocumentFormat(this.label, this.language, {this.markdown = false});
  final String label, language;
  final bool markdown;
}

const _plain = DocumentFormat('Plain text', 'text');
const _markdown = DocumentFormat('Markdown', 'markdown', markdown: true);
const _formats = <String, DocumentFormat>{
  'md': _markdown,
  'markdown': _markdown,
  'mdown': _markdown,
  'txt': _plain,
  'text': _plain,
  'log': _plain,
  'csv': _plain,
  'tsv': _plain,
  'rst': DocumentFormat('reStructuredText', 'text'),
  'json': DocumentFormat('JSON', 'json'),
  'jsonl': DocumentFormat('JSON Lines', 'jsonl'),
  'ndjson': DocumentFormat('JSON Lines', 'jsonl'),
  'yaml': DocumentFormat('YAML', 'yaml'),
  'yml': DocumentFormat('YAML', 'yaml'),
  'js': DocumentFormat('JavaScript', 'javascript'),
  'mjs': DocumentFormat('JavaScript', 'javascript'),
  'cjs': DocumentFormat('JavaScript', 'javascript'),
  'jsx': DocumentFormat('JSX', 'javascript'),
  'ts': DocumentFormat('TypeScript', 'typescript'),
  'tsx': DocumentFormat('TSX', 'typescript'),
  'c': DocumentFormat('C', 'cpp'),
  'h': DocumentFormat('C header', 'cpp'),
  'cpp': DocumentFormat('C++', 'cpp'),
  'cc': DocumentFormat('C++', 'cpp'),
  'cxx': DocumentFormat('C++', 'cpp'),
  'hpp': DocumentFormat('C++ header', 'cpp'),
  'cs': DocumentFormat('C#', 'cs'),
  'dart': DocumentFormat('Dart', 'dart'),
  'py': DocumentFormat('Python', 'python'),
  'pyi': DocumentFormat('Python', 'python'),
  'rb': DocumentFormat('Ruby', 'ruby'),
  'php': DocumentFormat('PHP', 'php'),
  'java': DocumentFormat('Java', 'java'),
  'kt': DocumentFormat('Kotlin', 'kotlin'),
  'kts': DocumentFormat('Kotlin', 'kotlin'),
  'swift': DocumentFormat('Swift', 'swift'),
  'go': DocumentFormat('Go', 'go'),
  'rs': DocumentFormat('Rust', 'rust'),
  'sh': DocumentFormat('Shell', 'bash'),
  'bash': DocumentFormat('Bash', 'bash'),
  'zsh': DocumentFormat('Shell', 'bash'),
  'ps1': DocumentFormat('PowerShell', 'powershell'),
  'html': DocumentFormat('HTML source', 'xml'),
  'htm': DocumentFormat('HTML source', 'xml'),
  'xml': DocumentFormat('XML', 'xml'),
  'svg': DocumentFormat('SVG source', 'xml'),
  'css': DocumentFormat('CSS', 'css'),
  'scss': DocumentFormat('SCSS', 'scss'),
  'sql': DocumentFormat('SQL', 'sql'),
  'graphql': DocumentFormat('GraphQL', 'graphql'),
  'gql': DocumentFormat('GraphQL', 'graphql'),
  'toml': DocumentFormat('TOML', 'ini'),
  'ini': DocumentFormat('INI', 'ini'),
  'cfg': DocumentFormat('Configuration', 'ini'),
  'conf': DocumentFormat('Configuration', 'ini'),
  'env': DocumentFormat('Environment file', 'bash'),
  'lua': DocumentFormat('Lua', 'lua'),
  'r': DocumentFormat('R', 'r'),
  'tex': DocumentFormat('LaTeX source', 'tex'),
  'diff': DocumentFormat('Diff', 'diff'),
  'patch': DocumentFormat('Diff', 'diff'),
  'proto': DocumentFormat('Protocol Buffers', 'protobuf'),
};

DocumentFormat documentFormatFor(String filename) {
  final name = filename.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name == 'dockerfile' || name.startsWith('dockerfile.')) {
    return const DocumentFormat('Dockerfile', 'dockerfile');
  }
  if (name == 'makefile' || name == 'gnumakefile') {
    return const DocumentFormat('Makefile', 'makefile');
  }
  if (name == '.gitignore' ||
      name == '.dockerignore' ||
      name == 'license' ||
      name == 'readme') {
    return _plain;
  }
  if (name == '.env' || name.startsWith('.env.')) return _formats['env']!;
  return _formats[name.split('.').last] ?? _plain;
}

bool isTextDocumentMime(String mime) {
  final type = mime.toLowerCase().split(';').first.trim();
  return type.startsWith('text/') ||
      type.endsWith('+json') ||
      type.endsWith('+xml') ||
      const {
        'application/json',
        'application/ld+json',
        'application/x-ndjson',
        'application/yaml',
        'application/x-yaml',
        'application/javascript',
        'application/x-javascript',
        'application/typescript',
        'application/xml',
        'application/toml',
        'application/sql',
        'application/x-sh',
        'application/x-shellscript',
        'application/x-php',
        'application/x-httpd-php',
        'application/x-perl',
        'application/x-ruby',
        'application/x-tex',
        'application/x-latex',
        'application/x-python-code',
        'image/svg+xml',
      }.contains(type);
}

/// Strict UTF-8 with binary/control rejection. The exact source is retained.
String decodeTextDocument(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > maxTextDocumentBytes) {
    throw const AppFailure(
      FailureKind.configuration,
      'Text and source files must be nonempty and at most 256 KiB.',
    );
  }
  String value;
  try {
    value = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const AppFailure(
      FailureKind.configuration,
      'This file is not valid UTF-8 text. Save it as UTF-8 before attaching it.',
    );
  }
  if (value.codeUnits.any(
    (c) => (c < 32 && c != 9 && c != 10 && c != 13) || c == 127,
  )) {
    throw const AppFailure(
      FailureKind.configuration,
      'This file contains binary or unsupported control data. Choose a UTF-8 text or source file.',
    );
  }
  return value;
}
