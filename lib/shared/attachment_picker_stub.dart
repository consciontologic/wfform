import 'attachment_picker.dart';
import 'diagnostics.dart';
import 'transport.dart';

AttachmentPicker createPicker() => UnsupportedAttachmentPicker();

class UnsupportedAttachmentPicker implements AttachmentPicker {
  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    throwIfAttachmentCancelled(cancel);
    throw const AppFailure(
      FailureKind.configuration,
      'File selection is unavailable on this platform. The browser picker is supported on web.',
    );
  }

  @override
  void dispose() {}
}
