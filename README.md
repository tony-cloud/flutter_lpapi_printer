# lpapi_printer

`lpapi_printer` is a Flutter BLE label-printer client modeled after the DothanTech LPAPI Android SDK.
It uses `universal_ble` for transport, implements LPAPI packet framing, discovers compatible BLE
printers by SDK-style device names, and can rasterize Flutter drawing jobs into printer command bytes.
This package writes in pure Dart, so it is portable to any platform supported by `universal_ble`, but it only implements the BLE transport at this time.

## Features

- BLE scan/connect/disconnect through `universal_ble`.
- LPAPI-compatible packet framing and command helpers.
- Android SDK-style printer name detection, including `-D...` and `-O...` BLE printer names.
- Raster image printing with threshold, inversion, margins, copies, and page keys.
- Label-size scaling plus continuous/gap/hole/black-mark paper settings.
- Left, middle, and right media-position alignment for printers with centered or left-loaded paper.
- LPAPI-style drawing facade for text, QR codes, shapes, lines, and images.

## Usage

```dart
final client = LpPrinterClient();

await client.requestPermissions();
await client.startScan();
final printers = await client.discoveredPrintersStream.first;
await client.connect(printers.first);

final api = LpApi(client: client);
api.startJob(48, 18, 0);
api.drawText('LPAPI BLE', 3, 2, 30, 5, 3.2, LpFontStyle.bold);
api.drawText('Flutter package', 3, 7, 30, 4, 2.4);
api.draw2DQRCode('https://pub.dev/packages/lpapi_printer', 34, 2, 12);

await api.commitJob(
  options: const LpPrintOptions(
    labelWidthMm: 48,
    labelHeightMm: 18,
    paperType: LpPaperType.gap,
    darkness: LpPrintParamValue.defaultPrintDarkness,
    speed: LpPrintParamValue.defaultPrintSpeed,
    alignment: LpPrintAlignment.center,
  ),
);
await client.disconnect();
```

For custom labels, use `LpApi`:

```dart
final api = LpApi(client: client);
await api.openPrinterByAddress(printers.first);
api.startJob(48, 18, 0);
api.drawText('Gateway', 2, 2, 44, 6, 4);
api.draw2DQRCode('payload', 2, 8, 8);
await api.commitJob();
```

For pre-rendered label images, use `LpPrinterClient.printPng` or
`LpPrinterClient.printImage` directly.

## Permissions

`lpapi_printer` uses `universal_ble` for BLE scanning and connections, so your
app must configure the platform Bluetooth permissions required by
`universal_ble` before calling scan or connect APIs. Runtime permission requests
can be made through this package:

```dart
final client = LpPrinterClient();

await client.requestPermissions(
  withAndroidFineLocation: false,
);

final granted = await client.hasPermissions();
```

See the `universal_ble` permission guide:
https://pub.dev/packages/universal_ble#permissions

## Notes

This package intentionally implements BLE printers only. Classic SPP, USB, WiFi, NFC, and the Android
WebView JavaScript bridge are outside the supported surface.
