import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/adapters/d11_capability_loader.dart';
import 'package:niimstudio/src/app.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';
import 'package:niimstudio/src/printing/d11_print_controller.dart';
import 'package:niimstudio/src/printing/d11_printer.dart';
import 'package:niimstudio/src/printing/d11_printer_gateway.dart';
import 'package:niimstudio/src/printing/d11_transport.dart';
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

  testWidgets('margin controls expose all presets and default to normal', (
    tester,
  ) async {
    final composer = _RecordingLabelComposer();
    await tester.pumpWidget(
      NiimStudioApp(capability: capability, composer: composer),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Tight, 1 millimetre'), findsOneWidget);
    expect(find.bySemanticsLabel('Normal, 1.5 millimetres'), findsOneWidget);
    expect(find.bySemanticsLabel('Wide, 2.5 millimetres'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('margin-normal')))
          .selected,
      isTrue,
    );
    expect(
      tester.getSemantics(find.byKey(const Key('margin-normal'))),
      matchesSemantics(
        label: 'Normal, 1.5 millimetres',
        isSelected: true,
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(composer.marginPresets, [LabelSafeMarginPreset.normal]);

    await tester.tap(find.byKey(const Key('margin-wide')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<ChoiceChip>(find.byKey(const Key('margin-wide'))).selected,
      isTrue,
    );
    expect(composer.marginPresets.last, LabelSafeMarginPreset.wide);
  });

  testWidgets('margin controls reflow on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const NiimStudioApp(capability: capability));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('margin-tight')), findsOneWidget);
    expect(find.byKey(const Key('margin-normal')), findsOneWidget);
    expect(find.byKey(const Key('margin-wide')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('moving to the background cancels active Bluetooth work', (
    tester,
  ) async {
    final gateway = _LifecycleGateway();
    final controller = D11PrintController(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      NiimStudioApp(
        capability: capability,
        composer: const _FakeLabelComposer(),
        printController: controller,
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(gateway.cancelCount, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(gateway.cancelCount, 1);
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

    composer.complete(0);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^Label preview: new text')),
      findsOneWidget,
    );
  });

  testWidgets(
    'margin changes disable printing and only print the latest raster',
    (tester) async {
      const device = D11PrinterDevice(id: 'd11', name: 'D11-test');
      final composer = _ControlledLabelComposer();
      final executor = _WidgetPrintExecutor();
      final controller = D11PrintController(
        _WidgetPrinterGateway(device),
        printerFactory: (_) => executor,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        NiimStudioApp(
          capability: capability,
          composer: composer,
          printController: controller,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('label-text-input')),
        '3,5x016',
      );
      await tester.pump();
      composer.complete(0);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('printer-scan-button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('D11-test').last);
      await tester.pumpAndSettle();

      FilledButton printButton() => tester.widget<FilledButton>(
        find.byKey(const Key('print-label-button')),
      );

      expect(printButton().onPressed, isNotNull);
      final stalePrintAction = printButton().onPressed!;
      await tester.tap(find.byKey(const Key('margin-tight')));
      stalePrintAction();
      await tester.pump();
      expect(executor.printCount, 0);
      expect(printButton().onPressed, isNull);
      expect(composer.requests[1].marginPreset, LabelSafeMarginPreset.tight);

      await tester.tap(find.byKey(const Key('margin-wide')));
      await tester.pump();
      expect(printButton().onPressed, isNull);
      expect(composer.requests[2].marginPreset, LabelSafeMarginPreset.wide);

      composer.complete(1);
      await tester.pump();
      expect(printButton().onPressed, isNull);

      composer.complete(2);
      await tester.pumpAndSettle();
      expect(printButton().onPressed, isNotNull);

      await tester.ensureVisible(find.byKey(const Key('print-label-button')));
      await tester.tap(find.byKey(const Key('print-label-button')));
      await tester.pumpAndSettle();
      expect(executor.lastRaster?.bytes.first, 0x20);
    },
  );

  testWidgets('requires discovery and selection before printing', (
    tester,
  ) async {
    const device = D11PrinterDevice(id: 'd11', name: 'D11-test');
    final executor = _WidgetPrintExecutor();
    final controller = D11PrintController(
      _WidgetPrinterGateway(device),
      printerFactory: (_) => executor,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      NiimStudioApp(
        capability: capability,
        composer: const _FakeLabelComposer(),
        printController: controller,
      ),
    );
    await tester.pumpAndSettle();

    FilledButton printButton() => tester.widget<FilledButton>(
      find.byKey(const Key('print-label-button')),
    );

    expect(printButton().onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('label-text-input')),
      '3,5x016',
    );
    await tester.pumpAndSettle();
    expect(printButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('printer-scan-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('printer-device-select')), findsOneWidget);
    expect(printButton().onPressed, isNull);

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D11-test').last);
    await tester.pumpAndSettle();
    expect(printButton().onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('print-label-button')));
    await tester.tap(find.byKey(const Key('print-label-button')));
    await tester.pumpAndSettle();
    expect(executor.printCount, 1);
    expect(find.text('Label printed.'), findsOneWidget);
  });
}

final class _FakeLabelComposer implements LabelComposer {
  const _FakeLabelComposer();

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
    required LabelSafeMarginPreset marginPreset,
  }) {
    return Future.value(_fakeLabel(text, orientation, marginPreset));
  }
}

final class _RecordingLabelComposer implements LabelComposer {
  final marginPresets = <LabelSafeMarginPreset>[];

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
    required LabelSafeMarginPreset marginPreset,
  }) {
    marginPresets.add(marginPreset);
    return Future.value(_fakeLabel(text, orientation, marginPreset));
  }
}

final class _ControlledLabelComposer implements LabelComposer {
  final requests = <_ControlledRender>[];

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
    required LabelSafeMarginPreset marginPreset,
  }) {
    if (text.isEmpty) {
      return Future.value(_fakeLabel(text, orientation, marginPreset));
    }
    final request = _ControlledRender(text, orientation, marginPreset);
    requests.add(request);
    return request.completer.future;
  }

  void complete(int index) {
    final request = requests[index];
    request.completer.complete(
      _fakeLabel(request.text, request.orientation, request.marginPreset),
    );
  }
}

final class _ControlledRender {
  _ControlledRender(this.text, this.orientation, this.marginPreset);

  final String text;
  final LabelContentOrientation orientation;
  final LabelSafeMarginPreset marginPreset;
  final completer = Completer<RenderedLabel>();
}

RenderedLabel _fakeLabel(
  String text,
  LabelContentOrientation orientation,
  LabelSafeMarginPreset marginPreset,
) {
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
    final marker = switch (marginPreset) {
      LabelSafeMarginPreset.tight => 0x80,
      LabelSafeMarginPreset.normal => 0x40,
      LabelSafeMarginPreset.wide => 0x20,
    };
    logicalBytes[0] = marker;
    nativeBytes[0] = marker;
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

final class _WidgetPrinterGateway implements D11PrinterGateway {
  const _WidgetPrinterGateway(this.device);

  final D11PrinterDevice device;

  @override
  Future<void> cancelScan() async {}

  @override
  Future<List<D11PrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async => [device];

  @override
  D11PrinterTransport createTransport(D11PrinterDevice device) =>
      const _WidgetTransport();
}

final class _LifecycleGateway implements D11PrinterGateway {
  var cancelCount = 0;

  @override
  Future<void> cancelScan() async {
    cancelCount++;
  }

  @override
  Future<List<D11PrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async => const [];

  @override
  D11PrinterTransport createTransport(D11PrinterDevice device) =>
      const _WidgetTransport();
}

final class _WidgetPrintExecutor implements D11PrintExecutor {
  var printCount = 0;
  MonochromeRaster? lastRaster;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  }) async {
    printCount++;
    lastRaster = raster;
    onProgress?.call(const D11PrintProgress(D11PrintPhase.connecting));
    onProgress?.call(const D11PrintProgress(D11PrintPhase.complete));
  }
}

final class _WidgetTransport implements D11PrinterTransport {
  const _WidgetTransport();

  @override
  Stream<Uint8List> get notifications => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> open() async {}

  @override
  Future<void> write(Uint8List bytes) async {}
}
