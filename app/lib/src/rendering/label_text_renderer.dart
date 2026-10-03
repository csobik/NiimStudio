import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../domain/label_geometry.dart';

final class RasterBounds {
  const RasterBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

final class MonochromeRaster {
  MonochromeRaster({required this.size, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes) {
    if (this.bytes.length != bytesPerRow * size.height) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Unexpected length');
    }
  }

  factory MonochromeRaster.blank(PixelSize size) {
    return MonochromeRaster(
      size: size,
      bytes: Uint8List(((size.width + 7) ~/ 8) * size.height),
    );
  }

  final PixelSize size;
  final Uint8List bytes;

  int get bytesPerRow => (size.width + 7) ~/ 8;

  bool isBlack(int x, int y) {
    if (x < 0 || x >= size.width || y < 0 || y >= size.height) {
      throw RangeError('Pixel is outside the raster');
    }
    final byte = bytes[y * bytesPerRow + x ~/ 8];
    return byte & (0x80 >> (x & 7)) != 0;
  }

  int get blackPixelCount {
    var count = 0;
    for (var y = 0; y < size.height; y++) {
      for (var x = 0; x < size.width; x++) {
        if (isBlack(x, y)) {
          count++;
        }
      }
    }
    return count;
  }

  RasterBounds? get blackBounds {
    int? left;
    int? top;
    int? right;
    int? bottom;
    for (var y = 0; y < size.height; y++) {
      for (var x = 0; x < size.width; x++) {
        if (!isBlack(x, y)) {
          continue;
        }
        left = left == null || x < left ? x : left;
        top = top == null || y < top ? y : top;
        right = right == null || x > right ? x : right;
        bottom = bottom == null || y > bottom ? y : bottom;
      }
    }
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    return RasterBounds(left: left, top: top, right: right, bottom: bottom);
  }
}

enum LabelRenderFailure { overflow, unsupportedCharacters }

final class RenderedLabel {
  const RenderedLabel({
    required this.logicalRaster,
    required this.nativeRaster,
    required this.fontSizePx,
    required this.failure,
  });

  final MonochromeRaster logicalRaster;
  final MonochromeRaster nativeRaster;
  final int? fontSizePx;
  final LabelRenderFailure? failure;

  bool get hasOverflow => failure == LabelRenderFailure.overflow;
}

abstract interface class LabelComposer {
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
  });
}

final class LabelTextRenderer implements LabelComposer {
  const LabelTextRenderer({
    required this.geometry,
    this.paddingPx = 8,
    this.minimumFontSizePx = 8,
  });

  static const fontFamily = 'BarlowCondensedBundled';
  static const _threshold = 128;

  final D11LabelGeometry geometry;
  final int paddingPx;
  final int minimumFontSizePx;

  @override
  Future<RenderedLabel> render({
    required String text,
    required LabelContentOrientation orientation,
  }) async {
    final canvas = geometry.canvasFor(orientation);
    final blankLogical = MonochromeRaster.blank(canvas.logicalSizePx);
    final blankNative = MonochromeRaster.blank(canvas.nativeSizePx);
    if (!_hasSupportedCharacters(text)) {
      return RenderedLabel(
        logicalRaster: blankLogical,
        nativeRaster: blankNative,
        fontSizePx: null,
        failure: LabelRenderFailure.unsupportedCharacters,
      );
    }
    if (text.trim().isEmpty) {
      return RenderedLabel(
        logicalRaster: blankLogical,
        nativeRaster: blankNative,
        fontSizePx: null,
        failure: null,
      );
    }

    final fontSizePx = await _largestFittingFontSize(
      text,
      canvas.logicalSizePx,
    );
    if (fontSizePx == null) {
      return RenderedLabel(
        logicalRaster: blankLogical,
        nativeRaster: blankNative,
        fontSizePx: null,
        failure: LabelRenderFailure.overflow,
      );
    }

    final logicalRaster = await _renderLogicalRaster(
      text,
      fontSizePx,
      canvas.logicalSizePx,
    );
    return RenderedLabel(
      logicalRaster: logicalRaster,
      nativeRaster: nativeRasterFor(logicalRaster, orientation),
      fontSizePx: fontSizePx,
      failure: null,
    );
  }

  Future<bool> fitsAtFontSize({
    required String text,
    required LabelContentOrientation orientation,
    required int fontSizePx,
  }) async {
    return _fitsInk(
      text,
      fontSizePx,
      geometry.canvasFor(orientation).logicalSizePx,
    );
  }

  Future<int?> _largestFittingFontSize(
    String text,
    PixelSize canvasSize,
  ) async {
    if (!await _fitsInk(text, minimumFontSizePx, canvasSize)) {
      return null;
    }

    var low = minimumFontSizePx;
    var high = minimumFontSizePx * 2;
    while (high < 2048 && await _fitsInk(text, high, canvasSize)) {
      low = high;
      high *= 2;
    }
    if (high > 2048) {
      high = 2048;
    }
    if (await _fitsInk(text, high, canvasSize)) {
      return high;
    }

    while (low + 1 < high) {
      final candidate = (low + high) ~/ 2;
      if (await _fitsInk(text, candidate, canvasSize)) {
        low = candidate;
      } else {
        high = candidate;
      }
    }
    return low;
  }

  Future<bool> _fitsInk(
    String text,
    int fontSizePx,
    PixelSize canvasSize,
  ) async {
    if (fontSizePx <= 0 || !_hasSupportedCharacters(text)) {
      return false;
    }
    final ink = await _renderInkRaster(text, fontSizePx);
    final bounds = ink.blackBounds;
    if (bounds == null) {
      return false;
    }
    return bounds.right - bounds.left + 1 <= canvasSize.width - 2 * paddingPx &&
        bounds.bottom - bounds.top + 1 <= canvasSize.height - 2 * paddingPx;
  }

  Future<MonochromeRaster> _renderLogicalRaster(
    String text,
    int fontSizePx,
    PixelSize canvasSize,
  ) async {
    final ink = await _renderInkRaster(text, fontSizePx);
    return _placeInk(ink, canvasSize);
  }

  Future<MonochromeRaster> _renderInkRaster(String text, int fontSizePx) async {
    final painter = _textPainter(text, fontSizePx)..layout();
    final margin = fontSizePx;
    final imageSize = PixelSize(
      width: painter.width.ceil() + margin * 2,
      height: painter.height.ceil() + margin * 2,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(
        0,
        0,
        imageSize.width.toDouble(),
        imageSize.height.toDouble(),
      ),
      ui.Paint()..color = const ui.Color(0xffffffff),
    );
    painter.paint(canvas, ui.Offset(margin.toDouble(), margin.toDouble()));
    painter.dispose();

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageSize.width, imageSize.height);
    picture.dispose();
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (rgba == null) {
      throw StateError('Flutter did not return label pixels');
    }

    return _thresholdPixels(rgba.buffer.asUint8List(), imageSize);
  }

  TextPainter _textPainter(String text, int fontSizePx) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color(0xff000000),
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: fontSizePx.toDouble(),
          height: 1,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.noScaling,
    );
  }

  MonochromeRaster _thresholdPixels(Uint8List rgba, PixelSize size) {
    final raster = _MutableMonochromeRaster(size);
    for (var y = 0; y < size.height; y++) {
      for (var x = 0; x < size.width; x++) {
        final offset = (y * size.width + x) * 4;
        final luminance =
            (rgba[offset] * 299 +
                rgba[offset + 1] * 587 +
                rgba[offset + 2] * 114) ~/
            1000;
        if (luminance < _threshold) {
          raster.setBlack(x, y);
        }
      }
    }
    return raster.freeze();
  }

  MonochromeRaster _placeInk(MonochromeRaster source, PixelSize targetSize) {
    final bounds = source.blackBounds;
    if (bounds == null) {
      return MonochromeRaster.blank(targetSize);
    }
    final inkWidth = bounds.right - bounds.left + 1;
    final inkHeight = bounds.bottom - bounds.top + 1;
    final targetLeft = (targetSize.width - inkWidth) ~/ 2;
    final targetTop = (targetSize.height - inkHeight) ~/ 2;
    final offsetX = targetLeft - bounds.left;
    final offsetY = targetTop - bounds.top;
    final centered = _MutableMonochromeRaster(targetSize);
    for (var y = bounds.top; y <= bounds.bottom; y++) {
      for (var x = bounds.left; x <= bounds.right; x++) {
        if (source.isBlack(x, y)) {
          centered.setBlack(x + offsetX, y + offsetY);
        }
      }
    }
    return centered.freeze();
  }

  MonochromeRaster nativeRasterFor(
    MonochromeRaster logical,
    LabelContentOrientation orientation,
  ) {
    if (logical.size != geometry.canvasFor(orientation).logicalSizePx) {
      throw ArgumentError.value(
        logical.size,
        'logical',
        'Raster size does not match the selected orientation',
      );
    }
    final native = _MutableMonochromeRaster(
      geometry.canvasFor(orientation).nativeSizePx,
    );
    for (var y = 0; y < logical.size.height; y++) {
      for (var x = 0; x < logical.size.width; x++) {
        if (!logical.isBlack(x, y)) {
          continue;
        }
        final point = geometry.logicalToNative(
          PixelPoint(x: x, y: y),
          orientation,
        );
        native.setBlack(point.x, point.y);
      }
    }
    return native.freeze();
  }

  bool _hasSupportedCharacters(String text) {
    // Prevent platform font fallback from changing raster bytes.
    const supportedCzech = 'ÁáČčĎďÉéĚěÍíŇňÓóŘřŠšŤťÚúŮůÝýŽž';
    return text.runes.every(
      (rune) =>
          (rune >= 0x20 && rune <= 0x7e) || supportedCzech.runes.contains(rune),
    );
  }
}

final class _MutableMonochromeRaster {
  _MutableMonochromeRaster(this.size)
    : _bytes = Uint8List(((size.width + 7) ~/ 8) * size.height);

  final PixelSize size;
  final Uint8List _bytes;

  int get _bytesPerRow => (size.width + 7) ~/ 8;

  void setBlack(int x, int y) {
    _bytes[y * _bytesPerRow + x ~/ 8] |= 0x80 >> (x & 7);
  }

  MonochromeRaster freeze() => MonochromeRaster(size: size, bytes: _bytes);
}
