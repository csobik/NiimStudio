import 'package:flutter/material.dart';

import '../adapters/d11_capability_loader.dart';
import '../domain/label_geometry.dart';
import '../rendering/label_text_renderer.dart';

final class LabelComposerScreen extends StatefulWidget {
  const LabelComposerScreen({
    super.key,
    required this.capability,
    this.composer,
  });

  final D11PreviewCapability capability;
  final LabelComposer? composer;

  @override
  State<LabelComposerScreen> createState() => _LabelComposerScreenState();
}

final class _LabelComposerScreenState extends State<LabelComposerScreen> {
  late final LabelComposer _composer;
  late Future<RenderedLabel> _preview;
  var _text = '';
  var _orientation = LabelContentOrientation.landscape;

  @override
  void initState() {
    super.initState();
    _composer =
        widget.composer ??
        LabelTextRenderer(geometry: widget.capability.geometry);
    _preview = _render();
  }

  Future<RenderedLabel> _render() {
    return _composer.render(text: _text, orientation: _orientation);
  }

  void _updateText(String text) {
    setState(() {
      _text = text;
      _preview = _render();
    });
  }

  void _updateOrientation(LabelContentOrientation orientation) {
    if (_orientation == orientation) {
      return;
    }
    setState(() {
      _orientation = orientation;
      _preview = _render();
    });
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
              canvas: canvas,
              onTextChanged: _updateText,
              onOrientationChanged: _updateOrientation,
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
                    SizedBox(width: 360, child: editor),
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
    required this.canvas,
    required this.onTextChanged,
    required this.onOrientationChanged,
  });

  final D11PreviewCapability capability;
  final LabelContentOrientation orientation;
  final LabelCanvas canvas;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<LabelContentOrientation> onOrientationChanged;

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
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                key: const Key('orientation-landscape'),
                label: const Text('Landscape'),
                selected: orientation == LabelContentOrientation.landscape,
                onSelected: (_) =>
                    onOrientationChanged(LabelContentOrientation.landscape),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                key: const Key('orientation-portrait'),
                label: const Text('Portrait'),
                selected: orientation == LabelContentOrientation.portrait,
                onSelected: (_) =>
                    onOrientationChanged(LabelContentOrientation.portrait),
              ),
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
      ],
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
