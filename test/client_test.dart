import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
        BleCharacteristic(BleUuidParser.number(0xffe2), [
          CharacteristicProperty.notify,
        ], const []),
      ]),
    ]);

    expect(endpoint?.writeCharacteristicUuid, BleUuidParser.number(0xffe1));
    expect(endpoint?.notifyCharacteristicUuid, BleUuidParser.number(0xffe2));
  });

  test(
    'scans supported printers without relying on service UUID filters',
    () async {
      final adapter = _FakeBleAdapter();
      final client = LpPrinterClient(adapter: adapter);
      addTearDown(client.dispose);

      await client.startScan();
      adapter.emitScan(
        BleDevice(deviceId: 'device-1', name: 'LP-D1234AB12', rssi: -42),
      );
      adapter.emitScan(
        BleDevice(deviceId: 'device-2', name: 'Gateway BLE', rssi: -1),
      );

      final printers = await client.discoveredPrintersStream.firstWhere(
        (items) => items.isNotEmpty,
      );
      expect(printers, hasLength(1));
      expect(printers.single.shownName, 'LP-D1234AB12');
    },
  );

  test(
    'connects, negotiates MTU fallback, and chunks paced writes to 20 bytes',
    () async {
      final adapter = _FakeBleAdapter();
      adapter.mtuResponses.addAll(<int, Object>{
        183: StateError('mtu rejected'),
        153: 153,
      });
      final client = LpPrinterClient(adapter: adapter);
      addTearDown(client.dispose);
      final printer = const LpPrinterAddress(
        deviceId: 'device-1',
        shownName: 'LP-D1234AB12',
      );

      await client.connect(printer);
      expect(client.printerInfo?.deviceDpi, 300);
      expect(client.printerInfo?.deviceWidth, 567);
      expect(client.writeChunkSize, 150);

      await client.sendCommand(
        Uint8List.fromList(List<int>.generate(55, (index) => index)),
      );

      expect(adapter.mtuRequests, <int>[183, 153]);
      expect(adapter.writes.map((write) => write.value.length), <int>[
        20,
        20,
        15,
      ]);
      expect(adapter.writes.every((write) => write.withoutResponse), isTrue);
    },
  );

  test('prints raster data as one MTU-sized package stream', () async {
    final adapter = _FakeBleAdapter();
    final client = LpPrinterClient(adapter: adapter);
    addTearDown(client.dispose);
    final printer = const LpPrinterAddress(
      deviceId: 'device-1',
      shownName: 'LP-D1234AB12',
    );

    await client.connect(printer);
    adapter.writes.clear();
    final image = await _largeImage();
    await client.printImage(image, options: const LpPrintOptions(pageKey: 11));

    final lengths = adapter.writes.map((write) => write.value.length);
    final package = Uint8List.fromList(
      adapter.writes.expand((write) => write.value).toList(),
    );

    expect(client.writeChunkSize, 180);
    expect(lengths, contains(180));
    expect(lengths.every((length) => length <= 180), isTrue);
    expect(LpPacket.tryDecode(package)?.command, 0x20);
    expect(package, contains(0x28));
    expect(adapter.writes.every((write) => write.withoutResponse), isTrue);
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
    canvas.drawRect(
      ui.Rect.fromLTWH(0, row.toDouble(), width.toDouble(), 1),
      paint,
    );
  }
  final picture = recorder.endRecording();
  return picture.toImage(64, 80);
}

class _FakeBleAdapter implements LpBleAdapter {
  final StreamController<BleDevice> _scanController =
      StreamController<BleDevice>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final Map<int, Object> mtuResponses = <int, Object>{};
  final List<int> mtuRequests = <int>[];
  final List<bool> hasPermissionChecks = [];
  final List<bool> permissionRequests = [];
  final List<
    ({
      String service,
      String characteristic,
      Uint8List value,
      bool withoutResponse,
    })
  >
  writes = [];

  void emitScan(BleDevice device) => _scanController.add(device);

  @override
  Stream<BleDevice> get scanStream => _scanController.stream;

  @override
  Stream<bool> connectionStream(String deviceId) =>
      _connectionController.stream;

  @override
  Stream<Uint8List> characteristicValueStream(
    String deviceId,
    String characteristicId,
  ) {
    return const Stream<Uint8List>.empty();
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
  Future<List<BleService>> discoverServices(
    String deviceId, {
    bool withDescriptors = false,
  }) async {
    return [
      BleService(BleUuidParser.number(0xffe0), [
        BleCharacteristic(BleUuidParser.number(0xffe1), [
          CharacteristicProperty.writeWithoutResponse,
        ], const []),
        BleCharacteristic(BleUuidParser.number(0xffe2), [
          CharacteristicProperty.notify,
        ], const []),
      ]),
    ];
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) async {
    hasPermissionChecks.add(withAndroidFineLocation);
    return false;
  }

  @override
  Future<Uint8List> read(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    return Uint8List(0);
  }

  @override
  Future<void> requestHighConnectionPriority(String deviceId) async {}

  @override
  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {
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
  }
}
