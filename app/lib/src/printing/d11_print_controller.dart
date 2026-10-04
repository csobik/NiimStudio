import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/label_geometry.dart';
import '../rendering/label_text_renderer.dart';
import 'd11_printer.dart';
import 'd11_printer_gateway.dart';
import 'd11_transport.dart';

enum D11PrintUiState {
  idle,
  scanning,
  ready,
  connecting,
  configuring,
  sendingRaster,
  waitingForPrinter,
  success,
  failure,
}

typedef D11PrinterFactory = D11PrintExecutor Function(
  D11PrinterTransport transport,
);

final class D11PrintController extends ChangeNotifier {
  D11PrintController(this._gateway, {D11PrinterFactory? printerFactory})
    : _printerFactory = printerFactory ?? D11Printer.new;

  static const _nativeSize = PixelSize(width: 96, height: 320);

  final D11PrinterGateway _gateway;
  final D11PrinterFactory _printerFactory;

  List<D11PrinterDevice> _devices = const [];
  D11PrinterDevice? _selectedDevice;
  D11PrintUiState _state = D11PrintUiState.idle;
  String _status = 'Find a nearby D11 printer.';
  double? _progress;
  var _printInProgress = false;
  D11PrintExecutor? _activePrinter;
  var _disposed = false;

  List<D11PrinterDevice> get devices => List.unmodifiable(_devices);
  D11PrinterDevice? get selectedDevice => _selectedDevice;
  D11PrintUiState get state => _state;
  String get status => _status;
  double? get progress => _progress;

  bool get isBusy =>
      _printInProgress ||
      switch (_state) {
        D11PrintUiState.scanning ||
        D11PrintUiState.connecting ||
        D11PrintUiState.configuring ||
        D11PrintUiState.sendingRaster ||
        D11PrintUiState.waitingForPrinter => true,
        _ => false,
      };

  bool canPrint(MonochromeRaster? raster) =>
      !isBusy &&
      _selectedDevice != null &&
      raster != null &&
      raster.size == _nativeSize &&
      raster.blackPixelCount > 0;

  Future<void> scan() async {
    if (isBusy) {
      return;
    }
    _devices = const [];
    _selectedDevice = null;
    _state = D11PrintUiState.scanning;
    _status = 'Scanning for D11 printers...';
    _progress = null;
    _notify();
    try {
      _devices = await _gateway.scan();
      _state = D11PrintUiState.idle;
      _status = _devices.isEmpty
          ? 'No D11 printer found. Check Bluetooth and try again.'
          : 'Select a D11 printer.';
    } catch (error) {
      _state = D11PrintUiState.failure;
      _status = _errorMessage(error);
    }
    _notify();
  }

  void selectDevice(D11PrinterDevice? device) {
    if (isBusy) {
      return;
    }
    if (device != null && !_devices.any((item) => item.id == device.id)) {
      throw ArgumentError.value(device, 'device', 'Device was not discovered');
    }
    _selectedDevice = device;
    _state = device == null ? D11PrintUiState.idle : D11PrintUiState.ready;
    _status = device == null
        ? 'Select a D11 printer.'
        : '${device.name} selected.';
    _notify();
  }

  Future<void> print(MonochromeRaster raster) async {
    final device = _selectedDevice;
    if (device == null || !canPrint(raster)) {
      return;
    }
    final printer = _printerFactory(_gateway.createTransport(device));
    _activePrinter = printer;
    _printInProgress = true;
    try {
      await printer.printRaster(raster, onProgress: _onPrintProgress);
      _state = D11PrintUiState.success;
      _status = 'Label printed.';
      _progress = 1;
    } catch (error) {
      _state = D11PrintUiState.failure;
      _status = _errorMessage(error);
      _progress = null;
    } finally {
      _activePrinter = null;
      _printInProgress = false;
      _notify();
    }
  }

  Future<void> cancelActiveOperation() async {
    final activePrinter = _activePrinter;
    await Future.wait([
      _ignoreCleanupError(_gateway.cancelScan()),
      if (activePrinter != null) _ignoreCleanupError(activePrinter.cancel()),
    ]);
  }

  void _onPrintProgress(D11PrintProgress progress) {
    switch (progress.phase) {
      case D11PrintPhase.connecting:
        _state = D11PrintUiState.connecting;
        _status = 'Connecting to ${_selectedDevice?.name ?? 'D11'}...';
        _progress = null;
      case D11PrintPhase.configuring:
        _state = D11PrintUiState.configuring;
        _status = 'Preparing printer...';
        _progress = null;
      case D11PrintPhase.sendingRaster:
        _state = D11PrintUiState.sendingRaster;
        final row = progress.row ?? 0;
        final total = progress.totalRows ?? 1;
        _progress = row / total;
        _status = 'Sending label ${(_progress! * 100).round()}%';
        if (row != 1 && row != total && row % 16 != 0) {
          return;
        }
      case D11PrintPhase.waitingForPrinter:
        _state = D11PrintUiState.waitingForPrinter;
        _status = 'Waiting for printer confirmation...';
        _progress = null;
      case D11PrintPhase.complete:
        _state = D11PrintUiState.waitingForPrinter;
        _status = 'Closing printer connection...';
        _progress = null;
    }
    _notify();
  }

  String _errorMessage(Object error) {
    if (error case D11PrintException(:final message)) {
      return message;
    }
    final message = error.toString();
    final separator = message.indexOf(': ');
    return separator < 0 ? message : message.substring(separator + 2);
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancelActiveOperation());
    super.dispose();
  }
}

Future<void> _ignoreCleanupError(Future<void> cleanup) async {
  try {
    await cleanup;
  } catch (_) {
    // Cleanup is best-effort when cancellation or disposal is already underway.
  }
}
