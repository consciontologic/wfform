import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/app/app_identity.dart';
import 'package:wfform/presentation/studio_app.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';

import 'studio_test.dart' show Harness, FakePlatform, FakeTransport, composer;

class _LinksPlatform extends FakePlatform {
  final opened = <Uri>[];
  bool fail = false;

  @override
  void openUrl(Uri url) {
    if (fail) throw UnsupportedError('Fixture has no URL opener');
    opened.add(url);
  }
}

Future<(StudioState, _LinksPlatform)> _mount(
  WidgetTester tester,
  Size size, {
  double scale = 1,
}) async {
  final platform = _LinksPlatform();
  final state = StudioState(
    config: Harness.config,
    transport: FakeTransport(),
    store: MemoryStore(),
    platform: platform,
    diagnostics: Diagnostics(Harness.config),
  );
  state.setTextScale(scale);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await state.initialize();
  await tester.pumpWidget(StudioApp(state: state));
  await tester.pumpAndSettle();
  return (state, platform);
}

Finder get _footer => find.byKey(const ValueKey('app-footer'));

void _expectAdjacentSourceLink(WidgetTester tester) {
  final version = tester.getRect(find.text('v$appVersion'));
  final source = find.byKey(const ValueKey('footer-github'));
  final sourceBounds = tester.getRect(source);
  final footer = tester.getRect(_footer);
  expect(sourceBounds.left, greaterThanOrEqualTo(version.right));
  expect(sourceBounds.left - version.right, lessThanOrEqualTo(12));
  expect(version.left - footer.left, lessThanOrEqualTo(24));
  expect(sourceBounds.right, lessThan(footer.right));
  expect(sourceBounds.center.dy, closeTo(version.center.dy, .1));
  expect(tester.widget<TextButton>(source).child, isA<Text>());
  expect(find.text('GitHub').hitTestable(), findsOneWidget);
}

void main() {
  setUpAll(() async {
    // Use the shipped font for tight, large-text layout checks. Flutter's
    // square-glyph test font does not represent the app's measured text width.
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
  });

  test('release version is 0.1.2', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(appVersion, '0.1.2');
    expect(
      RegExp(
        r'^version: (.+)\+',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1),
      appVersion,
    );
    expect(
      RegExp(r'^version: 0\.1\.2\+3$', multiLine: true).hasMatch(pubspec),
      isTrue,
    );
  });

  testWidgets(
    'desktop footer exposes information and source links with version',
    (tester) async {
      final (state, platform) = await _mount(tester, const Size(1440, 900));
      expect(_footer, findsOneWidget);
      expect(find.text('v0.1.2'), findsOneWidget);
      _expectAdjacentSourceLink(tester);
      await tester.enterText(composer, 'Keep my draft');
      for (final entry in {
        'About': 'about.html',
        'Terms and conditions': 'terms.html',
        'Liability': 'liability.html',
        'GitHub': 'https://github.com/consciontologic/wfform',
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump();
        expect(platform.opened.last, Uri.base.resolve(entry.value));
        expect(state.draft, 'Keep my draft');
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'Keep my draft',
        );
      }
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
      expect(tester.getBottomRight(_footer).dy, 900);
      expect(tester.takeException(), isNull);
      await state.flushHistory();
    },
  );

  testWidgets('compact large text footer keeps links and composer reachable', (
    tester,
  ) async {
    final (_, platform) = await _mount(tester, const Size(320, 740), scale: 2);
    expect(_footer, findsOneWidget);
    expect(find.text('v0.1.2'), findsOneWidget);
    _expectAdjacentSourceLink(tester);
    expect(tester.getSize(_footer).height, lessThanOrEqualTo(56));
    expect(composer.hitTestable(), findsOneWidget);
    for (final label in ['About', 'Terms and conditions', 'Liability']) {
      await tester.tap(find.byTooltip('Information links'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(platform.opened.map((url) => url.path.split('/').last), [
      'about.html',
      'terms.html',
      'liability.html',
    ]);
    await tester.tap(find.byTooltip('GitHub source code'));
    await tester.pump();
    expect(
      platform.opened.last.toString(),
      'https://github.com/consciontologic/wfform',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(_footer, findsNothing);
    expect(composer.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plain source link stays beside version through resizing', (
    tester,
  ) async {
    final (state, _) = await _mount(tester, const Size(1440, 900));
    _expectAdjacentSourceLink(tester);
    tester.view.physicalSize = const Size(750, 900);
    state.setTextScale(1.25);
    await tester.pumpAndSettle();
    _expectAdjacentSourceLink(tester);
    tester.view.physicalSize = const Size(320, 740);
    state.setTextScale(2);
    await tester.pumpAndSettle();
    _expectAdjacentSourceLink(tester);
    expect(find.byTooltip('Information links').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer links have semantics and keyboard activation', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final (_, platform) = await _mount(tester, const Size(1440, 900));
    expect(_footer, findsOneWidget);
    final source = find.byKey(const ValueKey('footer-source'));
    expect(tester.getSemantics(source).flagsCollection.isLink, isTrue);
    // Traverse the real app's controls to the first footer link.
    for (
      var i = 0;
      i < 40 && !Focus.of(tester.element(find.text('GitHub'))).hasFocus;
      i++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(Focus.of(tester.element(find.text('GitHub'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(platform.opened.last.toString(), sourceRepositoryUrl);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final link = find.byKey(const ValueKey('footer-about'));
    expect(tester.getSemantics(link).flagsCollection.isLink, isTrue);
    expect(Focus.of(tester.element(find.text('About'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(platform.opened.last.path.endsWith('about.html'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(platform.opened.last.path.endsWith('terms.html'), isTrue);
    handle.dispose();
  });

  testWidgets('unavailable platform opener shows an actionable failure', (
    tester,
  ) async {
    final (state, platform) = await _mount(tester, const Size(1440, 900));
    expect(_footer, findsOneWidget);
    platform.fail = true;
    await tester.tap(find.text('About'));
    await tester.pump();
    expect(find.textContaining('Could not open'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(state.diagnostics.events.first.data['operation'], 'link.open');
    expect(tester.takeException(), isNull);
  });
}
