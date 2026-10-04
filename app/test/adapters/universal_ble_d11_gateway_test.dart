import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/adapters/universal_ble_d11_gateway.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('isD11AdvertisedName', () {
    test('accepts D11 names case-insensitively', () {
      expect(isD11AdvertisedName('D11-G228011445'), isTrue);
      expect(isD11AdvertisedName('d11 printer'), isTrue);
      expect(isD11AdvertisedName('D-11_test'), isTrue);
    });

    test('does not misclassify longer model prefixes', () {
      expect(isD11AdvertisedName('D110-Printer'), isFalse);
      expect(isD11AdvertisedName('D11_H-Printer'), isFalse);
      expect(isD11AdvertisedName('D11H-Printer'), isFalse);
      expect(isD11AdvertisedName(null), isFalse);
    });
  });

  test('selects the only compatible characteristic by properties', () {
    final readOnly = BleCharacteristic('2a00', [
      CharacteristicProperty.read,
    ], []);
    final compatible = BleCharacteristic('2a01', [
      CharacteristicProperty.read,
      CharacteristicProperty.writeWithoutResponse,
      CharacteristicProperty.notify,
    ], []);
    final services = [
      BleService('1800', [readOnly]),
      BleService('1801', [compatible]),
    ];

    final selected = selectD11Characteristic(services);

    expect(BleUuidParser.compareStrings(selected.service.uuid, '1801'), isTrue);
    expect(
      BleUuidParser.compareStrings(selected.characteristic.uuid, '2a01'),
      isTrue,
    );
  });

  test('rejects missing or ambiguous compatible characteristics', () {
    final compatible = BleCharacteristic('2a01', [
      CharacteristicProperty.read,
      CharacteristicProperty.writeWithoutResponse,
      CharacteristicProperty.notify,
    ], []);

    expect(
      () => selectD11Characteristic([BleService('1800', [])]),
      throwsA(isA<D11BleException>()),
    );
    expect(
      () => selectD11Characteristic([
        BleService('1800', [compatible]),
        BleService('1801', [compatible]),
      ]),
      throwsA(isA<D11BleException>()),
    );
  });

  test('splits writes to the negotiated ATT payload size', () {
    final chunks = bleWriteChunks(
      Uint8List.fromList(List.generate(25, (index) => index)),
      20,
    );

    expect(chunks.map((chunk) => chunk.length), [20, 5]);
    expect(
      chunks.expand((chunk) => chunk),
      List.generate(25, (index) => index),
    );
  });

  group('UniversalBleD11Gateway', () {
    late _FakeUniversalBlePlatform platform;
    late UniversalBleD11Gateway gateway;

    setUp(() {
      platform = _FakeUniversalBlePlatform();
      UniversalBle.setInstance(platform);
      UniversalBle.queueType = QueueType.global;
      gateway = UniversalBleD11Gateway();
    });

    test('discovers only D11 devices and sorts strongest first', () async {
      final scan = gateway.scan(timeout: const Duration(minutes: 1));
      await platform.startCalled.future;
      platform.updateScanResult(
        BleDevice(deviceId: 'weak', name: 'D11-weak', rssi: -80),
      );
      platform.updateScanResult(
        BleDevice(deviceId: 'other', name: 'D110-other', rssi: -20),
      );
      platform.updateScanResult(
        BleDevice(deviceId: 'strong', name: 'D11-strong', rssi: -40),
      );

      await gateway.cancelScan();

      expect((await scan).map((device) => device.id), ['strong', 'weak']);
      expect(platform.stopCount, greaterThanOrEqualTo(1));
    });

    test('cancels promptly while the platform start call is pending', () async {
      platform.startBlocker = Completer<void>();
      final scan = gateway.scan(timeout: const Duration(minutes: 1));
      await platform.startCalled.future;

      await gateway.cancelScan().timeout(const Duration(milliseconds: 100));

      expect(await scan.timeout(const Duration(milliseconds: 100)), isEmpty);
      platform.startBlocker!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(platform.stopCount, greaterThanOrEqualTo(2));
    });

    test('applies the scan deadline while requesting permissions', () async {
      platform.permissionBlocker = Completer<void>();

      await expectLater(
        gateway
            .scan(timeout: Duration.zero)
            .timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<D11BleException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(platform.startCount, 0);
    });

    test('cancels promptly while permission request is pending', () async {
      platform.permissionBlocker = Completer<void>();
      final scan = gateway.scan(timeout: const Duration(minutes: 1));
      await platform.permissionCalled.future;

      await gateway.cancelScan().timeout(const Duration(milliseconds: 100));

      expect(await scan.timeout(const Duration(milliseconds: 100)), isEmpty);
      expect(platform.startCount, 0);
    });

    test(
      'stops a late scan start after a replacement scan is cancelled',
      () async {
        platform.startBlocker = Completer<void>();
        final firstScan = gateway.scan(timeout: const Duration(minutes: 1));
        await platform.startCalled.future;
        await gateway.cancelScan();
        await firstScan;
        final stopsBeforeLateStart = platform.stopCount;

        platform.availabilityBlocker = Completer<void>();
        platform.availabilityRequested = Completer<void>();
        final replacementScan = gateway.scan(
          timeout: const Duration(minutes: 1),
        );
        await platform.availabilityRequested.future;
        platform.startBlocker!.complete();
        await Future<void>.delayed(Duration.zero);

        await gateway.cancelScan();
        await replacementScan;
        await Future<void>.delayed(Duration.zero);

        expect(platform.stopCount, greaterThan(stopsBeforeLateStart));
      },
    );

    test(
      'transport connects, subscribes, chunks writes, and disconnects',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final transport = UniversalBleD11Transport('printer');

        await transport.open();
        final notification = transport.notifications.first;
        platform.updateCharacteristicValue(
          'printer',
          '2a01',
          Uint8List.fromList([1, 2, 3]),
          null,
        );
        await transport.write(Uint8List.fromList(List.generate(25, (i) => i)));
        await transport.close();

        expect(await notification, [1, 2, 3]);
        expect(platform.connectCount, 1);
        expect(platform.notifiableStates, [
          BleInputProperty.notification,
          BleInputProperty.disabled,
        ]);
        expect(platform.writes.map((bytes) => bytes.length), [20, 5]);
        expect(platform.disconnectCount, 1);
      },
    );

    test(
      'closing during subscription still unsubscribes and disconnects',
      () async {
        platform.notificationBlocker = Completer<void>();
        final transport = UniversalBleD11Transport('printer');
        final opening = transport.open();
        await platform.notificationRequested.future;

        final closing = transport.close();
        platform.notificationBlocker!.complete();

        await closing;
        await expectLater(opening, throwsA(isA<D11BleException>()));
        expect(platform.notifiableStates, [
          BleInputProperty.notification,
          BleInputProperty.disabled,
        ]);
        expect(platform.disconnectCount, 1);
      },
    );

    test(
      'closing during discovery cannot subscribe after disconnect',
      () async {
        platform.discoveryBlocker = Completer<void>();
        final transport = UniversalBleD11Transport('printer');
        final opening = transport.open();
        await platform.discoveryRequested.future;

        await transport.close();
        platform.discoveryBlocker!.complete();

        await expectLater(opening, throwsA(isA<D11BleException>()));
        expect(platform.notifiableStates, isEmpty);
        expect(platform.disconnectCount, 1);
      },
    );
  });
}

final class _FakeUniversalBlePlatform extends UniversalBlePlatform {
  AvailabilityState availability = AvailabilityState.poweredOn;
  Completer<void>? permissionBlocker;
  Completer<void>? startBlocker;
  Completer<void>? availabilityBlocker;
  final permissionCalled = Completer<void>();
  final startCalled = Completer<void>();
  var availabilityRequested = Completer<void>();
  var startCount = 0;
  var stopCount = 0;
  var connectCount = 0;
  var disconnectCount = 0;
  var connected = false;
  final notifiableStates = <BleInputProperty>[];
  final writes = <Uint8List>[];
  final notificationRequested = Completer<void>();
  Completer<void>? notificationBlocker;
  final discoveryRequested = Completer<void>();
  Completer<void>? discoveryBlocker;

  @override
  Future<void> requestPermissions({
    bool withAndroidFineLocation = false,
  }) async {
    if (!permissionCalled.isCompleted) {
      permissionCalled.complete();
    }
    await permissionBlocker?.future;
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async {
    if (!availabilityRequested.isCompleted) {
      availabilityRequested.complete();
    }
    await availabilityBlocker?.future;
    return availability;
  }

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    startCount++;
    if (!startCalled.isCompleted) {
      startCalled.complete();
    }
    await startBlocker?.future;
  }

  @override
  Future<void> stopScan() async {
    stopCount++;
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    connectCount++;
    connected = true;
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCount++;
    connected = false;
    updateConnection(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      connected
      ? BleConnectionState.connected
      : BleConnectionState.disconnected;

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => 23;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async {
    if (!discoveryRequested.isCompleted) {
      discoveryRequested.complete();
    }
    await discoveryBlocker?.future;
    return [
      BleService('1801', [
        BleCharacteristic.withMetaData(
          deviceId: deviceId,
          serviceId: '1801',
          uuid: '2a01',
          properties: const [
            CharacteristicProperty.read,
            CharacteristicProperty.writeWithoutResponse,
            CharacteristicProperty.notify,
          ],
          descriptors: const [],
        ),
      ]),
    ];
  }

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    notifiableStates.add(bleInputProperty);
    if (bleInputProperty == BleInputProperty.notification) {
      if (!notificationRequested.isCompleted) {
        notificationRequested.complete();
      }
      await notificationBlocker?.future;
    }
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    writes.add(Uint8List.fromList(value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
