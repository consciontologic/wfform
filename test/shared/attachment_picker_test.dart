import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/attachment_picker.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/transport.dart';

Matcher failsWith(FailureKind kind) =>
    throwsA(isA<AppFailure>().having((failure) => failure.kind, 'kind', kind));

class FakeSource implements AttachmentFileSource {
  FakeSource({
    this.name = 'private-user-file.png',
    this.mimeType = 'image/png',
    this.byteLength = 3,
    this.reader,
  });
  @override
  final String name;
  @override
  final String mimeType;
  @override
  final int byteLength;
  final Future<Uint8List> Function(CancelToken?)? reader;
  int reads = 0;
  @override
  Future<Uint8List> readBytes({CancelToken? cancel}) async {
    reads++;
    return reader?.call(cancel) ?? Uint8List(byteLength);
  }
}

void main() {
  const images = {'image/png', 'image/jpeg'};

  test('model attachment capabilities and picker whitelist remain aligned', () {
    const model = FreeModel(
      id: 'fixture/multimodal:free',
      name: 'Multimodal fixture',
      inputModalities: ['text', 'image', 'audio', 'video', 'file'],
    );
    expect(model.allowedAttachmentMimeTypes, supportedAttachmentMimeTypes);
    validateAttachmentBudget(
      allowedMimeTypes: model.allowedAttachmentMimeTypes,
      existingCount: 0,
      existingBytes: 0,
    );
  });

  test(
    'MIME normalization uses known aliases and cautious missing-MIME fallback',
    () {
      expect(
        normalizeAttachmentMimeType('image.jpg', ' IMAGE/JPG '),
        'image/jpeg',
      );
      expect(
        normalizeAttachmentMimeType('sound.wav', 'audio/x-wav'),
        'audio/wav',
      );
      expect(
        normalizeAttachmentMimeType('sound.wav', 'audio/wave'),
        'audio/wav',
      );
      expect(
        normalizeAttachmentMimeType('sound.mp3', 'audio/mp3'),
        'audio/mpeg',
      );
      expect(normalizeAttachmentMimeType('IMAGE.PNG', ''), 'image/png');
      expect(normalizeAttachmentMimeType('scan.PDF', '  '), 'application/pdf');
      expect(
        normalizeAttachmentMimeType('image.png', 'text/plain'),
        'text/plain',
      );
      for (final name in ['png', '.png', 'file.', 'file.unknown', 'file']) {
        expect(
          normalizeAttachmentMimeType(name, ''),
          'text/plain',
          reason: name,
        );
      }
    },
  );

  test('all file metadata is validated before any bytes are read', () async {
    final first = FakeSource();
    final unsupported = FakeSource(mimeType: 'application/zip');
    await expectLater(
      readAttachmentSources([first, unsupported], allowedMimeTypes: images),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.kind, 'kind', FailureKind.configuration)
            .having((e) => e.field, 'field', r'$.attachments[1].mimeType')
            .having(
              (e) => e.message,
              'message',
              isNot(contains(unsupported.name)),
            ),
      ),
    );
    expect(first.reads, 0);
    expect(unsupported.reads, 0);
  });

  test(
    'missing MIME with a known extension succeeds but conflicting MIME fails',
    () async {
      final accepted = FakeSource(name: 'photo.JPEG', mimeType: '');
      final picked = await readAttachmentSources([
        accepted,
      ], allowedMimeTypes: images);
      expect(picked.single.mimeType, 'image/jpeg');
      final rejected = FakeSource(name: 'photo.png', mimeType: 'text/plain');
      await expectLater(
        readAttachmentSources([rejected], allowedMimeTypes: images),
        failsWith(FailureKind.configuration),
      );
      expect(rejected.reads, 0);
    },
  );

  test(
    'four-file cap includes already selected files before reading',
    () async {
      final files = List.generate(3, (_) => FakeSource());
      await expectLater(
        readAttachmentSources(
          files,
          allowedMimeTypes: images,
          existingCount: 2,
        ),
        failsWith(FailureKind.configuration),
      );
      expect(files.every((file) => file.reads == 0), isTrue);
      expect(
        (await readAttachmentSources(
          files,
          allowedMimeTypes: images,
          existingCount: 1,
        )).length,
        3,
      );
    },
  );

  test(
    'empty and oversized files reject the whole selection without allocation',
    () async {
      for (final length in [0, -1, maxAttachmentFileBytes + 1]) {
        final first = FakeSource();
        final rejected = FakeSource(byteLength: length);
        await expectLater(
          readAttachmentSources([first, rejected], allowedMimeTypes: images),
          failsWith(FailureKind.configuration),
        );
        expect(first.reads, 0);
        expect(rejected.reads, 0);
      }
    },
  );

  test(
    'total budget counts existing bytes before reading any new file',
    () async {
      final file = FakeSource(byteLength: maxAttachmentFileBytes);
      await expectLater(
        readAttachmentSources(
          [file],
          allowedMimeTypes: images,
          existingCount: 1,
          existingBytes: maxAttachmentTotalBytes - maxAttachmentFileBytes + 1,
        ),
        failsWith(FailureKind.configuration),
      );
      expect(file.reads, 0);
    },
  );

  test('exact individual and aggregate byte limits remain usable', () async {
    final full = FakeSource(byteLength: maxAttachmentFileBytes);
    final remainder = FakeSource(
      byteLength: maxAttachmentTotalBytes - maxAttachmentFileBytes,
    );
    final result = await readAttachmentSources([
      full,
      remainder,
    ], allowedMimeTypes: images);
    expect(
      result.map((file) => file.bytes.length).reduce((a, b) => a + b),
      maxAttachmentTotalBytes,
    );
    expect(full.reads, 1);
    expect(remainder.reads, 1);
  });

  test('invalid picker constraints are rejected before file reads', () async {
    final file = FakeSource();
    for (final types in <Set<String>>[
      {},
      {'application/zip'},
      {'image/png', 'application/zip'},
    ]) {
      await expectLater(
        readAttachmentSources([file], allowedMimeTypes: types),
        failsWith(FailureKind.configuration),
      );
    }
    for (final limits in [
      (-1, 0),
      (5, 0),
      (0, -1),
      (0, maxAttachmentTotalBytes + 1),
    ]) {
      await expectLater(
        readAttachmentSources(
          [file],
          allowedMimeTypes: images,
          existingCount: limits.$1,
          existingBytes: limits.$2,
        ),
        failsWith(FailureKind.configuration),
      );
    }
    expect(file.reads, 0);
  });

  test(
    'user cancellation is an empty result without changing prior attachments',
    () async {
      expect(
        await readAttachmentSources(
          [],
          allowedMimeTypes: images,
          existingCount: 2,
          existingBytes: 100,
        ),
        isEmpty,
      );
    },
  );

  test('explicit cancellation before selection prevents reads', () async {
    final source = FakeSource();
    final cancel = CancelToken()..cancel();
    await expectLater(
      readAttachmentSources([source], allowedMimeTypes: images, cancel: cancel),
      failsWith(FailureKind.cancelled),
    );
    expect(source.reads, 0);
  });

  test(
    'cancellation after first read stops remaining reads and returns no partial selection',
    () async {
      final cancel = CancelToken();
      final first = FakeSource(
        reader: (_) async {
          cancel.cancel();
          return Uint8List(3);
        },
      );
      final second = FakeSource();
      await expectLater(
        readAttachmentSources(
          [first, second],
          allowedMimeTypes: images,
          cancel: cancel,
        ),
        failsWith(FailureKind.cancelled),
      );
      expect(first.reads, 1);
      expect(second.reads, 0);
    },
  );

  test('pending read receives the cancellation token', () async {
    final cancel = CancelToken();
    final started = Completer<void>();
    final pending = FakeSource(
      reader: (token) async {
        expect(identical(token, cancel), isTrue);
        started.complete();
        await token!.whenCancelled;
        throwIfAttachmentCancelled(token);
        return Uint8List(3);
      },
    );
    final operation = readAttachmentSources(
      [pending],
      allowedMimeTypes: images,
      cancel: cancel,
    );
    final expectation = expectLater(
      operation,
      failsWith(FailureKind.cancelled),
    );
    await started.future;
    cancel.cancel();
    await expectation;
  });

  test('truncated file bytes produce actionable storage failure', () async {
    final source = FakeSource(reader: (_) async => Uint8List(2));
    await expectLater(
      readAttachmentSources([source], allowedMimeTypes: images),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.kind, 'kind', FailureKind.storage)
            .having((e) => e.retryable, 'retryable', true)
            .having((e) => e.expected, 'expected bytes', '3')
            .having((e) => e.actual, 'actual bytes', '2'),
      ),
    );
  });

  test('selected files retain order and read-only byte views', () async {
    final result = await readAttachmentSources([
      FakeSource(name: 'first.png'),
      FakeSource(name: 'second.png'),
    ], allowedMimeTypes: images);
    expect(result.map((file) => file.name), ['first.png', 'second.png']);
    expect(() => result.add(result.first), throwsUnsupportedError);
    expect(() => result.first.bytes[0] = 7, throwsUnsupportedError);
  });

  test(
    'nonweb adapter explicitly reports unsupported platform and honors cancellation',
    () async {
      final picker = createAttachmentPicker();
      addTearDown(picker.dispose);
      await expectLater(
        picker.pick(allowedMimeTypes: images),
        failsWith(FailureKind.configuration),
      );
      await expectLater(
        picker.pick(allowedMimeTypes: images, cancel: CancelToken()..cancel()),
        failsWith(FailureKind.cancelled),
      );
    },
  );
}
