enum LabelContentOrientation { portrait, landscape }

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
