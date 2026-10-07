import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/chat/chat_controller.dart';
import 'package:wfform/features/documents/document_format.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/features/models/health.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';

import '../chat/fakes.dart';
import '../shared/attachment_picker_test.dart' show FakeSource;

ChatAttachment document({String source = 'const value = "世界 👋";\r\n'}) =>
    ChatAttachment.fromBytes(
      id: 'source-file',
      name: 'example.js',
      mimeType: 'application/javascript',
      bytes: utf8.encode(source),
    );

void main() {
  test('format registry recognizes common code and extensionless files', () {
    for (final pair in {
      'README.MD': 'markdown',
      'data.json': 'json',
      'ci.yml': 'yaml',
      'a.js': 'javascript',
      'a.tsx': 'typescript',
      'a.c': 'cpp',
      'a.hpp': 'cpp',
      'a.py': 'python',
      'a.rs': 'rust',
      'a.dart': 'dart',
      'a.go': 'go',
      'a.java': 'java',
      'a.cs': 'cs',
      'a.rb': 'ruby',
      'a.kt': 'kotlin',
      'a.swift': 'swift',
      'a.sh': 'bash',
      'a.sql': 'sql',
      'a.html': 'xml',
      'a.svg': 'xml',
      'a.css': 'css',
      'a.toml': 'ini',
      '.env.local': 'bash',
      'Dockerfile': 'dockerfile',
      'Makefile': 'makefile',
      '.gitignore': 'text',
      'a.custom': 'text',
    }.entries) {
      expect(
        documentFormatFor(pair.key).language,
        pair.value,
        reason: pair.key,
      );
    }
    expect(documentFormatFor('README.MD').markdown, true);
    expect(documentFormatFor('unsafe.html').markdown, false);
  });

  test(
    'text files keep all existing free pricing and compatibility guards',
    () {
      final file = document();
      for (final model in [
        const FreeModel(
          id: 'paid',
          name: 'Paid',
          pricing: {'prompt': '1', 'completion': '0'},
        ),
        const FreeModel(
          id: 'unresolved',
          name: 'Unknown',
          pricing: {'prompt': '-1', 'completion': '0'},
        ),
        const FreeModel(
          id: 'request',
          name: 'Request cost',
          pricing: {'prompt': '0', 'completion': '0', 'request': '1'},
        ),
        const FreeModel(
          id: 'output',
          name: 'Output',
          outputModalities: ['text', 'image'],
        ),
        const FreeModel(
          id: 'override',
          name: 'Override',
          pricingOverrides: [
            {'prompt': '0.001'},
          ],
        ),
      ]) {
        expect(file.compatibilityIssue(model), isNotNull, reason: model.id);
        expect(model.allowedAttachmentMimeTypes, isNot(contains('text/plain')));
      }
      expect(
        file.compatibilityIssue(
          const FreeModel(
            id: 'media-price',
            name: 'Text free',
            pricing: {'prompt': '0', 'completion': '0', 'image': '-1'},
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'picker rejects oversized source before read and binary after read',
    () async {
      final oversized = FakeSource(
        name: 'source.js',
        mimeType: 'application/javascript',
        byteLength: maxTextDocumentBytes + 1,
      );
      await expectLater(
        readAttachmentSources([oversized], allowedMimeTypes: {'text/plain'}),
        throwsA(isA<AppFailure>()),
      );
      expect(oversized.reads, 0);
      final binary = FakeSource(
        name: 'unknown.custom',
        mimeType: '',
        byteLength: 3,
      );
      await expectLater(
        readAttachmentSources([binary], allowedMimeTypes: {'text/plain'}),
        throwsA(isA<AppFailure>()),
      );
      final bytes = Uint8List.fromList(utf8.encode('Unicode 🌿'));
      final source = FakeSource(
        name: 'unknown.custom',
        mimeType: '',
        byteLength: bytes.length,
        reader: (_) async => bytes,
      );
      final selected = await readAttachmentSources(
        [source],
        allowedMimeTypes: {'text/plain'},
      );
      expect(selected.single.mimeType, 'text/plain');
      expect(selected.single.bytes, bytes);
    },
  );

  test(
    'source files roundtrip legacy and normalized history without repeated payloads',
    () {
      final file = document();
      final original = ConversationRecord(
        id: 'docs',
        title: 'Documents',
        draft: '',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        draftAttachments: [file],
        sessionData: {
          'version': 1,
          'messages': [
            ChatMessage(
              role: 'user',
              content: 'Review',
              attachments: [file],
            ).toJson(),
          ],
        },
      );
      final legacy = ConversationRecord.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(legacy.draftAttachments.single.textContent, file.textContent);
      final packed = PackedHistoryRecord.pack(legacy);
      expect(packed.attachments.length, 1);
      expect(packed.messages.single, isNot(contains(file.base64Data)));
      final restored = PackedHistoryRecord.unpack(
        packed.document(1),
        packed.messages,
        {file.id: base64Decode(file.base64Data)},
      );
      expect(
        restored.draftAttachments.single.toContentPart(),
        file.toContentPart(),
      );
      expect(restored.sessionData, original.sessionData);
    },
  );

  test(
    'source payload is budgeted, sent as text, and retained through edit and session restore',
    () async {
      const config = AppConfig(apiKey: 'fixture-key');
      final diagnostics = Diagnostics(config);
      final transport = FakeTransport(
        (_) => streamResponse('${delta('Done')}data: [DONE]\n\n'),
      );
      final health = HealthController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
      )..recordSuccess(testModel.id);
      final chat = ChatController(
        config: config,
        transport: transport,
        diagnostics: diagnostics,
        health: health,
      );
      addTearDown(() {
        chat.dispose();
        health.dispose();
        diagnostics.dispose();
      });
      final file = document(source: List.filled(18000, 'a').join());
      final plain = chat
          .contextBudget(testModel, draft: 'Review')
          .estimatedInputTokens;
      final withFile = chat.contextBudget(
        testModel,
        draft: 'Review',
        attachments: [file],
      );
      expect(
        withFile.estimatedInputTokens - plain,
        (utf8.encode(file.textRequestContent).length / 3).ceil() + 6,
      );
      expect(
        withFile.hasAttachments,
        false,
      ); // No uncertain media token estimate.
      await chat.send(testModel, 'Review', attachments: [file]);
      expect(chat.messages.last.content, 'Done');
      final content =
          (transport.requests.single.json['messages'] as List).single['content']
              as List;
      expect(content, [
        {'type': 'text', 'text': 'Review'},
        file.toContentPart(),
      ]);
      expect(
        transport.requests.single.json['provider']['max_price']['prompt'],
        '0',
      );
      expect(chat.restoreSession(chat.exportSession()), true);
      expect(
        chat.messages.first.attachments.single.textContent,
        file.textContent,
      );
      await chat.send(
        testModel,
        'Review again',
        attachments: [file],
        editedFrom: 0,
      );
      expect(
        chat.messages.where((message) => message.role == 'user').length,
        2,
      );
      expect(
        chat.messages
            .where((message) => message.role == 'user')
            .last
            .attachments
            .single
            .toContentPart(),
        file.toContentPart(),
      );
    },
  );
}
