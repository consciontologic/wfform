import '../shared/diagnostics.dart';
import '../shared/platform.dart';

/// Browser-local override. An empty value is an intentional clear, not absence.
/// Use the raw persistent store: a fallback store cannot confirm durability.
class CredentialPreference {
  CredentialPreference(this._store, this._diagnostics);

  static const storageKey = 'wfform.apiKey.v1';
  static const maxKeyLength = 4096;
  final LocalStore _store;
  final Diagnostics _diagnostics;
  String? _overrideValue;
  AppFailure? _error;

  String? get overrideValue => _overrideValue;
  AppFailure? get error => _error;
  String resolve(String fallback) => _overrideValue ?? fallback;

  /// A failed read disables credentials until a successful replacement. This
  /// avoids resurrecting a runtime key over an unreadable explicit clear.
  void load() {
    try {
      final value = _store.read(storageKey);
      if (value != null && !_valid(value)) {
        throw const FormatException('Invalid stored credential');
      }
      _overrideValue = value?.trim();
      _error = null;
      if (_overrideValue != null) _diagnostics.addSecret(_overrideValue!);
    } catch (_) {
      _overrideValue = '';
      _record(
        'credential.load',
        const AppFailure(
          FailureKind.storage,
          'The saved API key could not be read. Enter and save a key in Settings to restore the connection.',
          retryable: true,
        ),
      );
    }
  }

  /// Saves/replaces the key, or stores an explicit clear for an empty key.
  /// Only reports success after the persistent store returns the same value.
  /// On failure, the in-memory credential is unchanged; persistence is unknown.
  void save(String value) {
    if (!_valid(value)) {
      const failure = AppFailure(
        FailureKind.configuration,
        'The API key must be a single line of at most 4096 characters.',
      );
      _record('credential.save', failure);
      throw failure;
    }
    final normalized = value.trim();
    try {
      _store.write(storageKey, normalized);
      if (_store.read(storageKey) != normalized) {
        throw const FormatException('Credential write was not confirmed');
      }
    } catch (_) {
      const failure = AppFailure(
        FailureKind.storage,
        'Could not confirm the API key was saved in this browser. Check browser storage and retry. The current connection is unchanged.',
        retryable: true,
      );
      _record('credential.save', failure);
      throw failure;
    }
    _overrideValue = normalized;
    _error = null;
    _diagnostics.addSecret(normalized);
  }

  bool _valid(String value) =>
      value.length <= maxKeyLength &&
      !value.contains('\r') &&
      !value.contains('\n');

  void _record(String operation, AppFailure failure) {
    _error = failure;
    // Never retain the key or the store's exception text: either can contain
    // credentials, even when the exception was produced by browser storage.
    _diagnostics.record(operation, failure: failure);
  }
}
