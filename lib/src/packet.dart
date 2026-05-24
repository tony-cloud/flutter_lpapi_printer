import 'dart:typed_data';

class LpPacket {
  const LpPacket(this.command, [this.payload = const <int>[]]);

  static const int startByte = 0x1f;
  static const int longLengthMarker = 0xc0;
  static const int checksumBypass = 0x88;

  final int command;
  final List<int> payload;

  Uint8List encode() {
    final normalizedPayload = payload
        .map((value) => value & 0xff)
        .toList(growable: false);
    if (command == 0) {
      return Uint8List.fromList(normalizedPayload);
    }
    final length = normalizedPayload.length;
    final bytes = <int>[startByte, command & 0xff];
    if (length >= longLengthMarker) {
      bytes.add(((length >> 8) | longLengthMarker) & 0xff);
      bytes.add(length & 0xff);
    } else {
      bytes.add(length & 0xff);
    }
    bytes.addAll(normalizedPayload);
    bytes.add(_checksum(bytes, 1, bytes.length));
    return Uint8List.fromList(bytes);
  }

  static LpPacket? tryDecode(List<int> bytes) {
    if (bytes.length < 4 || bytes.first != startByte) {
      return null;
    }
    final command = bytes[1] & 0xff;
    final marker = bytes[2] & 0xff;
    final payloadOffset = marker >= longLengthMarker ? 4 : 3;
    if (bytes.length < payloadOffset + 1) {
      return null;
    }
    final length = marker >= longLengthMarker
        ? (((marker & 0x3f) << 8) | (bytes[3] & 0xff))
        : marker;
    final totalLength = payloadOffset + length + 1;
    if (bytes.length < totalLength) {
      return null;
    }
    final checksum = bytes[totalLength - 1] & 0xff;
    if (checksum != checksumBypass &&
        checksum != _checksum(bytes, 1, totalLength - 1)) {
      throw const FormatException('LPAPI packet checksum mismatch');
    }
    return LpPacket(
      command,
      bytes.sublist(payloadOffset, payloadOffset + length),
    );
  }

  static int writeVariableLength(List<int> target, int offset, int value) {
    final normalized = value.clamp(0, 0x3fffff);
    if (normalized >= longLengthMarker) {
      target[offset] = ((normalized >> 8) | longLengthMarker) & 0xff;
      target[offset + 1] = normalized & 0xff;
      return offset + 2;
    }
    target[offset] = normalized & 0xff;
    return offset + 1;
  }

  static List<int> variableLength(int value) {
    final bytes = List<int>.filled(2, 0);
    final next = writeVariableLength(bytes, 0, value);
    return bytes.sublist(0, next);
  }

  static Uint8List commandBytes(
    int command, [
    List<int> payload = const <int>[],
  ]) {
    return LpPacket(command, payload).encode();
  }

  static int _checksum(List<int> bytes, int start, int end) {
    var sum = 0;
    for (var index = start; index < end; index += 1) {
      sum = (sum + (bytes[index] & 0xff)) & 0xff;
    }
    return (~sum) & 0xff;
  }
}

class LpCommandBuilder {
  static Uint8List setPrintPageGapType(int value) =>
      LpPacket.commandBytes(0x42, <int>[value]);

  static Uint8List setPrintDarkness(int value) =>
      LpPacket.commandBytes(0x43, <int>[value]);

  static Uint8List setPrintSpeed(int value) =>
      LpPacket.commandBytes(0x44, <int>[value]);

  static Uint8List setPrintPageGapLength(int value) {
    final clamped = value.clamp(0, 4194303);
    if (clamped > 16383) {
      return LpPacket.commandBytes(0x45, <int>[
        ((clamped >> 16) | 0xc0) & 0xff,
        (clamped >> 8) & 0xff,
        clamped & 0xff,
      ]);
    }
    return LpPacket.commandBytes(0x45, LpPacket.variableLength(clamped));
  }
}
