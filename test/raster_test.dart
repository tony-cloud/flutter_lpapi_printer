import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lpapi_printer/lpapi_printer.dart';

void main() {
  test('raster builder emits deterministic page and row commands', () async {
    final image = await _testImage();
    final commands = await const LpRasterCommandBuilder().buildImageCommands(
      image,
      options: const LpPrintOptions(pageKey: 7),
    );

    expect(commands.first[1], 0x20);
    expect(commands.any((command) => command[1] == 0x26), isTrue);
    expect(commands.any((command) => command[1] == 0x27), isTrue);
    expect(commands.any((command) => command[1] == 0x21), isTrue);
    expect(commands.last[1], 0x28);
  });

  test('raster builder emits SDK-style density and repeat metadata', () {
    final page = LpRasterPage(
      width: 8,
      height: 3,
      bytes: Uint8List.fromList(<int>[0xf0, 0xf0, 0x00]),
    );
    final commands = const LpRasterCommandBuilder().buildRasterCommands(
      page,
      options: const LpPrintOptions(dpi: 25, pageKey: 1),
    );
    final maxDots = LpPacket.tryDecode(commands[1]);
    final printRows = commands
        .map(LpPacket.tryDecode)
        .firstWhere((packet) => packet?.command == 0x21);

    expect(maxDots?.payload, <int>[0x40, 0x04, 0x40, 0x02]);
    expect(printRows?.payload, <int>[1, 0, 0xf0]);
  });

  test('raster builder scales to label size without printer-width padding', () async {
    final image = await _testImage();
    final commands = await const LpRasterCommandBuilder().buildImageCommands(
      image,
      options: const LpPrintOptions(
        labelWidthMm: 25.4,
        labelHeightMm: 12.7,
        printableWidthPx: 384,
        alignment: LpPrintAlignment.center,
      ),
    );
    final lineBytes = commands
        .map(LpPacket.tryDecode)
        .firstWhere((packet) => packet?.command == 0x27);
    final lineCount = commands
        .map(LpPacket.tryDecode)
        .firstWhere((packet) => packet?.command == 0x26);

    expect(lineBytes?.payload, <int>[38]);
    expect(lineCount?.payload, <int>[150]);
  });
}

Future<ui.Image> _testImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 2), Paint()..color = Colors.white);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 2), Paint()..color = Colors.black);
  final picture = recorder.endRecording();
  return picture.toImage(8, 2);
}
