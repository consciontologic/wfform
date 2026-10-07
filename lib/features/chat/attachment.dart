import 'dart:convert';
import 'dart:math';

import '../../shared/attachment_limits.dart';
import '../../shared/diagnostics.dart';
import '../models/model.dart';
import '../documents/document_format.dart';

enum AttachmentKind { image, audio, video, pdf, text }

/// Leave room for text and record metadata below the history record size limit.
const maxConversationAttachmentBase64Chars = 24 * 1024 * 1024;

/// Immutable, validated local file payload. No remote URL fetching, executable
/// file rendering, parser plugin inference, or mutable byte buffer is retained.
class ChatAttachment {
  ChatAttachment._({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.base64Data,
    required this.byteLength,
    this.textContent,
  });
  final String id, name, mimeType, base64Data;
  final AttachmentKind kind;
  final int byteLength;
  final String? textContent;
  DocumentFormat get documentFormat => documentFormatFor(name);

  factory ChatAttachment.fromBytes({
    String? id,
    required String name,
    required String mimeType,
    required List<int> bytes,
  }) {
    final mime = normalizeAttachmentMime(mimeType);
    final kind = _kindForMime(mime);
    final attachmentId =
        id ??
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
    _validateMetadata(attachmentId, name, bytes.length);
    final textContent = kind == AttachmentKind.text
        ? decodeTextDocument(bytes)
        : null;
    if (kind != AttachmentKind.text && !_signatureMatches(mime, bytes)) {
      throw _attachmentFailure(
        'The file content does not match its declared format. Choose a valid supported file.',
      );
    }
    return ChatAttachment._(
      id: attachmentId,
      name: name,
      mimeType: mime,
      kind: kind,
      base64Data: base64Encode(bytes),
      byteLength: bytes.length,
      textContent: textContent,
    );
  }

  factory ChatAttachment.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['mimeType'] is! String ||
        value['kind'] is! String ||
        value['base64Data'] is! String ||
        value['byteLength'] is! int) {
      throw _attachmentFailure(
        'A stored attachment has an unsupported or damaged format.',
      );
    }
    final encoded = value['base64Data'] as String;
    final length = value['byteLength'] as int;
    _validateMetadata(value['id'] as String, value['name'] as String, length);
    if (encoded.length > ((maxAttachmentFileBytes + 2) ~/ 3) * 4) {
      throw _attachmentFailure(
        'A stored attachment exceeds the local file size limit.',
      );
    }
    List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      throw _attachmentFailure(
        'A stored attachment contains invalid base64 data.',
      );
    }
    if (bytes.length != length || base64Encode(bytes) != encoded) {
      throw _attachmentFailure(
        'A stored attachment has inconsistent data or size metadata.',
      );
    }
    final attachment = ChatAttachment.fromBytes(
      id: value['id'] as String,
      name: value['name'] as String,
      mimeType: value['mimeType'] as String,
      bytes: bytes,
    );
    if (attachment.kind.name != value['kind']) {
      throw _attachmentFailure(
        'A stored attachment type does not match its content format.',
      );
    }
    return attachment;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'kind': kind.name,
    'base64Data': base64Data,
    'byteLength': byteLength,
  };

  String get dataUrl => 'data:$mimeType;base64,$base64Data';
  String get label => kind == AttachmentKind.pdf ? 'PDF' : kind.name;

  static Set<String> mimeTypesFor(FreeModel model) =>
      model.allowedAttachmentMimeTypes;

  Map<String, Object?> toContentPart() => switch (kind) {
    AttachmentKind.text => {'type': 'text', 'text': textRequestContent},
    AttachmentKind.image => {
      'type': 'image_url',
      'image_url': {'url': dataUrl},
    },
    AttachmentKind.audio => {
      'type': 'input_audio',
      'input_audio': {
        'data': base64Data,
        'format': mimeType == 'audio/wav' ? 'wav' : 'mp3',
      },
    },
    AttachmentKind.video => {
      'type': 'video_url',
      'video_url': {'url': dataUrl},
    },
    AttachmentKind.pdf => {
      'type': 'file',
      'file': {'filename': name, 'file_data': dataUrl},
    },
  };

  late final String textRequestContent =
      'Attached file: $name (${documentFormat.label})\n\n${textContent ?? ''}';
  late final int estimatedTextTokens =
      (utf8.encode(textRequestContent).length / 3).ceil() + 6;

  String? compatibilityIssue(FreeModel model) {
    final supports = switch (kind) {
      AttachmentKind.image => model.acceptsImages,
      AttachmentKind.audio => model.acceptsAudio,
      AttachmentKind.video => model.acceptsVideo,
      AttachmentKind.pdf => model.acceptsPdf,
      AttachmentKind.text => model.acceptsTextFiles,
    };
    if (!supports) {
      return model.attachmentUnavailableReason(
            kind == AttachmentKind.pdf ? 'file' : kind.name,
          ) ??
          'This model cannot safely accept this ${kind.name} attachment at zero cost.';
    }
    return null;
  }
}

String normalizeAttachmentMime(String mime) => isTextDocumentMime(mime)
    ? 'text/plain'
    : switch (mime.trim().toLowerCase()) {
        'image/jpg' => 'image/jpeg',
        'audio/x-wav' || 'audio/wave' => 'audio/wav',
        'audio/mp3' => 'audio/mpeg',
        final normalized => normalized,
      };

AttachmentKind _kindForMime(String mime) => switch (mime) {
  'text/plain' => AttachmentKind.text,
  'image/jpeg' ||
  'image/png' ||
  'image/gif' ||
  'image/webp' => AttachmentKind.image,
  'audio/mpeg' || 'audio/wav' => AttachmentKind.audio,
  'video/mp4' => AttachmentKind.video,
  'application/pdf' => AttachmentKind.pdf,
  _ => throw _attachmentFailure(
    'Unsupported file format. Use UTF-8 text/source, JPEG, PNG, GIF, WebP, MP3, WAV, MP4, or a native PDF.',
  ),
};

void _validateMetadata(String id, String name, int bytes) {
  if (id.isEmpty ||
      id.length > 100 ||
      name.trim().isEmpty ||
      name.length > 240 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(id + name)) {
    throw _attachmentFailure(
      'The attachment has invalid identifying metadata.',
    );
  }
  if (bytes <= 0 || bytes > maxAttachmentFileBytes) {
    throw _attachmentFailure(
      'Each attachment must be nonempty and at most 8 MiB.',
    );
  }
}

bool _signatureMatches(String mime, List<int> bytes) {
  bool starts(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  bool text(String value, [int offset = 0]) =>
      starts(ascii.encode(value), offset);
  return switch (mime) {
    'image/png' => starts([137, 80, 78, 71, 13, 10, 26, 10]),
    'image/jpeg' => starts([255, 216, 255]),
    'image/gif' => text('GIF87a') || text('GIF89a'),
    'image/webp' => text('RIFF') && text('WEBP', 8),
    'audio/wav' => text('RIFF') && text('WAVE', 8),
    'audio/mpeg' =>
      text('ID3') ||
          (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224),
    'video/mp4' => text('ftyp', 4),
    'application/pdf' => text('%PDF-'),
    _ => false,
  };
}

AppFailure _attachmentFailure(String message) =>
    AppFailure(FailureKind.configuration, message);

/// Per-turn bounds are applied again at the domain boundary, including restored
/// sessions and explicit retries. Picker validation is only an earlier UX check.
void validateAttachments(List<ChatAttachment> attachments, {FreeModel? model}) {
  if (attachments.length > maxAttachmentFiles) {
    throw _attachmentFailure('Attach at most 4 files to one message.');
  }
  var bytes = 0;
  final ids = <String>{};
  for (final attachment in attachments) {
    if (!ids.add(attachment.id)) {
      throw _attachmentFailure(
        'The same attachment appears more than once in this message.',
      );
    }
    bytes += attachment.byteLength;
    if (model != null) {
      final issue = attachment.compatibilityIssue(model);
      if (issue != null) throw _attachmentFailure(issue);
    }
  }
  if (bytes > maxAttachmentTotalBytes) {
    throw _attachmentFailure(
      'Attachments in one message must total at most 12 MiB.',
    );
  }
}
