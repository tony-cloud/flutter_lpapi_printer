import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

abstract class LpBleAdapter {
  Stream<BleDevice> get scanStream;

  Stream<bool> connectionStream(String deviceId);

  Stream<Uint8List> characteristicValueStream(
      String deviceId, String characteristicId);

  Future<AvailabilityState> getBluetoothAvailabilityState();

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect(String deviceId, {Duration? timeout});

  Future<void> disconnect(String deviceId, {Duration? timeout});

  Future<List<BleService>> discoverServices(String deviceId,
      {bool withDescriptors = false});

  Future<void> subscribeNotifications(
      String deviceId, String service, String characteristic);

  Future<Uint8List> read(
      String deviceId, String service, String characteristic);

  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value, {
    bool withoutResponse = false,
  });

  Future<int> requestMtu(String deviceId, int expectedMtu);

  Future<void> requestHighConnectionPriority(String deviceId);
}

class UniversalBleLpAdapter implements LpBleAdapter {
  const UniversalBleLpAdapter();

  @override
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  @override
  Stream<bool> connectionStream(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Stream<Uint8List> characteristicValueStream(
      String deviceId, String characteristicId) {
    return UniversalBle.characteristicValueStream(deviceId, characteristicId);
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() {
    return UniversalBle.getBluetoothAvailabilityState();
  }

  @override
  Future<void> startScan() => UniversalBle.startScan();

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId, {Duration? timeout}) {
    return UniversalBle.connect(deviceId, timeout: timeout);
  }

  @override
  Future<void> disconnect(String deviceId, {Duration? timeout}) {
    return UniversalBle.disconnect(deviceId, timeout: timeout);
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId,
      {bool withDescriptors = false}) {
    return UniversalBle.discoverServices(deviceId,
        withDescriptors: withDescriptors);
  }

  @override
  Future<void> subscribeNotifications(
      String deviceId, String service, String characteristic) {
    return UniversalBle.subscribeNotifications(
        deviceId, service, characteristic);
  }

  @override
  Future<Uint8List> read(
      String deviceId, String service, String characteristic) {
    return UniversalBle.read(deviceId, service, characteristic);
  }

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value, {
    bool withoutResponse = false,
  }) {
    return UniversalBle.write(
      deviceId,
      service,
      characteristic,
      value,
      withoutResponse: withoutResponse,
    );
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) {
    return UniversalBle.requestMtu(deviceId, expectedMtu);
  }

  @override
  Future<void> requestHighConnectionPriority(String deviceId) async {
    await UniversalBle.requestConnectionPriority(
      deviceId,
      BleConnectionPriority.highPerformance,
    );
  }
}
