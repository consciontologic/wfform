import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app/studio_state.dart';
import 'config/app_config.dart';
import 'presentation/studio_app.dart';
import 'shared/diagnostics.dart';
import 'shared/platform.dart';
import 'shared/transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the accessible Flutter semantics tree available from first render.
  WidgetsBinding.instance.ensureSemantics();
  final transport = HttpApiTransport();
  final config = AppConfig.fromEnvironment();
  Future<AppConfig?> loadConfiguration() async {
    try {
      final response = await transport.send(
        'GET',
        Uri.base.resolve('config/local.json'),
        timeout: const Duration(seconds: 4),
        headers: {'Cache-Control': 'no-store'},
      );
      final text = await response.readText(maxBytes: 16384);
      if (response.status == 200) {
        final value = jsonDecode(text);
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Configuration must be a JSON object');
        }
        return AppConfig.fromJson(value);
      } else if (response.status != 404) {
        throw AppFailure(
          FailureKind.configuration,
          'Local configuration could not be loaded. Add a key in Settings.',
          status: response.status,
        );
      }
    } catch (error) {
      throw AppFailure(
        FailureKind.configuration,
        'Local configuration is unavailable or invalid. Default policies are active; add a key in Settings.',
        details: error is FormatException
            ? error.message
            : 'Network-only configuration unavailable, including during offline startup.',
      );
    }
    return null;
  }

  final diagnostics = Diagnostics(config);
  FlutterError.onError = (details) {
    diagnostics.record(
      'Flutter framework',
      failure: AppFailure(
        FailureKind.flutter,
        'The interface reported an error. Inspect this diagnostic and reload if necessary.',
        details:
            'Exception type: ${details.exception.runtimeType}; library: ${details.library ?? 'unknown'}',
      ),
    );
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.record(
      'unhandled Dart error',
      failure: AppFailure(
        FailureKind.flutter,
        'An unexpected application error occurred.',
        details: 'Exception type: ${error.runtimeType}',
      ),
    );
    return true;
  };
  final state = StudioState(
    config: config,
    transport: transport,
    store: createLocalStore(),
    recoveryStore: createSessionStore(),
    platform: createPlatformBridge(),
    diagnostics: diagnostics,
  );
  runApp(StudioApp(state: state));
  unawaited(
    state.initialize(loadConfiguration: kIsWeb ? loadConfiguration : null),
  );
}
