import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';
import 'package:niimstudio/src/printing/d11_printer.dart';
import 'package:niimstudio/src/printing/d11_transport.dart';
import 'package:niimstudio/src/printing/niimbot_packet.dart';
import 'package:niimstudio/src/rendering/label_text_renderer.dart';

void main() {
  test(
    'prints the native D11 raster with the reference command sequence',
    () async {
      final transport = _FakeD11Transport();
      final printer = D11Printer(
        transport,
        delay: (_) async {},
        commandTimeout: const Duration(milliseconds: 100),
      );
      final bytes = Uint8List(12 * 320)..setRange(0, 12, List.filled(12, 0xff));
      final raster = MonochromeRaster(
        size: const PixelSize(width: 96, height: 320),
        bytes: bytes,
      );

      await printer.printRaster(raster);

      final packets = transport.writes.map(NiimbotPacket.fromBytes).toList();
      expect(transport.openCount, 1);
      expect(transport.closeCount, 1);
      expect(packets, hasLength(329));
      expect(packets.take(6).map((packet) => packet.type), [
        0x21,
        0x23,
        0x01,
        0x03,
        0x13,
        0x15,
      ]);
      expect(packets[0].data, [3]);
      expect(packets[1].data, [1]);
      expect(packets[4].data, [0x01, 0x40, 0x00, 0x60]);
      expect(packets[5].data, [0x00, 0x01]);
      expect(packets[6].type, 0x85);
      expect(packets[6].data.take(6), [0, 0, 0, 0, 0, 1]);
      expect(packets[6].data.skip(6), List.filled(12, 0xff));
      expect(packets[325].data.take(2), [0x01, 0x3f]);
      expect(packets.skip(326).map((packet) => packet.type), [
        0xe3,
        0xa3,
        0xf3,
      ]);
    },
  );

  test(
    'polls page completion and reported quantity before succeeding',
    () async {
      final transport = _FakeD11Transport(
        endPageResponses: [0, 1],
        statusPages: [0, 1],
      );
      final progress = <D11PrintPhase>[];
      final printer = D11Printer(
        transport,
        delay: (_) async {},
        commandTimeout: const Duration(milliseconds: 100),
      );

      await printer.printRaster(
        _blankRaster(),
        onProgress: (value) {
          progress.add(value.phase);
        },
      );

      final packetTypes = transport.writes
          .map(NiimbotPacket.fromBytes)
          .map((packet) => packet.type);
      expect(packetTypes.where((type) => type == 0xe3), hasLength(2));
      expect(packetTypes.where((type) => type == 0xa3), hasLength(2));
      expect(
        progress,
        containsAllInOrder([
          D11PrintPhase.connecting,
          D11PrintPhase.configuring,
          D11PrintPhase.sendingRaster,
          D11PrintPhase.waitingForPrinter,
          D11PrintPhase.complete,
        ]),
      );
    },
  );

  test('times out a command and always closes the transport', () async {
    final transport = _FakeD11Transport(respond: false);
    final printer = D11Printer(
      transport,
      delay: (_) async {},
      commandTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      printer.printRaster(_blankRaster()),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
    expect(transport.closeCount, 1);
  });

  test('ends an interrupted print job before disconnecting', () async {
    final transport = _FakeD11Transport(rejectedRequest: 0x13);
    final printer = D11Printer(
      transport,
      delay: (_) async {},
      commandTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      printer.printRaster(_blankRaster()),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('set dimensions'),
        ),
      ),
    );

    expect(transport.writes.map(NiimbotPacket.fromBytes).last.type, 0xf3);
    expect(transport.closeCount, 1);
  });

  test('rejects a raster that is not the native D11 size', () async {
    final printer = D11Printer(_FakeD11Transport());
    final raster = MonochromeRaster.blank(
      const PixelSize(width: 320, height: 96),
    );

    await expectLater(printer.printRaster(raster), throwsArgumentError);
  });

  test(
    'ignores unrelated responses and decodes fragmented responses',
    () async {
      final transport = _FakeD11Transport(
        sendUnrelatedResponse: true,
        fragmentResponses: true,
      );
      final printer = D11Printer(
        transport,
        delay: (_) async {},
        commandTimeout: const Duration(milliseconds: 100),
      );

      await printer.printRaster(_blankRaster());

      expect(transport.closeCount, 1);
    },
  );

  test('reports printer error responses and closes the transport', () async {
    final transport = _FakeD11Transport(errorResponseType: 0xdb);
    final printer = D11Printer(
      transport,
      delay: (_) async {},
      commandTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      printer.printRaster(_blankRaster()),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('error response'),
        ),
      ),
    );
    expect(transport.closeCount, 1);
  });

  test('reports unsupported responses and closes the transport', () async {
    final transport = _FakeD11Transport(errorResponseType: 0x00);
    final printer = D11Printer(
      transport,
      delay: (_) async {},
      commandTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      printer.printRaster(_blankRaster()),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('does not support'),
        ),
      ),
    );
    expect(transport.closeCount, 1);
  });

  test(
    'reports a notification stream disconnect and closes transport',
    () async {
      final transport = _FakeD11Transport(closeNotificationsOnWrite: true);
      final printer = D11Printer(
        transport,
        delay: (_) async {},
        commandTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        printer.printRaster(_blankRaster()),
        throwsA(
          isA<D11PrintException>().having(
            (error) => error.message,
            'message',
            contains('disconnected'),
          ),
        ),
      );
      expect(transport.closeCount, 1);
    },
  );

  test('bounds transport close by the cleanup timeout', () async {
    final closeBlocker = Completer<void>();
    final transport = _FakeD11Transport(closeBlocker: closeBlocker);
    final printer = D11Printer(
      transport,
      delay: (_) async {},
      commandTimeout: const Duration(milliseconds: 100),
      cleanupTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      printer.printRaster(_blankRaster()),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('disconnect'),
        ),
      ),
    );
  });

  test('bounds cancellation close by the cleanup timeout', () async {
    final closeBlocker = Completer<void>();
    final printer = D11Printer(
      _FakeD11Transport(closeBlocker: closeBlocker),
      cleanupTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      printer.cancel(),
      throwsA(
        isA<D11PrintException>().having(
          (error) => error.message,
          'message',
          contains('cancel'),
        ),
      ),
    );
  });
}

MonochromeRaster _blankRaster() =>
    MonochromeRaster.blank(const PixelSize(width: 96, height: 320));

final class _FakeD11Transport implements D11PrinterTransport {
  _FakeD11Transport({
    this.respond = true,
    this.rejectedRequest,
    List<int>? endPageResponses,
    List<int>? statusPages,
    this.sendUnrelatedResponse = false,
    this.fragmentResponses = false,
    this.errorResponseType,
    this.closeNotificationsOnWrite = false,
    this.closeBlocker,
  }) : _endPageResponses = [...?endPageResponses],
       _statusPages = [...?statusPages];

  final bool respond;
  final int? rejectedRequest;
  final bool sendUnrelatedResponse;
  final bool fragmentResponses;
  final int? errorResponseType;
  final bool closeNotificationsOnWrite;
  final Completer<void>? closeBlocker;
  final List<int> _endPageResponses;
  final List<int> _statusPages;
  final _notifications = StreamController<Uint8List>.broadcast(sync: true);
  final List<Uint8List> writes = [];
  var openCount = 0;
  var closeCount = 0;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Future<void> open() async {
    openCount++;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    if (closeNotificationsOnWrite) {
      await _notifications.close();
      return;
    }
    if (!respond) {
      return;
    }
    final request = NiimbotPacket.fromBytes(bytes);
    if (request.type == 0x85) {
      return;
    }
    if (sendUnrelatedResponse) {
      _notifications.add(
        NiimbotPacket(0x99, Uint8List.fromList([1])).toBytes(),
      );
    }
    final responseType = switch (request.type) {
      0x21 || 0x23 || 0xa3 => request.type + 0x10,
      _ => (request.type + 1) & 0xff,
    };
    final responseData = switch (request.type) {
      0xe3 => [_endPageResponses.isEmpty ? 1 : _endPageResponses.removeAt(0)],
      0xa3 => [0, _statusPages.isEmpty ? 1 : _statusPages.removeAt(0), 0, 0],
      _ => [request.type == rejectedRequest ? 0 : 1],
    };
    final response = NiimbotPacket(
      errorResponseType ?? responseType,
      Uint8List.fromList(responseData),
    ).toBytes();
    if (fragmentResponses) {
      _notifications.add(Uint8List.fromList(response.sublist(0, 3)));
      _notifications.add(Uint8List.fromList(response.sublist(3)));
    } else {
      _notifications.add(response);
    }
  }

  @override
  Future<void> close() async {
    closeCount++;
    await closeBlocker?.future;
  }
}
