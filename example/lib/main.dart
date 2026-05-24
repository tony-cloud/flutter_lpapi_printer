import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lpapi_printer/lpapi_printer.dart';

void main() {
  runApp(const LpApiPrinterExampleApp());
}

class LpApiPrinterExampleApp extends StatelessWidget {
  const LpApiPrinterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PrinterDemoPage());
  }
}

class PrinterDemoPage extends StatefulWidget {
  const PrinterDemoPage({super.key});

  @override
  State<PrinterDemoPage> createState() => _PrinterDemoPageState();
}

class _PrinterDemoPageState extends State<PrinterDemoPage> {
  final LpPrinterClient _client = LpPrinterClient();
  StreamSubscription<List<LpPrinterAddress>>? _printersSubscription;
  List<LpPrinterAddress> _printers = const <LpPrinterAddress>[];
  LpPrinterAddress? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _printersSubscription = _client.discoveredPrintersStream.listen((printers) {
      setState(() {
        _printers = printers;
        _selected ??= printers.isEmpty ? null : printers.first;
      });
    });
  }

  @override
  void dispose() {
    _printersSubscription?.cancel();
    unawaited(_client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LPAPI Printer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan'),
                ),
                FilledButton.icon(
                  onPressed: _busy || _selected == null
                      ? null
                      : () => _connect(_selected!),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
                FilledButton.icon(
                  onPressed: _busy || !_client.isConnected
                      ? null
                      : _printSample,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print Sample'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButton<LpPrinterAddress>(
              value: _selected,
              hint: const Text('Select printer'),
              isExpanded: true,
              items: [
                for (final printer in _printers)
                  DropdownMenuItem(
                    value: printer,
                    child: Text(
                      '${printer.shownName} (${printer.rssi ?? '-'})',
                    ),
                  ),
              ],
              onChanged: (printer) => setState(() => _selected = printer),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan() => _run(() => _client.startScan());

  Future<void> _connect(LpPrinterAddress printer) =>
      _run(() => _client.connect(printer));

  Future<void> _printSample() {
    return _run(() async {
      final api = LpApi(client: _client);
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
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
