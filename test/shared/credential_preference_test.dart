import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/config/credential_preference.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';

class FailingCredentialStore extends MemoryStore {
  bool failRead = false;
  bool failWrite = false;
  bool discardWrite = false;

  @override
  String? read(String key) {
    if (key == CredentialPreference.storageKey && failRead) {
      throw StateError('private-credential-in-storage-exception');
    }
    return super.read(key);
  }

  @override
  void write(String key, String value) {
    if (key == CredentialPreference.storageKey) {
      if (failWrite) {
        throw StateError('private-credential-in-storage-exception');
      }
      if (discardWrite) return;
    }
    super.write(key, value);
  }
}

void main() {
  late FailingCredentialStore store;
  late Diagnostics diagnostics;
  late CredentialPreference preference;
  setUp(() {
    store = FailingCredentialStore();
    diagnostics = Diagnostics(const AppConfig());
    preference = CredentialPreference(store, diagnostics)..load();
  });
  tearDown(() => diagnostics.dispose());

  test('only an absent preference falls back to runtime configuration', () {
    expect(preference.overrideValue, isNull);
    expect(preference.resolve('runtime-key'), 'runtime-key');
    preference.save('  browser-key  ');
    final restored = CredentialPreference(store, diagnostics)..load();
    expect(restored.resolve('runtime-key'), 'browser-key');
    restored.save('replacement-key');
    expect(
      (CredentialPreference(store, diagnostics)..load()).overrideValue,
      'replacement-key',
    );
  });

  test('an explicit clear persists instead of resurrecting a runtime key', () {
    preference.save('browser-key');
    preference.save('');
    expect(store.read(CredentialPreference.storageKey), '');
    final restored = CredentialPreference(store, diagnostics)..load();
    expect(restored.overrideValue, '');
    expect(restored.resolve('runtime-key'), '');
  });

  test(
    'write failure preserves previous preference and emits safe details',
    () {
      preference.save('original-key');
      store.failWrite = true;
      expect(() => preference.save('unsaved-key'), throwsA(isA<AppFailure>()));
      expect(preference.resolve('runtime-key'), 'original-key');
      expect(preference.error?.kind, FailureKind.storage);
      expect(diagnostics.export(), isNot(contains('private-credential')));
      expect(diagnostics.export(), isNot(contains('original-key')));
      expect(diagnostics.export(), isNot(contains('unsaved-key')));
      store.failWrite = false;
      preference.save('retry-key');
      expect(preference.error, isNull);
      expect(preference.overrideValue, 'retry-key');
    },
  );

  test('a store silently discarding writes cannot report a saved key', () {
    store.discardWrite = true;
    expect(() => preference.save('unsaved-key'), throwsA(isA<AppFailure>()));
    expect(preference.overrideValue, isNull);
    expect(preference.error?.kind, FailureKind.storage);
  });

  test(
    'an unreadable write result remains unconfirmed and keeps current key',
    () {
      preference.save('original-key');
      store.failRead = true;
      expect(
        () => preference.save('replacement-key'),
        throwsA(isA<AppFailure>()),
      );
      expect(preference.overrideValue, 'original-key');
      expect(preference.error?.kind, FailureKind.storage);
      // The write may have succeeded: do not promise durable rollback when the
      // readback itself failed. A fresh successful read can establish its state.
      store.failRead = false;
      expect(
        (CredentialPreference(store, diagnostics)..load()).overrideValue,
        'replacement-key',
      );
    },
  );

  test('read failures disable fallback and remain visible without secrets', () {
    store.failRead = true;
    preference.load();
    expect(preference.resolve('runtime-key'), '');
    expect(preference.error?.kind, FailureKind.storage);
    expect(diagnostics.export(), isNot(contains('private-credential')));
  });

  test('malformed and oversized stored keys are not applied or logged', () {
    for (final value in ['key\nsecret', 'x' * 4097]) {
      store.write(CredentialPreference.storageKey, value);
      preference.load();
      expect(preference.resolve('runtime-key'), '');
      expect(preference.error?.kind, FailureKind.storage);
      expect(diagnostics.export(), isNot(contains(value)));
    }
  });

  test(
    'invalid replacement leaves durable and in-memory credentials intact',
    () {
      preference.save('original-key');
      for (final value in ['key\nsecret', 'x' * 4097]) {
        expect(() => preference.save(value), throwsA(isA<AppFailure>()));
        expect(preference.overrideValue, 'original-key');
        expect(store.read(CredentialPreference.storageKey), 'original-key');
      }
    },
  );
}
