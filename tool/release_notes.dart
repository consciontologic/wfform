import 'dart:io';
import 'release_version.dart';

String releaseNotes(String changelog, String version) {
  final heading = RegExp(
    '^## \\[${RegExp.escape(version)}\\].*\$',
    multiLine: true,
  ).firstMatch(changelog);
  if (heading == null) {
    throw StateError('CHANGELOG.md needs a release section for $version.');
  }
  final next = RegExp(
    r'^## ',
    multiLine: true,
  ).firstMatch(changelog.substring(heading.end));
  final end = next == null ? changelog.length : heading.end + next.start;
  final notes = changelog.substring(heading.start, end).trim();
  if (notes.split('\n').length < 3) {
    throw StateError('Release notes must describe $version.');
  }
  return '$notes\n';
}

void main() => stdout.write(
  releaseNotes(File('CHANGELOG.md').readAsStringSync(), readReleaseVersion()),
);
