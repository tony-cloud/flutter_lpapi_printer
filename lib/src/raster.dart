import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'models.dart';
import 'packet.dart';

class LpRasterCommandBuilder {
  const LpRasterCommandBuilder();

  Future<List<Uint8List>> buildImageCommands(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final prepared = await _prepareImage(image, options);
    try {
      final page = await rasterize(prepared, options: options);
      return buildRasterCommands(page, options: options);
    } finally {
      if (!identical(prepared, image)) {
        prepared.dispose();
      }
    }
  }

  Future<Uint8List> buildImageData(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final commands = await buildImageCommands(image, options: options);
    return combineCommands(commands);
  }

  Future<LpRasterPage> rasterize(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw const LpPrinterException('Unable to read image pixels');
    }
    final source = byteData.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    final marginLeft = math.max(0, options.marginLeftPx);
    final marginRight = math.max(0, options.marginRightPx);
    final marginTop = math.max(0, options.marginTopPx);
    final marginBottom = math.max(0, options.marginBottomPx);
    final contentWidth = math.max(1, width + marginLeft + marginRight);
    final maxPrintableWidth = options.printableWidthPx;
    final targetWidth = maxPrintableWidth == null || maxPrintableWidth <= 0
        ? contentWidth
        : math.max(1, maxPrintableWidth);
    final horizontalSlack = targetWidth - contentWidth;
    final placementOffset = horizontalSlack <= 0
        ? 0
        : switch (options.alignment) {
            LpPrintAlignment.left => 0,
            LpPrintAlignment.center => horizontalSlack ~/ 2,
            LpPrintAlignment.right => horizontalSlack,
          };
    final overflow = contentWidth - targetWidth;
    final cropOffset = overflow <= 0
        ? 0
        : switch (options.alignment) {
            LpPrintAlignment.left => 0,
            LpPrintAlignment.center => overflow ~/ 2,
            LpPrintAlignment.right => overflow,
          };
    final targetHeight = math.max(1, height + marginTop + marginBottom);
    final bytesPerRow = (targetWidth + 7) ~/ 8;
    final output = Uint8List(bytesPerRow * targetHeight);
    final threshold = options.threshold.clamp(1, 254);

    for (var y = 0; y < height; y += 1) {
      final targetY = y + marginTop;
      if (targetY < 0 || targetY >= targetHeight) continue;
      for (var x = 0; x < width; x += 1) {
        final sourceX = options.horizontalFlip ? width - x - 1 : x;
        final pixelOffset = (y * width + sourceX) * 4;
        final alpha = source[pixelOffset + 3];
        if (alpha == 0) continue;
        final red = source[pixelOffset];
        final green = source[pixelOffset + 1];
        final blue = source[pixelOffset + 2];
        final luma = ((red * 299) + (green * 587) + (blue * 114)) ~/ 1000;
        var black = luma < threshold;
        if (options.antiColor) black = !black;
        if (!black) continue;
        final targetX = x + marginLeft + placementOffset - cropOffset;
        if (targetX < 0 || targetX >= targetWidth) continue;
        final byteIndex = targetY * bytesPerRow + targetX ~/ 8;
        output[byteIndex] |= 0x80 >> (targetX & 0x7);
      }
    }

    return LpRasterPage(width: targetWidth, height: targetHeight, bytes: output);
  }

  List<Uint8List> buildRasterCommands(
    LpRasterPage page, {
    LpPrintOptions options = const LpPrintOptions(),
  }) {
    final commands = <Uint8List>[];
    final heat = _heatDensity(page, options.dpi);
    for (var copy = 0; copy < options.safeCopies; copy += 1) {
      commands.add(_pageHeader(options.pageKey ?? _nextPageKey(copy)));
      commands.add(_maxDotsCommand(heat.maxRowDots, heat.maxRollingDots));
      commands.addAll(_printOptionCommands(options));
      commands.add(_lineBytesCommand((page.width + 7) ~/ 8));
      commands.add(_lineCountCommand(page.height));
      commands.addAll(_rowCommands(page));
      commands.add(LpPacket.commandBytes(0x28));
    }
    return commands;
  }

  Uint8List buildRasterData(LpRasterPage page, {LpPrintOptions options = const LpPrintOptions()}) {
    return combineCommands(buildRasterCommands(page, options: options));
  }

  static Uint8List combineCommands(Iterable<Uint8List> commands) {
    var length = 0;
    for (final command in commands) {
      length += command.length;
    }
    final output = Uint8List(length);
    var offset = 0;
    for (final command in commands) {
      output.setRange(offset, offset + command.length, command);
      offset += command.length;
    }
    return output;
  }

  Uint8List _pageHeader(int pageKey) {
    final payload = Uint8List(8);
    payload[0] = (pageKey >> 8) & 0xff;
    payload[1] = pageKey & 0xff;
    return LpPacket.commandBytes(0x20, payload);
  }

  List<Uint8List> _printOptionCommands(LpPrintOptions options) {
    final commands = <Uint8List>[];
    final darkness = _printParamByte(options.darkness);
    if (darkness != null) {
      commands.add(LpCommandBuilder.setPrintDarkness(darkness));
    }
    final speed = _printParamByte(options.speed);
    if (speed != null) {
      commands.add(LpCommandBuilder.setPrintSpeed(speed));
    }
    final gapType = _printParamByte(options.effectiveGapType);
    if (gapType != null) {
      commands.add(LpCommandBuilder.setPrintPageGapType(gapType));
    }
    if (options.gapLength01Mm != null) {
      commands.add(LpCommandBuilder.setPrintPageGapLength(options.gapLength01Mm!));
    }
    return commands;
  }

  int? _printParamByte(int? value) {
    if (value == null || value < 0 || value >= 255) return null;
    return value;
  }

  Future<ui.Image> _prepareImage(ui.Image image, LpPrintOptions options) async {
    final width = options.labelWidthPx ?? image.width;
    final height = options.labelHeightPx ?? image.height;
    if (width == image.width &&
        height == image.height &&
        options.direction == LpPrintDirection.normal) {
      return image;
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..color = const ui.Color(0xffffffff);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);
    final source = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final imagePaint = ui.Paint();
    switch (options.direction) {
      case LpPrintDirection.normal:
        canvas.drawImageRect(
          image,
          source,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          imagePaint,
        );
        break;
      case LpPrintDirection.right90:
        canvas.translate(width.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        canvas.drawImageRect(
          image,
          source,
          ui.Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          imagePaint,
        );
        break;
      case LpPrintDirection.rotate180:
        canvas.translate(width.toDouble(), height.toDouble());
        canvas.rotate(math.pi);
        canvas.drawImageRect(
          image,
          source,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          imagePaint,
        );
        break;
      case LpPrintDirection.left270:
        canvas.translate(0, height.toDouble());
        canvas.rotate(-math.pi / 2);
        canvas.drawImageRect(
          image,
          source,
          ui.Rect.fromLTWH(0, 0, height.toDouble(), width.toDouble()),
          imagePaint,
        );
        break;
    }
    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  Uint8List _maxDotsCommand(int startFeedDots, int labelEndDots) {
    final start = 0x4000 + math.max(0, startFeedDots).toInt();
    final end = 0x4000 + math.max(0, labelEndDots).toInt();
    final payload = <int>[(start >> 8) & 0xff, start & 0xff, (end >> 8) & 0xff, end & 0xff];
    return LpPacket.commandBytes(0x25, payload);
  }

  Uint8List _lineBytesCommand(int bytesPerRow) {
    return LpPacket.commandBytes(0x27, LpPacket.variableLength(math.max(0, bytesPerRow)));
  }

  Uint8List _lineCountCommand(int lineCount) {
    return LpPacket.commandBytes(0x26, LpPacket.variableLength(math.max(0, lineCount)));
  }

  List<Uint8List> _rowCommands(LpRasterPage page) {
    final result = <Uint8List>[];
    final bytesPerRow = (page.width + 7) ~/ 8;
    var blankRows = 0;
    int? repeatFirst;
    Uint8List? repeatBytes;
    var repeatRows = 0;

    void flushRepeat() {
      final bytes = repeatBytes;
      final first = repeatFirst;
      if (bytes == null || first == null || repeatRows <= 0) return;
      var remaining = repeatRows;
      while (remaining > 0) {
        final count = math.min(remaining, 16384);
        result.add(_printRows(count, first, bytes));
        remaining -= count;
      }
      repeatFirst = null;
      repeatBytes = null;
      repeatRows = 0;
    }

    for (var row = 0; row < page.height; row += 1) {
      final rowStart = row * bytesPerRow;
      var first = 0;
      while (first < bytesPerRow && page.bytes[rowStart + first] == 0) {
        first += 1;
      }
      if (first == bytesPerRow) {
        flushRepeat();
        blankRows += 1;
        continue;
      }
      if (blankRows > 0) {
        result.add(_blankRows(blankRows));
        blankRows = 0;
      }
      var last = bytesPerRow - 1;
      while (last > first && page.bytes[rowStart + last] == 0) {
        last -= 1;
      }
      final rowBytes = page.bytes.sublist(rowStart + first, rowStart + last + 1);
      if (first == repeatFirst && _bytesEqual(rowBytes, repeatBytes)) {
        repeatRows += 1;
        continue;
      }
      flushRepeat();
      repeatFirst = first;
      repeatBytes = rowBytes;
      repeatRows = 1;
    }
    flushRepeat();
    if (blankRows > 0) {
      result.add(_blankRows(blankRows));
    }
    return result;
  }

  Uint8List _printRows(int count, int firstByteOffset, Uint8List rowBytes) {
    return LpPacket.commandBytes(0x21, <int>[
      ...LpPacket.variableLength(math.max(0, count - 1)),
      ...LpPacket.variableLength(firstByteOffset),
      ...rowBytes,
    ]);
  }

  Uint8List _blankRows(int count) {
    return LpPacket.commandBytes(0x22, LpPacket.variableLength(math.max(0, count - 1)));
  }

  ({int maxRowDots, int maxRollingDots}) _heatDensity(LpRasterPage page, int dpi) {
    final bytesPerRow = (page.width + 7) ~/ 8;
    final windowSize = math.max(1, ((dpi * 3) / 25.4).round());
    final window = List<int>.filled(windowSize, 0);
    var windowIndex = 0;
    var windowSum = 0;
    var maxRowDots = 0;
    var maxRollingDots = 0;

    for (var row = 0; row < page.height; row += 1) {
      final rowStart = row * bytesPerRow;
      var rowDots = 0;
      for (var index = 0; index < bytesPerRow; index += 1) {
        rowDots += _bitCounts[page.bytes[rowStart + index] & 0xff];
      }
      if (maxRowDots < rowDots) {
        maxRowDots = rowDots;
      }
      windowSum -= window[windowIndex];
      window[windowIndex] = rowDots;
      windowSum += rowDots;
      windowIndex = (windowIndex + 1) % windowSize;
      final rollingDots = windowSum ~/ windowSize;
      if (maxRollingDots < rollingDots) {
        maxRollingDots = rollingDots;
      }
    }

    return (maxRowDots: maxRowDots, maxRollingDots: maxRollingDots);
  }

  bool _bytesEqual(Uint8List a, Uint8List? b) {
    if (b == null || a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static final List<int> _bitCounts = List<int>.generate(256, (value) {
    var count = 0;
    var bits = value;
    while (bits != 0) {
      count += bits & 1;
      bits >>= 1;
    }
    return count;
  });

  int _nextPageKey(int offset) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((now + offset) % 65534) + 1;
  }
}
