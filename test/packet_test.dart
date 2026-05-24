import 'package:flutter_test/flutter_test.dart';
import 'package:lpapi_printer/lpapi_printer.dart';

void main() {
  test('encodes and decodes short LPAPI packet', () {
    final packet = const LpPacket(0x43, <int>[0x05]).encode();

    expect(packet, hasLength(5));
    expect(packet[0], LpPacket.startByte);
    expect(packet[1], 0x43);
    expect(packet[2], 1);

    final decoded = LpPacket.tryDecode(packet);
    expect(decoded?.command, 0x43);
    expect(decoded?.payload, <int>[0x05]);
  });

  test('encodes and decodes extended-length LPAPI packet', () {
    final payload = List<int>.generate(200, (index) => index);
    final packet = LpPacket(0x40, payload).encode();

    expect(packet[2] & 0xc0, 0xc0);
    final decoded = LpPacket.tryDecode(packet);
    expect(decoded?.command, 0x40);
    expect(decoded?.payload, payload.map((value) => value & 0xff).toList());
  });

  test('rejects checksum mismatch', () {
    final packet = const LpPacket(0x43, <int>[0x05]).encode();
    packet[4] ^= 0x01;

    expect(() => LpPacket.tryDecode(packet), throwsFormatException);
  });

  test('builds print parameter commands with SDK command ids', () {
    expect(LpCommandBuilder.setPrintPageGapType(2)[1], 0x42);
    expect(LpCommandBuilder.setPrintDarkness(5)[1], 0x43);
    expect(LpCommandBuilder.setPrintSpeed(3)[1], 0x44);
    expect(LpCommandBuilder.setPrintPageGapLength(16400)[1], 0x45);
  });
}
