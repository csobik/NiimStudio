import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/label_geometry.dart';

final class D11PreviewCapability {
  const D11PreviewCapability({
    required this.schemaVersion,
    required this.modelId,
    required this.modelName,
    required this.dpiX,
    required this.dpiY,
    required this.labelId,
    required this.labelName,
    required this.mediaWidthMm,
    required this.mediaLengthMm,
    required this.nativeWidthPx,
    required this.nativeLengthPx,
  });

  final int schemaVersion;
  final String modelId;
  final String modelName;
  final int dpiX;
  final int dpiY;
  final String labelId;
  final String labelName;
  final double mediaWidthMm;
  final double mediaLengthMm;
  final int nativeWidthPx;
  final int nativeLengthPx;

  D11LabelGeometry get geometry => D11LabelGeometry(
    mediaWidthMm: mediaWidthMm,
    mediaLengthMm: mediaLengthMm,
    nativeSizePx: PixelSize(width: nativeWidthPx, height: nativeLengthPx),
  );
}

final class D11CapabilityLoader {
  D11CapabilityLoader(this._assets);

  static const assetPath = 'assets/contracts/d11_preview_capabilities.v1.json';

  final AssetBundle _assets;

  Future<D11PreviewCapability> load() async {
    final decoded = jsonDecode(await _assets.loadString(assetPath));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('D11 capability contract must be an object');
    }

    final schemaVersion = _integer(decoded, 'schema_version');
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported D11 capability schema version $schemaVersion',
      );
    }

    return D11PreviewCapability(
      schemaVersion: schemaVersion,
      modelId: _string(decoded, 'model_id'),
      modelName: _string(decoded, 'model_name'),
      dpiX: _positiveInteger(decoded, 'dpi_x'),
      dpiY: _positiveInteger(decoded, 'dpi_y'),
      labelId: _string(decoded, 'label_id'),
      labelName: _string(decoded, 'label_name'),
      mediaWidthMm: _positiveDouble(decoded, 'media_width_mm'),
      mediaLengthMm: _positiveDouble(decoded, 'media_length_mm'),
      nativeWidthPx: _positiveInteger(decoded, 'native_width_px'),
      nativeLengthPx: _positiveInteger(decoded, 'native_length_px'),
    );
  }
}

int _integer(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is! int) {
    throw FormatException('$key must be an integer');
  }
  return value;
}

int _positiveInteger(Map<String, dynamic> values, String key) {
  final value = _integer(values, key);
  if (value <= 0) {
    throw FormatException('$key must be positive');
  }
  return value;
}

String _string(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

double _positiveDouble(Map<String, dynamic> values, String key) {
  final value = double.tryParse(_string(values, key));
  if (value == null || !value.isFinite || value <= 0) {
    throw FormatException('$key must be a positive decimal string');
  }
  return value;
}
