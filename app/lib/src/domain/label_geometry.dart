enum LabelContentOrientation { portrait, landscape }

enum LabelSafeMarginPreset {
  tight(displayLabel: 'Tight', millimetres: 1),
  normal(displayLabel: 'Normal', millimetres: 1.5),
  wide(displayLabel: 'Wide', millimetres: 2.5);

  const LabelSafeMarginPreset({
    required this.displayLabel,
    required this.millimetres,
  });

  final String displayLabel;
  final double millimetres;
}

final class PixelSize {
  const PixelSize({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PixelSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

final class PixelPoint {
  const PixelPoint({required this.x, required this.y});

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is PixelPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class LabelContentInsets {
  const LabelContentInsets({
    required this.horizontalPx,
    required this.verticalPx,
  });

  final int horizontalPx;
  final int verticalPx;

  @override
  bool operator ==(Object other) =>
      other is LabelContentInsets &&
      other.horizontalPx == horizontalPx &&
      other.verticalPx == verticalPx;

  @override
  int get hashCode => Object.hash(horizontalPx, verticalPx);
}

final class LabelCanvas {
  const LabelCanvas({
    required this.logicalSizePx,
    required this.displayWidthMm,
    required this.displayHeightMm,
    required this.nativeSizePx,
  });

  final PixelSize logicalSizePx;
  final double displayWidthMm;
  final double displayHeightMm;
  final PixelSize nativeSizePx;

  LabelContentInsets contentInsetsFor(LabelSafeMarginPreset preset) {
    final horizontalPx =
        (preset.millimetres * logicalSizePx.width / displayWidthMm).round();
    final verticalPx =
        (preset.millimetres * logicalSizePx.height / displayHeightMm).round();
    if (logicalSizePx.width - 2 * horizontalPx <= 0 ||
        logicalSizePx.height - 2 * verticalPx <= 0) {
      throw StateError('Safe margin leaves no positive label content area');
    }
    return LabelContentInsets(
      horizontalPx: horizontalPx,
      verticalPx: verticalPx,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LabelCanvas &&
      other.logicalSizePx == logicalSizePx &&
      other.displayWidthMm == displayWidthMm &&
      other.displayHeightMm == displayHeightMm &&
      other.nativeSizePx == nativeSizePx;

  @override
  int get hashCode =>
      Object.hash(logicalSizePx, displayWidthMm, displayHeightMm, nativeSizePx);
}

final class D11LabelGeometry {
  const D11LabelGeometry({
    required this.mediaWidthMm,
    required this.mediaLengthMm,
    required this.nativeSizePx,
  });

  final double mediaWidthMm;
  final double mediaLengthMm;
  final PixelSize nativeSizePx;

  LabelCanvas canvasFor(LabelContentOrientation orientation) {
    return switch (orientation) {
      LabelContentOrientation.portrait => LabelCanvas(
        logicalSizePx: nativeSizePx,
        displayWidthMm: mediaWidthMm,
        displayHeightMm: mediaLengthMm,
        nativeSizePx: nativeSizePx,
      ),
      LabelContentOrientation.landscape => LabelCanvas(
        logicalSizePx: PixelSize(
          width: nativeSizePx.height,
          height: nativeSizePx.width,
        ),
        displayWidthMm: mediaLengthMm,
        displayHeightMm: mediaWidthMm,
        nativeSizePx: nativeSizePx,
      ),
    };
  }

  PixelPoint logicalToNative(
    PixelPoint point,
    LabelContentOrientation orientation,
  ) {
    final logicalSize = canvasFor(orientation).logicalSizePx;
    if (point.x < 0 ||
        point.x >= logicalSize.width ||
        point.y < 0 ||
        point.y >= logicalSize.height) {
      throw RangeError('Logical point is outside the label canvas');
    }

    return switch (orientation) {
      LabelContentOrientation.portrait => point,
      LabelContentOrientation.landscape => PixelPoint(
        x: logicalSize.height - 1 - point.y,
        y: point.x,
      ),
    };
  }
}
