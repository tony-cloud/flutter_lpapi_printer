import 'package:flutter_test/flutter_test.dart';
import 'package:lpapi_printer/lpapi_printer.dart';

void main() {
  test('print options map LPAPI print parameters', () {
    const options = LpPrintOptions(
      darkness: LpPrintParamValue.maxPrintDarkness,
      speed: LpPrintParamValue.minPrintSpeed,
      direction: LpPrintDirection.rotate180,
      copies: 3,
      paperType: LpPaperType.gap,
      antiColor: true,
    );

    expect(options.toParamMap(), containsPair('PRINT_DENSITY', 14));
    expect(options.toParamMap(), containsPair('PRINT_SPEED', 0));
    expect(options.toParamMap(), containsPair('PRINT_DIRECTION', 180));
    expect(options.toParamMap(), containsPair('PRINT_COPIES', 3));
    expect(options.toParamMap(), containsPair('GAP_TYPE', 2));
    expect(options.toParamMap(), containsPair('ANTI_COLOR', true));
  });

  test('print options parse LPAPI direction and output values', () {
    final options = LpPrintOptions.fromParamMap(const <String, Object?>{
      'PRINT_DENSITY': 5,
      'PRINT_SPEED': 2,
      'PRINT_DIRECTION': 270,
      'PRINT_COPIES': 2,
      'GAP_TYPE': 3,
      'ANTI_COLOR': true,
    });

    expect(options.darkness, 5);
    expect(options.speed, 2);
    expect(options.direction, LpPrintDirection.left270);
    expect(options.copies, 2);
    expect(options.paperType, LpPaperType.blackMark);
    expect(options.antiColor, isTrue);
  });

  test('printer info normalizes SDK width in dots or millimeters', () {
    const dotWidthInfo = LpPrinterInfo(
      deviceName: 'LP-D1234AB12',
      deviceAddress: 'device-1',
      deviceDpi: 300,
      deviceWidth: 567,
    );
    const mmWidthInfo = LpPrinterInfo(
      deviceName: 'LP-D1234AB12',
      deviceAddress: 'device-1',
      deviceDpi: 300,
      deviceWidth: 48,
    );

    expect(dotWidthInfo.printableWidthPx, 567);
    expect(dotWidthInfo.deviceWidthMm, closeTo(48, 0.1));
    expect(mmWidthInfo.printableWidthPx, 567);
    expect(mmWidthInfo.deviceWidthMm, 48);
  });

  test('printer info exposes the device reported maximum darkness', () {
    const info = LpPrinterInfo(
      deviceName: 'LP-D1234AB12',
      deviceAddress: 'device-1',
      darknessCount: 20,
    );

    expect(info.maxPrintDarkness, 19);
    expect(
      const LpPrinterInfo(deviceName: 'LP-D1234AB12', deviceAddress: 'device-1').maxPrintDarkness,
      LpPrintParamValue.maxPrintDarkness,
    );
  });
}
