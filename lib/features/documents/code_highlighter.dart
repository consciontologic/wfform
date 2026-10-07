import 'package:flutter/material.dart';
import 'package:highlight/highlight_core.dart' as syntax;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/diff.dart';
import 'package:highlight/languages/dockerfile.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/graphql.dart';
import 'package:highlight/languages/ini.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/lua.dart';
import 'package:highlight/languages/makefile.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/powershell.dart';
import 'package:highlight/languages/protobuf.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/r.dart';
import 'package:highlight/languages/ruby.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/scss.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/tex.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

const maxHighlightedCodeCharacters = 12000;
bool _registered = false;

String normalizeCodeLanguage(String value) {
  final name = value.trim().toLowerCase().split(RegExp(r'\s+')).first;
  return const {
        'js': 'javascript',
        'jsx': 'javascript',
        'ts': 'typescript',
        'tsx': 'typescript',
        'c': 'cpp',
        'c++': 'cpp',
        'c#': 'cs',
        'py': 'python',
        'rb': 'ruby',
        'sh': 'bash',
        'shell': 'bash',
        'zsh': 'bash',
        'html': 'xml',
        'svg': 'xml',
        'yml': 'yaml',
        'toml': 'ini',
        'rs': 'rust',
        'kt': 'kotlin',
        'text': 'plaintext',
        'txt': 'plaintext',
      }[name] ??
      name;
}

final _languages = {
  'bash': bash,
  'cpp': cpp,
  'cs': cs,
  'css': css,
  'dart': dart,
  'diff': diff,
  'dockerfile': dockerfile,
  'go': go,
  'graphql': graphql,
  'ini': ini,
  'java': java,
  'javascript': javascript,
  'json': json,
  'kotlin': kotlin,
  'lua': lua,
  'makefile': makefile,
  'php': php,
  'powershell': powershell,
  'protobuf': protobuf,
  'python': python,
  'r': r,
  'ruby': ruby,
  'rust': rust,
  'scss': scss,
  'sql': sql,
  'swift': swift,
  'tex': tex,
  'typescript': typescript,
  'xml': xml,
  'yaml': yaml,
};

/// Named grammars only, with bounded work. No auto-detection or HTML output.
TextSpan highlightedSource(
  String source,
  String language,
  Brightness brightness,
) {
  final name = normalizeCodeLanguage(language);
  if (source.length > maxHighlightedCodeCharacters ||
      !_languages.containsKey(name)) {
    return TextSpan(text: source);
  }
  if (!_registered) {
    _languages.forEach(syntax.highlight.registerLanguage);
    _registered = true;
  }
  final dark = brightness == Brightness.dark;
  Color? color(String? type) => switch (type?.split(' ').first) {
    'keyword' ||
    'selector-tag' ||
    'built_in' ||
    'literal' => dark ? const Color(0xffcbb6ff) : const Color(0xff683394),
    'string' ||
    'regexp' ||
    'attr' ||
    'attribute' => dark ? const Color(0xff9ed7b1) : const Color(0xff24613c),
    'number' ||
    'symbol' ||
    'bullet' => dark ? const Color(0xffffc79e) : const Color(0xff884712),
    'comment' ||
    'quote' => dark ? const Color(0xffb2bbc5) : const Color(0xff57616c),
    'title' ||
    'name' ||
    'type' => dark ? const Color(0xffa1caff) : const Color(0xff255c94),
    _ => null,
  };
  TextSpan span(syntax.Node node) => TextSpan(
    text: node.value,
    style: TextStyle(color: color(node.className)),
    children: node.children?.map(span).toList(),
  );
  try {
    final parsed = syntax.highlight.parse(source, language: name);
    return TextSpan(children: parsed.nodes?.map(span).toList());
  } catch (_) {
    // Cosmetic parsing is optional: the exact source must always remain visible.
    return TextSpan(text: source);
  }
}
