class LpPrintParamName {
  static const pageKey = 'PAGE_KEY';
  static const printDarkness = 'PRINT_DENSITY';
  static const printDensity = 'PRINT_DENSITY';
  static const printSpeed = 'PRINT_SPEED';
  static const printDirection = 'PRINT_DIRECTION';
  static const printSeparateLine = 'PRINT_SEPARATE_LINE';
  static const printCopies = 'PRINT_COPIES';
  static const gapType = 'GAP_TYPE';
  static const gapLength01Mm = 'GAP_LENGTH_01MM';
  static const gapLengthPx = 'GAP_LENGTH_PX';
  static const gapLength = 'GAP_LENGTH_01MM';
  static const printAlignment = 'PRINT_ALIGNMENT';
  static const printableWidthPx = 'PRINTABLE_WIDTH_PX';
  static const antiColor = 'ANTI_COLOR';
  static const horizontalFlip = 'HOR_FLIP';
  static const horizontalOffset01Mm = 'HORIZONTAL_OFFSET_01MM';
  static const horizontalOffsetPx = 'HORIZONTAL_OFFSET_PX';
  static const verticalOffset01Mm = 'VERTICAL_OFFSET_01MM';
  static const verticalOffsetPx = 'VERTICAL_OFFSET_PX';
  static const leftMargin01Mm = 'LEFT_MARGIN_01MM';
  static const leftMarginPx = 'LEFT_MARGIN_PX';
  static const rightMargin01Mm = 'RIGHT_MARGIN_01MM';
  static const rightMarginPx = 'RIGHT_MARGIN_PX';
  static const topMargin01Mm = 'TOP_MARGIN_01MM';
  static const topMarginPx = 'TOP_MARGIN_PX';
  static const bottomMargin01Mm = 'BOTTOM_MARGIN_01MM';
  static const bottomMarginPx = 'BOTTOM_MARGIN_PX';
  static const imageThreshold = 'IMAGE_THRESHOLD';
  static const printBle = 'PRINT_BLE';
  static const printCt = 'PRINT_CT';
  static const printDpi = 'PRINT_DPI';
  static const supportPageKey = 'SUPPORT_PAGE_KEY';
}

class LpPrintParamValue {
  static const minPrintDarkness = 0;
  static const defaultPrintDarkness = 5;
  static const maxPrintDarkness = 14;
  static const minPrintSpeed = 0;
  static const defaultPrintSpeed = 2;
  static const maxPrintSpeed = 4;
  static const gapNone = 0;
  static const gapHole = 1;
  static const gapGap = 2;
  static const gapBlack = 3;
  static const printAlignmentLeft = 1024;
  static const printAlignmentCenter = 512;
  static const printAlignmentRight = 0;
}

class LpItemAlignment {
  static const near = 0;
  static const center = 1;
  static const far = 2;
  static const sameAsItem = 3;
  static const left = near;
  static const right = far;
  static const top = near;
  static const middle = center;
  static const bottom = far;
}

class LpFontStyle {
  static const regular = 0;
  static const bold = 1;
  static const italic = 2;
  static const boldItalic = 3;
  static const underline = 4;
  static const strikeout = 8;
}

class LpPenAlignment {
  static const center = 0;
  static const inset = 1;
}

class LpBarcodeType {
  static const upcA = 20;
  static const upcE = 21;
  static const ean13 = 22;
  static const ean8 = 23;
  static const code39 = 24;
  static const itf25 = 25;
  static const codabar = 26;
  static const code93 = 27;
  static const code128 = 28;
  static const isbn = 29;
  static const ecode39 = 30;
  static const auto = 60;
  static const code128A = 61;
  static const code128B = 62;
  static const code128C = 63;
}

class LpQrErrorCorrection {
  static const l = 0;
  static const m = 1;
  static const q = 2;
  static const h = 3;
}
