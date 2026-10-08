import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/studio_state.dart';
import 'package:wfform/app/app_identity.dart';
import 'package:wfform/app/theme.dart';
import 'package:wfform/features/history/conversation.dart';
import 'package:wfform/features/history/history_repository.dart';
import 'package:wfform/presentation/app_footer.dart';
import 'package:wfform/presentation/studio_app.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';

import 'studio_test.dart' show Harness, FakePlatform, FakeTransport, composer;

class _LinksPlatform extends FakePlatform {
  final opened = <Uri>[];
  final navigated = <Uri>[];
  bool fail = false;

  @override
  void openUrl(Uri url) {
    if (fail) throw UnsupportedError('Fixture has no URL opener');
    opened.add(url);
  }

  @override
  void navigateTo(Uri url) {
    if (fail) throw UnsupportedError('Fixture has no URL opener');
    navigated.add(url);
    opened.add(url);
  }
}

class _CheckpointRepository extends MemoryHistoryRepository {
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> save(
    ConversationRecord record, {
    bool makeActive = false,
  }) async {
    await gate?.future;
    if (fail) throw historyFailure('Fixture storage is full.');
    await super.save(record, makeActive: makeActive);
  }
}

Future<(StudioState, _LinksPlatform)> _mount(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  MemoryHistoryRepository? repository,
  bool sidebarOnly = false,
}) async {
  final platform = _LinksPlatform();
  final state = StudioState(
    config: Harness.config,
    transport: FakeTransport(),
    store: MemoryStore(),
    platform: platform,
    diagnostics: Diagnostics(Harness.config),
    historyRepository: repository,
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
  await tester.pumpWidget(
    sidebarOnly
        ? MaterialApp(
            theme: studioTheme(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: AppFooter(
                    key: const ValueKey('sidebar-app-footer'),
                    state: state,
                    inSidebar: true,
                  ),
                ),
              ),
            ),
          )
        : StudioApp(state: state),
  );
  await tester.pumpAndSettle();
  return (state, platform);
}

Finder get _footer => find.byKey(const ValueKey('app-footer'));
Finder get _sidebarFooter => find.byKey(const ValueKey('sidebar-app-footer'));

void _expectAdjacentSourceLink(WidgetTester tester, {Finder? within}) {
  final version = tester.getRect(find.text('v$appVersion'));
  final source = find.byKey(const ValueKey('footer-github'));
  final sourceBounds = tester.getRect(source);
  final footer = tester.getRect(within ?? _footer);
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

  testWidgets('sidebar links use aligned full-width rows at large text', (
    tester,
  ) async {
    final (_, platform) = await _mount(
      tester,
      const Size(260, 220),
      scale: 2,
      sidebarOnly: true,
    );
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    final informationButtons = [
      for (final label in ['About', 'Terms and conditions', 'Liability'])
        find.widgetWithText(TextButton, label),
    ];
    final rows = informationButtons.map(tester.getRect).toList();
    for (final row in rows) {
      expect(row.width, 236);
      expect(row.left, 12);
    }
    for (var index = 1; index < rows.length; index++) {
      expect(rows[index].top, greaterThanOrEqualTo(rows[index - 1].bottom));
    }
    final versionBounds = tester.getRect(find.text('v$appVersion'));
    final firstLinkBounds = tester.getRect(find.text('About'));
    expect(versionBounds.left, firstLinkBounds.left);
    for (final entry in {
      'GitHub': sourceRepositoryUrl,
      'About': 'about.html',
      'Terms and conditions': 'terms.html',
      'Liability': 'liability.html',
    }.entries) {
      final button = find.widgetWithText(TextButton, entry.key);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(button).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(button).right, lessThanOrEqualTo(260));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(platform.opened.last, Uri.base.resolve(entry.value));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('sidebar About waits for its draft checkpoint', (tester) async {
    final repository = _CheckpointRepository();
    final (state, platform) = await _mount(
      tester,
      const Size(340, 400),
      sidebarOnly: true,
      repository: repository,
    );
    state.setDraft('Preserve sidebar navigation draft');
    repository.gate = Completer<void>();
    await tester.tap(find.text('About'));
    await tester.pump();
    expect(platform.navigated, isEmpty);
    expect(state.draft, 'Preserve sidebar navigation draft');
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(platform.navigated.single, Uri.base.resolve('about.html'));
    final saved = await repository.read(state.activeConversationId!);
    expect(saved!.draft, 'Preserve sidebar navigation draft');
  });

  testWidgets('About waits for durable draft then navigates in same tab', (
    tester,
  ) async {
    final repository = _CheckpointRepository();
    final (state, platform) = await _mount(
      tester,
      const Size(1440, 900),
      repository: repository,
    );
    await tester.enterText(composer, 'Keep unfinished work when returning');
    repository.gate = Completer<void>();
    await tester.tap(find.text('About'));
    await tester.pump();
    expect(platform.opened, isEmpty, reason: 'Do not leave before checkpoint');
    expect(state.draft, 'Keep unfinished work when returning');
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(platform.navigated.single, Uri.base.resolve('about.html'));
    final saved = await repository.read(state.activeConversationId!);
    expect(saved!.draft, 'Keep unfinished work when returning');
    await tester.tap(find.text('GitHub'));
    await tester.pump();
    expect(platform.navigated.length, 1);
    expect(platform.opened.last.toString(), sourceRepositoryUrl);
  });

  testWidgets('failed draft checkpoint keeps information navigation in app', (
    tester,
  ) async {
    final repository = _CheckpointRepository();
    final (state, platform) = await _mount(
      tester,
      const Size(1440, 900),
      repository: repository,
    );
    await tester.enterText(composer, 'Unsaved work must stay here');
    repository.fail = true;
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(platform.opened, isEmpty);
    expect(state.draft, 'Unsaved work must stay here');
    expect(find.textContaining('Fixture storage is full.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('release version is 0.2.3', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(appVersion, '0.2.3');
    expect(
      RegExp(
        r'^version: (.+)\+',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1),
      appVersion,
    );
    expect(
      RegExp(r'^version: 0\.2\.3\+8$', multiLine: true).hasMatch(pubspec),
      isTrue,
    );
  });

  testWidgets(
    'desktop footer exposes information and source links with version',
    (tester) async {
      final (state, platform) = await _mount(tester, const Size(1440, 900));
      expect(_footer, findsOneWidget);
      expect(find.text('v0.2.3'), findsOneWidget);
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

  testWidgets('compact large text moves information links into drawer', (
    tester,
  ) async {
    final (_, platform) = await _mount(tester, const Size(320, 740), scale: 2);
    expect(_footer, findsNothing);
    expect(_sidebarFooter, findsNothing);
    expect(composer.hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Open sidebar'));
    await tester.pumpAndSettle();
    expect(_sidebarFooter, findsOneWidget);
    expect(find.byTooltip('Information links'), findsNothing);
    await tester.ensureVisible(find.text('v$appVersion'));
    await tester.pumpAndSettle();
    _expectAdjacentSourceLink(tester, within: _sidebarFooter);
    for (final label in ['About', 'Terms and conditions', 'Liability']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(platform.opened.map((url) => url.path.split('/').last), [
      'about.html',
      'terms.html',
      'liability.html',
    ]);
    await tester.ensureVisible(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('GitHub source code'));
    await tester.pump();
    expect(
      platform.opened.last.toString(),
      'https://github.com/consciontologic/wfform',
    );
    await tester.tapAt(const Offset(319, 250));
    await tester.pumpAndSettle();
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
    for (final scenario in [
      (const Size(750, 900), 1.25),
      (const Size(320, 740), 2.0),
    ]) {
      tester.view.physicalSize = scenario.$1;
      state.setTextScale(scenario.$2);
      await tester.pumpAndSettle();
      expect(_footer, findsNothing);
      await tester.tap(find.byTooltip('Open sidebar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('v$appVersion'));
      await tester.pumpAndSettle();
      _expectAdjacentSourceLink(tester, within: _sidebarFooter);
      expect(find.byTooltip('Information links'), findsNothing);
      await tester.tapAt(Offset(scenario.$1.width - 1, 250));
      await tester.pumpAndSettle();
    }
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
