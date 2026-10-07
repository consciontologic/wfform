import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/theme.dart';
import 'package:wfform/presentation/sidebar_resize_handle.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final direction in TextDirection.values) {
      testWidgets('sidebar meets its divider in $brightness / $direction', (
        tester,
      ) async {
        final boundaryKey = GlobalKey();
        final palette = brightness == Brightness.light
            ? StudioPalette.light
            : StudioPalette.dark;
        await tester.pumpWidget(
          MaterialApp(
            theme: studioTheme(brightness: brightness),
            home: Scaffold(
              body: Directionality(
                textDirection: direction,
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 120,
                      height: 100,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 48,
                            child: ColoredBox(color: palette.cream),
                          ),
                          SidebarResizeHandle(
                            value: 290,
                            minimum: 240,
                            maximum: 440,
                            onChanged: (_) {},
                            onChangeEnd: (_) {},
                            onCancelled: () {},
                            onCollapse: (_) {},
                          ),
                          Expanded(child: ColoredBox(color: palette.paper)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(SidebarResizeHandle)).width, 24);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        const pixelRatio = 4.0;
        final capture = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: pixelRatio);
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final width = image.width;
          image.dispose();
          return (pixels: pixels, width: width);
        }))!;
        Color pixel(double x, double y) => _pixel(
          capture.pixels,
          capture.width,
          (x * pixelRatio).floor(),
          (y * pixelRatio).floor(),
        );
        final left = direction == TextDirection.ltr
            ? palette.cream
            : palette.paper;
        final right = direction == TextDirection.ltr
            ? palette.paper
            : palette.cream;
        // Compare both sides of the wide hit target with the adjoining panels.
        // Check near the edges too, so a short painted band cannot hide a gap.
        for (final y in [1.0, 50.0, 99.0]) {
          expect(pixel(47, y), left);
          expect(pixel(49, y), left);
          expect(pixel(58, y), left);
          expect(pixel(60, y), palette.border);
          expect(pixel(62, y), right);
          expect(pixel(71, y), right);
          expect(pixel(73, y), right);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Color _pixel(ByteData pixels, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}
