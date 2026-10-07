import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/chat/chat_api.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/attachment_limits.dart';
import 'package:wfform/shared/diagnostics.dart';

import 'fakes.dart';

const mediaModel = FreeModel(
  id: 'maker/media:free',
  name: 'Media',
  inputModalities: ['text', 'image', 'audio', 'video', 'file'],
);

ChatAttachment imageAttachment({String id = 'image-1', int bytes = 8}) =>
    ChatAttachment.fromBytes(
      id: id,
      name: 'photo.png',
      mimeType: 'image/png',
      bytes: [
        ...[137, 80, 78, 71, 13, 10, 26, 10],
        ...List.filled(bytes - 8, 0),
      ],
    );

void main() {
  test(
    'generated attachment IDs are usable and distinct without caller IDs',
    () {
      final identifiers = <String>{};
      for (var i = 0; i < 100; i++) {
        final file = ChatAttachment.fromBytes(
          name: 'photo.png',
          mimeType: 'image/png',
          bytes: [137, 80, 78, 71, 13, 10, 26, 10],
        );
        expect(file.id, matches(RegExp(r'^[a-z0-9]+-[a-z0-9]+$')));
        expect(identifiers.add(file.id), isTrue);
        expect(ChatAttachment.fromJson(file.toJson()).id, file.id);
      }
    },
  );

  test(
    'supported formats validate, serialize and produce documented parts',
    () {
      final files = [
        imageAttachment(),
        ChatAttachment.fromBytes(
          name: 'picture.jpg',
          mimeType: 'image/jpg',
          bytes: [255, 216, 255],
        ),
        ChatAttachment.fromBytes(
          name: 'animation.gif',
          mimeType: 'image/gif',
          bytes: ascii.encode('GIF89a'),
        ),
        ChatAttachment.fromBytes(
          name: 'picture.webp',
          mimeType: 'image/webp',
          bytes: ascii.encode('RIFF0000WEBP'),
        ),
        ChatAttachment.fromBytes(
          name: 'voice.wav',
          mimeType: 'audio/x-wav',
          bytes: ascii.encode('RIFF0000WAVE'),
        ),
        ChatAttachment.fromBytes(
          name: 'voice.mp3',
          mimeType: 'audio/mpeg',
          bytes: ascii.encode('ID3'),
        ),
        ChatAttachment.fromBytes(
          name: 'clip.mp4',
          mimeType: 'video/mp4',
          bytes: ascii.encode('0000ftyp'),
        ),
        ChatAttachment.fromBytes(
          name: 'document.pdf',
          mimeType: 'application/pdf',
          bytes: ascii.encode('%PDF-1.7'),
        ),
      ];
      expect(files.map((file) => file.id).toSet().length, files.length);
      for (final file in files) {
        final restored = ChatAttachment.fromJson(
          jsonDecode(jsonEncode(file.toJson())),
        );
        expect(restored.toJson(), file.toJson());
        expect(file.compatibilityIssue(mediaModel), isNull);
      }
      expect(files[0].toContentPart(), {
        'type': 'image_url',
        'image_url': {'url': files[0].dataUrl},
      });
      expect(files[4].toContentPart(), {
        'type': 'input_audio',
        'input_audio': {'data': files[4].base64Data, 'format': 'wav'},
      });
      expect(files[5].toContentPart(), {
        'type': 'input_audio',
        'input_audio': {'data': files[5].base64Data, 'format': 'mp3'},
      });
      expect(files[6].toContentPart(), {
        'type': 'video_url',
        'video_url': {'url': files[6].dataUrl},
      });
      expect(files[7].toContentPart(), {
        'type': 'file',
        'file': {'filename': 'document.pdf', 'file_data': files[7].dataUrl},
      });
    },
  );

  test(
    'rejects unsupported formats, misleading MIME, damaged persisted data',
    () {
      expect(
        () => ChatAttachment.fromBytes(
          name: 'archive.zip',
          mimeType: 'application/zip',
          bytes: ascii.encode('PK0000'),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => ChatAttachment.fromBytes(
          name: 'photo.png',
          mimeType: 'image/png',
          bytes: ascii.encode('<script>'),
        ),
        throwsA(isA<AppFailure>()),
      );
      final valid = imageAttachment().toJson();
      for (final damaged in [
        {...valid, 'base64Data': 'not-base64%'},
        {...valid, 'byteLength': 1},
        {...valid, 'kind': 'audio'},
        {...valid, 'version': 2},
        {...valid, 'name': '\nphoto.png'},
        {...valid, 'byteLength': '8'},
      ]) {
        expect(
          () => ChatAttachment.fromJson(damaged),
          throwsA(isA<AppFailure>()),
        );
      }
    },
  );

  test(
    'per-file, per-turn, duplicate and compatibility bounds are enforced',
    () {
      expect(
        () => ChatAttachment.fromBytes(
          name: 'large.png',
          mimeType: 'image/png',
          bytes: Uint8List(maxAttachmentFileBytes + 1),
        ),
        throwsA(isA<AppFailure>()),
      );
      final file = imageAttachment();
      expect(
        () => validateAttachments([file, file]),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => validateAttachments([
          for (var i = 0; i < 5; i++) imageAttachment(id: '$i'),
        ]),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => validateAttachments([file], model: testModel),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => validateAttachments([
          imageAttachment(id: 'large-1', bytes: 7 * 1024 * 1024),
          imageAttachment(id: 'large-2', bytes: 7 * 1024 * 1024),
        ]),
        throwsA(isA<AppFailure>()),
      );
    },
  );

  test(
    'PDF in any history turn forces only native parser with zero media guards',
    () {
      final api = ChatApi(const AppConfig(), FakeTransport((_) => endpoints()));
      final pdf = ChatAttachment.fromBytes(
        name: 'document.pdf',
        mimeType: 'application/pdf',
        bytes: ascii.encode('%PDF-1.7'),
      );
      final body = api.requestBody(mediaModel, [
        {
          'role': 'user',
          'content': [pdf.toContentPart()],
        },
        {'role': 'assistant', 'content': 'Earlier answer'},
        {'role': 'user', 'content': 'Follow-up'},
      ]);
      expect(body['plugins'], [
        {
          'id': 'file-parser',
          'pdf': {'engine': 'native'},
        },
      ]);
      expect((body['provider'] as Map)['max_price'], {
        'prompt': '0',
        'completion': '0',
        'request': '0',
        'image': '0',
        'audio': '0',
      });
      expect(
        api
            .requestBody(mediaModel, [
              {'role': 'user', 'content': 'Text only'},
            ])
            .containsKey('plugins'),
        isFalse,
      );
    },
  );
}
