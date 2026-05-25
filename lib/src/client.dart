import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_adapter.dart';
import 'models.dart';
import 'packet.dart';
import 'printer_name.dart';
import 'raster.dart';

class LpPrinterClient {
  LpPrinterClient({
    LpBleAdapter? adapter,
    LpRasterCommandBuilder? rasterBuilder,
  }) : _adapter = adapter ?? const UniversalBleLpAdapter(),
       _rasterBuilder = rasterBuilder ?? const LpRasterCommandBuilder();

  static const List<int> mtuFallbacks = <int>[183, 153, 123, 63, 23];
  static const String deviceInfoServiceUuid =
      '0000180a-0000-1000-8000-00805f9b34fb';
  static const String modelNumberCharacteristicUuid =
      '00002a24-0000-1000-8000-00805f9b34fb';
  static const String softwareRevisionCharacteristicUuid =
      '00002a28-0000-1000-8000-00805f9b34fb';

  final LpBleAdapter _adapter;
  final LpRasterCommandBuilder _rasterBuilder;
  final StreamController<List<LpPrinterAddress>> _discoveredPrintersController =
      StreamController<List<LpPrinterAddress>>.broadcast();
  final StreamController<LpPrinterEvent> _eventsController =
      StreamController<LpPrinterEvent>.broadcast();
  final List<LpPrinterAddress> _discoveredPrinters = <LpPrinterAddress>[];
  final Set<String> _seenDeviceIds = <String>{};

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Uint8List>? _notificationSubscription;
  LpPrinterAddress? _connectedAddress;
  LpPrinterInfo? _printerInfo;
  LpBleEndpoint? _endpoint;
  int _writeChunkSize = 20;
  Duration _writeChunkDelay = const Duration(milliseconds: 5);
  LpPrinterState _state = LpPrinterState.disconnected;

  Stream<List<LpPrinterAddress>> get discoveredPrintersStream =>
      _discoveredPrintersController.stream;

  Stream<LpPrinterEvent> get events => _eventsController.stream;

  List<LpPrinterAddress> get discoveredPrinters =>
      List.unmodifiable(_discoveredPrinters);

  LpPrinterState get printerState => _state;

  LpPrinterInfo? get printerInfo => _printerInfo;

  LpPrinterAddress? get connectedAddress => _connectedAddress;

  bool get isConnected => _state.group == 2 && _connectedAddress != null;

  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) {
    return _adapter.hasPermissions(
      withAndroidFineLocation: withAndroidFineLocation,
    );
  }

  Future<void> requestPermissions({bool withAndroidFineLocation = false}) {
    return _adapter.requestPermissions(
      withAndroidFineLocation: withAndroidFineLocation,
    );
  }

  Future<void> startScan() async {
    _discoveredPrinters.clear();
    _seenDeviceIds.clear();
    _discoveredPrintersController.add(const <LpPrinterAddress>[]);
    await _scanSubscription?.cancel();
    _scanSubscription = _adapter.scanStream.listen(_handleScanResult);
    await _adapter.startScan();
  }

  Future<void> stopScan() async {
    await _adapter.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> connect(
    LpPrinterAddress address, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await stopScan();
    _setState(LpPrinterState.connecting, address);
    _connectedAddress = address;
    try {
      await _adapter.connect(address.deviceId, timeout: timeout);
      await _connectionSubscription?.cancel();
      _connectionSubscription = _adapter
          .connectionStream(address.deviceId)
          .listen((connected) {
            if (!connected && _state != LpPrinterState.disconnected) {
              _connectedAddress = null;
              _setState(LpPrinterState.disconnected, address);
            }
          });
      final services = await _adapter.discoverServices(
        address.deviceId,
        withDescriptors: true,
      );
      _endpoint = selectEndpoint(services);
      final endpoint = _endpoint;
      if (endpoint == null) {
        throw const LpPrinterException(
          'No compatible LPAPI BLE characteristics found',
        );
      }
      _printerInfo = await _readPrinterInfo(address);
      await _adapter.subscribeNotifications(
        address.deviceId,
        endpoint.serviceUuid,
        endpoint.notifyCharacteristicUuid,
      );
      _notificationSubscription = _adapter
          .characteristicValueStream(
            address.deviceId,
            endpoint.notifyCharacteristicUuid,
          )
          .listen((value) {
            _eventsController.add(
              LpPrinterEvent(
                type: LpPrinterEventType.progressInfo,
                printer: address,
                info: Uint8List.fromList(value),
              ),
            );
          });
      await _negotiateMtu(address.deviceId);
      await _requestHighPriority(address.deviceId);
      _setState(LpPrinterState.connected, address);
    } catch (_) {
      _connectedAddress = null;
      _endpoint = null;
      _setState(LpPrinterState.disconnected, address);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final address = _connectedAddress;
    await _notificationSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _notificationSubscription = null;
    _connectionSubscription = null;
    _endpoint = null;
    _printerInfo = null;
    _connectedAddress = null;
    if (address != null) {
      await _adapter.disconnect(address.deviceId);
    }
    _setState(LpPrinterState.disconnected, address);
  }

  Future<void> reconnect() async {
    final address = _connectedAddress;
    if (address == null) {
      throw const LpPrinterException(
        'No previous printer address to reconnect',
      );
    }
    await connect(address);
  }

  Future<void> sendCommand(Uint8List commandBytes) async {
    await _writeRaw(commandBytes, paced: commandBytes.length > 20);
  }

  Future<void> setPrintPageGapType(int value) =>
      sendCommand(LpCommandBuilder.setPrintPageGapType(value));

  Future<void> setPrintPageGapLength(int value) =>
      sendCommand(LpCommandBuilder.setPrintPageGapLength(value));

  Future<void> setPrintDarkness(int value) =>
      sendCommand(LpCommandBuilder.setPrintDarkness(value));

  Future<void> setPrintSpeed(int value) =>
      sendCommand(LpCommandBuilder.setPrintSpeed(value));

  Future<void> printPng(
    Uint8List pngBytes, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    await printImage(frame.image, options: options);
  }

  Future<void> printImage(
    ui.Image image, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final printerInfo = _printerInfo;
    final effectiveOptions = options.copyWith(
      dpi: options.dpi == 203 ? printerInfo?.deviceDpi : null,
      printableWidthPx: options.printableWidthPx ?? printerInfo?.deviceWidth,
    );
    final data = LpPrintData(
      printObj: image,
      printParam: effectiveOptions.toParamMap(),
    );
    final printer = _connectedAddress;
    _setState(LpPrinterState.printing, printer);
    _eventsController.add(
      LpPrinterEvent(
        type: LpPrinterEventType.printProgress,
        printer: printer,
        printData: data,
        printProgress: LpPrintProgress.connected,
      ),
    );
    try {
      await _applyOptions(effectiveOptions);
      final printData = await _rasterBuilder.buildImageData(
        image,
        options: effectiveOptions,
      );
      await _writeRaw(printData, interChunkDelay: _writeChunkDelay);
      _eventsController.add(
        LpPrinterEvent(
          type: LpPrinterEventType.printProgress,
          printer: printer,
          printData: data,
          printProgress: LpPrintProgress.success,
        ),
      );
      _setState(LpPrinterState.connected, printer);
    } catch (_) {
      _eventsController.add(
        LpPrinterEvent(
          type: LpPrinterEventType.printProgress,
          printer: printer,
          printData: data,
          printProgress: LpPrintProgress.failed,
          failReason: LpPrintFailReason.other,
        ),
      );
      _setState(
        isConnected ? LpPrinterState.connected : LpPrinterState.disconnected,
        printer,
      );
      rethrow;
    }
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _discoveredPrintersController.close();
    await _eventsController.close();
  }

  @visibleForTesting
  int get writeChunkSize => _writeChunkSize;

  static LpBleEndpoint? selectEndpoint(List<BleService> services) {
    BleCharacteristic? writeCharacteristic;
    BleService? writeService;
    BleCharacteristic? notifyCharacteristic;
    BleService? notifyService;

    for (final service in services) {
      final serviceShort = _shortUuid(service.uuid);
      for (final characteristic in service.characteristics) {
        final characteristicShort = _shortUuid(characteristic.uuid);
        final canWrite =
            characteristic.properties.contains(CharacteristicProperty.write) ||
            characteristic.properties.contains(
              CharacteristicProperty.writeWithoutResponse,
            );
        if (writeCharacteristic == null &&
            canWrite &&
            (serviceShort != 'ffe0' || characteristicShort == 'ffe1')) {
          writeCharacteristic = characteristic;
          writeService = service;
        }
        final canNotify =
            characteristic.properties.contains(CharacteristicProperty.notify) &&
            !characteristic.properties.contains(
              CharacteristicProperty.indicate,
            );
        if (notifyCharacteristic == null && canNotify) {
          notifyCharacteristic = characteristic;
          notifyService = service;
        }
      }
    }

    if (writeCharacteristic == null || writeService == null) return null;
    notifyCharacteristic ??= writeCharacteristic;
    notifyService ??= writeService;
    return LpBleEndpoint(
      serviceUuid: writeService.uuid,
      writeCharacteristicUuid: writeCharacteristic.uuid,
      notifyCharacteristicUuid: notifyCharacteristic.uuid,
    );
  }

  void _handleScanResult(BleDevice device) {
    final name = device.name ?? device.rawName ?? '';
    if (!LpPrinterName.isSupported(name) ||
        _seenDeviceIds.contains(device.deviceId)) {
      return;
    }
    final address = LpPrinterAddress(
      deviceId: device.deviceId,
      shownName: name,
      macAddress: device.deviceId.contains(':')
          ? device.deviceId.toUpperCase()
          : null,
      rssi: device.rssi,
    );
    _seenDeviceIds.add(device.deviceId);
    _discoveredPrinters.add(address);
    _discoveredPrinters.sort(
      (a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999),
    );
    _discoveredPrintersController.add(
      List<LpPrinterAddress>.unmodifiable(_discoveredPrinters),
    );
    _eventsController.add(
      LpPrinterEvent(type: LpPrinterEventType.discovered, printer: address),
    );
  }

  Future<LpPrinterInfo> _readPrinterInfo(LpPrinterAddress address) async {
    var model = address.shownName;
    var software = '';
    try {
      final bytes = await _adapter.read(
        address.deviceId,
        deviceInfoServiceUuid,
        modelNumberCharacteristicUuid,
      );
      if (bytes.isNotEmpty) model = String.fromCharCodes(bytes).trim();
    } catch (_) {}
    try {
      final bytes = await _adapter.read(
        address.deviceId,
        deviceInfoServiceUuid,
        softwareRevisionCharacteristicUuid,
      );
      if (bytes.isNotEmpty) software = String.fromCharCodes(bytes).trim();
    } catch (_) {}
    final defaults = LpPrinterName.defaultsFor(model.isEmpty ? null : model);
    final addressDefaults = LpPrinterName.defaultsFor(address.shownName);
    final useModelDefaults = defaults.dpi != 203;
    return LpPrinterInfo(
      deviceName: model.isEmpty ? address.shownName : model,
      deviceAddress: address.macAddress ?? address.deviceId,
      softwareVersion: software,
      deviceDpi: useModelDefaults ? defaults.dpi : addressDefaults.dpi,
      deviceWidth: useModelDefaults
          ? defaults.widthDots
          : addressDefaults.widthDots,
    );
  }

  Future<void> _negotiateMtu(String deviceId) async {
    _writeChunkSize = 20;
    _writeChunkDelay = const Duration(milliseconds: 5);
    for (final requested in mtuFallbacks) {
      try {
        final mtu = await _adapter.requestMtu(deviceId, requested);
        _writeChunkSize = math.max(20, math.min(mtu, requested) - 3);
        _writeChunkDelay = _writeDelayForMtuRequest(requested);
        return;
      } catch (_) {}
    }
  }

  Future<void> _requestHighPriority(String deviceId) async {
    try {
      await _adapter.requestHighConnectionPriority(deviceId);
    } catch (_) {}
  }

  Future<void> _applyOptions(LpPrintOptions options) async {
    final gapType = options.effectiveGapType;
    if (gapType != null) await setPrintPageGapType(gapType);
    if (options.gapLength01Mm != null) {
      await setPrintPageGapLength(options.gapLength01Mm!);
    }
    if (options.darkness != null) await setPrintDarkness(options.darkness!);
    if (options.speed != null) await setPrintSpeed(options.speed!);
  }

  Future<void> _writeRaw(
    Uint8List data, {
    bool paced = false,
    Duration? interChunkDelay,
  }) async {
    final address = _connectedAddress;
    final endpoint = _endpoint;
    if (address == null || endpoint == null) {
      throw const LpPrinterException('Printer is not connected');
    }
    var offset = 0;
    final chunkLimit = paced ? math.min(_writeChunkSize, 20) : _writeChunkSize;
    final delay = paced ? const Duration(milliseconds: 5) : interChunkDelay;
    while (offset < data.length) {
      final next = math.min(offset + chunkLimit, data.length);
      await _adapter.write(
        address.deviceId,
        endpoint.serviceUuid,
        endpoint.writeCharacteristicUuid,
        Uint8List.fromList(data.sublist(offset, next)),
        withoutResponse: true,
      );
      offset = next;
      if (offset < data.length && delay != null && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
  }

  static Duration _writeDelayForMtuRequest(int requested) {
    return switch (requested) {
      23 => const Duration(milliseconds: 5),
      _ => const Duration(milliseconds: 15),
    };
  }

  void _setState(LpPrinterState state, LpPrinterAddress? printer) {
    _state = state;
    _eventsController.add(
      LpPrinterEvent(
        type: LpPrinterEventType.stateChanged,
        printer: printer,
        state: state,
      ),
    );
  }

  static String _shortUuid(String uuid) {
    final normalized =
        BleUuidParser.stringOrNull(uuid)?.toLowerCase() ?? uuid.toLowerCase();
    if (normalized.startsWith('0000') &&
        normalized.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return normalized.substring(4, 8);
    }
    return normalized;
  }
}
