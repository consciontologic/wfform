/// Recognize only generated content identities; arbitrary URL query data is unsafe.
String? pwaCacheBuild(Uri uri) {
  final parameters = uri.queryParametersAll;
  if (parameters.length != 1 || parameters['build']?.length != 1) return null;
  final build = parameters['build']!.single;
  return RegExp(r'^[a-f0-9]{64}$').hasMatch(build) ? build : null;
}

String? pwaCompletionBuild(Uri uri) {
  if (uri.path.endsWith('/release.json')) {
    final build = pwaCacheBuild(uri);
    if (build != null) return build;
  }
  if (uri.hasQuery) return null;
  return RegExp(
    r'/__releases/([a-f0-9]{64})/release\.json$',
  ).firstMatch(uri.path)?.group(1);
}
