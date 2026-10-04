import 'dart:async';
import 'dart:typed_data';

import '../domain/label_geometry.dart';
import '../rendering/label_text_renderer.dart';
import 'd11_transport.dart';
import 'niimbot_packet.dart';

enum D11PrintPhase {
  connecting,
  configuring,
  sendingRaster,
  waitingForPrinter,
  complete,
}

final class D11PrintProgress {
  const D11PrintProgress(this.phase, {this.row, this.totalRows});

  final D11PrintPhase phase;
  final int? row;
  final int? totalRows;
}

final class D11PrintException implements Exception {
  const D11PrintException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'D11PrintException: $message';
}

typedef D11PrintDelay = Future<void> Function(Duration duration);
typedef D11PrintProgressCallback = void Function(D11PrintProgress progress);

abstract interface class D11PrintExecutor {
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  });

  Future<void> cancel();
}

final class D11Printer implements D11PrintExecutor {
  D11Printer(
    this._transport, {
    this.commandTimeout = const Duration(seconds: 10),
    this.jobTimeout = const Duration(seconds: 120),
    this.cleanupTimeout = const Duration(seconds: 10),
    D11PrintDelay? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  static const _nativeSize = PixelSize(width: 96, height: 320);
  static const _rowDelay = Duration(milliseconds: 10);
  static const _pollDelay = Duration(milliseconds: 50);

  final D11PrinterTransport _transport;
  final Duration commandTimeout;
  final Duration jobTimeout;
  final Duration cleanupTimeout;
  final D11PrintDelay _delay;
  final NiimbotPacketDecoder _decoder = NiimbotPacketDecoder();

  Completer<NiimbotPacket>? _response;
  int? _expectedResponseType;
  DateTime? _deadline;
  var _cancelled = false;

  @override
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  }) async {
    if (raster.size != _nativeSize) {
      throw ArgumentError.value(
        raster.size,
        'raster',
        'D11 raster must be 96 x 320 pixels',
      );
    }

    Object? primaryError;
    var printStartAttempted = false;
    var endPrintAttempted = false;
    StreamSubscription<Uint8List>? notifications;
    _cancelled = false;
    _deadline = DateTime.now().add(jobTimeout);
    try {
      onProgress?.call(const D11PrintProgress(D11PrintPhase.connecting));
      notifications = _transport.notifications.listen(
        _handleNotification,
        onError: _handleNotificationError,
        onDone: _handleNotificationDone,
      );
      await _withRemainingTime(_transport.open());

      onProgress?.call(const D11PrintProgress(D11PrintPhase.configuring));
      _requireAck(
        await _acknowledged(0x21, [3], responseOffset: 0x10),
        'set label density',
      );
      _requireAck(
        await _acknowledged(0x23, [1], responseOffset: 0x10),
        'set label type',
      );
      printStartAttempted = true;
      _requireAck(await _acknowledged(0x01, [1]), 'start print');
      _requireAck(await _acknowledged(0x03, [1]), 'start page print');
      _requireAck(
        await _acknowledged(0x13, [0x01, 0x40, 0x00, 0x60]),
        'set dimensions',
      );
      _requireAck(await _acknowledged(0x15, [0x00, 0x01]), 'set quantity');

      for (var row = 0; row < raster.size.height; row++) {
        onProgress?.call(
          D11PrintProgress(
            D11PrintPhase.sendingRaster,
            row: row + 1,
            totalRows: raster.size.height,
          ),
        );
        await _write(_rowPacket(raster, row).toBytes());
        await _pause(_rowDelay);
      }

      onProgress?.call(const D11PrintProgress(D11PrintPhase.waitingForPrinter));
      while (!await _acknowledged(0xe3, [1])) {
        await _pause(_pollDelay);
      }
      while (await _printedPageCount() < 1) {
        await _pause(_pollDelay);
      }

      endPrintAttempted = true;
      _requireAck(await _acknowledged(0xf3, [1]), 'end print');
      onProgress?.call(const D11PrintProgress(D11PrintPhase.complete));
    } on D11PrintException catch (error) {
      primaryError = error;
      rethrow;
    } on TimeoutException catch (error) {
      final wrapped = D11PrintException(
        'Print job timed out after ${jobTimeout.inSeconds} seconds',
        error,
      );
      primaryError = wrapped;
      throw wrapped;
    } catch (error) {
      final text = error.toString();
      final separator = text.indexOf(': ');
      final wrapped = D11PrintException(
        separator < 0
            ? 'Bluetooth printing failed'
            : text.substring(separator + 2),
        error,
      );
      primaryError = wrapped;
      throw wrapped;
    } finally {
      if (printStartAttempted && !endPrintAttempted) {
        final jobDeadline = _deadline;
        _deadline = DateTime.now().add(cleanupTimeout);
        try {
          await _acknowledged(0xf3, [1]);
        } catch (_) {
          // Preserve the original print failure.
        } finally {
          _deadline = jobDeadline;
        }
      }
      Object? closeError;
      await notifications?.cancel();
      try {
        await _transport.close().timeout(cleanupTimeout);
      } catch (error) {
        closeError = error;
      }
      _response = null;
      _expectedResponseType = null;
      _decoder.reset();
      _deadline = null;
      if (primaryError == null && closeError != null) {
        throw D11PrintException(
          'Failed to disconnect from printer',
          closeError,
        );
      }
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(const D11PrintException('Print cancelled'));
    }
    try {
      await _transport.close().timeout(cleanupTimeout);
    } catch (error) {
      throw D11PrintException('Failed to cancel the print connection', error);
    }
  }

  Future<bool> _acknowledged(
    int requestType,
    List<int> data, {
    int responseOffset = 1,
  }) async {
    final response = await _sendCommand(
      requestType,
      Uint8List.fromList(data),
      responseOffset: responseOffset,
    );
    if (response.data.isEmpty) {
      throw D11PrintException(
        'Printer returned an empty response to command 0x${requestType.toRadixString(16).padLeft(2, '0')}',
      );
    }
    return response.data[0] != 0;
  }

  Future<int> _printedPageCount() async {
    final response = await _sendCommand(
      0xa3,
      Uint8List.fromList([1]),
      responseOffset: 0x10,
    );
    if (response.data.length < 4) {
      throw const D11PrintException('Printer returned an invalid print status');
    }
    return response.data[0] << 8 | response.data[1];
  }

  Future<NiimbotPacket> _sendCommand(
    int requestType,
    Uint8List data, {
    required int responseOffset,
  }) async {
    if (_response != null) {
      throw StateError('A printer command is already in progress');
    }
    _decoder.reset();
    final response = Completer<NiimbotPacket>();
    _response = response;
    _expectedResponseType = (requestType + responseOffset) & 0xff;
    // Notifications may arrive synchronously from a fake or fast platform channel.
    unawaited(
      response.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    final commandDeadline = DateTime.now().add(
      _shorter(commandTimeout, _remaining()),
    );
    try {
      await _transport
          .write(NiimbotPacket(requestType, data).toBytes())
          .timeout(_until(commandDeadline));
      return await response.future.timeout(_until(commandDeadline));
    } on TimeoutException catch (error) {
      throw D11PrintException(
        'Printer command 0x${requestType.toRadixString(16).padLeft(2, '0')} timed out',
        error,
      );
    } finally {
      if (identical(_response, response)) {
        _response = null;
        _expectedResponseType = null;
      }
    }
  }

  void _handleNotification(Uint8List bytes) {
    try {
      for (final packet in _decoder.add(bytes)) {
        final response = _response;
        if (response == null || response.isCompleted) {
          continue;
        }
        if (packet.type == 0x00) {
          response.completeError(
            const D11PrintException('Printer does not support this command'),
          );
        } else if (packet.type == 0xdb) {
          response.completeError(
            const D11PrintException('Printer returned an error response'),
          );
        } else if (packet.type == _expectedResponseType) {
          response.complete(packet);
        }
      }
    } catch (error) {
      final response = _response;
      if (response != null && !response.isCompleted) {
        response.completeError(
          D11PrintException('Invalid printer response', error),
        );
      }
    }
  }

  void _handleNotificationError(Object error, StackTrace stackTrace) {
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(
        D11PrintException('Printer notification failed', error),
        stackTrace,
      );
    }
  }

  void _handleNotificationDone() {
    final response = _response;
    if (response != null && !response.isCompleted) {
      response.completeError(
        const D11PrintException('Printer disconnected during command'),
      );
    }
  }

  NiimbotPacket _rowPacket(MonochromeRaster raster, int row) {
    final data = Uint8List(6 + raster.bytesPerRow);
    data[0] = row >> 8;
    data[1] = row & 0xff;
    data[5] = 1;
    final rowStart = row * raster.bytesPerRow;
    data.setRange(6, data.length, raster.bytes, rowStart);
    return NiimbotPacket(0x85, data);
  }

  Future<void> _write(Uint8List bytes) async {
    if (_cancelled) {
      throw const D11PrintException('Print cancelled');
    }
    try {
      await _transport
          .write(bytes)
          .timeout(_shorter(commandTimeout, _remaining()));
    } on TimeoutException catch (error) {
      throw D11PrintException('Printer write timed out', error);
    }
  }

  Future<void> _pause(Duration duration) async {
    if (_cancelled) {
      throw const D11PrintException('Print cancelled');
    }
    final remaining = _remaining();
    if (remaining < duration) {
      throw TimeoutException('Print job deadline exceeded');
    }
    await _delay(duration).timeout(remaining);
  }

  Future<T> _withRemainingTime<T>(Future<T> operation) =>
      operation.timeout(_remaining());

  Duration _remaining() {
    final deadline = _deadline;
    if (deadline == null) {
      throw StateError('No print job is active');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Print job deadline exceeded');
    }
    return remaining;
  }

  static Duration _until(DateTime deadline) {
    final duration = deadline.difference(DateTime.now());
    return duration > Duration.zero ? duration : Duration.zero;
  }

  static Duration _shorter(Duration first, Duration second) =>
      first <= second ? first : second;

  static void _requireAck(bool acknowledged, String operation) {
    if (!acknowledged) {
      throw D11PrintException('Printer rejected operation: $operation');
    }
  }
}
