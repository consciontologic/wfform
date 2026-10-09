import 'dart:convert';
import 'dart:io';

/// A deliberately small CLI for a fixed example CSV format. It accepts no
/// paths, commands or model-written code, and never writes to disk.
void main(List<String> args) {
  if (args.isNotEmpty) {
    stderr.writeln('This example accepts no arguments.');
    exitCode = 64;
    return;
  }
  try {
    final file = File.fromUri(Platform.script.resolve('fixtures/sales.csv'));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.lengthSync() > 4096) {
      throw const FormatException('Invalid sample file.');
    }
    final lines = const LineSplitter().convert(file.readAsStringSync());
    if (lines.first != 'item,quantity,unit_price_cents') {
      throw const FormatException('Unexpected sample header.');
    }
    var total = 0;
    final items = <Map<String, Object>>[];
    for (final line in lines.skip(1)) {
      final cells = line.split(',');
      if (cells.length != 3) throw const FormatException('Unexpected row.');
      final quantity = int.parse(cells[1]);
      final price = int.parse(cells[2]);
      if (quantity < 0 || quantity > 1000000 || price < 0 || price > 1000000) {
        throw const FormatException('Unexpected value.');
      }
      final subtotal = quantity * price;
      total += subtotal;
      items.add({
        'item': cells[0],
        'quantity': quantity,
        'subtotalCents': subtotal,
      });
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'source': 'bundled sales.csv',
        'rows': items.length,
        'currency': 'USD',
        'items': items,
        'totalCents': total,
      }),
    );
  } on Object {
    stderr.writeln('Could not read the fixed sales sample.');
    exitCode = 65;
  }
}
