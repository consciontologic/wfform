import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Deterministic original pixel artwork, encoded without image dependencies.
void main() {
  Directory('web/icons').createSync(recursive: true);
  for (final size in [192, 512]) {
    final bytes = iconPng(size);
    File('web/icons/Icon-$size.png').writeAsBytesSync(bytes);
    File('web/icons/Icon-maskable-$size.png').writeAsBytesSync(bytes);
  }
  File('web/favicon.png').writeAsBytesSync(iconPng(48));
}

List<int> iconPng(int size) {
  const background = [248, 245, 252];
  const ink = [41, 36, 59];
  const mint = [219, 239, 229];
  final pixels = BytesBuilder();
  for (var y = 0; y < size; y++) {
    pixels.addByte(0); // PNG filter: none.
    for (var x = 0; x < size; x++) {
      // Match the Flutter header's bracketed conversation mark. Its artwork is
      // inset to stay inside a maskable icon's central safe circle.
      final u = (x / size - .14) / .72 * 48;
      final v = (y / size - .14) / .72 * 48;
      var color = background;
      bool rect(double l, double t, double r, double b) =>
          u >= l && u <= r && v >= t && v <= b;
      if (rect(2.6, 7.6, 5.4, 40.4) ||
          rect(2.6, 7.6, 11.4, 10.4) ||
          rect(2.6, 37.6, 11.4, 40.4) ||
          rect(42.6, 7.6, 45.4, 40.4) ||
          rect(36.6, 7.6, 45.4, 10.4) ||
          rect(36.6, 37.6, 45.4, 40.4)) {
        color = ink;
      }
      if (rect(12.6, 13.6, 35.4, 31.4) ||
          (rect(16.6, 30, 24, 37) && v <= 37 - (u - 16.6) * 5 / 6)) {
        color = ink;
      }
      if (rect(15.4, 16.4, 32.6, 28.6)) color = mint;
      for (final cx in [19.0, 24.0, 29.0]) {
        if ((u - cx) * (u - cx) + (v - 22.5) * (v - 22.5) <= 1.5625) {
          color = ink;
        }
      }
      pixels.add(color);
    }
  }
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
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
