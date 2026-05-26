import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lpapi_printer/lpapi_printer.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('selects writable and notify characteristics using SDK rules', () {
    final endpoint = LpPrinterClient.selectEndpoint([
      BleService(BleUuidParser.number(0xffe0), [
        BleCharacteristic(BleUuidParser.number(0xffe1), [
          CharacteristicProperty.writeWithoutResponse,
        ], const []),
        BleCharacteristic(BleUuidParser.number(0xffe2), [CharacteristicProperty.notify], const []),
      ]),
    ]);

    expect(endpoint?.writeCharacteristicUuid, BleUuidParser.number(0xffe1));
    expect(endpoint?.notifyCharacteristicUuid, BleUuidParser.number(0xffe2));
  });

  test('scans supported printers without relying on service UUID filters', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);

    await client.startScan();
    adapter.emitScan(BleDevice(deviceId: 'device-1', name: 'LP-D1234AB12', rssi: -42));
    adapter.emitScan(BleDevice(deviceId: 'device-2', name: 'Gateway BLE', rssi: -1));

    final printers = await client.discoveredPrintersStream.firstWhere((items) => items.isNotEmpty);
    expect(printers, hasLength(1));
    expect(printers.single.shownName, 'LP-D1234AB12');
  });

  test('connects, negotiates MTU fallback, and chunks paced writes to 20 bytes', () async {
    final adapter = _FakeBleAdapter();
    adapter.mtuResponses.addAll(<int, Object>{183: StateError('mtu rejected'), 153: 153});
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    expect(client.printerInfo?.deviceDpi, 300);
    expect(client.printerInfo?.deviceWidth, 1181);
    expect(client.printerInfo?.darknessCount, 20);
    expect(client.writeChunkSize, 150);

    adapter.writes.clear();
    await client.sendCommand(Uint8List.fromList(List<int>.generate(55, (index) => index)));

    expect(adapter.mtuRequests, <int>[183, 153]);
    expect(adapter.writes.map((write) => write.value.length), <int>[20, 20, 15]);
    expect(adapter.writes.every((write) => write.withoutResponse), isTrue);
  });

  test('logs connected printer info details', () async {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);

    final printerInfoLog = messages.singleWhere(
      (message) => message.contains('[lpapi_printer] connected printerInfo'),
    );
    expect(printerInfoLog, contains('deviceDpi: 300'));
    expect(printerInfoLog, contains('deviceWidth: 1181'));
    expect(printerInfoLog, contains('deviceWidthMm: 99.99'));
    expect(printerInfoLog, contains('printableWidthPx: 1181'));
    expect(printerInfoLog, contains('darknessCount: 20'));
    expect(messages.any((message) => message.contains('lpapi info query complete')), isTrue);
  });

  test('refreshes printer width from LPAPI parameter responses', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);

    expect(client.printerInfo?.deviceDpi, 300);
    expect(client.printerInfo?.deviceWidth, 1181);
    expect(client.printerInfo?.darknessCount, 20);
    expect(client.printerInfo?.deviceWidthMm.toStringAsFixed(2), '99.99');
    expect(
      adapter.writes.expand((write) => write.value),
      containsAllInOrder(<int>[
        0x1f,
        0x71,
        0x00,
        0x8e,
        0x1f,
        0x72,
        0x00,
        0x8d,
        0x1f,
        0x78,
        0x00,
        0x87,
      ]),
    );
  });

  test('prints raster data as one MTU-sized package stream', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    adapter.writes.clear();
    final image = await _largeImage();
    await client.printImage(image, options: const LpPrintOptions(pageKey: 11));

    final lengths = adapter.writes.map((write) => write.value.length);
    final package = Uint8List.fromList(adapter.writes.expand((write) => write.value).toList());

    expect(client.writeChunkSize, 180);
    expect(lengths, contains(180));
    expect(lengths.every((length) => length <= 180), isTrue);
    expect(LpPacket.tryDecode(package)?.command, 0x20);
    expect(package, contains(0x28));
    final lineBytes = _decodePackets(package).firstWhere((packet) => packet.command == 0x27);
    expect(lineBytes.payload, <int>[8]);
    expect(adapter.writes.every((write) => write.withoutResponse), isTrue);
  });

  test('writes print options inside the raster job stream', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    adapter.writes.clear();
    final image = await _largeImage();
    await client.printImage(
      image,
      options: const LpPrintOptions(
        pageKey: 11,
        darkness: 14,
        speed: 3,
        paperType: LpPaperType.gap,
        gapLength01Mm: 200,
      ),
    );

    final package = Uint8List.fromList(adapter.writes.expand((write) => write.value).toList());
    final packets = _decodePackets(package);
    expect(packets.map((packet) => packet.command).take(8), <int>[
      0x20,
      0x25,
      0x43,
      0x44,
      0x42,
      0x45,
      0x27,
      0x26,
    ]);
    expect(packets[2].payload, <int>[19]);
    expect(packets[3].payload, <int>[3]);
    expect(packets[4].payload, <int>[LpPaperType.gap.gapType]);
    expect(packets[5].payload, LpPacket.variableLength(200));
  });

  test('keeps darkness inside draw-job raster data before line setup', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    final api = LpApi(client: client);
    adapter.writes.clear();
    expect(api.startJob(25.4, 12.7, 0), isTrue);
    expect(api.drawText('Dark', 0, 0, 12, 5, 3), isTrue);
    expect(await api.commitJob(options: const LpPrintOptions(pageKey: 11, darkness: 14)), isTrue);

    final package = Uint8List.fromList(adapter.writes.expand((write) => write.value).toList());
    final packets = _decodePackets(package);
    expect(packets.map((packet) => packet.command).take(5), <int>[0x20, 0x25, 0x43, 0x27, 0x26]);
    expect(packets[2].payload, <int>[19]);
  });

  test('maps documented max darkness to connected printer level count', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    adapter.writes.clear();
    await client.setPrintDarkness(LpPrintParamValue.maxPrintDarkness);

    final packet = LpPacket.tryDecode(adapter.writes.single.value);
    expect(client.printerInfo?.darknessCount, 20);
    expect(packet?.command, 0x43);
    expect(packet?.payload, <int>[19]);
  });

  test('LPAPI drawing jobs use connected printer DPI', () async {
    final adapter = _FakeBleAdapter();
    final rasterBuilder = _RecordingRasterBuilder();
    final client = LpPrinterClient(adapter: adapter, rasterBuilder: rasterBuilder);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(deviceId: 'device-1', shownName: 'LP-D1234AB12');

    await client.connect(printer);
    final api = LpApi(client: client);
    expect(api.startJob(25.4, 12.7, 0), isTrue);
    expect(api.drawText('DPI', 0, 0, 12, 5, 3), isTrue);
    expect(await api.commitJob(), isTrue);

    expect(rasterBuilder.lastImageWidth, 300);
    expect(rasterBuilder.lastImageHeight, 150);
    expect(rasterBuilder.lastOptions?.dpi, 300);
    expect(rasterBuilder.lastOptions?.printableWidthPx, 1181);
  });

  test('wraps universal BLE permission APIs through the client', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);

    expect(await client.hasPermissions(withAndroidFineLocation: true), isFalse);
    await client.requestPermissions(withAndroidFineLocation: true);

    expect(adapter.hasPermissionChecks, <bool>[true]);
    expect(adapter.permissionRequests, <bool>[true]);
  });
}

class _RecordingRasterBuilder extends LpRasterCommandBuilder {
  int? lastImageWidth;
  int? lastImageHeight;
  LpPrintOptions? lastOptions;

  @override
  Future<Uint8List> buildImageData(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    lastImageWidth = image.width;
    lastImageHeight = image.height;
    lastOptions = options;
    return LpPacket.commandBytes(0x28);
  }
}

Future<ui.Image> _largeImage() {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 64, 80),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  final paint = ui.Paint()..color = const ui.Color(0xff000000);
  for (var row = 0; row < 80; row += 1) {
    final width = ((row * 17) % 63) + 1;
    canvas.drawRect(ui.Rect.fromLTWH(0, row.toDouble(), width.toDouble(), 1), paint);
  }
  final picture = recorder.endRecording();
  return picture.toImage(64, 80);
}

List<LpPacket> _decodePackets(Uint8List bytes) {
  final packets = <LpPacket>[];
  var offset = 0;
  while (offset < bytes.length) {
    final packet = LpPacket.tryDecode(bytes.sublist(offset));
    if (packet == null) break;
    packets.add(packet);
    final lengthMarker = bytes[offset + 2] & 0xff;
    final payloadOffset = lengthMarker >= LpPacket.longLengthMarker ? 4 : 3;
    final payloadLength = lengthMarker >= LpPacket.longLengthMarker
        ? (((lengthMarker & 0x3f) << 8) | (bytes[offset + 3] & 0xff))
        : lengthMarker;
    offset += payloadOffset + payloadLength + 1;
  }
  return packets;
}

class _FakeBleAdapter implements LpBleAdapter {
  final StreamController<BleDevice> _scanController = StreamController<BleDevice>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final Map<int, Object> mtuResponses = <int, Object>{};
  final List<int> mtuRequests = <int>[];
  final List<bool> hasPermissionChecks = [];
  final List<bool> permissionRequests = [];
  final List<({String service, String characteristic, Uint8List value, bool withoutResponse})>
  writes = [];
  final StreamController<Uint8List> _notificationController =
      StreamController<Uint8List>.broadcast();

  void emitScan(BleDevice device) => _scanController.add(device);

  @override
  Stream<BleDevice> get scanStream => _scanController.stream;

  @override
  Stream<bool> connectionStream(String deviceId) => _connectionController.stream;

  @override
  Stream<Uint8List> characteristicValueStream(String deviceId, String characteristicId) {
    return _notificationController.stream;
  }

  @override
  Future<void> connect(String deviceId, {Duration? timeout}) async {
    _connectionController.add(true);
  }

  @override
  Future<void> disconnect(String deviceId, {Duration? timeout}) async {
    _connectionController.add(false);
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId, {bool withDescriptors = false}) async {
    return [
      BleService(BleUuidParser.number(0xffe0), [
        BleCharacteristic(BleUuidParser.number(0xffe1), [
          CharacteristicProperty.writeWithoutResponse,
        ], const []),
        BleCharacteristic(BleUuidParser.number(0xffe2), [CharacteristicProperty.notify], const []),
      ]),
    ];
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => AvailabilityState.poweredOn;

  @override
  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) async {
    hasPermissionChecks.add(withAndroidFineLocation);
    return false;
  }

  @override
  Future<Uint8List> read(String deviceId, String service, String characteristic) async {
    return Uint8List(0);
  }

  @override
  Future<void> requestHighConnectionPriority(String deviceId) async {}

  @override
  Future<void> requestPermissions({bool withAndroidFineLocation = false}) async {
    permissionRequests.add(withAndroidFineLocation);
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    mtuRequests.add(expectedMtu);
    final response = mtuResponses[expectedMtu] ?? expectedMtu;
    if (response is Error) throw response;
    if (response is Exception) throw response;
    return response as int;
  }

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String service,
    String characteristic,
  ) async {}

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value, {
    bool withoutResponse = false,
  }) async {
    writes.add((
      service: service,
      characteristic: characteristic,
      value: Uint8List.fromList(value),
      withoutResponse: withoutResponse,
    ));
    if (_containsCommand(value, 0x71)) {
      _notificationController.add(LpPacket.commandBytes(0x71, <int>[0x01, 0x2c]));
    }
    if (_containsCommand(value, 0x72)) {
      _notificationController.add(LpPacket.commandBytes(0x72, <int>[0x04, 0x9d]));
    }
    if (_containsCommand(value, 0x78)) {
      _notificationController.add(LpPacket.commandBytes(0x78, _printerInfoPayload()));
    }
  }

  List<int> _printerInfoPayload() {
    return <int>[
      1,
      0,
      0,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...'Dothan'.codeUnits,
      0,
      ...'LP-D1234AB12'.codeUnits,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x01,
      0x2c,
      0x04,
      0x9d,
      0x10,
      ...'20260108'.codeUnits,
      0,
      20,
      0,
      5,
    ];
  }

  bool _containsCommand(Uint8List value, int command) {
    var offset = 0;
    while (offset < value.length) {
      final packet = LpPacket.tryDecode(value.sublist(offset));
      if (packet == null) return false;
      if (packet.command == command) return true;
      final lengthMarker = value[offset + 2] & 0xff;
      final payloadOffset = lengthMarker >= LpPacket.longLengthMarker ? 4 : 3;
      final payloadLength = lengthMarker >= LpPacket.longLengthMarker
          ? (((lengthMarker & 0x3f) << 8) | (value[offset + 3] & 0xff))
          : lengthMarker;
      offset += payloadOffset + payloadLength + 1;
    }
    return false;
  }
}
