import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';
import 'package:niimstudio/src/rendering/label_text_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const geometry = D11LabelGeometry(
    mediaWidthMm: 12,
    mediaLengthMm: 40,
    nativeSizePx: PixelSize(width: 96, height: 320),
  );
  const renderer = LabelTextRenderer(geometry: geometry, paddingPx: 8);

  setUpAll(() async {
    final fontLoader = FontLoader('BarlowCondensedBundled')
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
    await fontLoader.load();
  });

  testWidgets('empty text produces blank logical and native rasters', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: '',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    expect(label.fontSizePx, isNull);
    expect(label.hasOverflow, isFalse);
    expect(label.logicalRaster.size, const PixelSize(width: 320, height: 96));
    expect(label.nativeRaster.size, const PixelSize(width: 96, height: 320));
    expect(label.logicalRaster.blackPixelCount, 0);
    expect(label.nativeRaster.blackPixelCount, 0);
    expect(label.nativeRaster.bytesPerRow, 12);
    expect(label.nativeRaster.bytes, hasLength(3840));
  });

  testWidgets('auto fit chooses the largest fitting integer font size', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: '3,5x016',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    expect(label.hasOverflow, isFalse);
    expect(label.fontSizePx, isNotNull);
    final selectedSizeFits = (await tester.runAsync(
      () => renderer.fitsAtFontSize(
        text: '3,5x016',
        orientation: LabelContentOrientation.landscape,
        fontSizePx: label.fontSizePx!,
      ),
    ))!;
    final nextSizeFits = (await tester.runAsync(
      () => renderer.fitsAtFontSize(
        text: '3,5x016',
        orientation: LabelContentOrientation.landscape,
        fontSizePx: label.fontSizePx! + 1,
      ),
    ))!;
    expect(selectedSizeFits, isTrue);
    expect(nextSizeFits, isFalse);
  });

  testWidgets('rendered ink is centered on the landscape canvas', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: '3,5x016',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;
    final bounds = label.logicalRaster.blackBounds;

    expect(bounds, isNotNull);
    expect(bounds!.centerX, closeTo(159.5, 0.5));
    expect(bounds.centerY, closeTo(47.5, 0.5));
    expect(bounds.left, greaterThanOrEqualTo(8));
    expect(bounds.top, greaterThanOrEqualTo(8));
    expect(bounds.right, lessThan(312));
    expect(bounds.bottom, lessThan(88));
  });

  testWidgets('landscape logical pixels map exactly to the native raster', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: '3,5x016',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    for (var y = 0; y < label.logicalRaster.size.height; y++) {
      for (var x = 0; x < label.logicalRaster.size.width; x++) {
        final nativePoint = geometry.logicalToNative(
          PixelPoint(x: x, y: y),
          LabelContentOrientation.landscape,
        );
        expect(
          label.nativeRaster.isBlack(nativePoint.x, nativePoint.y),
          label.logicalRaster.isBlack(x, y),
        );
      }
    }
  });

  testWidgets('content that cannot fit reports overflow without ink', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: List.filled(200, 'W').join(),
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    expect(label.hasOverflow, isTrue);
    expect(label.fontSizePx, isNull);
    expect(label.logicalRaster.blackPixelCount, 0);
    expect(label.nativeRaster.blackPixelCount, 0);
  });

  testWidgets('unsupported glyphs fail instead of using a system fallback', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: 'LED 💡',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    expect(label.failure, LabelRenderFailure.unsupportedCharacters);
    expect(label.hasOverflow, isFalse);
    expect(label.logicalRaster.blackPixelCount, 0);
  });

  testWidgets('font gaps and separator-only input are rejected', (
    tester,
  ) async {
    for (final text in ['Ĕ', '\n']) {
      final label = (await tester.runAsync(
        () => renderer.render(
          text: text,
          orientation: LabelContentOrientation.landscape,
        ),
      ))!;

      expect(label.failure, LabelRenderFailure.unsupportedCharacters);
      expect(label.logicalRaster.blackPixelCount, 0);
    }
  });

  testWidgets('verified Czech characters render with the bundled font', (
    tester,
  ) async {
    final label = (await tester.runAsync(
      () => renderer.render(
        text: 'Číslo žárovky',
        orientation: LabelContentOrientation.landscape,
      ),
    ))!;

    expect(label.failure, isNull);
    expect(label.logicalRaster.blackPixelCount, greaterThan(0));
  });

  test('native raster uses MSB-first bytes after clockwise rotation', () {
    final logicalBytes = Uint8List(40 * 96);
    logicalBytes[0] = 0x80;
    logicalBytes[logicalBytes.length - 1] = 0x01;
    final logical = MonochromeRaster(
      size: const PixelSize(width: 320, height: 96),
      bytes: logicalBytes,
    );

    final native = renderer.nativeRasterFor(
      logical,
      LabelContentOrientation.landscape,
    );

    expect(native.bytes, hasLength(12 * 320));
    expect(native.blackPixelCount, 2);
    expect(native.bytes[11], 0x01);
    expect(native.bytes[319 * 12], 0x80);
  });
}
