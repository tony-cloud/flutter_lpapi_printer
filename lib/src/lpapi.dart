import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'client.dart';
import 'constants.dart';
import 'models.dart';
import 'printer_name.dart';

class LpApi {
  LpApi({LpPrinterClient? client}) : client = client ?? LpPrinterClient();

  factory LpApi.createInstance({LpPrinterClient? client}) {
    return LpApi(client: client);
  }

  final LpPrinterClient client;
  _LpDrawJob? _job;

  Stream<List<LpPrinterAddress>> get discoveredPrintersStream =>
      client.discoveredPrintersStream;

  Stream<LpPrinterEvent> get events => client.events;

  LpPrinterState get printerState => client.printerState;

  LpPrinterInfo? getPrinterInfo() => client.printerInfo;

  String getPrinterName() => client.printerInfo?.deviceName ?? '';

  LpPrinterState getPrinterState() => client.printerState;

  Future<void> discovery() => client.startScan();

  Future<void> stopDiscovery() => client.stopScan();

  bool isPrinterSupported(String name, [String? modelName]) {
    return LpPrinterName.isSupported(name) &&
        (modelName == null ||
            modelName.isEmpty ||
            name.toLowerCase().contains(modelName.toLowerCase()));
  }

  bool isDeviceSupported(Object printer, [String? modelName]) {
    if (printer is LpPrinterAddress) {
      return isPrinterSupported(printer.shownName, modelName);
    }
    if (printer is BleDevice) {
      return isPrinterSupported(
        printer.name ?? printer.rawName ?? '',
        modelName,
      );
    }
    return isPrinterSupported(printer.toString(), modelName);
  }

  String getAllPrinters([String? modelName]) {
    return getAllPrinterAddresses(
      modelName,
    ).map((printer) => printer.shownName).join('\n');
  }

  List<LpPrinterAddress> getAllPrinterAddresses([String? modelName]) {
    return client.discoveredPrinters
        .where((printer) => isPrinterSupported(printer.shownName, modelName))
        .toList(growable: false);
  }

  String getFirstPrinter([String? modelName]) {
    return getFirstPrinterAddress(modelName)?.shownName ?? '';
  }

  LpPrinterAddress? getFirstPrinterAddress([String? modelName]) {
    final printers = getAllPrinterAddresses(modelName);
    return printers.isEmpty ? null : printers.first;
  }

  Future<bool> openPrinter([String? name]) async {
    final printer = name == null || name.isEmpty
        ? getFirstPrinterAddress()
        : client.discoveredPrinters.cast<LpPrinterAddress?>().firstWhere(
            (address) => address?.shownName == name || address?.key == name,
            orElse: () => null,
          );
    if (printer == null) return false;
    await client.connect(printer);
    return true;
  }

  Future<bool> openPrinterSync([String? name]) => openPrinter(name);

  Future<bool> openPrinterByAddress(LpPrinterAddress address) async {
    await client.connect(address);
    return true;
  }

  Future<bool> openPrinterByAddressSync(LpPrinterAddress address) =>
      openPrinterByAddress(address);

  Future<void> closePrinter() => client.disconnect();

  Future<void> reopenPrinter() => client.reconnect();

  Future<void> reopenPrinterSync() => reopenPrinter();

  Future<void> quit() => client.dispose();

  bool isPrinterOpened() => client.isConnected;

  void cancel() {
    abortJob();
  }

  Future<bool> waitPrinterState(LpPrinterState state, int millis) async {
    if (client.printerState == state) return true;
    try {
      await client.events
          .where(
            (event) =>
                event.type == LpPrinterEventType.stateChanged &&
                event.state == state,
          )
          .first
          .timeout(Duration(milliseconds: millis));
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> setPrintPageGapType(int value) =>
      client.setPrintPageGapType(value);

  Future<void> setPrintPageGapLength(int value) =>
      client.setPrintPageGapLength(value);

  Future<void> setPrintDarkness(int value) => client.setPrintDarkness(value);

  Future<void> setPrintSpeed(int value) => client.setPrintSpeed(value);

  Future<void> printPng(
    Uint8List bytes, {
    LpPrintOptions options = const LpPrintOptions(),
  }) {
    return client.printPng(bytes, options: options);
  }

  Future<void> printImage(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) {
    return client.printImage(image, options: options);
  }

  Future<bool> printBitmap(
    ui.Image bitmap, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    await client.printImage(bitmap, options: options);
    return true;
  }

  Future<bool> printBitmapWithParam(
    ui.Image bitmap,
    Map<String, Object?> printParam,
  ) {
    return printBitmap(
      bitmap,
      options: LpPrintOptions.fromParamMap(printParam),
    );
  }

  bool startJob(double widthMm, double heightMm, int rotation) {
    _job = _LpDrawJob(widthMm: widthMm, heightMm: heightMm, rotation: rotation);
    return true;
  }

  void abortJob() {
    _job = null;
  }

  void endJob() {}

  Future<bool> commitJob({
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final job = _job;
    if (job == null) return false;
    final image = await job.toImage();
    await client.printImage(image, options: options);
    _job = null;
    return true;
  }

  Future<bool> commitJobWithParam(Map<String, Object?> printParam) {
    return commitJob(options: LpPrintOptions.fromParamMap(printParam));
  }

  bool startPage() => _job != null;

  void endPage() {}

  void setBackground(int color) {
    _job?.setBackground(Color(color));
  }

  bool drawText(
    String text,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double fontSizeMm, [
    int fontStyle = LpFontStyle.regular,
  ]) {
    return drawTextRegular(
      text,
      xMm,
      yMm,
      widthMm,
      heightMm,
      fontSizeMm,
      fontStyle,
      0,
    );
  }

  bool drawTextRegular(
    String text,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double fontSizeMm,
    int fontStyle,
    double indent,
  ) {
    return _withJob((job) {
      job.drawText(text, xMm, yMm, widthMm, heightMm, fontSizeMm, fontStyle);
    });
  }

  bool drawRichText(
    String text,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double fontSizeMm,
    int fontStyle,
  ) {
    return drawTextRegular(
      text,
      xMm,
      yMm,
      widthMm,
      heightMm,
      fontSizeMm,
      fontStyle,
      0,
    );
  }

  bool draw2DQRCode(String text, double xMm, double yMm, double sizeMm) {
    return _withJob((job) => job.drawQr(text, xMm, yMm, sizeMm));
  }

  bool draw1DBarcode(
    String text,
    int type,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double textHeightMm,
  ) {
    return _withJob(
      (job) => job.drawCode39LikeBarcode(text, xMm, yMm, widthMm, heightMm),
    );
  }

  bool draw2DDataMatrix(String text, double xMm, double yMm, double sizeMm) {
    return draw2DQRCode(text, xMm, yMm, sizeMm);
  }

  bool drawImage(
    ui.Image image,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
  ) {
    return _withJob((job) => job.drawImage(image, xMm, yMm, widthMm, heightMm));
  }

  bool drawBitmap(
    ui.Image image,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
  ) {
    return drawImage(image, xMm, yMm, widthMm, heightMm);
  }

  bool drawRectangle(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double lineWidthMm,
  ) {
    return _withJob(
      (job) => job.drawRect(xMm, yMm, widthMm, heightMm, lineWidthMm, false),
    );
  }

  bool fillRectangle(double xMm, double yMm, double widthMm, double heightMm) {
    return _withJob(
      (job) => job.drawRect(xMm, yMm, widthMm, heightMm, 0, true),
    );
  }

  bool drawRoundRectangle(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double radiusX,
    double radiusY,
    double lineWidthMm,
  ) {
    return _withJob((job) {
      job.drawRoundRect(
        xMm,
        yMm,
        widthMm,
        heightMm,
        radiusX,
        radiusY,
        lineWidthMm,
        false,
      );
    });
  }

  bool fillRoundRectangle(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double radiusX,
    double radiusY,
  ) {
    return _withJob((job) {
      job.drawRoundRect(xMm, yMm, widthMm, heightMm, radiusX, radiusY, 0, true);
    });
  }

  bool drawEllipse(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double lineWidthMm,
  ) {
    return _withJob(
      (job) => job.drawOval(xMm, yMm, widthMm, heightMm, lineWidthMm, false),
    );
  }

  bool fillEllipse(double xMm, double yMm, double widthMm, double heightMm) {
    return _withJob(
      (job) => job.drawOval(xMm, yMm, widthMm, heightMm, 0, true),
    );
  }

  bool drawCircle(double xMm, double yMm, double radiusMm, double lineWidthMm) {
    return drawEllipse(
      xMm - radiusMm,
      yMm - radiusMm,
      radiusMm * 2,
      radiusMm * 2,
      lineWidthMm,
    );
  }

  bool fillCircle(double xMm, double yMm, double radiusMm) {
    return fillEllipse(
      xMm - radiusMm,
      yMm - radiusMm,
      radiusMm * 2,
      radiusMm * 2,
    );
  }

  bool drawLine(
    double x1Mm,
    double y1Mm,
    double x2Mm,
    double y2Mm,
    double lineWidthMm,
  ) {
    return _withJob((job) => job.drawLine(x1Mm, y1Mm, x2Mm, y2Mm, lineWidthMm));
  }

  bool drawDashLine(
    double x1Mm,
    double y1Mm,
    double x2Mm,
    double y2Mm,
    double lineWidthMm,
    List<double> intervals,
    int phase,
  ) {
    return _withJob(
      (job) => job.drawDashLine(x1Mm, y1Mm, x2Mm, y2Mm, lineWidthMm, intervals),
    );
  }

  bool _withJob(void Function(_LpDrawJob job) callback) {
    final job = _job;
    if (job == null) return false;
    callback(job);
    return true;
  }
}

class _LpDrawJob {
  _LpDrawJob({
    required this.widthMm,
    required this.heightMm,
    required this.rotation,
    this.dpi = 203,
  }) : widthPx = math.max(1, (widthMm * dpi / 25.4).round()),
       heightPx = math.max(1, (heightMm * dpi / 25.4).round()) {
    _canvas.drawColor(Colors.white, BlendMode.src);
    if (rotation != 0) {
      _canvas.translate(widthPx / 2, heightPx / 2);
      _canvas.rotate(rotation * math.pi / 180);
      _canvas.translate(-widthPx / 2, -heightPx / 2);
    }
  }

  final double widthMm;
  final double heightMm;
  final int rotation;
  final int dpi;
  final int widthPx;
  final int heightPx;
  final ui.PictureRecorder _recorder = ui.PictureRecorder();
  late final Canvas _canvas = Canvas(_recorder);

  double _px(double mm) => mm * dpi / 25.4;

  void setBackground(Color color) {
    _canvas.drawColor(color, BlendMode.src);
  }

  void drawText(
    String text,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double fontSizeMm,
    int fontStyle,
  ) {
    final isBold = (fontStyle & LpFontStyle.bold) != 0;
    final isItalic = (fontStyle & LpFontStyle.italic) != 0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: _px(fontSizeMm),
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          decoration: TextDecoration.combine(<TextDecoration>[
            if ((fontStyle & LpFontStyle.underline) != 0)
              TextDecoration.underline,
            if ((fontStyle & LpFontStyle.strikeout) != 0)
              TextDecoration.lineThrough,
          ]),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: math.max(
        1,
        (_px(heightMm) / math.max(1, _px(fontSizeMm))).floor(),
      ),
      ellipsis: '',
    )..layout(maxWidth: _px(widthMm));
    painter.paint(_canvas, Offset(_px(xMm), _px(yMm)));
  }

  void drawQr(String data, double xMm, double yMm, double sizeMm) {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    _canvas.save();
    _canvas.translate(_px(xMm), _px(yMm));
    painter.paint(_canvas, Size.square(_px(sizeMm)));
    _canvas.restore();
  }

  void drawImage(
    ui.Image image,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
  ) {
    _canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(_px(xMm), _px(yMm), _px(widthMm), _px(heightMm)),
      Paint(),
    );
  }

  void drawCode39LikeBarcode(
    String data,
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
  ) {
    final payload = data.isEmpty ? ' ' : data;
    final units = payload.length * 12 + 20;
    final unitWidth = _px(widthMm) / units;
    var cursor = _px(xMm);
    final top = _px(yMm);
    final height = _px(heightMm);
    final paint = Paint()..color = Colors.black;
    for (final codeUnit in payload.codeUnits) {
      for (var bit = 0; bit < 8; bit += 1) {
        final wide = ((codeUnit >> bit) & 0x1) == 1;
        final barWidth = unitWidth * (wide ? 2 : 1);
        if (bit.isEven) {
          _canvas.drawRect(Rect.fromLTWH(cursor, top, barWidth, height), paint);
        }
        cursor += barWidth + unitWidth;
      }
      cursor += unitWidth * 2;
    }
  }

  void drawRect(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double lineWidthMm,
    bool fill,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(1, _px(lineWidthMm))
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;
    _canvas.drawRect(
      Rect.fromLTWH(_px(xMm), _px(yMm), _px(widthMm), _px(heightMm)),
      paint,
    );
  }

  void drawRoundRect(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double radiusX,
    double radiusY,
    double lineWidthMm,
    bool fill,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(1, _px(lineWidthMm))
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;
    _canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_px(xMm), _px(yMm), _px(widthMm), _px(heightMm)),
        Radius.elliptical(_px(radiusX), _px(radiusY)),
      ),
      paint,
    );
  }

  void drawOval(
    double xMm,
    double yMm,
    double widthMm,
    double heightMm,
    double lineWidthMm,
    bool fill,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(1, _px(lineWidthMm))
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke;
    _canvas.drawOval(
      Rect.fromLTWH(_px(xMm), _px(yMm), _px(widthMm), _px(heightMm)),
      paint,
    );
  }

  void drawLine(
    double x1Mm,
    double y1Mm,
    double x2Mm,
    double y2Mm,
    double lineWidthMm,
  ) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = math.max(1, _px(lineWidthMm))
      ..strokeCap = StrokeCap.square;
    _canvas.drawLine(
      Offset(_px(x1Mm), _px(y1Mm)),
      Offset(_px(x2Mm), _px(y2Mm)),
      paint,
    );
  }

  void drawDashLine(
    double x1Mm,
    double y1Mm,
    double x2Mm,
    double y2Mm,
    double lineWidthMm,
    List<double> intervals,
  ) {
    final pattern = intervals.isEmpty ? const <double>[2, 2] : intervals;
    final start = Offset(_px(x1Mm), _px(y1Mm));
    final end = Offset(_px(x2Mm), _px(y2Mm));
    final vector = end - start;
    final distance = vector.distance;
    if (distance <= 0) return;
    final direction = vector / distance;
    var drawn = 0.0;
    var index = 0;
    while (drawn < distance) {
      final segment = _px(pattern[index % pattern.length]);
      final next = math.min(distance, drawn + segment);
      if (index.isEven) {
        final from = start + direction * drawn;
        final to = start + direction * next;
        drawLine(
          from.dx * 25.4 / dpi,
          from.dy * 25.4 / dpi,
          to.dx * 25.4 / dpi,
          to.dy * 25.4 / dpi,
          lineWidthMm,
        );
      }
      drawn = next;
      index += 1;
    }
  }

  Future<ui.Image> toImage() async {
    final picture = _recorder.endRecording();
    return picture.toImage(widthPx, heightPx);
  }
}
