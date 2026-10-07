import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';

const textModel = FreeModel(id: 'fixture/text', name: 'Text only');

void main() {
  test(
    'text-compatible free models accept locally decoded source documents',
    () {
      expect(ChatAttachment.mimeTypesFor(textModel), contains('text/plain'));
      const source = '# Notes\n\nHello 世界 👋\n```js\nconst count = 3;\n```\n';
      final attachment = ChatAttachment.fromBytes(
        id: 'source-one',
        name: 'README.md',
        mimeType: 'text/markdown',
        bytes: utf8.encode(source),
      );
      expect(attachment.kind.name, 'text');
      expect(attachment.compatibilityIssue(textModel), isNull);
      final part = attachment.toContentPart();
      expect(part['type'], 'text');
      expect(part['text'], contains(source));
      expect(part['text'], contains('README.md'));
      expect(part.containsKey('file'), false);
      expect(
        ChatAttachment.fromJson(attachment.toJson()).toContentPart(),
        part,
      );
    },
  );

  test(
    'source extensions and generic MIME fallback normalize without relabeling media',
    () {
      for (final name in [
        'note.md',
        'a.json',
        'a.yml',
        'a.js',
        'a.c',
        'Dockerfile',
        'unknown.custom',
      ]) {
        expect(normalizeAttachmentMimeType(name, ''), 'text/plain');
        expect(
          normalizeAttachmentMimeType(name, 'application/octet-stream'),
          'text/plain',
        );
      }
      expect(
        normalizeAttachmentMimeType('a.js', 'application/javascript'),
        'text/plain',
      );
      for (final mime in ['application/x-tex', 'application/x-latex']) {
        expect(normalizeAttachmentMimeType('document.tex', mime), 'text/plain');
      }
      expect(
        normalizeAttachmentMimeType('source.ts', 'video/mp2t'),
        'text/plain',
      );
      expect(
        normalizeAttachmentMimeType('source.py', 'application/x-python-code'),
        'text/plain',
      );
      expect(
        normalizeAttachmentMimeType('unknown.custom', 'application/x-custom'),
        'text/plain',
      );
      expect(normalizeAttachmentMimeType('photo.png', ''), 'image/png');
      expect(
        normalizeAttachmentMimeType('photo.png', 'application/pdf'),
        'application/pdf',
      );
    },
  );

  test('text files reject binary, malformed UTF-8 and oversized payloads', () {
    for (final bytes in [
      [0, 1, 2],
      [0xc3, 0x28],
      [65, 0, 66],
      List.filled(256 * 1024 + 1, 65),
    ]) {
      expect(
        () => ChatAttachment.fromBytes(
          name: 'source.txt',
          mimeType: 'text/plain',
          bytes: bytes,
        ),
        throwsA(isA<AppFailure>()),
      );
    }
  });
}
