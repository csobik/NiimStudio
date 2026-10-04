import 'dart:async';

import 'package:flutter/material.dart';

import '../adapters/d11_capability_loader.dart';
import '../adapters/universal_ble_d11_gateway.dart';
import '../domain/label_geometry.dart';
import '../printing/d11_print_controller.dart';
import '../printing/d11_printer_gateway.dart';
import '../rendering/label_text_renderer.dart';

final class LabelComposerScreen extends StatefulWidget {
  const LabelComposerScreen({
    super.key,
    required this.capability,
    this.composer,
    this.printController,
  });

  final D11PreviewCapability capability;
  final LabelComposer? composer;
  final D11PrintController? printController;

  @override
  State<LabelComposerScreen> createState() => _LabelComposerScreenState();
}

final class _LabelComposerScreenState extends State<LabelComposerScreen>
    with WidgetsBindingObserver {
  late final LabelComposer _composer;
  late final D11PrintController _printController;
  late final bool _ownsPrintController;
  late Future<RenderedLabel> _preview;
  MonochromeRaster? _printableRaster;
  var _renderRevision = 0;
  var _text = '';
  var _orientation = LabelContentOrientation.landscape;
  var _marginPreset = LabelSafeMarginPreset.normal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer =
        widget.composer ??
        LabelTextRenderer(geometry: widget.capability.geometry);
    _ownsPrintController = widget.printController == null;
    _printController =
        widget.printController ?? D11PrintController(UniversalBleD11Gateway());
    _preview = _render();
  }

  Future<RenderedLabel> _render() {
    final revision = ++_renderRevision;
    final preview = _composer.render(
      text: _text,
      orientation: _orientation,
      marginPreset: _marginPreset,
    );
    unawaited(
      preview.then<void>((rendered) {
        if (!mounted || revision != _renderRevision) {
          return;
        }
        setState(() {
          _printableRaster =
              rendered.failure == null &&
                  rendered.nativeRaster.blackPixelCount > 0
              ? rendered.nativeRaster
              : null;
        });
      }, onError: (_) {}),
    );
    return preview;
  }

  void _updateText(String text) {
    setState(() {
      _text = text;
      _printableRaster = null;
      _preview = _render();
    });
  }

  void _updateOrientation(LabelContentOrientation orientation) {
    if (_orientation == orientation) {
      return;
    }
    setState(() {
      _orientation = orientation;
      _printableRaster = null;
      _preview = _render();
    });
  }

  void _updateMarginPreset(LabelSafeMarginPreset marginPreset) {
    if (_marginPreset == marginPreset) {
      return;
    }
    setState(() {
      _marginPreset = marginPreset;
      _printableRaster = null;
      _preview = _render();
    });
  }

  void _printCurrentRaster() {
    final raster = _printableRaster;
    if (raster == null || !_printController.canPrint(raster)) {
      return;
    }
    unawaited(_printController.print(raster));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        return;
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        unawaited(_printController.cancelActiveOperation());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsPrintController) {
      _printController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = widget.capability.geometry.canvasFor(_orientation);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 840;
            final editor = _EditorPanel(
              capability: widget.capability,
              orientation: _orientation,
              marginPreset: _marginPreset,
              canvas: canvas,
              onTextChanged: _updateText,
              onOrientationChanged: _updateOrientation,
              onMarginPresetChanged: _updateMarginPreset,
              printController: _printController,
              printableRaster: _printableRaster,
              onPrint: _printCurrentRaster,
            );
            final preview = _PreviewPanel(
              preview: _preview,
              text: _text,
              canvas: canvas,
              fillAvailableHeight: isDesktop,
            );
            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Row(
                  key: const Key('composer-desktop-layout'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 360,
                      child: SingleChildScrollView(child: editor),
                    ),
                    const SizedBox(width: 40),
                    Expanded(child: preview),
                  ],
                ),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [editor, const SizedBox(height: 28), preview],
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.capability,
    required this.orientation,
    required this.marginPreset,
    required this.canvas,
    required this.onTextChanged,
    required this.onOrientationChanged,
    required this.onMarginPresetChanged,
    required this.printController,
    required this.printableRaster,
    required this.onPrint,
  });

  final D11PreviewCapability capability;
  final LabelContentOrientation orientation;
  final LabelSafeMarginPreset marginPreset;
  final LabelCanvas canvas;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<LabelContentOrientation> onOrientationChanged;
  final ValueChanged<LabelSafeMarginPreset> onMarginPresetChanged;
  final D11PrintController printController;
  final MonochromeRaster? printableRaster;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'NIIMSTUDIO / QUICK LABEL',
          style: textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'NiimStudio',
          style: textTheme.displaySmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 12),
        Text('D11 / ${capability.labelName}', style: textTheme.titleMedium),
        const SizedBox(height: 32),
        TextField(
          key: const Key('label-text-input'),
          maxLines: 1,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Text on label',
            hintText: '3,5x016',
          ),
          onChanged: onTextChanged,
        ),
        const SizedBox(height: 24),
        Text('Reading orientation', style: textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('orientation-landscape'),
              label: const Text('Landscape'),
              selected: orientation == LabelContentOrientation.landscape,
              onSelected: (_) =>
                  onOrientationChanged(LabelContentOrientation.landscape),
            ),
            ChoiceChip(
              key: const Key('orientation-portrait'),
              label: const Text('Portrait'),
              selected: orientation == LabelContentOrientation.portrait,
              onSelected: (_) =>
                  onOrientationChanged(LabelContentOrientation.portrait),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Content margin', style: textTheme.labelLarge),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in LabelSafeMarginPreset.values)
              ChoiceChip(
                key: Key('margin-${preset.name}'),
                label: Semantics(
                  label: _marginSemanticsLabel(preset),
                  excludeSemantics: true,
                  child: Text(
                    '${preset.displayLabel}\n${_millimetreValue(preset)} mm',
                    textAlign: TextAlign.center,
                  ),
                ),
                selected: marginPreset == preset,
                onSelected: (_) => onMarginPresetChanged(preset),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _millimetreSize(canvas),
                style: textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${canvas.logicalSizePx.width} x '
                '${canvas.logicalSizePx.height} px preview',
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xffc9d7d3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PrinterPanel(
          controller: printController,
          raster: printableRaster,
          onPrint: onPrint,
        ),
      ],
    );
  }
}

final class _PrinterPanel extends StatelessWidget {
  const _PrinterPanel({
    required this.controller,
    required this.raster,
    required this.onPrint,
  });

  final D11PrintController controller;
  final MonochromeRaster? raster;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final devices = controller.devices;
        final selected = controller.selectedDevice;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'BLUETOOTH PRINT',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  OutlinedButton.icon(
                    key: const Key('printer-scan-button'),
                    onPressed: controller.isBusy ? null : controller.scan,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(
                      controller.state == D11PrintUiState.scanning
                          ? 'Scanning'
                          : 'Find D11',
                    ),
                  ),
                ],
              ),
              if (devices.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  key: const Key('printer-device-select'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'printer-${devices.map((device) => device.id).join('-')}-'
                      '${selected?.id}',
                    ),
                    initialValue: selected?.id,
                    decoration: const InputDecoration(labelText: 'D11 printer'),
                    items: [
                      for (final device in devices)
                        DropdownMenuItem(
                          value: device.id,
                          child: Text(_deviceLabel(device)),
                        ),
                    ],
                    onChanged: controller.isBusy
                        ? null
                        : (id) {
                            final device = devices
                                .where((item) => item.id == id)
                                .firstOrNull;
                            controller.selectDevice(device);
                          },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.status,
                  key: const Key('printer-status'),
                ),
              ),
              if (controller.isBusy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: controller.progress),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('print-label-button'),
                onPressed: controller.canPrint(raster) ? onPrint : null,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print label'),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.preview,
    required this.text,
    required this.canvas,
    required this.fillAvailableHeight,
  });

  final Future<RenderedLabel> preview;
  final String text;
  final LabelCanvas canvas;
  final bool fillAvailableHeight;

  @override
  Widget build(BuildContext context) {
    final previewWidget = FutureBuilder<RenderedLabel>(
      future: preview,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _PreviewMessage(message: 'Preview failed: ${snapshot.error}');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PreviewMessage(message: 'Rendering preview...');
        }
        final rendered = snapshot.data;
        if (rendered == null) {
          return const _PreviewMessage(message: 'Rendering preview...');
        }
        if (rendered.hasOverflow) {
          return const _PreviewMessage(
            message: 'Text is too long for this label.',
          );
        }
        if (rendered.failure == LabelRenderFailure.unsupportedCharacters) {
          return const _PreviewMessage(
            message: 'Use ASCII or Czech letters, numbers, and punctuation.',
          );
        }
        return Semantics(
          label:
              'Label preview: $text, ${_millimetreSize(canvas)}, '
              '${_orientationName(canvas)}',
          image: true,
          child: LabelRasterPreview(
            key: const Key('label-preview'),
            raster: rendered.logicalRaster,
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fillAvailableHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              'PRINT PREVIEW',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(_millimetreSize(canvas)),
          ],
        ),
        const SizedBox(height: 12),
        if (fillAvailableHeight)
          Expanded(child: Center(child: previewWidget))
        else
          previewWidget,
      ],
    );
  }
}

final class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 120),
        alignment: Alignment.center,
        color: Colors.white,
        child: Text(message),
      ),
    );
  }
}

final class LabelRasterPreview extends StatelessWidget {
  const LabelRasterPreview({super.key, required this.raster});

  final MonochromeRaster raster;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xff17211f), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: raster.size.width / raster.size.height,
        child: CustomPaint(painter: _RasterPainter(raster)),
      ),
    );
  }
}

final class _RasterPainter extends CustomPainter {
  const _RasterPainter(this.raster);

  final MonochromeRaster raster;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pixelWidth = size.width / raster.size.width;
    final pixelHeight = size.height / raster.size.height;
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var y = 0; y < raster.size.height; y++) {
      for (var x = 0; x < raster.size.width; x++) {
        if (raster.isBlack(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * pixelWidth,
              y * pixelHeight,
              pixelWidth,
              pixelHeight,
            ),
            ink,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RasterPainter oldDelegate) =>
      oldDelegate.raster.bytes != raster.bytes;
}

String _millimetreSize(LabelCanvas canvas) {
  return '${canvas.displayWidthMm.toStringAsFixed(0)} x '
      '${canvas.displayHeightMm.toStringAsFixed(0)} mm';
}

String _orientationName(LabelCanvas canvas) {
  return canvas.displayWidthMm > canvas.displayHeightMm
      ? 'landscape'
      : 'portrait';
}

String _millimetreValue(LabelSafeMarginPreset preset) {
  final millimetres = preset.millimetres;
  return millimetres == millimetres.truncateToDouble()
      ? millimetres.toStringAsFixed(0)
      : millimetres.toStringAsFixed(1);
}

String _marginSemanticsLabel(LabelSafeMarginPreset preset) {
  final unit = preset.millimetres == 1 ? 'millimetre' : 'millimetres';
  return '${preset.displayLabel}, ${_millimetreValue(preset)} $unit';
}

String _deviceLabel(D11PrinterDevice device) {
  final rssi = device.rssi;
  return rssi == null ? device.name : '${device.name}  $rssi dBm';
}
