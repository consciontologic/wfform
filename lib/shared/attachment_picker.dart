import 'dart:typed_data';
import '../features/documents/document_format.dart';

import 'attachment_limits.dart';
import 'attachment_picker_stub.dart'
    if (dart.library.js_interop) 'attachment_picker_web.dart'
    as implementation;
import 'diagnostics.dart';
import 'transport.dart';

export 'attachment_limits.dart';

const supportedAttachmentMimeTypes = {
  'text/plain',
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'audio/mpeg',
  'audio/wav',
  'video/mp4',
  'application/pdf',
};

/// Raw user-selected bytes. Domain validation/encoding happens after selection.
class PickedAttachmentFile {
  const PickedAttachmentFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

abstract interface class AttachmentPicker {
  /// Call directly from a user gesture. Empty result means the dialog was cancelled.
  /// Cancellation through [cancel] or [dispose] reports FailureKind.cancelled.
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  });
  void dispose();
}

AttachmentPicker createAttachmentPicker() => implementation.createPicker();

/// Small platform boundary keeps metadata-first validation deterministic in tests.
abstract interface class AttachmentFileSource {
  String get name;
  String get mimeType;
  int get byteLength;
  Future<Uint8List> readBytes({CancelToken? cancel});
}

/// Preserve supported media MIME declarations. Unknown MIME/extension pairs can
/// be UTF-8 source (notably .ts reported as video/mp2t); strict bytes validation
/// decides text eligibility after selection. Media still requires signatures.
String normalizeAttachmentMimeType(String name, String reportedType) {
  final type = reportedType.trim().toLowerCase();
  if (isTextDocumentMime(type)) return 'text/plain';
  if (type.isNotEmpty && type != 'application/octet-stream') {
    return switch (type) {
      'image/jpg' => 'image/jpeg',
      'audio/x-wav' || 'audio/wave' => 'audio/wav',
      'audio/mp3' => 'audio/mpeg',
      _ => supportedAttachmentMimeTypes.contains(type) ? type : 'text/plain',
    };
  }
  final separator = name.lastIndexOf('.');
  if (separator <= 0 || separator == name.length - 1) return 'text/plain';
  final extension = name.substring(separator + 1).toLowerCase();
  return const {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'mp4': 'video/mp4',
        'pdf': 'application/pdf',
      }[extension] ??
      'text/plain';
}

void validateAttachmentBudget({
  required Set<String> allowedMimeTypes,
  required int existingCount,
  required int existingBytes,
}) {
  if (allowedMimeTypes.isEmpty ||
      !supportedAttachmentMimeTypes.containsAll(allowedMimeTypes)) {
    throw const AppFailure(
      FailureKind.configuration,
      'The selected model has no supported attachment types for this picker.',
    );
  }
  if (existingCount < 0 ||
      existingCount > maxAttachmentFiles ||
      existingBytes < 0 ||
      existingBytes > maxAttachmentTotalBytes) {
    throw const AppFailure(
      FailureKind.configuration,
      'The existing attachments exceed the local selection limits. Remove an attachment and try again.',
    );
  }
}

void throwIfAttachmentCancelled(CancelToken? cancel) {
  if (cancel?.isCancelled ?? false) {
    throw const AppFailure(
      FailureKind.cancelled,
      'Attachment selection cancelled.',
    );
  }
}

/// Validates the whole selection before the first allocation, then reads one
/// bounded file at a time. A failed selection does not return partial additions.
Future<List<PickedAttachmentFile>> readAttachmentSources(
  List<AttachmentFileSource> sources, {
  required Set<String> allowedMimeTypes,
  int existingCount = 0,
  int existingBytes = 0,
  CancelToken? cancel,
}) async {
  throwIfAttachmentCancelled(cancel);
  validateAttachmentBudget(
    allowedMimeTypes: allowedMimeTypes,
    existingCount: existingCount,
    existingBytes: existingBytes,
  );
  if (sources.isEmpty) return const [];
  if (sources.length + existingCount > maxAttachmentFiles) {
    throw const AppFailure(
      FailureKind.configuration,
      'Attach at most 4 files per message. Remove a file and try again.',
    );
  }
  var total = existingBytes;
  final types = <String>[];
  for (var index = 0; index < sources.length; index++) {
    final file = sources[index];
    final type = normalizeAttachmentMimeType(file.name, file.mimeType);
    if (!allowedMimeTypes.contains(type)) {
      throw AppFailure(
        FailureKind.configuration,
        'A selected file type is unsupported by this model. Choose one of the offered file types.',
        field: '\$.attachments[$index].mimeType',
        expected: allowedMimeTypes.join(', '),
        actual: type.isEmpty ? 'unknown MIME type' : type,
      );
    }
    final limit = type == 'text/plain'
        ? maxTextDocumentBytes
        : maxAttachmentFileBytes;
    if (file.byteLength <= 0 || file.byteLength > limit) {
      throw AppFailure(
        FailureKind.configuration,
        type == 'text/plain'
            ? 'Text and source files must contain data and be at most 256 KiB.'
            : 'Each attachment must contain data and be at most 8 MiB.',
        field: '\$.attachments[$index].byteLength',
        expected: '1–$limit bytes',
        actual: '${file.byteLength} bytes',
      );
    }
    total += file.byteLength;
    if (total > maxAttachmentTotalBytes) {
      throw const AppFailure(
        FailureKind.configuration,
        'Attachments may total at most 12 MiB per message. Remove a file and try again.',
      );
    }
    types.add(type);
  }
  final result = <PickedAttachmentFile>[];
  for (var index = 0; index < sources.length; index++) {
    throwIfAttachmentCancelled(cancel);
    final source = sources[index];
    final bytes = await source.readBytes(cancel: cancel);
    throwIfAttachmentCancelled(cancel);
    if (bytes.length != source.byteLength) {
      throw AppFailure(
        FailureKind.storage,
        'A selected file changed or could not be read completely. Select it again.',
        field: '\$.attachments[$index].byteLength',
        expected: '${source.byteLength}',
        actual: '${bytes.length}',
        retryable: true,
      );
    }
    if (types[index] == 'text/plain') decodeTextDocument(bytes);
    result.add(
      PickedAttachmentFile(
        name: source.name,
        mimeType: types[index],
        bytes: bytes.asUnmodifiableView(),
      ),
    );
  }
  return List.unmodifiable(result);
}
