import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/presentation/brand_artwork.dart';
import 'package:wfform/presentation/brand_mark.dart';

import '../../tool/icons.dart' as icons;

void main() {
  test('every platform PNG has transparent background and cradle interior', () {
    final files = [
      ...Directory('web').listSync().whereType<File>().where(
        (file) => file.path.contains('/favicon') && file.path.endsWith('.png'),
      ),
      ...Directory('web/icons').listSync().whereType<File>().where(
        (file) => file.path.endsWith('.png'),
      ),
      ...Directory('android/app/src/main/res')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('/ic_launcher.png')),
      ...Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png')),
    ];
    expect(files.length, 40, reason: 'All web, Android and iOS exports remain');
    final withoutAlpha = files
        .where((file) => file.readAsBytesSync()[25] != 6)
        .map((file) => file.path)
        .toList();
    expect(
      withoutAlpha,
      isEmpty,
      reason:
          'Every icon must be RGBA, including legacy maskable and iOS files',
    );
    for (final file in files) {
      final png = file.readAsBytesSync();
      final size = ByteData.sublistView(png).getUint32(16);
      final pixels = _decodePng(png, size);
      int alpha(int x, int y) => pixels[y * (1 + size * 4) + 1 + x * 4 + 3];
      final scale = file.path.contains('favicon')
          ? 1.0
          : file.path.contains('maskable')
          ? .76
          : .75;
      int coordinate(int value) =>
          ((50 + (value - 50) * scale) * size / 100).floor();
      // The 16px mark's antialiased right curve reaches the last pixel. Keep
      // its established footprint while requiring every exterior pixel clear.
      final left = coordinate(7), top = coordinate(14);
      final right = ((50 + 45 * scale) * size / 100).ceil();
      final bottom = ((50 + 35 * scale) * size / 100).ceil();
      var paintedExterior = 0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if ((x < left || x >= right || y < top || y >= bottom) &&
              alpha(x, y) != 0) {
            paintedExterior++;
          }
        }
      }
      expect(paintedExterior, 0, reason: '${file.path}: no background plate');
      for (final (x, y) in [(55, 64), (65, 16)]) {
        expect(
          alpha(coordinate(x), coordinate(y)),
          0,
          reason: '${file.path}: the cradle center and opening have no plate',
        );
      }
      final dark = file.path.contains('dark') || file.path.contains('night');
      expect(
        _countColor(pixels, size, dark ? [200, 184, 220] : [183, 168, 201]),
        greaterThan(0),
        reason: '${file.path}: the lavender nodes remain visible',
      );
      expect(
        _countColor(pixels, size, dark ? [246, 243, 236] : [48, 45, 52]),
        greaterThan(0),
        reason: '${file.path}: the contrasting cradle remains visible',
      );
    }
  });

  test('Open Cradle exports contain two connected lavender nodes', () {
    const size = 100;
    for (final dark in [false, true]) {
      final pixels = _decodePng(icons.iconPng(size, dark: dark), size);
      final accent = dark ? [200, 184, 220, 255] : [183, 168, 201, 255];
      for (final (x, y) in [(40, 52), (64, 35), (52, 44)]) {
        final offset = y * (1 + size * 4) + 1 + x * 4;
        expect(
          pixels.sublist(offset, offset + 4),
          accent,
          reason: 'Both rounded nodes and their connecting link remain visible',
        );
      }
      for (final (x, y) in [(55, 64), (65, 16), (21, 72)]) {
        final offset = y * (1 + size * 4) + 1 + x * 4;
        expect(
          pixels[offset + 3],
          0,
          reason:
              'The cradle center, opening and fold have no background plate',
        );
      }
      final ink = dark ? [246, 243, 236, 255] : [48, 45, 52, 255];
      for (final (x, y) in [(12, 53), (50, 80)]) {
        final offset = y * (1 + size * 4) + 1 + x * 4;
        expect(
          pixels.sublist(offset, offset + 4),
          ink,
          reason: 'The cradle is a filled ribbon, rather than an outlined W',
        );
      }
    }
  });

  test('favicons retain both connected nodes with transparent backgrounds', () {
    for (final size in [16, 32, 48]) {
      final pixels = _decodePng(icons.iconPng(size), size);
      expect(_countColor(pixels, size, [183, 168, 201]), greaterThan(0));
      expect(pixels.sublist(1, 5), [0, 0, 0, 0]);
      expect(_countColor(pixels, size, [48, 45, 52]), greaterThan(0));
      for (final (x, y) in [(40, 52), (64, 35)]) {
        final offset =
            (y * size ~/ 100) * (1 + size * 4) + 1 + (x * size ~/ 100) * 4;
        expect(
          pixels.sublist(offset, offset + 4),
          [183, 168, 201, 255],
          reason: 'Both node centers remain opaque lavender at $size pixels',
        );
      }
    }
  });

  test('both maskable palettes stay inside the safe circle at every size', () {
    for (final size in [192, 512]) {
      for (final dark in [false, true]) {
        final pixels = _decodePng(
          icons.iconPng(size, style: icons.IconStyle.maskable, dark: dark),
          size,
        );
        var artworkPixels = 0;
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final offset = y * (1 + size * 4) + 1 + x * 4;
            if (pixels[offset + 3] == 0) {
              continue;
            }
            artworkPixels++;
            final dx = (x + .5) / size - .5;
            final dy = (y + .5) / size - .5;
            expect(
              dx * dx + dy * dy,
              lessThanOrEqualTo(.4 * .4),
              reason: 'All cradle details stay safe at $size, dark=$dark',
            );
          }
        }
        expect(
          artworkPixels,
          greaterThan(size),
          reason: 'Safe icons retain visible artwork',
        );
      }
    }
  });

  test('checked-in web and native icons match deterministic generation', () {
    final assets = <(String, int, icons.IconStyle)>[
      for (final size in [16, 32, 48])
        (
          size == 48 ? 'web/favicon.png' : 'web/favicon-$size.png',
          size,
          icons.IconStyle.favicon,
        ),
      for (final size in [192, 512]) ...[
        ('web/icons/Icon-$size.png', size, icons.IconStyle.launcher),
        ('web/icons/Icon-maskable-$size.png', size, icons.IconStyle.maskable),
      ],
      for (final entry in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries)
        (
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
          entry.value,
          icons.IconStyle.launcher,
        ),
    ];
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final manifest =
        jsonDecode(File('$ios/Contents.json').readAsStringSync()) as Map;
    for (final icon in manifest['images'] as List) {
      if (icon['appearances'] != null) {
        expect(
          File('$ios/${icon['filename']}').readAsBytesSync(),
          icons.iconPng(1024, style: icons.IconStyle.launcher, dark: true),
        );
        continue;
      }
      final points = double.parse((icon['size'] as String).split('x').first);
      final scale = double.parse((icon['scale'] as String).split('x').first);
      assets.add((
        '$ios/${icon['filename']}',
        (points * scale).round(),
        icons.IconStyle.store,
      ));
    }
    for (final (path, size, style) in assets) {
      expect(
        File(path).readAsBytesSync(),
        icons.iconPng(size, style: style),
        reason: path,
      );
    }
    for (final size in [16, 32, 48]) {
      expect(
        File('web/favicon-dark-$size.png').readAsBytesSync(),
        icons.iconPng(size, dark: true),
      );
      final light = _decodePng(icons.iconPng(size), size);
      final dark = _decodePng(icons.iconPng(size, dark: true), size);
      expect(dark.sublist(1, 5), [0, 0, 0, 0]);
      expect(_countColor(dark, size, [200, 184, 220]), greaterThan(0));
      expect(dark, isNot(equals(light)));
    }
    for (final size in [192, 512]) {
      expect(
        File('web/icons/Icon-dark-$size.png').readAsBytesSync(),
        icons.iconPng(size, style: icons.IconStyle.launcher, dark: true),
      );
      expect(
        File('web/icons/Icon-maskable-dark-$size.png').readAsBytesSync(),
        icons.iconPng(size, style: icons.IconStyle.maskable, dark: true),
      );
    }
    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      expect(
        File(
          'android/app/src/main/res/mipmap-night-${entry.key}/ic_launcher.png',
        ).readAsBytesSync(),
        icons.iconPng(entry.value, style: icons.IconStyle.launcher, dark: true),
      );
    }
  });

  testWidgets('all companion glyphs paint at small sizes in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final glyph in BrandGlyph.values) {
        for (final size in [16.0, 24.0]) {
          final pixels = await _render(
            tester,
            IconTheme(
              data: IconThemeData(
                color: Color(
                  brightness == Brightness.dark ? brandPaper : brandInk,
                ),
                opacity: 1,
              ),
              child: BrandIcon(glyph, size: size),
            ),
            size,
            brightness,
          );
          final colors = <int>{};
          for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
            if (pixels.getUint8(offset + 3) == 255) {
              colors.add(
                0xff000000 |
                    pixels.getUint8(offset) << 16 |
                    pixels.getUint8(offset + 1) << 8 |
                    pixels.getUint8(offset + 2),
              );
            }
          }
          expect(
            colors,
            contains(
              brightness == Brightness.dark ? brandDarkLavender : brandLavender,
            ),
            reason: '$glyph $brightness at $size',
          );
          expect(
            colors,
            contains(brightness == Brightness.dark ? brandPaper : brandInk),
            reason:
                '$glyph $brightness at $size retains its contrasting outline',
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets(
    'Open Cradle keeps open space and adapts its filled band in dark mode',
    (tester) async {
      final light = await _render(
        tester,
        const WfformMark(size: 100),
        100,
        Brightness.light,
      );
      final dark = await _render(
        tester,
        const WfformMark(size: 100),
        100,
        Brightness.dark,
      );
      int rgb(ByteData data, int x, int y) {
        final offset = (y * 100 + x) * 4;
        return 0xff000000 |
            data.getUint8(offset) << 16 |
            data.getUint8(offset + 1) << 8 |
            data.getUint8(offset + 2);
      }

      for (final (x, y) in [(55, 64), (65, 16), (21, 72)]) {
        expect(
          light.getUint8((y * 100 + x) * 4 + 3),
          0,
          reason: 'Center, upper opening and ribbon fold remain transparent',
        );
        expect(dark.getUint8((y * 100 + x) * 4 + 3), 0);
      }
      for (final (x, y) in [(12, 53), (50, 80)]) {
        expect(rgb(light, x, y), brandInk);
        expect(rgb(dark, x, y), brandPaper);
        expect(light.getUint8((y * 100 + x) * 4 + 3), 255);
        expect(dark.getUint8((y * 100 + x) * 4 + 3), 255);
      }
      for (final (x, y) in [(40, 52), (64, 35), (52, 44)]) {
        expect(rgb(light, x, y), brandLavender);
        expect(rgb(dark, x, y), brandDarkLavender);
      }
    },
  );

  testWidgets('companion icons honor disabled opacity and stay decorative', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: IconThemeData(
            color: Colors.black.withValues(alpha: .5),
            opacity: .4,
          ),
          child: const Center(child: BrandIcon(BrandGlyph.documents)),
        ),
      ),
    );
    final icon = find.byType(BrandIcon);
    final opacity = tester.widget<Opacity>(
      find.descendant(of: icon, matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, closeTo(.2, .002));
    expect(
      find.descendant(of: icon, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    expect(tester.getSize(icon), const Size.square(24));
  });

  testWidgets('filled-button foreground keeps the open Chat icon distinct', (
    tester,
  ) async {
    for (final (brightness, foreground, accent) in [
      (Brightness.light, Colors.white, brandDarkLavender),
      (Brightness.dark, const Color(0xff29153e), brandLavender),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(foregroundColor: foreground),
              onPressed: () {},
              icon: RepaintBoundary(
                key: key,
                child: const BrandIcon(BrandGlyph.chat),
              ),
              label: const Text('New conversation'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await tester.runAsync(() => boundary.toImage());
      final pixels = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      image!.dispose();
      int rgb(int x, int y) {
        final offset = (y * 24 + x) * 4;
        return 0xff000000 |
            pixels!.getUint8(offset) << 16 |
            pixels.getUint8(offset + 1) << 8 |
            pixels.getUint8(offset + 2);
      }

      expect(
        pixels!.getUint8((14 * 24 + 10) * 4 + 3),
        0,
        reason: '$brightness open bubble must show the button surface',
      );
      expect(
        rgb(10, 11),
        foreground.toARGB32(),
        reason: 'The message stroke inherits the actual button foreground',
      );
      expect(
        rgb(18, 5),
        accent,
        reason: 'The open-corner node keeps the brand accent',
      );
    }
  });
}

Future<ByteData> _render(
  WidgetTester tester,
  Widget child,
  double size,
  Brightness brightness,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: size, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage());
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  image!.dispose();
  return data!;
}

List<int> _decodePng(List<int> png, int size) {
  expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  final bytes = Uint8List.fromList(png);
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(16), size);
  expect(data.getUint32(20), size);
  expect(
    data.getUint8(25),
    6,
    reason: 'All exported icon artwork uses transparent RGBA PNGs',
  );
  final compressed = <int>[];
  for (var offset = 8; offset < bytes.length;) {
    final length = data.getUint32(offset);
    final kind = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    final payload = bytes.sublist(offset + 4, offset + 8 + length);
    expect(data.getUint32(offset + 8 + length), icons.crc32(payload));
    if (kind == 'IDAT') compressed.addAll(payload.skip(4));
    offset += 12 + length;
  }
  final pixels = ZLibDecoder().convert(compressed);
  expect(pixels.length, size * (1 + size * 4));
  return pixels;
}

int _countColor(List<int> pixels, int size, List<int> rgb) {
  var count = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final offset = y * (1 + size * 4) + 1 + x * 4;
      if (pixels[offset] == rgb[0] &&
          pixels[offset + 1] == rgb[1] &&
          pixels[offset + 2] == rgb[2]) {
        count++;
      }
    }
  }
  return count;
}
