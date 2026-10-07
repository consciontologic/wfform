import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'attachment_picker.dart';
import 'diagnostics.dart';
import 'transport.dart';

AttachmentPicker createPicker() => BrowserAttachmentPicker();

class BrowserAttachmentPicker implements AttachmentPicker {
  CancelToken? _active;
  bool _disposed = false;

  @override
  Future<List<PickedAttachmentFile>> pick({
    required Set<String> allowedMimeTypes,
    int existingCount = 0,
    int existingBytes = 0,
    CancelToken? cancel,
  }) async {
    throwIfAttachmentCancelled(cancel);
    if (_disposed) {
      throw const AppFailure(
        FailureKind.cancelled,
        'Attachment picker is closed.',
      );
    }
    if (_active != null) {
      throw const AppFailure(
        FailureKind.configuration,
        'A file picker is already open. Finish that selection first.',
      );
    }
    validateAttachmentBudget(
      allowedMimeTypes: allowedMimeTypes,
      existingCount: existingCount,
      existingBytes: existingBytes,
    );
    if (existingCount == maxAttachmentFiles ||
        existingBytes == maxAttachmentTotalBytes) {
      throw const AppFailure(
        FailureKind.configuration,
        'The attachment limit is reached. Remove an attachment before adding another.',
      );
    }
    final token = CancelToken();
    _active = token;
    var finished = false;
    cancel?.whenCancelled.then((_) {
      if (!finished) token.cancel();
    });
    try {
      // Opens synchronously before this method's first await, retaining the gesture.
      final files = await _chooseFiles(allowedMimeTypes, token);
      return await readAttachmentSources(
        files.map(_BrowserFileSource.new).toList(),
        allowedMimeTypes: allowedMimeTypes,
        existingCount: existingCount,
        existingBytes: existingBytes,
        cancel: token,
      );
    } finally {
      finished = true;
      token.cancel();
      if (identical(_active, token)) _active = null;
    }
  }

  Future<List<web.File>> _chooseFiles(Set<String> types, CancelToken token) {
    final completion = Completer<List<web.File>>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true
      // Text/source files may have custom extensions or no extension. Validate
      // MIME, size and UTF-8 bytes after selection instead of hiding such files.
      ..accept = types.contains('text/plain') ? '' : types.join(',')
      ..tabIndex = -1;
    input.style.display = 'none';
    input.setAttribute('aria-hidden', 'true');
    final change = ((web.Event _) {
      if (completion.isCompleted) return;
      final files = input.files;
      completion.complete(
        files == null
            ? const []
            : [
                for (var index = 0; index < files.length; index++)
                  files.item(index)!,
              ],
      );
    }).toJS;
    final cancelled = ((web.Event _) {
      if (!completion.isCompleted) completion.complete(const []);
    }).toJS;
    input.addEventListener('change', change);
    input.addEventListener('cancel', cancelled);
    web.document.body?.append(input);
    token.whenCancelled.then((_) {
      if (!completion.isCompleted) {
        completion.completeError(
          const AppFailure(
            FailureKind.cancelled,
            'Attachment selection cancelled.',
          ),
        );
      }
    });
    final result = completion.future.whenComplete(() {
      input.removeEventListener('change', change);
      input.removeEventListener('cancel', cancelled);
      input.remove();
    });
    try {
      input.click();
    } catch (_) {
      if (!completion.isCompleted) {
        completion.completeError(
          const AppFailure(
            FailureKind.configuration,
            'The browser could not open its file dialog. Use the Attach button and try again.',
            retryable: true,
          ),
        );
      }
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _active?.cancel();
  }
}

class _BrowserFileSource implements AttachmentFileSource {
  _BrowserFileSource(this.file);
  final web.File file;
  @override
  String get name => file.name;
  @override
  String get mimeType => file.type;
  @override
  int get byteLength => file.size;

  @override
  Future<Uint8List> readBytes({CancelToken? cancel}) {
    throwIfAttachmentCancelled(cancel);
    final reader = web.FileReader();
    final completion = Completer<Uint8List>();
    final loaded = ((web.Event _) {
      if (completion.isCompleted) return;
      try {
        final bytes = (reader.result as JSArrayBuffer).toDart.asUint8List();
        completion.complete(bytes);
      } catch (_) {
        completion.completeError(
          const AppFailure(
            FailureKind.storage,
            'The selected file returned unreadable data. Select it again.',
            retryable: true,
          ),
        );
      }
    }).toJS;
    final failed = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          const AppFailure(
            FailureKind.storage,
            'A selected file could not be read. Check that it is still available and try again.',
            retryable: true,
          ),
        );
      }
    }).toJS;
    final aborted = ((web.Event _) {
      if (!completion.isCompleted) {
        completion.completeError(
          const AppFailure(
            FailureKind.cancelled,
            'Attachment reading cancelled.',
          ),
        );
      }
    }).toJS;
    reader.addEventListener('load', loaded);
    reader.addEventListener('error', failed);
    reader.addEventListener('abort', aborted);
    cancel?.whenCancelled.then((_) {
      if (!completion.isCompleted) {
        reader.abort();
        if (!completion.isCompleted) {
          completion.completeError(
            const AppFailure(
              FailureKind.cancelled,
              'Attachment reading cancelled.',
            ),
          );
        }
      }
    });
    final result = completion.future
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            reader.abort();
            throw const AppFailure(
              FailureKind.timeout,
              'Reading the selected file timed out. Select a smaller local file and try again.',
              retryable: true,
            );
          },
        )
        .whenComplete(() {
          reader.removeEventListener('load', loaded);
          reader.removeEventListener('error', failed);
          reader.removeEventListener('abort', aborted);
        });
    try {
      reader.readAsArrayBuffer(file);
    } catch (_) {
      if (!completion.isCompleted) {
        completion.completeError(
          const AppFailure(
            FailureKind.storage,
            'The browser could not read a selected file. Select it again.',
            retryable: true,
          ),
        );
      }
    }
    return result;
  }
}
