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
}
