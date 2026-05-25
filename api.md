# lpapi_printer Flutter API

Version: 0.1.0

`lpapi_printer` is a Flutter package for DothanTech/LPAPI-compatible BLE label
printers. It mirrors the Android LPAPI printing model where it is practical in a
cross-platform Flutter package:

- scan and connect to supported BLE printers
- submit PNG or `ui.Image` raster jobs
- create LPAPI-style drawing jobs in millimeters
- send LPAPI packet commands for density, speed, gap type, and gap length
- use Android LPAPI print parameter names through `LpPrintOptions.fromParamMap`

The package is intentionally generic. Application-specific label generation,
such as KNX FDSK stickers, belongs in the host app.

## Supported Transports

Supported:

- BLE through `universal_ble`

Not implemented by this package:

- Classic Bluetooth SPP
- USB
- Wi-Fi
- NFC
- Android WebView JavaScript bridge

Apps must still declare the platform Bluetooth permissions required by
`universal_ble`, but runtime permission checks and requests are exposed through
`lpapi_printer`.

## Basic Workflow

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
  ),
);

await client.disconnect();
```

## API Layers

### `LpPrinterClient`

Low-level BLE client for scanning, connecting, command sending, and raster image
printing.

| Dart API | Purpose |
| --- | --- |
| `startScan()` | Start BLE scan. Supported printers are emitted on `discoveredPrintersStream`. |
| `stopScan()` | Stop BLE scan. |
| `hasPermissions(...)` | Check runtime BLE permissions through `universal_ble`. |
| `requestPermissions(...)` | Request runtime BLE permissions through `universal_ble`. |
| `connect(LpPrinterAddress address)` | Connect to a discovered printer. |
| `disconnect()` | Disconnect the current printer. |
| `reconnect()` | Reconnect the current remembered address. |
| `sendCommand(Uint8List bytes)` | Send a raw LPAPI packet. |
| `setPrintPageGapType(int value)` | Send command `0x42`. |
| `setPrintDarkness(int value)` | Send command `0x43`. |
| `setPrintSpeed(int value)` | Send command `0x44`. |
| `setPrintPageGapLength(int value)` | Send command `0x45`. |
| `printPng(Uint8List bytes, {LpPrintOptions options})` | Print a PNG image. |
| `printImage(ui.Image image, {LpPrintOptions options})` | Print a Flutter image. |
| `dispose()` | Stop scanning, disconnect, and close streams. |

Streams:

| Stream | Purpose |
| --- | --- |
| `discoveredPrintersStream` | Emits discovered supported printers. |
| `events` | Emits discovery, state, print-progress, and notification events. |

### `LpApi`

LPAPI-style facade for Android SDK method names and millimeter drawing.

Create:

```dart
final api = LpApi.createInstance();
```

Connection helpers:

| Android LPAPI concept | Flutter API |
| --- | --- |
| `isPrinterSupported(String, modelName)` | `isPrinterSupported(String name, [String? modelName])` |
| `isDeviceSupported(device, modelName)` | `isDeviceSupported(Object printer, [String? modelName])` |
| `getAllPrinters(modelName)` | `getAllPrinters([String? modelName])` |
| `getAllPrinterAddresses(modelName)` | `getAllPrinterAddresses([String? modelName])` |
| `getFirstPrinter(modelName)` | `getFirstPrinter([String? modelName])` |
| `getFirstPrinterAddress(modelName)` | `getFirstPrinterAddress([String? modelName])` |
| `openPrinter(modelName)` | `openPrinter([String? name])` |
| `openPrinterByAddress(address)` | `openPrinterByAddress(LpPrinterAddress address)` |
| `openPrinterSync(modelName)` | `openPrinterSync([String? name])` |
| `openPrinterByAddressSync(address)` | `openPrinterByAddressSync(LpPrinterAddress address)` |
| `closePrinter()` | `closePrinter()` |
| `reopenPrinter()` | `reopenPrinter()` |
| `reopenPrinterSync()` | `reopenPrinterSync()` |
| `isPrinterOpened()` | `isPrinterOpened()` |
| `getPrinterName()` | `getPrinterName()` |
| `getPrinterInfo()` | `getPrinterInfo()` |
| `getPrinterState()` | `getPrinterState()` |
| `waitPrinterState(state, millis)` | `waitPrinterState(LpPrinterState state, int millis)` |
| `cancel()` | `cancel()` clears the current drawing job. |
| `quit()` | `quit()` disposes the client. |

Permission helpers:

| Flutter API | Purpose |
| --- | --- |
| `hasPermissions({withAndroidFineLocation})` | Check runtime BLE permissions. |
| `requestPermissions({withAndroidFineLocation})` | Request runtime BLE permissions. Throws if the user denies required permissions. |

Printing helpers:

| Android LPAPI concept | Flutter API |
| --- | --- |
| `printBitmap(bitmap, bundle)` | `printBitmap(ui.Image bitmap, {LpPrintOptions options})` |
| `printBitmap(bitmap, Bundle)` | `printBitmapWithParam(ui.Image bitmap, Map<String, Object?> printParam)` |
| PNG/image printing | `printPng(...)` and `printImage(...)` |

Drawing job helpers:

| Android LPAPI concept | Flutter API |
| --- | --- |
| `startJob(width, height, orientation)` | `startJob(double widthMm, double heightMm, int rotation)` |
| `abortJob()` | `abortJob()` |
| `commitJob()` | `commitJob({LpPrintOptions options})` |
| `commitJobWithParam(Bundle)` | `commitJobWithParam(Map<String, Object?> printParam)` |
| `startPage()` | `startPage()` |
| `endPage()` | `endPage()` |
| `endJob()` | `endJob()` |
| `setBackground(color)` | `setBackground(int argbColor)` |

Drawing methods use millimeters:

- `drawText`
- `drawTextRegular`
- `drawRichText`
- `draw1DBarcode`
- `draw2DQRCode`
- `draw2DDataMatrix` (currently rendered as QR fallback)
- `drawImage`
- `drawBitmap`
- `drawRectangle`
- `fillRectangle`
- `drawRoundRectangle`
- `fillRoundRectangle`
- `drawEllipse`
- `fillEllipse`
- `drawCircle`
- `fillCircle`
- `drawLine`
- `drawDashLine`

## Print Parameters

Use typed Dart options where possible:

```dart
const options = LpPrintOptions(
  labelWidthMm: 48,
  labelHeightMm: 18,
  darkness: LpPrintParamValue.maxPrintDarkness,
  speed: LpPrintParamValue.minPrintSpeed,
  direction: LpPrintDirection.normal,
  copies: 1,
  paperType: LpPaperType.gap,
  gapLength01Mm: 200,
  alignment: LpPrintAlignment.center,
  antiColor: false,
);
```

Android-style string keys are also supported:

```dart
final options = LpPrintOptions.fromParamMap({
  'PRINT_DENSITY': 14,
  'PRINT_SPEED': 0,
  'PRINT_DIRECTION': 0,
  'PRINT_COPIES': 1,
  'GAP_TYPE': 2,
  'GAP_LENGTH_01MM': 200,
  'ANTI_COLOR': false,
  'PAGE_KEY': 123,
});
```

### `LpPrintParamName`

| Constant | Android key |
| --- | --- |
| `printDarkness`, `printDensity` | `PRINT_DENSITY` |
| `printSpeed` | `PRINT_SPEED` |
| `printDirection` | `PRINT_DIRECTION` |
| `printCopies` | `PRINT_COPIES` |
| `gapType` | `GAP_TYPE` |
| `gapLength01Mm`, `gapLength` | `GAP_LENGTH_01MM` |
| `horizontalOffset01Mm` | `HORIZONTAL_OFFSET_01MM` |
| `horizontalOffsetPx` | `HORIZONTAL_OFFSET_PX` |
| `verticalOffset01Mm` | `VERTICAL_OFFSET_01MM` |
| `verticalOffsetPx` | `VERTICAL_OFFSET_PX` |
| `antiColor` | `ANTI_COLOR` |
| `pageKey` | `PAGE_KEY` |
| `printAlignment` | `PRINT_ALIGNMENT` |
| `imageThreshold` | `IMAGE_THRESHOLD` |

### `LpPrintParamValue`

| Constant | Value | Description |
| --- | ---: | --- |
| `minPrintDarkness` | `0` | Minimum density. |
| `defaultPrintDarkness` | `5` | Default density. |
| `maxPrintDarkness` | `14` | Maximum density. |
| `minPrintSpeed` | `0` | Slowest print speed. |
| `defaultPrintSpeed` | `2` | Default speed. |
| `maxPrintSpeed` | `4` | Fastest print speed. |
| `gapNone` | `0` | Continuous/no mark. |
| `gapHole` | `1` | Hole-mark label. |
| `gapGap` | `2` | Gap label. |
| `gapBlack` | `3` | Black-mark label. |
| `printAlignmentLeft` | `1024` | Left-loaded paper. |
| `printAlignmentCenter` | `512` | Center-loaded paper. |
| `printAlignmentRight` | `0` | Right alignment. |

### Typed Enums

| Enum | Values |
| --- | --- |
| `LpPaperType` | `continuous`, `hole`, `gap`, `blackMark` |
| `LpPrintAlignment` | `left`, `center`, `right` |
| `LpPrintDirection` | `normal` (`0`), `right90` (`90`), `rotate180` (`180`), `left270` (`270`) |

## Callback Model

The Android SDK uses `LPAPI.Callback`. This Flutter package exposes streams
instead:

```dart
client.events.listen((event) {
  switch (event.type) {
    case LpPrinterEventType.discovered:
      break;
    case LpPrinterEventType.stateChanged:
      break;
    case LpPrinterEventType.printProgress:
      break;
    case LpPrinterEventType.progressInfo:
      break;
  }
});
```

Related models:

- `LpPrinterEvent`
- `LpPrinterEventType`
- `LpPrinterState`
- `LpPrintProgress`
- `LpPrintFailReason`
- `LpPrinterInfo`
- `LpPrinterAddress`
- `LpPrintData`

## BLE Compatibility Notes

Printer discovery follows the Android SDK naming rules, including `-D...` and
`-O...` suffix forms. The package does not require advertised service UUIDs.

Connection setup:

- discovers GATT services
- reads Device Information `180A/2A24` and `180A/2A28` when available
- selects write/notify characteristics using SDK-compatible rules
- subscribes to notifications
- requests high connection priority
- negotiates MTU using the SDK fallback sequence

Raster printing:

- uses LPAPI packet framing (`0x1f`, command, length, payload, complement
  checksum)
- rasterizes to monochrome with threshold/invert/margins/alignment/direction
- sends SDK command sequence `0x20`, `0x25`, `0x27`, `0x26`, rows, `0x28`
- streams the final package in MTU-sized BLE writes

## Differences From Android LPAPI

The following Android SDK capabilities are intentionally outside the package:

- paired-device enumeration from Android system settings
- Android `BluetoothDevice` overloads
- USB/SPP/Wi-Fi/NFC connection helpers
- Android `Bitmap`, `Bundle`, and `InputStream` overloads
- WebView JavaScript bridge
- printer firmware upgrade APIs

Where Android uses `Bundle`, use `LpPrintOptions` or
`LpPrintOptions.fromParamMap`.
