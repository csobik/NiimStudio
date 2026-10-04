import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';

void main() {
  const geometry = D11LabelGeometry(
    mediaWidthMm: 12,
    mediaLengthMm: 40,
    nativeSizePx: PixelSize(width: 96, height: 320),
  );

  test('portrait uses the native D11 canvas', () {
    expect(
      geometry.canvasFor(LabelContentOrientation.portrait),
      const LabelCanvas(
        logicalSizePx: PixelSize(width: 96, height: 320),
        displayWidthMm: 12,
        displayHeightMm: 40,
        nativeSizePx: PixelSize(width: 96, height: 320),
      ),
    );
  });

  test('landscape presents the long physical edge horizontally', () {
    expect(
      geometry.canvasFor(LabelContentOrientation.landscape),
      const LabelCanvas(
        logicalSizePx: PixelSize(width: 320, height: 96),
        displayWidthMm: 40,
        displayHeightMm: 12,
        nativeSizePx: PixelSize(width: 96, height: 320),
      ),
    );
  });

  test('safe-margin presets have stable labels and physical values', () {
    expect(LabelSafeMarginPreset.values, [
      LabelSafeMarginPreset.tight,
      LabelSafeMarginPreset.normal,
      LabelSafeMarginPreset.wide,
    ]);
    expect(
      LabelSafeMarginPreset.values
          .map((preset) => (preset.displayLabel, preset.millimetres))
          .toList(),
      [('Tight', 1.0), ('Normal', 1.5), ('Wide', 2.5)],
    );
  });

  test('every preset resolves on every D11 edge in both orientations', () {
    const expectedInsets = {
      LabelSafeMarginPreset.tight: 8,
      LabelSafeMarginPreset.normal: 12,
      LabelSafeMarginPreset.wide: 20,
    };

    for (final orientation in LabelContentOrientation.values) {
      for (final MapEntry(key: preset, value: insetPx)
          in expectedInsets.entries) {
        expect(
          geometry.canvasFor(orientation).contentInsetsFor(preset),
          LabelContentInsets(horizontalPx: insetPx, verticalPx: insetPx),
        );
      }
    }
  });

  test('margin conversion rounds each logical axis independently', () {
    const canvas = LabelCanvas(
      logicalSizePx: PixelSize(width: 101, height: 199),
      displayWidthMm: 20,
      displayHeightMm: 30,
      nativeSizePx: PixelSize(width: 101, height: 199),
    );

    expect(
      canvas.contentInsetsFor(LabelSafeMarginPreset.normal),
      const LabelContentInsets(horizontalPx: 8, verticalPx: 10),
    );
  });

  test('rejects a safe margin that leaves no positive content area', () {
    const canvas = LabelCanvas(
      logicalSizePx: PixelSize(width: 4, height: 40),
      displayWidthMm: 4,
      displayHeightMm: 40,
      nativeSizePx: PixelSize(width: 4, height: 40),
    );

    expect(
      () => canvas.contentInsetsFor(LabelSafeMarginPreset.wide),
      throwsStateError,
    );
  });

  test('landscape maps clockwise into native pixels without mirroring', () {
    expect(
      geometry.logicalToNative(
        const PixelPoint(x: 0, y: 0),
        LabelContentOrientation.landscape,
      ),
      const PixelPoint(x: 95, y: 0),
    );
    expect(
      geometry.logicalToNative(
        const PixelPoint(x: 319, y: 0),
        LabelContentOrientation.landscape,
      ),
      const PixelPoint(x: 95, y: 319),
    );
    expect(
      geometry.logicalToNative(
        const PixelPoint(x: 0, y: 95),
        LabelContentOrientation.landscape,
      ),
      const PixelPoint(x: 0, y: 0),
    );
    expect(
      geometry.logicalToNative(
        const PixelPoint(x: 319, y: 95),
        LabelContentOrientation.landscape,
      ),
      const PixelPoint(x: 0, y: 319),
    );
  });

  test('portrait maps logical pixels directly to native pixels', () {
    expect(
      geometry.logicalToNative(
        const PixelPoint(x: 17, y: 203),
        LabelContentOrientation.portrait,
      ),
      const PixelPoint(x: 17, y: 203),
    );
  });

  test('rejects logical pixels outside the selected canvas', () {
    expect(
      () => geometry.logicalToNative(
        const PixelPoint(x: 320, y: 0),
        LabelContentOrientation.landscape,
      ),
      throwsRangeError,
    );
  });
}
