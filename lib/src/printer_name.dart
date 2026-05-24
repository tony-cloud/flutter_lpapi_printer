class LpPrinterName {
  static final RegExp _directBlePattern = RegExp(
    r'.*-[DO][0-9]{4,5}[0-9A-Z]{2,5}[0-9]{2}$',
  );
  static final RegExp _serialPattern = RegExp(
    r'^[A-Z]{0,2}[0-9]{4,5}[0-9A-Z]{2,5}[0-9]{2}$',
  );
  static const List<int> _encodedDpis = <int>[305, 180, 203, 300, 600];

  static bool isSupported(String? name) {
    if (name == null) return false;
    final normalized = name.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    if (_directBlePattern.hasMatch(normalized)) return true;

    final dashIndex = normalized.lastIndexOf('-');
    if (dashIndex <= 0 || dashIndex + 8 >= normalized.length) {
      return false;
    }
    var suffix = normalized.substring(dashIndex + 1);
    final atIndex = suffix.lastIndexOf('@');
    if (atIndex > 0 &&
        atIndex + 7 >= suffix.length &&
        suffix.substring(0, atIndex).length < 8) {
      return false;
    }
    if (atIndex > 0) {
      suffix = suffix.substring(0, atIndex);
    }
    if (!_serialPattern.hasMatch(suffix)) {
      return false;
    }
    return _hasValidSdkChecksum(suffix);
  }

  static String baseName(String name) {
    final index = name.lastIndexOf('-');
    return index > 0 ? name.substring(0, index) : name;
  }

  static LpPrinterNameDefaults defaultsFor(String? name) {
    final serial = _serialSuffix(name);
    if (serial == null) {
      return const LpPrinterNameDefaults(dpi: 203, widthDots: 384);
    }
    var suffix = serial;
    var prefix = '';
    if (suffix.length >= 2 && int.tryParse(suffix[1]) == null) {
      prefix = suffix.substring(0, 2);
      suffix = suffix.substring(2);
    } else if (int.tryParse(suffix[0]) == null) {
      prefix = suffix.substring(0, 1);
      suffix = suffix.substring(1);
    }
    var dpi = 203;
    if (suffix.length >= 9 && int.tryParse(suffix[4]) != null) {
      dpi = _encodedDpis[(suffix.codeUnitAt(4) - 48) % _encodedDpis.length];
    } else if (prefix.isNotEmpty) {
      dpi = 300;
    }
    return LpPrinterNameDefaults(
      dpi: dpi,
      widthDots: (48 * dpi / 25.4).round(),
    );
  }

  static bool _hasValidSdkChecksum(String value) {
    var serial = value;
    var prefix = '';
    var checksum = 0;
    final allDigits = RegExp(r'^[0-9]+$').hasMatch(serial);
    if (serial.length >= 2 && int.tryParse(serial[1]) == null) {
      prefix = serial.substring(0, 2);
      serial = serial.substring(2);
      checksum += prefix.codeUnitAt(0) * 11;
      checksum += prefix.codeUnitAt(1) * 13;
    } else if (int.tryParse(serial[0]) == null) {
      prefix = serial.substring(0, 1);
      serial = serial.substring(1);
      checksum += prefix.codeUnitAt(0) * 17;
    }
    if (serial.length < 8) {
      return false;
    }
    if (!allDigits || serial.length >= 9 || serial[3] != '0') {
      if (allDigits) {
        checksum += (serial.codeUnitAt(0) - 48) << 1;
        checksum += (serial.codeUnitAt(1) - 48) * 3;
        checksum += (serial.codeUnitAt(2) - 48) * 5;
        for (var index = 4; index < serial.length; index += 1) {
          checksum += (serial.codeUnitAt(index) - 48) * (index.isEven ? 7 : 9);
        }
      } else {
        checksum += serial.codeUnitAt(0) << 1;
        checksum += serial.codeUnitAt(1) * 3;
        checksum += serial.codeUnitAt(2) * 5;
        for (var index = 4; index < serial.length; index += 1) {
          checksum += serial.codeUnitAt(index) * (index.isEven ? 7 : 9);
        }
      }
      if ('5682904137'[checksum % 10] != serial[3]) {
        return false;
      }
    }
    final family = int.tryParse(serial.substring(1, 3));
    if (family == null) return false;
    return family ~/ 20 >= 0 && family ~/ 20 <= 2;
  }

  static String? _serialSuffix(String? name) {
    if (name == null) return null;
    final normalized = name.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final dashIndex = normalized.lastIndexOf('-');
    var suffix = dashIndex > 0
        ? normalized.substring(dashIndex + 1)
        : normalized;
    final atIndex = suffix.lastIndexOf('@');
    if (atIndex > 0) {
      suffix = suffix.substring(0, atIndex);
    }
    if (!_serialPattern.hasMatch(suffix)) {
      return null;
    }
    return suffix;
  }
}

class LpPrinterNameDefaults {
  const LpPrinterNameDefaults({required this.dpi, required this.widthDots});

  final int dpi;
  final int widthDots;
}
