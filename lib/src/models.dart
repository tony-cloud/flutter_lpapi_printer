import 'dart:typed_data';

enum LpPrinterAddressType { ble }

enum LpPrinterState {
  connecting(1),
  connected(2),
  connected2(2),
  printing(2),
  working(2),
  disconnected(0);

  const LpPrinterState(this.group);
  final int group;
}

enum LpPrintProgress { connected, startCopy, dataEnded, success, failed }

enum LpPrintFailReason {
  ok,
  isPrinting,
  isRotating,
  cancelled,
  envNotReady,
  volTooLow,
  volTooHigh,
  tphNotFound,
  tphTooHot,
  coverOpened,
  noPaper,
  tphOpened,
  noRibbon,
  unmatchedRibbon,
  tphTooCold,
  usedupRibbon,
  usedupRibbon2,
  noLabel,
  unmatchedLabel,
  usedupLabel,
  noRibbon2,
  unmatchedRibbon2,
  labelCanOpend,
  disconnected,
  timeout,
  other,
}

enum LpGeneralProgress {
  start,
  success,
  success2,
  failed,
  cancelled,
  timeout,
  info,
}

enum LpPrinterEventType {
  discovered,
  stateChanged,
  printProgress,
  progressInfo,
}

enum LpPaperType {
  continuous(0),
  hole(1),
  gap(2),
  blackMark(3);

  const LpPaperType(this.gapType);

  final int gapType;

  static LpPaperType? fromGapType(int? value) {
    return switch (value) {
      0 => LpPaperType.continuous,
      1 => LpPaperType.hole,
      2 => LpPaperType.gap,
      3 => LpPaperType.blackMark,
      _ => null,
    };
  }
}

enum LpPrintAlignment {
  left(1024),
  center(512),
  right(0);

  const LpPrintAlignment(this.sdkValue);

  final int sdkValue;

  static LpPrintAlignment fromSdkValue(int? value) {
    return switch (value) {
      0 => LpPrintAlignment.right,
      512 => LpPrintAlignment.center,
      1024 => LpPrintAlignment.left,
      _ => LpPrintAlignment.center,
    };
  }
}

enum LpPrintDirection {
  normal(0),
  right90(90),
  rotate180(180),
  left270(270);

  const LpPrintDirection(this.degrees);

  final int degrees;

  static LpPrintDirection fromDegrees(int? value) {
    return switch (value) {
      90 => LpPrintDirection.right90,
      180 => LpPrintDirection.rotate180,
      270 => LpPrintDirection.left270,
      _ => LpPrintDirection.normal,
    };
  }
}

class LpPrinterAddress {
  const LpPrinterAddress({
    required this.deviceId,
    required this.shownName,
    this.macAddress,
    this.rssi,
    this.addressType = LpPrinterAddressType.ble,
  });

  final String deviceId;
  final String shownName;
  final String? macAddress;
  final int? rssi;
  final LpPrinterAddressType addressType;

  String get key => shownName.split('-').first.trim();

  bool equalsAddress(String value) {
    return deviceId.toLowerCase() == value.toLowerCase() ||
        (macAddress?.toLowerCase() == value.toLowerCase());
  }

  @override
  String toString() {
    return 'LpPrinterAddress(shownName: $shownName, deviceId: $deviceId, macAddress: $macAddress)';
  }
}

class LpPrinterInfo {
  const LpPrinterInfo({
    required this.deviceName,
    required this.deviceAddress,
    this.deviceType = 0,
    this.deviceVersion = '',
    this.softwareVersion = '',
    this.deviceDpi = 203,
    this.deviceWidth = 384,
    this.manufacturer = '',
    this.seriesName = '',
    this.devIntName = '',
    this.peripheralFlags = 0,
    this.hardwareFlags = 0,
    this.softwareFlags = 0,
    this.mcuId = '',
  });

  final int deviceType;
  final String deviceName;
  final String deviceVersion;
  final String softwareVersion;
  final String deviceAddress;
  final int deviceDpi;
  final int deviceWidth;
  final String manufacturer;
  final String seriesName;
  final String devIntName;
  final int peripheralFlags;
  final int hardwareFlags;
  final int softwareFlags;
  final String mcuId;
}

class LpPrintData {
  const LpPrintData({
    required this.printObj,
    this.printParam = const <String, Object?>{},
    this.printCopy = 0,
    this.pageKey = 0,
  });

  final Object printObj;
  final Map<String, Object?> printParam;
  final int printCopy;
  final int pageKey;
}

class LpPrinterEvent {
  const LpPrinterEvent({
    required this.type,
    this.printer,
    this.state,
    this.printData,
    this.printProgress,
    this.failReason,
    this.info,
  });

  final LpPrinterEventType type;
  final LpPrinterAddress? printer;
  final LpPrinterState? state;
  final LpPrintData? printData;
  final LpPrintProgress? printProgress;
  final LpPrintFailReason? failReason;
  final Object? info;
}

class LpPrintOptions {
  const LpPrintOptions({
    this.labelWidthMm,
    this.labelHeightMm,
    this.dpi = 203,
    this.darkness,
    this.speed,
    this.copies = 1,
    this.pageKey,
    this.gapType,
    this.paperType,
    this.gapLength01Mm,
    this.alignment = LpPrintAlignment.center,
    this.direction = LpPrintDirection.normal,
    this.printableWidthPx,
    this.antiColor = false,
    this.horizontalFlip = false,
    this.threshold = 192,
    this.marginLeftPx = 0,
    this.marginRightPx = 0,
    this.marginTopPx = 0,
    this.marginBottomPx = 0,
  });

  final double? labelWidthMm;
  final double? labelHeightMm;
  final int dpi;
  final int? darkness;
  final int? speed;
  final int copies;
  final int? pageKey;
  final int? gapType;
  final LpPaperType? paperType;
  final int? gapLength01Mm;
  final LpPrintAlignment alignment;
  final LpPrintDirection direction;
  final int? printableWidthPx;
  final bool antiColor;
  final bool horizontalFlip;
  final int threshold;
  final int marginLeftPx;
  final int marginRightPx;
  final int marginTopPx;
  final int marginBottomPx;

  int get safeCopies => copies <= 0 ? 1 : copies;

  int? get effectiveGapType => gapType ?? paperType?.gapType;

  int? get labelWidthPx => labelWidthMm == null
      ? null
      : (labelWidthMm! * dpi / 25.4).round().clamp(1, 65535).toInt();

  int? get labelHeightPx => labelHeightMm == null
      ? null
      : (labelHeightMm! * dpi / 25.4).round().clamp(1, 65535).toInt();

  LpPrintOptions copyWith({
    double? labelWidthMm,
    double? labelHeightMm,
    int? dpi,
    int? darkness,
    int? speed,
    int? copies,
    int? pageKey,
    int? gapType,
    LpPaperType? paperType,
    int? gapLength01Mm,
    LpPrintAlignment? alignment,
    LpPrintDirection? direction,
    int? printableWidthPx,
    bool? antiColor,
    bool? horizontalFlip,
    int? threshold,
    int? marginLeftPx,
    int? marginRightPx,
    int? marginTopPx,
    int? marginBottomPx,
  }) {
    return LpPrintOptions(
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      dpi: dpi ?? this.dpi,
      darkness: darkness ?? this.darkness,
      speed: speed ?? this.speed,
      copies: copies ?? this.copies,
      pageKey: pageKey ?? this.pageKey,
      gapType: gapType ?? this.gapType,
      paperType: paperType ?? this.paperType,
      gapLength01Mm: gapLength01Mm ?? this.gapLength01Mm,
      alignment: alignment ?? this.alignment,
      direction: direction ?? this.direction,
      printableWidthPx: printableWidthPx ?? this.printableWidthPx,
      antiColor: antiColor ?? this.antiColor,
      horizontalFlip: horizontalFlip ?? this.horizontalFlip,
      threshold: threshold ?? this.threshold,
      marginLeftPx: marginLeftPx ?? this.marginLeftPx,
      marginRightPx: marginRightPx ?? this.marginRightPx,
      marginTopPx: marginTopPx ?? this.marginTopPx,
      marginBottomPx: marginBottomPx ?? this.marginBottomPx,
    );
  }

  factory LpPrintOptions.fromParamMap(Map<String, Object?> params) {
    int? intValue(String key) {
      final value = params[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    bool boolValue(String key) {
      final value = params[key];
      if (value is bool) return value;
      return value?.toString().toLowerCase() == 'true';
    }

    final gapType = intValue('GAP_TYPE');
    return LpPrintOptions(
      dpi: intValue('PRINT_DPI') ?? 203,
      darkness: intValue('PRINT_DENSITY'),
      speed: intValue('PRINT_SPEED'),
      copies: intValue('PRINT_COPIES') ?? 1,
      pageKey: intValue('PAGE_KEY'),
      gapType: gapType,
      paperType: LpPaperType.fromGapType(gapType),
      gapLength01Mm: intValue('GAP_LENGTH_01MM'),
      alignment: LpPrintAlignment.fromSdkValue(intValue('PRINT_ALIGNMENT')),
      direction: LpPrintDirection.fromDegrees(intValue('PRINT_DIRECTION')),
      printableWidthPx: intValue('PRINTABLE_WIDTH_PX'),
      antiColor: boolValue('ANTI_COLOR'),
      horizontalFlip: boolValue('HOR_FLIP'),
      threshold: intValue('IMAGE_THRESHOLD') ?? 192,
      marginLeftPx: intValue('LEFT_MARGIN_PX') ?? 0,
      marginRightPx: intValue('RIGHT_MARGIN_PX') ?? 0,
      marginTopPx: intValue('TOP_MARGIN_PX') ?? 0,
      marginBottomPx: intValue('BOTTOM_MARGIN_PX') ?? 0,
    );
  }

  Map<String, Object?> toParamMap() {
    return <String, Object?>{
      'PRINT_DPI': dpi,
      if (darkness != null) 'PRINT_DENSITY': darkness,
      if (speed != null) 'PRINT_SPEED': speed,
      'PRINT_COPIES': copies,
      if (pageKey != null) 'PAGE_KEY': pageKey,
      if (effectiveGapType != null) 'GAP_TYPE': effectiveGapType,
      if (gapLength01Mm != null) 'GAP_LENGTH_01MM': gapLength01Mm,
      'PRINT_ALIGNMENT': alignment.sdkValue,
      'PRINT_DIRECTION': direction.degrees,
      if (printableWidthPx != null) 'PRINTABLE_WIDTH_PX': printableWidthPx,
      'ANTI_COLOR': antiColor,
      'HOR_FLIP': horizontalFlip,
      'IMAGE_THRESHOLD': threshold,
      'LEFT_MARGIN_PX': marginLeftPx,
      'RIGHT_MARGIN_PX': marginRightPx,
      'TOP_MARGIN_PX': marginTopPx,
      'BOTTOM_MARGIN_PX': marginBottomPx,
    };
  }
}

class LpBleEndpoint {
  const LpBleEndpoint({
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
  });

  final String serviceUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;
}

class LpRasterPage {
  const LpRasterPage({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

class LpPrinterException implements Exception {
  const LpPrinterException(this.message);

  final String message;

  @override
  String toString() => 'LpPrinterException: $message';
}
