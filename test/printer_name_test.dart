import 'package:flutter_test/flutter_test.dart';
import 'package:lpapi_printer/lpapi_printer.dart';

void main() {
  test('accepts Android SDK BLE printer name patterns', () {
    expect(LpPrinterName.isSupported('LP-D1234AB12'), isTrue);
    expect(LpPrinterName.isSupported('LP-O1234AB12'), isTrue);
    expect(LpPrinterName.isSupported('Printer-10102345'), isTrue);
  });

  test('rejects unsupported names and bad SDK checksums', () {
    expect(LpPrinterName.isSupported(''), isFalse);
    expect(LpPrinterName.isSupported('Gateway BLE'), isFalse);
    expect(LpPrinterName.isSupported('Printer-12345678'), isFalse);
  });

  test('normalizes base name', () {
    expect(LpPrinterName.baseName('Printer-10102345'), 'Printer');
  });

  test('derives SDK-style DPI defaults from BLE suffix', () {
    final defaults = LpPrinterName.defaultsFor('LP-D1234AB12');

    expect(defaults.dpi, 300);
    expect(defaults.widthDots, 567);
  });
}
