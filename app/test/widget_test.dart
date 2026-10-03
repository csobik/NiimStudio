import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/adapters/d11_capability_loader.dart';
import 'package:niimstudio/src/app.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';
import 'package:niimstudio/src/rendering/label_text_renderer.dart';
import 'package:niimstudio/src/ui/label_composer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const capability = D11PreviewCapability(
    schemaVersion: 1,
    modelId: 'd11',
    modelName: 'NIIMBOT D11',
    dpiX: 203,
    dpiY: 203,
    labelId: 'd-12x40',
    labelName: '12 x 40 mm',
    mediaWidthMm: 12,
    mediaLengthMm: 40,
    nativeWidthPx: 96,
    nativeLengthPx: 320,
  );

  setUpAll(() async {
    final fontLoader = FontLoader('BarlowCondensedBundled')
      ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
    await fontLoader.load();
  });

  testWidgets('phone layout exposes the focused landscape composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NiimStudioApp(capability: capability));
    await tester.pumpAndSettle();

    expect(find.text('NiimStudio'), findsOneWidget);
    expect(find.byKey(const Key('label-text-input')), findsOneWidget);
    expect(find.text('40 x 12 mm'), findsNWidgets(2));
    expect(find.text('D11 / 12 x 40 mm'), findsOneWidget);
    expect(find.byKey(const Key('label-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text input updates the rendered preview', (tester) async {
    await tester.pumpWidget(
      const NiimStudioApp(
        capability: capability,
        composer: _FakeLabelComposer(),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('label-text-input')),
      '3,5x016',
    );
    await tester.pumpAndSettle();

    final preview = tester.widget<LabelRasterPreview>(
      find.byKey(const Key('label-preview')),
    );
    expect(preview.raster.blackPixelCount, greaterThan(0));
    expect(preview.raster.size, const PixelSize(width: 320, height: 96));
    expect(
      find.bySemanticsLabel(RegExp(r'^Label preview: 3,5x016')),
      findsOneWidget,
    );
  });

  testWidgets('portrait control updates physical and pixel orientation', (
    tester,
  ) async {
    await tester.pumpWidget(const NiimStudioApp(capability: capability));
    await tester.tap(find.byKey(const Key('orientation-portrait')));
    await tester.pumpAndSettle();

    expect(find.text('12 x 40 mm'), findsNWidgets(2));
    final preview = tester.widget<LabelRasterPreview>(
      find.byKey(const Key('label-preview')),
    );
    expect(preview.raster.size, const PixelSize(width: 96, height: 320));
  });

  testWidgets('desktop layout remains usable without overflow', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NiimStudioApp(capability: capability));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composer-desktop-layout')), findsOneWidget);
    expect(find.byKey(const Key('label-text-input')), findsOneWidget);
    expect(find.byKey(const Key('label-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop portrait preview fits the available height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const NiimStudioApp(capability: capability));
    await tester.tap(find.byKey(const Key('orientation-portrait')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('label-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not label a stale raster as the current text', (
    tester,
  ) async {
    final composer = _ControlledLabelComposer();
    await tester.pumpWidget(
      NiimStudioApp(capability: capability, composer: composer),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('label-text-input')),
      'new text',
    );
    await tester.pump();

    expect(find.byKey(const Key('label-preview')), findsNothing);
    expect(find.text('Rendering preview...'), findsOneWidget);

    composer.complete('new text', LabelContentOrientation.landscape);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^Label preview: new text')),
      findsOneWidget,
    );
  });
}

final class _FakeLabelComposer implements LabelComposer {
  const _FakeLabelComposer();

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
  }) {
    return Future.value(_fakeLabel(text, orientation));
  }
}

final class _ControlledLabelComposer implements LabelComposer {
  Completer<RenderedLabel>? _pending;

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
  }) {
    if (text.isEmpty) {
      return Future.value(_fakeLabel(text, orientation));
    }
    _pending = Completer<RenderedLabel>();
    return _pending!.future;
  }

  void complete(String text, LabelContentOrientation orientation) {
    _pending!.complete(_fakeLabel(text, orientation));
  }
}

RenderedLabel _fakeLabel(String text, LabelContentOrientation orientation) {
  final logicalSize = switch (orientation) {
    LabelContentOrientation.portrait => const PixelSize(width: 96, height: 320),
    LabelContentOrientation.landscape => const PixelSize(
      width: 320,
      height: 96,
    ),
  };
  final logicalBytes = Uint8List(
    ((logicalSize.width + 7) ~/ 8) * logicalSize.height,
  );
  final nativeBytes = Uint8List(12 * 320);
  if (text.isNotEmpty) {
    logicalBytes[0] = 0x80;
    nativeBytes[0] = 0x80;
  }
  return RenderedLabel(
    logicalRaster: MonochromeRaster(size: logicalSize, bytes: logicalBytes),
    nativeRaster: MonochromeRaster(
      size: const PixelSize(width: 96, height: 320),
      bytes: nativeBytes,
    ),
    fontSizePx: text.isEmpty ? null : 12,
    failure: null,
  );
}
