import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_adapter.dart';
import 'constants.dart';
import 'models.dart';
import 'packet.dart';
import 'printer_name.dart';
import 'raster.dart';

class LpPrinterClient {
  LpPrinterClient({LpBleAdapter? adapter, LpRasterCommandBuilder? rasterBuilder})
    : _adapter = adapter ?? const UniversalBleLpAdapter(),
      _rasterBuilder = rasterBuilder ?? const LpRasterCommandBuilder();

  static const List<int> mtuFallbacks = <int>[183, 153, 123, 63, 23];
  static const String deviceInfoServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
  static const String modelNumberCharacteristicUuid = '00002a24-0000-1000-8000-00805f9b34fb';
  static const String softwareRevisionCharacteristicUuid = '00002a28-0000-1000-8000-00805f9b34fb';

  final LpBleAdapter _adapter;
  final LpRasterCommandBuilder _rasterBuilder;
  final StreamController<List<LpPrinterAddress>> _discoveredPrintersController =
      StreamController<List<LpPrinterAddress>>.broadcast();
  final StreamController<LpPrinterEvent> _eventsController =
      StreamController<LpPrinterEvent>.broadcast();
  final StreamController<LpPacket> _responsePacketsController =
      StreamController<LpPacket>.broadcast();
  final List<LpPrinterAddress> _discoveredPrinters = <LpPrinterAddress>[];
  final List<int> _notificationBuffer = <int>[];
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

  List<LpPrinterAddress> get discoveredPrinters => List.unmodifiable(_discoveredPrinters);

  LpPrinterState get printerState => _state;

  LpPrinterInfo? get printerInfo => _printerInfo;

  LpPrinterAddress? get connectedAddress => _connectedAddress;

  bool get isConnected => _state.group == 2 && _connectedAddress != null;

  Future<bool> hasPermissions({bool withAndroidFineLocation = false}) {
    return _adapter.hasPermissions(withAndroidFineLocation: withAndroidFineLocation);
  }

  Future<void> requestPermissions({bool withAndroidFineLocation = false}) {
    return _adapter.requestPermissions(withAndroidFineLocation: withAndroidFineLocation);
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
      _connectionSubscription = _adapter.connectionStream(address.deviceId).listen((connected) {
        if (!connected && _state != LpPrinterState.disconnected) {
          _connectedAddress = null;
          _setState(LpPrinterState.disconnected, address);
        }
      });
      final services = await _adapter.discoverServices(address.deviceId, withDescriptors: true);
      _endpoint = selectEndpoint(services);
      final endpoint = _endpoint;
      if (endpoint == null) {
        throw const LpPrinterException('No compatible LPAPI BLE characteristics found');
      }
      _printerInfo = await _readBlePrinterInfo(address);
      await _adapter.subscribeNotifications(
        address.deviceId,
        endpoint.serviceUuid,
        endpoint.notifyCharacteristicUuid,
      );
      _notificationSubscription = _adapter
          .characteristicValueStream(address.deviceId, endpoint.notifyCharacteristicUuid)
          .listen((value) => _handleNotification(address, value));
      _printerInfo = await _refreshPrinterInfo(_printerInfo!);
      _logPrinterInfo(_printerInfo);
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
    _notificationBuffer.clear();
    if (address != null) {
      await _adapter.disconnect(address.deviceId);
    }
    _setState(LpPrinterState.disconnected, address);
  }

  Future<void> reconnect() async {
    final address = _connectedAddress;
    if (address == null) {
      throw const LpPrinterException('No previous printer address to reconnect');
    }
    await connect(address);
  }

  Future<void> sendCommand(Uint8List commandBytes) async {
    await _writeRaw(
      commandBytes,
      paced: commandBytes.length > 20,
      debugName: 'command ${_packetSummary(commandBytes)}',
    );
  }

  Future<void> setPrintPageGapType(int value) =>
      sendCommand(LpCommandBuilder.setPrintPageGapType(value));

  Future<void> setPrintPageGapLength(int value) =>
      sendCommand(LpCommandBuilder.setPrintPageGapLength(value));

  Future<void> setPrintDarkness(int value) =>
      sendCommand(LpCommandBuilder.setPrintDarkness(_resolveDarkness(value)));

  Future<void> setPrintSpeed(int value) => sendCommand(LpCommandBuilder.setPrintSpeed(value));

  Future<void> printPng(
    Uint8List pngBytes, {
    LpPrintOptions options = const LpPrintOptions(),
  }) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    await printImage(frame.image, options: options);
  }

  Future<void> printImage(ui.Image image, {LpPrintOptions options = const LpPrintOptions()}) async {
    final printerInfo = _printerInfo;
    final effectiveOptions = options.copyWith(
      dpi: options.dpi == 203 ? printerInfo?.deviceDpi : null,
      darkness: _resolveOptionalDarkness(options.darkness),
      printableWidthPx: options.printableWidthPx ?? printerInfo?.printableWidthPx,
    );
    final data = LpPrintData(printObj: image, printParam: effectiveOptions.toParamMap());
    final printer = _connectedAddress;
    _log(
      'print job start '
      'image=${image.width}x${image.height} '
      'printer=${printer?.shownName ?? 'unknown'} '
      'printerInfo=$printerInfo '
      'requested=${_formatOptions(options)} '
      'effective=${_formatOptions(effectiveOptions)}',
    );
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
      final printData = await _rasterBuilder.buildImageData(image, options: effectiveOptions);
      _log('print job raster ${_packetSummary(printData)}');
      await _writeRaw(printData, interChunkDelay: _writeChunkDelay, debugName: 'print job');
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
      _setState(isConnected ? LpPrinterState.connected : LpPrinterState.disconnected, printer);
      rethrow;
    }
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _discoveredPrintersController.close();
    await _eventsController.close();
    await _responsePacketsController.close();
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
            characteristic.properties.contains(CharacteristicProperty.writeWithoutResponse);
        if (writeCharacteristic == null &&
            canWrite &&
            (serviceShort != 'ffe0' || characteristicShort == 'ffe1')) {
          writeCharacteristic = characteristic;
          writeService = service;
        }
        final canNotify =
            characteristic.properties.contains(CharacteristicProperty.notify) &&
            !characteristic.properties.contains(CharacteristicProperty.indicate);
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
    if (!LpPrinterName.isSupported(name) || _seenDeviceIds.contains(device.deviceId)) {
      return;
    }
    final address = LpPrinterAddress(
      deviceId: device.deviceId,
      shownName: name,
      macAddress: device.deviceId.contains(':') ? device.deviceId.toUpperCase() : null,
      rssi: device.rssi,
    );
    _seenDeviceIds.add(device.deviceId);
    _discoveredPrinters.add(address);
    _discoveredPrinters.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    _discoveredPrintersController.add(List<LpPrinterAddress>.unmodifiable(_discoveredPrinters));
    _eventsController.add(LpPrinterEvent(type: LpPrinterEventType.discovered, printer: address));
  }

  Future<LpPrinterInfo> _readBlePrinterInfo(LpPrinterAddress address) async {
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
      deviceWidth: useModelDefaults ? defaults.widthDots : addressDefaults.widthDots,
    );
  }

  Future<LpPrinterInfo> _refreshPrinterInfo(LpPrinterInfo fallback) async {
    final response = await _readLpapiPrinterInfo();
    if (response == null) return fallback;
    return LpPrinterInfo(
      deviceName: fallback.deviceName,
      deviceAddress: fallback.deviceAddress,
      deviceType: fallback.deviceType,
      deviceVersion: fallback.deviceVersion,
      softwareVersion: fallback.softwareVersion,
      deviceDpi: response.dpi ?? fallback.deviceDpi,
      deviceWidth: response.widthPx ?? fallback.deviceWidth,
      manufacturer: fallback.manufacturer,
      seriesName: fallback.seriesName,
      devIntName: fallback.devIntName,
      peripheralFlags: fallback.peripheralFlags,
      hardwareFlags: fallback.hardwareFlags,
      softwareFlags: fallback.softwareFlags,
      mcuId: fallback.mcuId,
      darknessCount: response.darknessCount ?? fallback.darknessCount,
    );
  }

  Future<_LpapiPrinterInfoResponse?> _readLpapiPrinterInfo() async {
    final packets = <int, LpPacket>{};
    final receivedExpectedPackets = Completer<void>();
    late final StreamSubscription<LpPacket> subscription;
    subscription = _responsePacketsController.stream.listen((packet) {
      if (packet.command == 0x43 ||
          packet.command == 0x71 ||
          packet.command == 0x72 ||
          packet.command == 0x78) {
        packets[packet.command] = packet;
        _log(
          'lpapi info response command=${_hexByte(packet.command)} '
          'payloadLen=${packet.payload.length} '
          'payload=${_hex(packet.payload)}',
        );
        if (packets.containsKey(0x71) &&
            packets.containsKey(0x72) &&
            (packets.containsKey(0x43) || packets.containsKey(0x78)) &&
            !receivedExpectedPackets.isCompleted) {
          receivedExpectedPackets.complete();
        }
      }
    });
    try {
      _log('lpapi info query start commands=0x71,0x72,0x78,0x43');
      await _writeRaw(
        LpRasterCommandBuilder.combineCommands(<Uint8List>[
          LpPacket.commandBytes(0x71),
          LpPacket.commandBytes(0x72),
          LpPacket.commandBytes(0x78),
          LpPacket.commandBytes(0x43),
        ]),
        paced: true,
        debugName: 'lpapi info query',
      );
      var timedOut = false;
      await receivedExpectedPackets.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () {
          timedOut = true;
        },
      );
      _log(
        'lpapi info query ${timedOut ? 'timeout' : 'complete'} '
        'received=${_formatCommandSet(packets.keys)}',
      );
    } catch (error) {
      _log('lpapi info query failed error=$error');
      return null;
    } finally {
      await subscription.cancel();
    }

    final dpi = _decodeUint16(packets[0x71]?.payload, 0);
    final widthPx = _decodeUint16(packets[0x72]?.payload, 0);
    final darknessCount =
        _decodeDeviceInfoDarknessCount(packets[0x78]?.payload) ??
        _decodeDarknessLevelCount(packets[0x43]?.payload);
    _log(
      'lpapi info decoded dpi=$dpi widthPx=$widthPx '
      'darknessCount=$darknessCount',
    );
    if (dpi == null && widthPx == null && darknessCount == null) {
      _log('lpapi info decoded no usable values');
      return null;
    }
    return _LpapiPrinterInfoResponse(dpi: dpi, widthPx: widthPx, darknessCount: darknessCount);
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

  void _logPrinterInfo(LpPrinterInfo? printerInfo) {
    _log('connected printerInfo: $printerInfo');
  }

  void _handleNotification(LpPrinterAddress address, Uint8List value) {
    _eventsController.add(
      LpPrinterEvent(
        type: LpPrinterEventType.progressInfo,
        printer: address,
        info: Uint8List.fromList(value),
      ),
    );
    _notificationBuffer.addAll(value);
    while (_notificationBuffer.isNotEmpty) {
      final startIndex = _notificationBuffer.indexOf(LpPacket.startByte);
      if (startIndex < 0) {
        _notificationBuffer.clear();
        return;
      }
      if (startIndex > 0) {
        _notificationBuffer.removeRange(0, startIndex);
      }
      if (_notificationBuffer.length < 4) return;

      final lengthMarker = _notificationBuffer[2] & 0xff;
      final payloadOffset = lengthMarker >= LpPacket.longLengthMarker ? 4 : 3;
      if (_notificationBuffer.length < payloadOffset + 1) return;
      final payloadLength = lengthMarker >= LpPacket.longLengthMarker
          ? (((lengthMarker & 0x3f) << 8) | (_notificationBuffer[3] & 0xff))
          : lengthMarker;
      final packetLength = payloadOffset + payloadLength + 1;
      if (_notificationBuffer.length < packetLength) return;

      final packetBytes = _notificationBuffer.sublist(0, packetLength);
      _notificationBuffer.removeRange(0, packetLength);
      try {
        final packet = LpPacket.tryDecode(packetBytes);
        if (packet != null) {
          if (_isInfoCommand(packet.command)) {
            _log(
              'notify packet command=${_hexByte(packet.command)} '
              'payloadLen=${packet.payload.length} '
              'payload=${_hex(packet.payload)}',
            );
          }
          _responsePacketsController.add(packet);
        }
      } catch (error) {
        debugPrint('[lpapi_printer] ignored malformed notify packet: $error');
      }
    }
  }

  int? _decodeUint16(List<int>? bytes, int offset) {
    if (bytes == null || bytes.length < offset + 2) return null;
    return ((bytes[offset] & 0xff) << 8) | (bytes[offset + 1] & 0xff);
  }

  int? _decodeDarknessLevelCount(List<int>? bytes) {
    if (bytes == null || bytes.length < 2) return null;
    final level = bytes[1] & 0xff;
    return level <= 0 ? null : level;
  }

  int? _decodeDeviceInfoDarknessCount(List<int>? bytes) {
    if (bytes == null || bytes.length < 24) return null;
    var offset = 0;

    int? readByte() {
      if (offset >= bytes.length) return null;
      return bytes[offset++] & 0xff;
    }

    bool skip(int count) {
      if (offset + count > bytes.length) return false;
      offset += count;
      return true;
    }

    bool skipCString() {
      while (offset < bytes.length) {
        final value = bytes[offset++] & 0xff;
        if (value == 0) return true;
      }
      return false;
    }

    if (readByte() == null || !skip(2)) return null;
    final version = readByte();
    if (version == null) return null;
    if (!skip(version >= 2 ? 4 : 2)) return null;
    if (!skip(4)) return null;
    if (!skipCString() || !skipCString()) return null;
    if (readByte() == null || !skip(6)) return null;
    if (!skip(2) || !skip(2)) return null;
    if (readByte() == null || !skipCString()) return null;
    final count = readByte();
    return count == null || count <= 0 ? null : count;
  }

  int? _resolveOptionalDarkness(int? value) {
    return value == null ? null : _resolveDarkness(value);
  }

  int _resolveDarkness(int value) {
    final printerInfo = _printerInfo;
    final count = printerInfo?.darknessCount;
    if (count == null || count <= 0 || value < 0 || value >= 255) {
      return value;
    }
    final max = printerInfo!.maxPrintDarkness;
    if (value >= max) {
      return max;
    }
    if (value == LpPrintParamValue.maxPrintDarkness && max > value) {
      return max;
    }
    return value;
  }

  Future<void> _writeRaw(
    Uint8List data, {
    bool paced = false,
    Duration? interChunkDelay,
    String? debugName,
  }) async {
    final address = _connectedAddress;
    final endpoint = _endpoint;
    if (address == null || endpoint == null) {
      throw const LpPrinterException('Printer is not connected');
    }
    var offset = 0;
    final chunkLimit = paced ? math.min(_writeChunkSize, 20) : _writeChunkSize;
    final delay = paced ? const Duration(milliseconds: 5) : interChunkDelay;
    var chunks = 0;
    var maxChunk = 0;
    while (offset < data.length) {
      final next = math.min(offset + chunkLimit, data.length);
      final chunkLength = next - offset;
      await _adapter.write(
        address.deviceId,
        endpoint.serviceUuid,
        endpoint.writeCharacteristicUuid,
        Uint8List.fromList(data.sublist(offset, next)),
        withoutResponse: true,
      );
      chunks += 1;
      if (maxChunk < chunkLength) maxChunk = chunkLength;
      offset = next;
      if (offset < data.length && delay != null && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
    if (debugName != null) {
      _log(
        'write[$debugName] bytes=${data.length} chunks=$chunks '
        'maxChunk=$maxChunk chunkLimit=$chunkLimit '
        'delayMs=${delay?.inMilliseconds ?? 0} paced=$paced',
      );
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
      LpPrinterEvent(type: LpPrinterEventType.stateChanged, printer: printer, state: state),
    );
  }

  static String _shortUuid(String uuid) {
    final normalized = BleUuidParser.stringOrNull(uuid)?.toLowerCase() ?? uuid.toLowerCase();
    if (normalized.startsWith('0000') && normalized.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return normalized.substring(4, 8);
    }
    return normalized;
  }

  void _log(String message) {
    debugPrint('[lpapi_printer] $message');
  }

  bool _isInfoCommand(int command) {
    return command == 0x43 || command == 0x71 || command == 0x72 || command == 0x78;
  }

  String _formatOptions(LpPrintOptions options) {
    return '{'
        'sizeMm=${_formatDouble(options.labelWidthMm)}x'
        '${_formatDouble(options.labelHeightMm)}, '
        'dpi=${options.dpi}, '
        'darkness=${options.darkness}, '
        'speed=${options.speed}, '
        'copies=${options.copies}, '
        'pageKey=${options.pageKey}, '
        'gapType=${options.effectiveGapType}, '
        'gapLength01Mm=${options.gapLength01Mm}, '
        'alignment=${options.alignment.name}, '
        'direction=${options.direction.degrees}, '
        'printableWidthPx=${options.printableWidthPx}, '
        'antiColor=${options.antiColor}, '
        'threshold=${options.threshold}'
        '}';
  }

  String _formatDouble(double? value) {
    return value == null ? 'null' : value.toStringAsFixed(2);
  }

  String _packetSummary(Uint8List bytes) {
    final packets = _decodePacketsForLog(bytes, limit: 24);
    if (packets.isEmpty) {
      return 'bytes=${bytes.length} packets=0 raw=${_hex(bytes)}';
    }
    final counts = <int, int>{};
    for (final packet in packets) {
      counts[packet.command] = (counts[packet.command] ?? 0) + 1;
    }
    final commands = packets.map((packet) => _formatPacketForLog(packet)).join(',');
    final lineBytes = _firstVariableLengthPayload(packets, 0x27);
    final lineCount = _firstVariableLengthPayload(packets, 0x26);
    final density = _firstPayloadByte(packets, 0x43);
    final speed = _firstPayloadByte(packets, 0x44);
    final gapType = _firstPayloadByte(packets, 0x42);
    return 'bytes=${bytes.length} '
        'packets=${packets.length}${_hasMorePackets(bytes, packets) ? '+' : ''} '
        'commands=$commands '
        'counts=${_formatCommandCounts(counts)} '
        'lineBytes=$lineBytes lineCount=$lineCount '
        'density=$density speed=$speed gapType=$gapType';
  }

  List<LpPacket> _decodePacketsForLog(Uint8List bytes, {required int limit}) {
    final packets = <LpPacket>[];
    var offset = 0;
    while (offset < bytes.length && packets.length < limit) {
      final packet = LpPacket.tryDecode(bytes.sublist(offset));
      if (packet == null) break;
      packets.add(packet);
      final packetLength = _packetLength(bytes, offset);
      if (packetLength == null || packetLength <= 0) break;
      offset += packetLength;
    }
    return packets;
  }

  bool _hasMorePackets(Uint8List bytes, List<LpPacket> packets) {
    var offset = 0;
    for (var index = 0; index < packets.length; index += 1) {
      final packetLength = _packetLength(bytes, offset);
      if (packetLength == null) return false;
      offset += packetLength;
    }
    return offset < bytes.length;
  }

  int? _packetLength(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length || bytes[offset] != LpPacket.startByte) {
      return null;
    }
    final lengthMarker = bytes[offset + 2] & 0xff;
    final payloadOffset = lengthMarker >= LpPacket.longLengthMarker ? 4 : 3;
    if (offset + payloadOffset + 1 > bytes.length) return null;
    final payloadLength = lengthMarker >= LpPacket.longLengthMarker
        ? (((lengthMarker & 0x3f) << 8) | (bytes[offset + 3] & 0xff))
        : lengthMarker;
    final totalLength = payloadOffset + payloadLength + 1;
    return offset + totalLength <= bytes.length ? totalLength : null;
  }

  String _formatPacketForLog(LpPacket packet) {
    final payload = switch (packet.command) {
      0x20 || 0x21 || 0x22 || 0x25 || 0x26 || 0x27 => '',
      _ => ':${_hex(packet.payload, limit: 8)}',
    };
    return '${_hexByte(packet.command)}$payload';
  }

  String _formatCommandCounts(Map<int, int> counts) {
    final entries = counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((entry) => '${_hexByte(entry.key)}:${entry.value}').join(',');
  }

  String _formatCommandSet(Iterable<int> commands) {
    final values = commands.toList()..sort();
    return values.map(_hexByte).join(',');
  }

  int? _firstPayloadByte(List<LpPacket> packets, int command) {
    for (final packet in packets) {
      if (packet.command == command && packet.payload.isNotEmpty) {
        return packet.payload.first & 0xff;
      }
    }
    return null;
  }

  int? _firstVariableLengthPayload(List<LpPacket> packets, int command) {
    for (final packet in packets) {
      if (packet.command == command) {
        return _decodeVariableLength(packet.payload);
      }
    }
    return null;
  }

  int? _decodeVariableLength(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final first = bytes.first & 0xff;
    if (first >= LpPacket.longLengthMarker) {
      if (bytes.length < 2) return null;
      return ((first & 0x3f) << 8) | (bytes[1] & 0xff);
    }
    return first;
  }

  String _hexByte(int value) {
    return '0x${(value & 0xff).toRadixString(16).padLeft(2, '0')}';
  }

  String _hex(List<int> bytes, {int limit = 32}) {
    final shown = bytes.take(limit).map(_hexByte).join(' ');
    if (bytes.length <= limit) return shown;
    return '$shown ...(+${bytes.length - limit})';
  }
}

class _LpapiPrinterInfoResponse {
  const _LpapiPrinterInfoResponse({this.dpi, this.widthPx, this.darknessCount});

  final int? dpi;
  final int? widthPx;
  final int? darknessCount;
}
