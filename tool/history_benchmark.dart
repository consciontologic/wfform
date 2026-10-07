// Synthetic, opt-in VM benchmark. Run with:
// flutter test tool/history_benchmark.dart --reporter expanded
// This measures codec preparation, not browser UI or IndexedDB latency.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/chat/attachment.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_codec.dart';
import 'package:wfform/features/history/history_repository.dart';

final _crcTable = List<int>.generate(256, (value) {
  var crc = value;
  for (var bit = 0; bit < 8; bit++) {
    crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  return crc;
});

int _crc(List<int> bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index++) {
    crc = _crcTable[(crc ^ bytes[index]) & 255] ^ (crc >>> 8);
  }
  return crc ^ 0xffffffff;
}

Uint8List _chunk(String type, List<int> data) {
  final output = Uint8List(data.length + 12);
  final view = ByteData.sublistView(output);
  view.setUint32(0, data.length);
  output.setRange(4, 8, ascii.encode(type));
  output.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, _crc(output, 4, 8 + data.length));
  return output;
}

/// A valid 1px PNG with a large ancillary tEXt chunk. Keeping a tiny image
/// avoids measuring an image decoder while exercising realistic storage bytes.
Uint8List syntheticPng(int size) {
  final header = Uint8List(13);
  ByteData.sublistView(header)
    ..setUint32(0, 1)
    ..setUint32(4, 1);
  header[8] = 8;
  header[9] = 6;
  final pixel = Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._chunk('IHDR', header),
    ..._chunk('IDAT', ZLibEncoder().convert([0, 0, 0, 0, 255])),
    ..._chunk('IEND', []),
  ]);
  final dataLength = size - pixel.length - 12;
  final output = Uint8List(size);
  final insert = pixel.length - 12; // Before IEND.
  output.setRange(0, insert, pixel);
  final view = ByteData.sublistView(output);
  view.setUint32(insert, dataLength);
  output.setRange(insert + 4, insert + 8, ascii.encode('tEXt'));
  output.setRange(insert + 8, insert + 13, ascii.encode('note\u0000'));
  output.fillRange(insert + 13, insert + 8 + dataLength, 65);
  view.setUint32(
    insert + 8 + dataLength,
    _crc(output, insert + 4, insert + 8 + dataLength),
  );
  output.setRange(size - 12, size, pixel, pixel.length - 12);
  return output;
}

double median(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

void main() {
  test(
    'synthetic 12 MiB history serialization baseline and incremental codec',
    () async {
      const fileBytes = 6 * 1024 * 1024;
      const checkpointCount = 10;
      final bytes = syntheticPng(fileBytes);
      final imageCodec = await ui.instantiateImageCodec(bytes);
      final frame = await imageCodec.getNextFrame();
      expect(frame.image.width, 1);
      expect(frame.image.height, 1);
      frame.image.dispose();
      imageCodec.dispose();
      final files = [
        for (var i = 0; i < 2; i++)
          ChatAttachment.fromBytes(
            id: 'benchmark-file-$i',
            name: 'synthetic-$i.png',
            mimeType: 'image/png',
            bytes: bytes,
          ),
      ];
      ConversationRecord snapshot(int checkpoint) => ConversationRecord(
        id: 'benchmark',
        title: 'Synthetic benchmark',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        draft: '',
        messageCount: 2,
        sessionData: {
          'version': 1,
          'retryUserIndex': 0,
          'retryModelId': 'fixture/vision',
          'messages': [
            {
              'role': 'user',
              'content': 'Synthetic fixture only',
              'reasoning': '',
              'complete': true,
              'attachments': files.map((file) => file.toJson()).toList(),
            },
            {
              'role': 'assistant',
              'content': List.filled(
                checkpoint + 1,
                'Synthetic incremental response. ',
              ).join(),
              'reasoning': '',
              'complete': false,
            },
          ],
        },
      );
      final firstWatch = Stopwatch()..start();
      var previous = PackedHistoryRecord.pack(snapshot(0));
      firstWatch.stop();
      // Warm both paths. Neither timing includes generating the PNG fixture.
      encodeHistoryRecord(snapshot(0));
      previous = PackedHistoryRecord.pack(snapshot(0), previous: previous);
      final legacyMicros = <int>[];
      final incrementalMicros = <int>[];
      var legacyWriteBytes = 0;
      var incrementalWriteBytes = 0;
      var changedMessageRows = 0;
      for (var i = 1; i <= checkpointCount; i++) {
        final record = snapshot(i);
        final legacyWatch = Stopwatch()..start();
        final legacy = encodeHistoryRecord(record);
        legacyWatch.stop();
        legacyMicros.add(legacyWatch.elapsedMicroseconds);
        legacyWriteBytes +=
            utf8.encode(legacy).length +
            utf8.encode(jsonEncode(record.summary.toJson())).length +
            record.id.length;
        final incrementalWatch = Stopwatch()..start();
        final packed = PackedHistoryRecord.pack(record, previous: previous);
        final document = jsonEncode(packed.document(i + 1));
        final summary = jsonEncode(record.summary.toJson());
        final changed = packed.messagesChangedSince(previous).toList();
        incrementalWatch.stop();
        incrementalMicros.add(incrementalWatch.elapsedMicroseconds);
        incrementalWriteBytes +=
            utf8.encode(document).length + utf8.encode(summary).length;
        for (final index in changed) {
          incrementalWriteBytes += utf8.encode(packed.messages[index]).length;
        }
        changedMessageRows += changed.length;
        expect(changed, [1]);
        expect(packed.attachments.length, 2);
        previous = packed;
      }
      final report = {
        'benchmark': 'wfform history checkpoint preparation',
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'runtime': Platform.version,
        'execution':
            'Flutter test Dart VM; synthetic data; no browser or IndexedDB timing',
        'command':
            'flutter test tool/history_benchmark.dart --reporter expanded',
        'fixture': {
          'files': 2,
          'bytesPerFile': fileBytes,
          'totalRawAttachmentBytes': fileBytes * 2,
          'format': 'Valid 1px PNG with ancillary tEXt chunk',
          'checkpoints': checkpointCount,
        },
        'coldNormalizedPreparationMicroseconds': firstWatch.elapsedMicroseconds,
        'legacy': {
          'microseconds': legacyMicros,
          'medianMicroseconds': median(legacyMicros),
          'modeledCheckpointWriteBytes': legacyWriteBytes,
        },
        'incremental': {
          'microseconds': incrementalMicros,
          'medianMicroseconds': median(incrementalMicros),
          'modeledCheckpointWriteBytes': incrementalWriteBytes,
          'changedMessageRows': changedMessageRows,
          'initialAttachmentBytesStoredOnce': fileBytes * 2,
          'attachmentBytesRewrittenDuringCheckpoints': 0,
        },
        'limits': [
          'Preparation timings are VM wall-clock observations, not release-browser frame time or IndexedDB latency.',
          'Write sizes model the payload queued by each implementation; browser encoding, transaction and filesystem overhead are not measured.',
          'The initial normalized save writes 12 MiB of bytes plus its metadata; checkpoints measured here begin after that commit.',
          'One fixture and one machine do not establish performance across devices or long conversations.',
        ],
      };
      await Directory('outputs').create(recursive: true);
      await File(
        'outputs/history-performance.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      // Keep the terminal useful without dumping fixture payloads.
      // ignore: avoid_print
      print(
        'legacy median ${median(legacyMicros)}µs; incremental median ${median(incrementalMicros)}µs; modeled checkpoint bytes $legacyWriteBytes → $incrementalWriteBytes',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
