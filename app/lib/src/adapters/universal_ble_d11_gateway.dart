import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../printing/d11_printer_gateway.dart';
import '../printing/d11_transport.dart';

final class D11BleException implements Exception {
  const D11BleException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'D11BleException: $message';
}

final class D11CharacteristicSelection {
  const D11CharacteristicSelection({
    required this.service,
    required this.characteristic,
  });

  final BleService service;
  final BleCharacteristic characteristic;
}

bool isD11AdvertisedName(String? name) {
  if (name == null) {
    return false;
  }
  final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return normalized.startsWith('d11') &&
      !normalized.startsWith('d110') &&
      !normalized.startsWith('d11h');
}

D11CharacteristicSelection selectD11Characteristic(List<BleService> services) {
  final candidates = <D11CharacteristicSelection>[];
  for (final service in services) {
    for (final characteristic in service.characteristics) {
      final properties = characteristic.properties.toSet();
      if (properties.containsAll(const {
        CharacteristicProperty.read,
        CharacteristicProperty.writeWithoutResponse,
        CharacteristicProperty.notify,
      })) {
        candidates.add(
          D11CharacteristicSelection(
            service: service,
            characteristic: characteristic,
          ),
        );
      }
    }
  }
  if (candidates.length != 1) {
    throw const D11BleException(
      'Cannot find a unique D11 Bluetooth characteristic',
    );
  }
  return candidates.single;
}

List<Uint8List> bleWriteChunks(Uint8List bytes, int maximumLength) {
  if (maximumLength < 1) {
    throw ArgumentError.value(
      maximumLength,
      'maximumLength',
      'Must be positive',
    );
  }
  return [
    for (var offset = 0; offset < bytes.length; offset += maximumLength)
      Uint8List.fromList(
        bytes.sublist(
          offset,
          offset + maximumLength < bytes.length
              ? offset + maximumLength
              : bytes.length,
        ),
      ),
  ];
}

final class UniversalBleD11Gateway implements D11PrinterGateway {
  static const _cleanupTimeout = Duration(seconds: 2);

  Completer<void>? _scanCancellation;
  Completer<void>? _scanCleanupDone;
  _ScanPhase? _scanPhase;
  var _queueRevision = 0;

  @override
  Future<List<D11PrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_scanCancellation != null) {
      throw StateError('A D11 Bluetooth scan is already active');
    }
    final found = <String, D11PrinterDevice>{};
    StreamSubscription<BleDevice>? subscription;
    final cancellation = Completer<void>();
    final cleanupDone = Completer<void>();
    _scanCancellation = cancellation;
    _scanCleanupDone = cleanupDone;
    _scanPhase = _ScanPhase.preparing;
    final deadline = DateTime.now().add(timeout);
    final scanQueueId = _nextQueueId('scan');
    Future<void>? startFuture;
    try {
      final permissionsCompleted = await Future.any<bool>([
        UniversalBle.requestPermissions().then((_) => true),
        cancellation.future.then((_) => false),
        Future<bool>.delayed(
          _remaining(deadline),
          () =>
              throw TimeoutException('Bluetooth permission request timed out'),
        ),
      ]);
      if (!permissionsCompleted) {
        return const [];
      }
      final availability = await Future.any<AvailabilityState?>([
        UniversalBle.getBluetoothAvailabilityState(queueId: scanQueueId)
            .then<AvailabilityState?>((value) => value),
        cancellation.future.then<AvailabilityState?>((_) => null),
        Future<AvailabilityState?>.delayed(
          _remaining(deadline),
          () =>
              throw TimeoutException('Bluetooth availability check timed out'),
        ),
      ]);
      if (availability == null) {
        return const [];
      }
      if (availability != AvailabilityState.poweredOn) {
        throw D11BleException(switch (availability) {
          AvailabilityState.unauthorized =>
            'Bluetooth permission is not available',
          AvailabilityState.unsupported =>
            'Bluetooth Low Energy is not supported',
          AvailabilityState.poweredOff => 'Bluetooth is turned off',
          _ => 'Bluetooth is not ready',
        });
      }

      subscription = UniversalBle.scanStream.listen((device) {
        if (!isD11AdvertisedName(device.name)) {
          return;
        }
        found[device.deviceId] = D11PrinterDevice(
          id: device.deviceId,
          name: device.name!,
          rssi: device.rssi,
        );
      });
      startFuture = UniversalBle.startScan(queueId: scanQueueId);
      final startResult = await Future.any([
        startFuture.then((_) => _ScanStartResult.started),
        cancellation.future.then((_) => _ScanStartResult.cancelled),
        Future<_ScanStartResult>.delayed(
          _remaining(deadline),
          () => _ScanStartResult.timedOut,
        ),
      ]);
      if (startResult != _ScanStartResult.started) {
        _stopWhenStartCompletes(startFuture, cancellation);
        if (startResult == _ScanStartResult.timedOut) {
          throw TimeoutException('Bluetooth scan did not start in time');
        }
      } else {
        _scanPhase = _ScanPhase.scanning;
        await Future.any([
          Future<void>.delayed(_remaining(deadline)),
          cancellation.future,
        ]);
      }
    } on D11BleException {
      rethrow;
    } on TimeoutException catch (error) {
      throw D11BleException('Bluetooth device scan timed out', error);
    } on UniversalBleException catch (error) {
      if (const {
        UniversalBleErrorCode.bluetoothNotAllowed,
        UniversalBleErrorCode.bluetoothUnauthorized,
        UniversalBleErrorCode.accessDenied,
      }.contains(error.code)) {
        throw D11BleException('Bluetooth permission was denied', error);
      }
      throw D11BleException('Bluetooth device scan failed', error);
    } catch (error) {
      throw D11BleException('Bluetooth device scan failed', error);
    } finally {
      try {
        if (startFuture != null) {
          _scanPhase = _ScanPhase.stopping;
          await _stopScan();
        }
      } finally {
        await subscription?.cancel();
        UniversalBle.clearQueue(scanQueueId);
        if (identical(_scanCancellation, cancellation)) {
          _scanCancellation = null;
          _scanCleanupDone = null;
          _scanPhase = null;
        }
        if (!cleanupDone.isCompleted) {
          cleanupDone.complete();
        }
      }
    }

    final devices = found.values.toList()
      ..sort((left, right) {
        final signalOrder = (right.rssi ?? -1000).compareTo(left.rssi ?? -1000);
        return signalOrder != 0 ? signalOrder : left.name.compareTo(right.name);
      });
    return devices;
  }

  @override
  Future<void> cancelScan() async {
    final cancellation = _scanCancellation;
    if (cancellation == null) {
      return;
    }
    if (!cancellation.isCompleted) {
      cancellation.complete();
    }
    await _scanCleanupDone?.future;
  }

  @override
  D11PrinterTransport createTransport(D11PrinterDevice device) =>
      UniversalBleD11Transport(device.id);

  static Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  String _nextQueueId(String operation) =>
      'niimstudio-d11-$operation-${_queueRevision++}';

  Future<void> _stopScan() async {
    final queueId = _nextQueueId('stop-scan');
    try {
      await UniversalBle.stopScan(queueId: queueId).timeout(_cleanupTimeout);
    } catch (_) {
      // Scanning has its own deadline; cleanup must never extend it indefinitely.
    } finally {
      UniversalBle.clearQueue(queueId);
    }
  }

  void _stopWhenStartCompletes(
    Future<void> startFuture,
    Completer<void> cancellation,
  ) {
    unawaited(
      startFuture.then<void>(
        (_) => _stopLateStartedScan(cancellation),
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  Future<void> _stopLateStartedScan(Completer<void> sourceCancellation) async {
    while (true) {
      final activeCancellation = _scanCancellation;
      if (activeCancellation == null ||
          identical(activeCancellation, sourceCancellation) ||
          _scanPhase == _ScanPhase.stopping) {
        await _stopScan();
        return;
      }
      final activeCleanup = _scanCleanupDone;
      if (activeCleanup == null) {
        continue;
      }
      await activeCleanup.future;
    }
  }
}

enum _ScanStartResult { started, cancelled, timedOut }

enum _ScanPhase { preparing, scanning, stopping }

final class UniversalBleD11Transport implements D11PrinterTransport {
  UniversalBleD11Transport(this.deviceId)
    : _operationQueueId =
          'niimstudio-d11-transport-${_transportRevision++}-operations';

  static var _transportRevision = 0;

  final String deviceId;
  final String _operationQueueId;
  final _notifications = StreamController<Uint8List>.broadcast();
  BleCharacteristic? _characteristic;
  StreamSubscription<Uint8List>? _valueSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  var _connected = false;
  var _connectionAttempted = false;
  var _subscriptionAttempted = false;
  var _subscribed = false;
  var _disconnectedUnexpectedly = false;
  var _closing = false;
  var _maximumWriteLength = 20;
  Future<void>? _closeFuture;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Future<void> open() async {
    if (_connected) {
      throw StateError('D11 transport is already open');
    }
    try {
      _connectionAttempted = true;
      await UniversalBle.connect(
        deviceId,
        timeout: const Duration(seconds: 10),
        platformConfig: ConnectionPlatformConfig(
          android: AndroidConnectionOptions(closeGattOnDetach: true),
        ),
      );
      _ensureNotClosing();
      _connected = true;
      _connectionSubscription = UniversalBle.connectionStream(deviceId)
          .listen((connected) {
            if (_connected && !_closing && !connected) {
              _disconnectedUnexpectedly = true;
              _notifications.addError(
                const D11BleException('D11 printer disconnected'),
              );
            }
          }, onError: _notifications.addError);
      try {
        final mtu = await UniversalBle.requestMtu(
          deviceId,
          256,
          queueId: _operationQueueId,
        );
        final payloadLength = defaultTargetPlatform == TargetPlatform.linux
            ? mtu
            : mtu - 3;
        _maximumWriteLength = payloadLength > 0 ? payloadLength : 20;
      } catch (_) {
        // MTU requests are best-effort; fall back to the default ATT payload.
        _maximumWriteLength = 20;
      }
      _ensureNotClosing();
      final services = await UniversalBle.discoverServices(
        deviceId,
        timeout: const Duration(seconds: 10),
        queueId: _operationQueueId,
      );
      _ensureNotClosing();
      final selection = selectD11Characteristic(services);
      _characteristic = selection.characteristic;
      _valueSubscription = selection.characteristic.onValueReceived.listen(
        _notifications.add,
        onError: _notifications.addError,
      );
      _subscriptionAttempted = true;
      await selection.characteristic.notifications.subscribe(
        timeout: const Duration(seconds: 10),
        queueId: _operationQueueId,
      );
      if (_closing) {
        await close();
        throw const D11BleException('D11 connection was cancelled');
      }
      _subscribed = true;
    } catch (error) {
      try {
        await close();
      } catch (_) {
        // The connection error is more useful than a secondary cleanup error.
      }
      if (error is D11BleException) {
        rethrow;
      }
      throw D11BleException('Failed to connect to the D11 printer', error);
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final characteristic = _characteristic;
    if (_disconnectedUnexpectedly) {
      throw const D11BleException('D11 printer disconnected');
    }
    if (!_connected || !_subscribed || characteristic == null) {
      throw const D11BleException('D11 printer is not connected');
    }
    try {
      for (final chunk in bleWriteChunks(bytes, _maximumWriteLength)) {
        await characteristic.write(
          chunk,
          withResponse: false,
          timeout: const Duration(seconds: 10),
          queueId: _operationQueueId,
        );
      }
    } catch (error) {
      throw D11BleException('Failed to write to the D11 printer', error);
    }
  }

  @override
  Future<void> close() {
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    Object? cleanupError;
    _closing = true;
    final disconnectQueueId = '$_operationQueueId-disconnect';
    final characteristic = _characteristic;
    if (_subscriptionAttempted && characteristic != null) {
      try {
        await characteristic.unsubscribe(
          timeout: const Duration(seconds: 10),
          queueId: _operationQueueId,
        );
      } catch (error) {
        cleanupError = error;
      }
    }
    _subscriptionAttempted = false;
    _subscribed = false;
    try {
      await _valueSubscription?.cancel();
    } catch (error) {
      cleanupError ??= error;
    }
    _valueSubscription = null;
    _characteristic = null;
    _connected = false;
    try {
      await _connectionSubscription?.cancel();
    } catch (error) {
      cleanupError ??= error;
    }
    _connectionSubscription = null;
    if (_connectionAttempted) {
      try {
        await UniversalBle.disconnect(
          deviceId,
          timeout: const Duration(seconds: 10),
          queueId: disconnectQueueId,
        );
      } catch (error) {
        cleanupError ??= error;
      }
    }
    _connectionAttempted = false;
    UniversalBle.clearQueue(_operationQueueId);
    UniversalBle.clearQueue(disconnectQueueId);
    if (cleanupError != null) {
      throw D11BleException('Failed to close the D11 connection', cleanupError);
    }
  }

  void _ensureNotClosing() {
    if (_closing) {
      throw const D11BleException('D11 connection was cancelled');
    }
  }
}
