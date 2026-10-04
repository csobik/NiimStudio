import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';
import 'package:niimstudio/src/printing/d11_print_controller.dart';
import 'package:niimstudio/src/printing/d11_printer.dart';
import 'package:niimstudio/src/printing/d11_printer_gateway.dart';
import 'package:niimstudio/src/printing/d11_transport.dart';
import 'package:niimstudio/src/rendering/label_text_renderer.dart';

void main() {
  test('scan requires explicit device selection', () async {
    final device = const D11PrinterDevice(id: 'one', name: 'D11-one');
    final controller = D11PrintController(_FakeGateway([device]));

    await controller.scan();

    expect(controller.devices, [device]);
    expect(controller.selectedDevice, isNull);
    expect(controller.status, 'Select a D11 printer.');

    controller.selectDevice(device);
    expect(controller.selectedDevice, same(device));
    expect(controller.canPrint(_raster()), isTrue);
  });

  test('publishes progress and success only after print completion', () async {
    final device = const D11PrinterDevice(id: 'one', name: 'D11-one');
    final executor = _FakeExecutor();
    final controller = D11PrintController(
      _FakeGateway([device]),
      printerFactory: (_) => executor,
    );
    await controller.scan();
    controller.selectDevice(device);

    await controller.print(_raster());

    expect(executor.printCount, 1);
    expect(controller.state, D11PrintUiState.success);
    expect(controller.status, 'Label printed.');
  });

  test('reports a print failure without losing the selection', () async {
    final device = const D11PrinterDevice(id: 'one', name: 'D11-one');
    final controller = D11PrintController(
      _FakeGateway([device]),
      printerFactory: (_) => _FakeExecutor(failure: 'Paper jam'),
    );
    await controller.scan();
    controller.selectDevice(device);

    await controller.print(_raster());

    expect(controller.state, D11PrintUiState.failure);
    expect(controller.status, contains('Paper jam'));
    expect(controller.selectedDevice, same(device));
  });

  test('stays busy until transport cleanup has completed', () async {
    final device = const D11PrinterDevice(id: 'one', name: 'D11-one');
    final cleanup = Completer<void>();
    final executor = _DelayedCleanupExecutor(cleanup.future);
    final controller = D11PrintController(
      _FakeGateway([device]),
      printerFactory: (_) => executor,
    );
    await controller.scan();
    controller.selectDevice(device);

    final firstPrint = controller.print(_raster());
    await executor.completedProtocol.future;
    expect(controller.isBusy, isTrue);

    await controller.print(_raster());
    expect(executor.printCount, 1);

    cleanup.complete();
    await firstPrint;
    expect(controller.isBusy, isFalse);
    expect(controller.state, D11PrintUiState.success);
  });

  test(
    'cancels active gateway and printer work without leaking errors',
    () async {
      final device = const D11PrinterDevice(id: 'one', name: 'D11-one');
      final gateway = _FakeGateway([device]);
      final executor = _CancellableExecutor();
      final controller = D11PrintController(
        gateway,
        printerFactory: (_) => executor,
      );
      await controller.scan();
      controller.selectDevice(device);
      final print = controller.print(_raster());
      await executor.started.future;

      await controller.cancelActiveOperation();
      await print;

      expect(gateway.cancelCount, 1);
      expect(executor.cancelCount, 1);
      expect(controller.isBusy, isFalse);
    },
  );
}

MonochromeRaster _raster() {
  final bytes = Uint8List(12 * 320)..first = 0x80;
  return MonochromeRaster(
    size: const PixelSize(width: 96, height: 320),
    bytes: bytes,
  );
}

final class _FakeGateway implements D11PrinterGateway {
  _FakeGateway(this.result);

  final List<D11PrinterDevice> result;
  var cancelCount = 0;

  @override
  Future<void> cancelScan() async {
    cancelCount++;
  }

  @override
  Future<List<D11PrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async => result;

  @override
  D11PrinterTransport createTransport(D11PrinterDevice device) =>
      _UnusedTransport();
}

final class _FakeExecutor implements D11PrintExecutor {
  _FakeExecutor({this.failure});

  final String? failure;
  var printCount = 0;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  }) async {
    printCount++;
    onProgress?.call(const D11PrintProgress(D11PrintPhase.connecting));
    onProgress?.call(
      const D11PrintProgress(
        D11PrintPhase.sendingRaster,
        row: 160,
        totalRows: 320,
      ),
    );
    if (failure != null) {
      throw D11PrintException(failure!);
    }
    onProgress?.call(const D11PrintProgress(D11PrintPhase.complete));
  }
}

final class _UnusedTransport implements D11PrinterTransport {
  @override
  Stream<Uint8List> get notifications => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> open() async {}

  @override
  Future<void> write(Uint8List bytes) async {}
}

final class _DelayedCleanupExecutor implements D11PrintExecutor {
  _DelayedCleanupExecutor(this.cleanup);

  final Future<void> cleanup;
  final completedProtocol = Completer<void>();
  var printCount = 0;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  }) async {
    printCount++;
    onProgress?.call(const D11PrintProgress(D11PrintPhase.complete));
    completedProtocol.complete();
    await cleanup;
  }
}

final class _CancellableExecutor implements D11PrintExecutor {
  final started = Completer<void>();
  final _cancelled = Completer<void>();
  var cancelCount = 0;

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  @override
  Future<void> printRaster(
    MonochromeRaster raster, {
    D11PrintProgressCallback? onProgress,
  }) async {
    started.complete();
    await _cancelled.future;
    throw const D11PrintException('Print cancelled');
  }
}
