import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wfform/presentation/brand_artwork.dart';

enum IconStyle { favicon, launcher, maskable, store }

/// Regenerate every checked-in launcher from the same canonical Flutter mark.
void main() {
  Directory('web/icons').createSync(recursive: true);
  for (final size in [192, 512]) {
    File(
      'web/icons/Icon-$size.png',
    ).writeAsBytesSync(iconPng(size, style: IconStyle.launcher));
    File(
      'web/icons/Icon-maskable-$size.png',
    ).writeAsBytesSync(iconPng(size, style: IconStyle.maskable));
    File(
      'web/icons/Icon-dark-$size.png',
    ).writeAsBytesSync(iconPng(size, style: IconStyle.launcher, dark: true));
    File(
      'web/icons/Icon-maskable-dark-$size.png',
    ).writeAsBytesSync(iconPng(size, style: IconStyle.maskable, dark: true));
  }
  for (final size in [16, 32, 48]) {
    final path = size == 48 ? 'web/favicon.png' : 'web/favicon-$size.png';
    File(path).writeAsBytesSync(iconPng(size));
    File(
      'web/favicon-dark-$size.png',
    ).writeAsBytesSync(iconPng(size, dark: true));
  }
  const androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in androidSizes.entries) {
    File(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
    ).writeAsBytesSync(iconPng(entry.value, style: IconStyle.launcher));
    final night = File(
      'android/app/src/main/res/mipmap-night-${entry.key}/ic_launcher.png',
    );
    night.parent.createSync(recursive: true);
    night.writeAsBytesSync(
      iconPng(entry.value, style: IconStyle.launcher, dark: true),
    );
  }
  const iosPath = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final manifest =
      jsonDecode(File('$iosPath/Contents.json').readAsStringSync()) as Map;
  final written = <String>{};
  for (final image in manifest['images'] as List) {
    final filename = image['filename'] as String;
    if (!written.add(filename)) continue;
    final points = double.parse((image['size'] as String).split('x').first);
    final scale = double.parse((image['scale'] as String).split('x').first);
    final dark = (image['appearances'] as List? ?? []).any(
      (appearance) =>
          appearance['appearance'] == 'luminosity' &&
          appearance['value'] == 'dark',
    );
    File('$iosPath/$filename').writeAsBytesSync(
      iconPng(
        (points * scale).round(),
        style: dark ? IconStyle.launcher : IconStyle.store,
        dark: dark,
      ),
    );
  }
}

/// Four samples per axis keep rounded strokes legible even at 16 pixels.
/// Every style has a transparent background. Legacy maskable-sized marks retain
/// their central 80%-diameter safe-circle footprint.
List<int> iconPng(
  int size, {
  IconStyle style = IconStyle.favicon,
  bool dark = false,
}) {
  if (size < 1 || size > 2048) throw ArgumentError.value(size, 'size');
  const samples = 4;
  final raster = _Raster(size * samples);
  final ink = dark ? brandPaper : brandInk;
  final accent = dark ? brandDarkLavender : brandLavender;
  final scale = switch (style) {
    IconStyle.favicon => 1.0,
    IconStyle.launcher => .75,
    IconStyle.maskable => .76,
    IconStyle.store => .75,
  };
  math.Point<double> transform(math.Point<double> p) =>
      math.Point((p.x - 50) * scale + 50, (p.y - 50) * scale + 50);
  for (final band in cradleBands) {
    final points = <math.Point<double>>[math.Point(band.x, band.y)];
    for (final c in band.curves) {
      final start = points.last;
      for (var step = 1; step <= 24; step++) {
        final t = step / 24;
        final u = 1 - t;
        points.add(
          math.Point(
            u * u * u * start.x +
                3 * u * u * t * c[0] +
                3 * u * t * t * c[2] +
                t * t * t * c[4],
            u * u * u * start.y +
                3 * u * u * t * c[1] +
                3 * u * t * t * c[3] +
                t * t * t * c[5],
          ),
        );
      }
    }
    raster.polygon(points.map(transform).toList(), ink);
  }
  raster.stroke(
    cradleNodes.map((node) => transform(math.Point(node.x, node.y))).toList(),
    cradleLinkWidth * scale,
    accent,
  );
  for (final node in cradleNodes) {
    raster.circle(
      transform(math.Point(node.x, node.y)),
      node.radius * scale,
      accent,
    );
  }
  final pixels = BytesBuilder();
  for (var y = 0; y < size; y++) {
    pixels.addByte(0); // PNG filter: none.
    for (var x = 0; x < size; x++) {
      var red = 0, green = 0, blue = 0, alpha = 0;
      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final rgb = raster
              .pixels[(y * samples + sy) * raster.size + x * samples + sx];
          final a = (rgb >> 24) & 255;
          alpha += a;
          red += ((rgb >> 16) & 255) * a;
          green += ((rgb >> 8) & 255) * a;
          blue += (rgb & 255) * a;
        }
      }
      pixels.add([
        alpha == 0 ? 0 : (red / alpha).round(),
        alpha == 0 ? 0 : (green / alpha).round(),
        alpha == 0 ? 0 : (blue / alpha).round(),
        (alpha / (samples * samples)).round(),
      ]);
    }
  }
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  void chunk(String name, List<int> content) {
    final payload = [...ascii.encode(name), ...content];
    final length = ByteData(4)..setUint32(0, content.length);
    final checksum = ByteData(4)..setUint32(0, crc32(payload));
    output
      ..add(length.buffer.asUint8List())
      ..add(payload)
      ..add(checksum.buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(pixels.takeBytes()));
  chunk('IEND', []);
  return output.takeBytes();
}

int crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

/// Small scanline rasterizer for the canonical filled path and rounded stroke.
/// It is generation tooling only; Flutter paints the original cubic curves.
class _Raster {
  _Raster(this.size) : pixels = Uint32List(size * size);
  final int size;
  final Uint32List pixels;

  void polygon(List<math.Point<double>> points, int color) {
    final scaled = points
        .map((p) => math.Point(p.x * size / 100, p.y * size / 100))
        .toList();
    final top = scaled.map((p) => p.y).reduce(math.min).floor().clamp(0, size);
    final bottom = scaled
        .map((p) => p.y)
        .reduce(math.max)
        .ceil()
        .clamp(0, size);
    for (var y = top; y < bottom; y++) {
      final scan = y + .5;
      final intersections = <double>[];
      for (var i = 0; i < scaled.length; i++) {
        final a = scaled[i], b = scaled[(i + 1) % scaled.length];
        if ((a.y <= scan && b.y > scan) || (b.y <= scan && a.y > scan)) {
          intersections.add(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y));
        }
      }
      intersections.sort();
      for (var i = 0; i + 1 < intersections.length; i += 2) {
        _span(y, intersections[i], intersections[i + 1], color);
      }
    }
  }

  void _span(int y, double left, double right, int color) {
    final from = (left - .5).ceil().clamp(0, size);
    final to = (right - .5).ceil().clamp(0, size);
    if (from < to) pixels.fillRange(y * size + from, y * size + to, color);
  }

  void stroke(List<math.Point<double>> points, double width, int color) {
    final radius = width / 2;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final dx = b.x - a.x, dy = b.y - a.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) {
        final ox = -dy / length * radius, oy = dx / length * radius;
        polygon([
          math.Point(a.x + ox, a.y + oy),
          math.Point(b.x + ox, b.y + oy),
          math.Point(b.x - ox, b.y - oy),
          math.Point(a.x - ox, a.y - oy),
        ], color);
      }
      circle(a, radius, color);
    }
    if (points.isNotEmpty) circle(points.last, radius, color);
  }

  void circle(math.Point<double> center, double radius, int color) {
    final cx = center.x * size / 100, cy = center.y * size / 100;
    final r = radius * size / 100;
    final top = (cy - r).floor().clamp(0, size);
    final bottom = (cy + r).ceil().clamp(0, size);
    for (var y = top; y < bottom; y++) {
      final d = y + .5 - cy;
      if (d.abs() > r) continue;
      final half = math.sqrt(r * r - d * d);
      _span(y, cx - half, cx + half, color);
    }
  }
}
