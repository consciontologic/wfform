/// All policy lives here; adapters and widgets consume typed values.
class AppConfig {
  const AppConfig({
    this.apiBaseUrl = 'https://openrouter.ai/api/v1',
    this.apiKey = '',
    this.requestTimeout = const Duration(seconds: 90),
    this.probeTimeout = const Duration(seconds: 25),
    this.healthTtl = const Duration(minutes: 5),
    this.cooldown = const Duration(seconds: 15),
    this.maxBackoff = const Duration(minutes: 5),
    this.cacheTtl = const Duration(hours: 24),
    this.maxDiagnostics = 100,
    this.maxDetailChars = 2000,
    this.maxMessages = 80,
    this.maxResponseChars = 120000,
    this.maxCatalogBytes = 8000000,
    this.firstResponseTimeout = const Duration(seconds: 90),
    this.streamIdleTimeout = const Duration(seconds: 45),
    this.streamOverallTimeout = const Duration(minutes: 5),
    this.endpointTtl = const Duration(minutes: 30),
    this.quotaTtl = const Duration(minutes: 5),
    this.maxOutputTokens = 2048,
  });
  final String apiBaseUrl, apiKey;
  final Duration requestTimeout,
      probeTimeout,
      healthTtl,
      cooldown,
      maxBackoff,
      cacheTtl;
  final int maxDiagnostics,
      maxDetailChars,
      maxMessages,
      maxResponseChars,
      maxCatalogBytes;
  final Duration firstResponseTimeout,
      streamIdleTimeout,
      streamOverallTimeout,
      endpointTtl,
      quotaTtl;
  final int maxOutputTokens;

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://openrouter.ai/api/v1',
    ),
    apiKey: String.fromEnvironment('API_KEY'),
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    String text(String key, String fallback) {
      if (!json.containsKey(key)) return fallback;
      if (json[key] is! String) throw FormatException('$key must be a string');
      return json[key] as String;
    }

    int number(String key, int fallback) {
      if (!json.containsKey(key)) return fallback;
      if (json[key] is! int) throw FormatException('$key must be an integer');
      return json[key] as int;
    }

    final config = AppConfig(
      apiBaseUrl: text(
        'apiBaseUrl',
        'https://openrouter.ai/api/v1',
      ).replaceFirst(RegExp(r'/+$'), ''),
      apiKey: text('apiKey', ''),
      requestTimeout: Duration(seconds: number('requestTimeoutSeconds', 90)),
      probeTimeout: Duration(seconds: number('probeTimeoutSeconds', 25)),
      healthTtl: Duration(seconds: number('healthTtlSeconds', 300)),
      cooldown: Duration(seconds: number('cooldownSeconds', 15)),
      maxBackoff: Duration(seconds: number('maxBackoffSeconds', 300)),
      cacheTtl: Duration(seconds: number('cacheTtlSeconds', 86400)),
      maxDiagnostics: number('maxDiagnostics', 100),
      maxDetailChars: number('maxDetailChars', 2000),
      maxMessages: number('maxMessages', 80),
      maxResponseChars: number('maxResponseChars', 120000),
      maxCatalogBytes: number('maxCatalogBytes', 8000000),
      firstResponseTimeout: Duration(
        seconds: number('firstResponseTimeoutSeconds', 90),
      ),
      streamIdleTimeout: Duration(
        seconds: number('streamIdleTimeoutSeconds', 45),
      ),
      streamOverallTimeout: Duration(
        seconds: number('streamOverallTimeoutSeconds', 300),
      ),
      endpointTtl: Duration(seconds: number('endpointTtlSeconds', 1800)),
      quotaTtl: Duration(seconds: number('quotaTtlSeconds', 300)),
      maxOutputTokens: number('maxOutputTokens', 2048),
    );
    final problems = config.validate();
    if (problems.isNotEmpty) throw FormatException(problems.join('; '));
    return config;
  }

  List<String> validate() {
    final errors = <String>[];
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      errors.add(
        'apiBaseUrl must be HTTPS (or HTTP localhost), without credentials, query, or fragment',
      );
    }
    for (final entry in {
      'requestTimeout': requestTimeout,
      'probeTimeout': probeTimeout,
      'healthTtl': healthTtl,
      'cooldown': cooldown,
      'maxBackoff': maxBackoff,
      'cacheTtl': cacheTtl,
      'firstResponseTimeout': firstResponseTimeout,
      'streamIdleTimeout': streamIdleTimeout,
      'streamOverallTimeout': streamOverallTimeout,
      'endpointTtl': endpointTtl,
      'quotaTtl': quotaTtl,
    }.entries) {
      if (entry.value < const Duration(seconds: 1) ||
          entry.value > const Duration(days: 30)) {
        errors.add('${entry.key} must be between 1 second and 30 days');
      }
    }
    if (maxBackoff < cooldown) {
      errors.add('maxBackoff must be at least cooldown');
    }
    if (streamOverallTimeout < firstResponseTimeout ||
        streamOverallTimeout < streamIdleTimeout) {
      errors.add(
        'streamOverallTimeout must cover first-response and idle timeouts',
      );
    }
    if (maxOutputTokens < 16 || maxOutputTokens > 32768) {
      errors.add('maxOutputTokens must be 16–32768');
    }
    if (maxDiagnostics < 10 || maxDiagnostics > 1000) {
      errors.add('maxDiagnostics must be 10–1000');
    }
    if (maxDetailChars < 100 || maxDetailChars > 10000) {
      errors.add('maxDetailChars must be 100–10000');
    }
    if (maxMessages < 2 || maxMessages > 200) {
      errors.add('maxMessages must be 2–200');
    }
    if (maxResponseChars < 1024 || maxResponseChars > 1000000) {
      errors.add('maxResponseChars must be 1024–1000000');
    }
    if (maxCatalogBytes < 1024 || maxCatalogBytes > 20000000) {
      errors.add('maxCatalogBytes must be 1024–20000000');
    }
    if (apiKey.contains('\n') || apiKey.contains('\r')) {
      errors.add('apiKey must be a single line');
    }
    return errors;
  }

  AppConfig copyWith({String? apiKey}) => AppConfig(
    apiBaseUrl: apiBaseUrl,
    apiKey: apiKey ?? this.apiKey,
    requestTimeout: requestTimeout,
    probeTimeout: probeTimeout,
    healthTtl: healthTtl,
    cooldown: cooldown,
    maxBackoff: maxBackoff,
    cacheTtl: cacheTtl,
    maxDiagnostics: maxDiagnostics,
    maxDetailChars: maxDetailChars,
    maxMessages: maxMessages,
    maxResponseChars: maxResponseChars,
    maxCatalogBytes: maxCatalogBytes,
    firstResponseTimeout: firstResponseTimeout,
    streamIdleTimeout: streamIdleTimeout,
    streamOverallTimeout: streamOverallTimeout,
    endpointTtl: endpointTtl,
    quotaTtl: quotaTtl,
    maxOutputTokens: maxOutputTokens,
  );
}
